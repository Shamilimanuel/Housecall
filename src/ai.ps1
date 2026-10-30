<#
    The AI chat (?): the problem in the client's own words, and Claude picks
    which of Housecall's checks to run.

    The loop runs here, one relay round at a time. Claude (behind the
    relay, which holds the key and the system prompt) answers with
    run_check calls; Housecall runs those checks on this PC -- the same
    read-only checks as the menu -- and sends the results back. Claude ends
    with give_answer: a plain summary, the problem it points to, the fixes
    it recommends and manual steps.

    The AI never changes anything. The fixes it names must be ones the check
    itself offered; they go through the normal Wat nu? menu with a J/N, the
    check again as proof, and U to undo. Only the problem text and the check
    results leave the PC.

    Each turn's content is kept exactly as the API returned it (as a JSON
    string) and sent back unchanged, because Claude's thinking blocks must
    come back as they were.
#>

$script:AiMaxChecks = 6
$script:AiMaxRounds = 10

# One check by code, without asking anything: A3 and A4 take the site or
# email address the AI passes along.
function Get-HcAiCheck {
    param([string]$Code, [string]$Value)
    switch ($Code) {
        'A3'    { return New-HcSiteCheck (ConvertTo-HcHostName $Value) }
        'A4'    { return New-HcMailCheck (ConvertTo-HcMailDomain $Value) }
        default {
            $handler = $script:ProblemHandlers[$Code]
            if ($handler) { return & $handler }
            return $null
        }
    }
}

# A report as text for the AI: the lines, the finding, the advice, and the
# fixes Housecall offers, by id.
function Format-HcReportForAi {
    param([pscustomobject]$Report)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($r in $Report.Results) { $lines.Add("[$($r.Status)] $($r.Text)") }
    if ($Report.FindingId) {
        $all = @('finding.' + $Report.FindingId) + @($Report.FindingArgs)
        $lines.Add("Finding ($($Report.FindingId)): $(T @all)")
        $lines.Add("Advice: $(T ('advice.' + $Report.FindingId))")
    }
    $actions = @($Report.Actions)
    if ($actions.Count) {
        $lines.Add('Offered fixes:')
        foreach ($a in $actions) { $lines.Add("- $($a.FixId): $(Get-HcFixLabel $a)") }
    } else {
        $lines.Add('Offered fixes: none')
    }
    $lines -join "`n"
}

function ConvertTo-HcContentJson {
    param([object[]]$Blocks)
    ConvertTo-Json -InputObject @($Blocks) -Depth 20 -Compress
}

# What this visit already found (25 Oct), said once at the start of a
# conversation so the AI does not check it all again: codes, findings and
# the Windows version only; no names, files or anything typed.
function Get-HcAiKnown {
    param($Environment)
    $lines = @()
    foreach ($v in @($script:HcVisit | Where-Object { $_.FindingId })) {
        $all = @('finding.' + $v.FindingId) + @($v.FindingArgs)
        $lines += "$($v.Code) $(T "problem.$($v.Code)"): $(T @all)"
    }
    if ($Environment -and $Environment.Os) { $lines += "Windows: $($Environment.Os)" }
    $lines
}

# The first message: the language, the problem, and what is already known.
function New-HcAiFirstText {
    param([string]$Problem, [string[]]$Known = @(), [string]$Lang = $script:Lang)
    $t = "[$Lang]`n$Problem"
    $known = @($Known | Where-Object { $_ })
    if ($known.Count) { $t += "`n`nWhat Housecall already found on this PC during this visit:`n- " + ($known -join "`n- ") }
    $t
}

# A conversation between turns: the history as the API returned it, the
# check results and the answer or question still waiting for their reply,
# how many checks ran, and each check's result by code and input.
function New-HcAiConvo {
    @{ History = @(); Pending = @(); PendingIds = @(); ChecksRun = 0; Cache = @{} }
}

<#
    One turn of a conversation (25 Oct: the chat goes on after an answer).
    The technician's message -- or the client's answer to the AI's question -- goes
    in; Claude runs Housecall's checks; the turn ends at an answer
    (give_answer), a question back (ask_client), or an error. Returns what
    happened and, in .Convo, the conversation to pass to the next turn.

    A check the AI asks for again with the same input is not run again: its
    result from earlier in the conversation is sent instead. At most
    $AiMaxChecks checks in a whole conversation.
