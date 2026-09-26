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

<#
    One AI conversation. Returns the answer (the give_answer input), plus
    the reports and checks it ran, so the menu can offer the fixes.
#>
function Invoke-HcAiConversation {
    param([string]$Problem)
    $history = New-Object System.Collections.ArrayList
    $first = @(@{ type = 'text'; text = "[$script:Lang]`n$Problem" })
    [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $first) })

    $state = [pscustomobject]@{ Answer = $null; Text = $null; Reports = @{}; Checks = @{}; Error = $null; Refused = $false }
    $checksRun = 0
    for ($round = 0; $round -lt $script:AiMaxRounds; $round++) {
        Write-Dim (T 'ai.thinking')
        $r = Invoke-HcRelay @{ action = 'chat'; token = $script:HcToken; messages = @($history) }
        if (-not $r.Ok) { $state.Error = $r.Error; return $state }
        [void]$history.Add(@{ role = 'assistant'; content_json = [string]$r.Data.content_json })
        if ($r.Data.stop_reason -eq 'refusal') { $state.Refused = $true; return $state }

        $results = @()
        foreach ($block in @($r.Data.content)) {
            if ($block.type -eq 'text' -and $block.text) { $state.Text = $block.text }
            if ($block.type -ne 'tool_use') { continue }
            if ($block.name -eq 'give_answer') {
                $state.Answer = $block.input
                continue
            }
            $code = [string]$block.input.code
            $check = $null
            if ($checksRun -lt $script:AiMaxChecks) { $check = Get-HcAiCheck $code ([string]$block.input.input) }
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
            $results += @{ type = 'tool_result'; tool_use_id = $block.id; content = (Format-HcReportForAi $report) }
        }
        if ($state.Answer -or $results.Count -eq 0) { return $state }
        [void]$history.Add(@{ role = 'user'; content_json = (ConvertTo-HcContentJson $results) })
    }
    $state
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