#>
function Invoke-HcAiTurn {
    param([hashtable]$Convo, [string]$Text, [string]$Effort = 'medium')
    if (-not $Convo) { $Convo = New-HcAiConvo }
    $history = New-Object System.Collections.ArrayList
    foreach ($h in @($Convo.History)) { if ($h) { [void]$history.Add($h) } }
    # Every tool call of the last turn gets its reply first: the check
    # results that were waiting, the answer to the question, "shown" for an answer.
    $content = @(@($Convo.Pending) | Where-Object { $_ })
    foreach ($p in @($Convo.PendingIds | Where-Object { $_ })) {
        if ($p.Kind -eq 'ask' -and $Text) { $content += @{ type = 'tool_result'; tool_use_id = $p.Id; content = $Text }; $Text = '' }
        else { $content += @{ type = 'tool_result'; tool_use_id = $p.Id; content = 'Shown to Shamil and the client.' } }
    }
    if ($Text) { $content += @{ type = 'text'; text = $Text } }
    [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $content) })

    # Inputs: the site or email address the AI passed with A3 or A4, so the
    # window can check the same one again after a fix.
    $state = [pscustomobject]@{ Answer = $null; Question = $null; Text = $null; Ran = @(); Reports = @{}; Checks = @{}; Inputs = @{}
                                Error = $null; Refused = $false; Convo = $Convo }
    $checksRun = [int]$Convo.ChecksRun
    $cache = @{}
    foreach ($k in @($Convo.Cache.Keys)) { $cache[$k] = $Convo.Cache[$k] }
    for ($round = 0; $round -lt $script:AiMaxRounds; $round++) {
        Write-Dim (T 'ai.thinking')
        $r = Invoke-HcRelay @{ action = 'chat'; token = $script:HcToken; messages = @($history); effort = $Effort }
        if (-not $r.Ok) { $state.Error = $r.Error; return $state }
        [void]$history.Add(@{ role = 'assistant'; content_json = [string]$r.Data.content_json })
        if ($r.Data.stop_reason -eq 'refusal') { $state.Refused = $true; return $state }

        $results = @()
        $waiting = @()
        foreach ($block in @($r.Data.content)) {
            if ($block.type -eq 'text' -and $block.text) { $state.Text = $block.text }
            if ($block.type -ne 'tool_use') { continue }
            if ($block.name -eq 'give_answer') { $state.Answer = $block.input; $waiting += @{ Kind = 'answer'; Id = $block.id }; continue }
            if ($block.name -eq 'ask_client') { $state.Question = $block.input; $waiting += @{ Kind = 'ask'; Id = $block.id }; continue }
            $code = [string]$block.input.code
            $value = [string]$block.input.input
            $key = "$code|$value"
            if ($cache.ContainsKey($key)) {
                $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = $cache[$key] }
                continue
            }
            $check = $null
            if ($checksRun -lt $script:AiMaxChecks) { $check = Get-HcAiCheck $code $value }
            if ($null -eq $check) {
                $why = if ($checksRun -ge $script:AiMaxChecks) { 'The limit of checks for this conversation is reached; call give_answer now.' } else { "Check $code could not run with that input." }
                $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = $why; is_error = $true }
                continue
            }
            $checksRun++
            Write-Step (T 'ai.running' $code (T "problem.$code"))
            $report = & $check
            $state.Reports[$code] = $report
            $state.Checks[$code] = $check
            $state.Inputs[$code] = $value
            $state.Ran += [pscustomobject]@{ Code = $code; Input = $value; Report = $report }
            $text = Format-HcReportForAi $report
            $cache[$key] = $text
            $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = $text }
        }
        # An answer, a question, or plain text: the turn is over, and the
        # replies to this turn's tool calls go along with the next message.
        if ($waiting.Count -or $results.Count -eq 0) {
            $state.Convo = @{ History = @($history); Pending = @($results); PendingIds = @($waiting); ChecksRun = $checksRun; Cache = $cache }
            return $state
        }
        [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $results) })
    }
    $state
}

<#
    One AI conversation for the text menu. Returns the answer (the
    give_answer input), plus the reports and checks it ran, so the menu can
    offer the fixes. A question back from the AI is asked on the console.
#>
function Invoke-HcAiConversation {
    param([string]$Problem)
    $all = [pscustomobject]@{ Answer = $null; Text = $null; Reports = @{}; Checks = @{}; Inputs = @{}; Error = $null; Refused = $false }
    $convo = New-HcAiConvo
    $text = New-HcAiFirstText $Problem
    for ($asked = 0; $asked -lt 3; $asked++) {
        $s = Invoke-HcAiTurn $convo $text
        foreach ($k in @($s.Reports.Keys)) { $all.Reports[$k] = $s.Reports[$k]; $all.Checks[$k] = $s.Checks[$k]; $all.Inputs[$k] = $s.Inputs[$k] }
        $all.Answer = $s.Answer; $all.Text = $s.Text; $all.Error = $s.Error; $all.Refused = $s.Refused
        if (-not $s.Question -or $s.Error -or $s.Answer) { break }
        # The question, with its answers numbered: a number or own words.
        $options = @($s.Question.options | Where-Object { $_ })
        Write-Host ''
        Write-HcLabelled (T 'ai.answer') ([string]$s.Question.question) 'Yellow'
        for ($i = 0; $i -lt $options.Count; $i++) { Write-Host ("     [$($i + 1)] " + [string]$options[$i]) }
        $reply = "$(Read-HcLine (T 'ai.reply'))".Trim()
        $n = 0
        if ([int]::TryParse($reply, [ref]$n) -and $n -ge 1 -and $n -le $options.Count) { $reply = [string]$options[$n - 1] }
        if (-not $reply) { $reply = T 'ai.noReply' }
        $convo = $s.Convo
        $text = $reply
    }
    $all
}

function Invoke-HcAi {
    param([pscustomobject]$Environment, [string]$Text)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ?  ' + (T 'ai.title')) -ForegroundColor Yellow
    Write-Host ''
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }
    if (-not (Unlock-HcRelay)) {
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }
    if ($Text) {
        Write-Dim (T 'ai.youTyped' $Text)
    } else {
        $Text = "$(Read-HcLine (T 'ai.describe'))".Trim()
        if (-not $Text -or $Text -eq 'Q') { return }
    }
    Write-Dim (T 'ai.privacy')
    Write-Host ''

    $state = Invoke-HcAiConversation $Text
    Write-Host ''
    if ($state.Error) {
        Write-Warn2 (Get-HcRelayMessage $state.Error)
    } elseif ($state.Refused) {
        Write-Warn2 (T 'ai.refused')
    } elseif (-not $state.Answer) {
        if ($state.Text) { Write-HcLabelled (T 'ai.answer') $state.Text 'Yellow' } else { Write-Warn2 (T 'ai.noAnswer') }
    } else {
        $a = $state.Answer
        Write-HcLabelled (T 'ai.answer') ([string]$a.summary) 'Yellow'
        Write-Dim (T ('ai.confidence.' + $a.confidence))
        $steps = @($a.steps | Where-Object { $_ })
        if ($steps.Count) {
            Write-Host ''
            Write-Host ('  ' + (T 'ai.steps')) -ForegroundColor Cyan
            for ($i = 0; $i -lt $steps.Count; $i++) { Write-HcLabelled "$($i + 1)." ([string]$steps[$i]) 'Cyan' }
        }
        $code = [string]$a.problem_code
        if ($state.Reports.ContainsKey($code)) {
            # The fixes the AI chose, from what that check offered, through the normal menu.
            $script:HcCurrentCode = $code
            Save-HcVisit $code $state.Reports[$code]
            Write-Host ''
            Write-HcReport $state.Reports[$code] -LinesOnly
            Invoke-HcReportLoop $code $state.Checks[$code] $state.Reports[$code] -OnlyFixes @($a.fix_ids | ForEach-Object { [string]$_ })
            return
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}
