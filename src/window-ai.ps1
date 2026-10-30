<#
    The window's AI-hulp tab. Since 25 Oct a chat session, styled the way
    The technician liked in the preview: one calm column in the middle, his words in
    a soft bubble on the right, the AI's replies as plain text next to the
    house mark, the checks it ran as rows that fold open, and one rounded box
    at the bottom whose send button becomes Stop while it works.

    A conversation goes on after an answer: the AI can ask the client a
    question back (ask_client) with answers to click, the technician can ask more,
    edit his last message or try again. Each turn (Invoke-HcAiTurn, ai.ps1)
    runs in the worker, checks included. "/" opens commands; "+ Wat
    Housecall al weet" sends this visit's findings along with the first
    question; "Op het briefje" puts the AI's summary on the note and invoice.
    Without internet the box suggests the nearest problems from the menu.

    The AI never runs anything itself: it picks Housecall's own checks, and
    the fixes it names open in Problemen with the same Ja/Nee, check again
    and undo as always.
#>

function New-HcAiState {
    @{
        Stage = 'new'; Items = (New-Object System.Collections.ArrayList); Convo = $null; Reports = @{}
        Busy = $false; Live = ''; LiveStart = $null; LiveBlock = $null; StopAsked = $false; Job = $null
        SendKnown = $true; ShowKnown = $false; ToNote = $true; Effort = 'medium'; NextEffort = $null; AnswerLang = $null
        Extra = @(); Editing = $null; PendingSend = $null; Slash = @(); SlashSel = 0; Ui = $null; Speech = $null
    }
}

function Start-HcAi {
    $w = $script:HcWin
    $a = $w.Ai
    if (-not $w.Environment.Online) { $a.Stage = 'offline' }
    elseif (-not (Test-HcUnlocked)) { $a.Stage = 'code' }
    else { $a.Stage = 'chat' }
}

# ------------------------------------------------------------ pure parts --

# The problems the box can start straight away ("/c1"): every check of the
# menu except A3 and A4 (they need an address) and the phone ones.
function Get-HcAiDirectCodes {
    @($script:ProblemHandlers.Keys | Where-Object { $_ -match '^[A-G]\d$' -and $_ -notin @('A3', 'A4') } | Sort-Object)
}

# The "/" commands, in the order the list shows them.
$script:HcAiCommands = @('klant', 'voorlezen', 'stappen', 'briefje', 'eerder', 'grondig', 'snel', 'engels', 'nederlands', 'nieuw')

# What the "/" list shows for the text typed so far: commands first, then
# checks to start. Empty when the box does not start with a slash.
function Get-HcAiSlashItems {
    param([string]$Typed)
    if ($Typed -notmatch '^/(\S*)$') { return @() }
    $f = $Matches[1].ToLowerInvariant()
    $items = @()
    foreach ($c in $script:HcAiCommands) {
        if ($c.StartsWith($f)) { $items += [pscustomobject]@{ Cmd = "/$c"; Name = $c; Code = $null; Text = (T "win.ai.cmd.$c") } }
    }
    foreach ($code in @(Get-HcAiDirectCodes)) {
        $title = T "problem.$code"
        if ($code.ToLowerInvariant().StartsWith($f) -or ($f.Length -gt 2 -and $title.ToLowerInvariant().Contains($f))) {
            $items += [pscustomobject]@{ Cmd = '/' + $code.ToLowerInvariant(); Name = $null; Code = $code; Text = (T 'win.ai.toolTitle' $code $title) }
        }
    }
    $items
}

# Words that point to a problem when there is no AI (no internet). Besides
# these, the words of each problem's own title count too.
$script:HcAiHints = @{
    'internet' = 'A1 A2'; 'wifi' = 'A2 A1'; 'wlan' = 'A2'; 'netwerk' = 'A1 A2'; 'verbinding' = 'A1 A2'; 'router' = 'A1 A2'
    'mail' = 'A4'; 'email' = 'A4'; 'outlook' = 'A4'; 'website' = 'A3'; 'site' = 'A3'
    'geluid' = 'B1'; 'sound' = 'B1'; 'speaker' = 'B1'; 'horen' = 'B1 B2'; 'hoort' = 'B1 B2'; 'camera' = 'B2 F4'; 'microfoon' = 'B2 F4'
    'videobellen' = 'B2'; 'beeldbellen' = 'B2'; 'teams' = 'B2'; 'zoom' = 'B2'; 'scherm' = 'B3 B6'; 'groot' = 'B3 B5'; 'klein' = 'B3 B5'
    'donker' = 'B4 B3'; 'slaap' = 'B4'; 'groter' = 'B5'; 'lezen' = 'B5'; 'tweede' = 'B6'; 'beamer' = 'B6'; 'zwart' = 'B7'; 'spel' = 'B7'
    'printer' = 'C1'; 'printen' = 'C1'; 'afdrukken' = 'C1'; 'print' = 'C1'; 'muis' = 'C2'; 'toetsenbord' = 'C2'; 'usb' = 'C2'; 'stick' = 'C2'
    'bluetooth' = 'C3'; 'koptelefoon' = 'C3 B1'; 'accu' = 'C4'; 'batterij' = 'C4'; 'opladen' = 'C4'; 'touchpad' = 'C5'
    'traag' = 'D1'; 'langzaam' = 'D1'; 'sloom' = 'D1'; 'slow' = 'D1'; 'opstarten' = 'D2'; 'starten' = 'D2'; 'vastlopen' = 'D3'; 'loopt' = 'D3'
    'crash' = 'D3'; 'vol' = 'D4'; 'ruimte' = 'D4'; 'opslag' = 'D4'; 'uitvallen' = 'D5'; 'herstart' = 'D5'; 'zomaar' = 'D5'
    'heet' = 'D6'; 'warm' = 'D6'; 'lawaai' = 'D6'; 'ventilator' = 'D6'; 'herrie' = 'D6'
    'update' = 'E1'; 'updates' = 'E1'; 'bijwerken' = 'E1'; 'foutmelding' = 'E2'; 'melding' = 'E2'; 'fout' = 'E2'; 'afsluiten' = 'E3'; 'uitzetten' = 'E3'
    'reclame' = 'E5'; 'advertenties' = 'E5'; 'tips' = 'E5'; 'installeren' = 'E6'; 'programma' = 'E6 D3'
    'virus' = 'F1 F3'; 'popup' = 'F1'; 'belde' = 'F2'; 'gebeld' = 'F2'; 'helpdesk' = 'F2'; 'hacker' = 'F3 F2'; 'gehackt' = 'F3'; 'veilig' = 'F3'
    'browser' = 'F5'; 'zoekmachine' = 'F5'; 'startpagina' = 'F5'; 'bureaublad' = 'G1'; 'taakbalk' = 'G1'; 'iconen' = 'G1'
    'bestanden' = 'G2 G3'; 'kwijt' = 'G2 G3'; 'foto' = 'G4 G2'; "foto's" = 'G4 G2'; 'fotos' = 'G4 G2'; 'backup' = 'G4'; 'vinden' = 'G3'; 'zoeken' = 'G3'
}

# The problems that fit typed words best, at most three, best first.
function Get-HcAiNearest {
    param([string]$Text)
    $words = @(("$Text".ToLowerInvariant() -split "[^\p{L}\p{N}']+") | Where-Object { $_.Length -ge 3 })
    $score = @{}
    foreach ($word in $words) {
        if ($script:HcAiHints.ContainsKey($word)) {
            $weight = 3
            foreach ($code in ($script:HcAiHints[$word] -split ' ')) { $score[$code] = [int]$score[$code] + $weight; $weight = 1 }
        }
    }
    foreach ($code in @(Get-HcAiDirectCodes)) {
        $title = @(("$(T "problem.$code")".ToLowerInvariant() -split "[^\p{L}\p{N}']+") | Where-Object { $_.Length -ge 4 })
        foreach ($word in $words) { if ($title -contains $word) { $score[$code] = [int]$score[$code] + 2 } }
    }
    @($score.Keys | Where-Object { $score[$_] -gt 0 } | Sort-Object @{ Expression = { $score[$_] }; Descending = $true }, @{ Expression = { $_ } } | Select-Object -First 3)
}

# What goes to the AI for a message: the first one carries the language and
# what Housecall already knows; later ones a language switch and anything
# The technician ran himself in between.
function New-HcAiPayload {
    param([hashtable]$Ai, [string]$Text, $Environment)
    if (-not $Ai.Convo) {
        $known = if ($Ai.SendKnown) { @(Get-HcAiKnown $Environment) } else { @() }
        $lang = if ($Ai.AnswerLang) { $Ai.AnswerLang } else { $script:Lang }
        return (New-HcAiFirstText $Text $known $lang)
    }
    $parts = @()
    if ($Ai.AnswerLang) { $parts += "[$($Ai.AnswerLang)]" }
    $parts += @($Ai.Extra | Where-Object { $_ })
    $parts += $Text
    $parts -join "`n"
}

# The fold-open row of one check: what Housecall saw, and its finding.
function New-HcAiTool {
    param([string]$Code, $Report)
    $lines = @(@($Report.Results) | Select-Object -First 8 | ForEach-Object { [string]$_.Text })
    if ($Report.FindingId) { $all = @('finding.' + $Report.FindingId) + @($Report.FindingArgs); $lines += (T @all) }
    @{ Title = (T 'win.ai.toolTitle' $Code (T "problem.$Code")); Lines = $lines; Open = $false }
}

# The last answer in the conversation, or $null.
function Get-HcAiLastAnswer {
    param([hashtable]$Ai)
    for ($i = $Ai.Items.Count - 1; $i -ge 0; $i--) { if ($Ai.Items[$i].Answer) { return $Ai.Items[$i].Answer } }
    $null
}

# "Op het briefje": the summary on the note and the invoice, once.
function Add-HcAiNote {
    param([string]$Summary)
    $s = "$Summary".Trim()
    if (-not $s -or $script:HcAiNotes -contains $s) { return }
    [void]$script:HcAiNotes.Add($s)
}

# ------------------------------------------------------------- sending --

function Send-HcAiText {
    param([string]$Text, [switch]$Big, [string]$Payload)
    $w = $script:HcWin
    $a = $w.Ai
    $t = "$Text".Trim()
    if (-not $t -or $a.Busy -or (Test-HcBusy)) { return }
    # An edited message replaces itself and everything after it.
    if ($null -ne $a.Editing) {
        $me = $a.Items[$a.Editing]
        $a.Convo = $me.Before
        while ($a.Items.Count -gt $a.Editing) { $a.Items.RemoveAt($a.Items.Count - 1) }
        $a.Editing = $null
    }
    foreach ($i in $a.Items) { if ($i.Question) { $i.Answered = $true } }
    if (-not $w.Environment.Online) {
        [void]$a.Items.Add(@{ Kind = 'me'; Text = $t })
        $near = @(Get-HcAiNearest $t)
        $item = @{ Kind = 'ai'; Tools = @(); Text = $(if ($near.Count) { T 'win.ai.offlineMsg' } else { T 'win.ai.offlineNone' }); Codes = $near }
        [void]$a.Items.Add($item)
        Update-HcAiPanel
        return
    }
    if (-not (Test-HcUnlocked)) { $a.PendingSend = $t; $a.Stage = 'code'; Update-HcAiPanel; return }
    $body = if ($Payload) { $Payload } else { New-HcAiPayload $a $t $w.Environment }
    [void]$a.Items.Add(@{ Kind = 'me'; Text = $t; Before = $a.Convo; Payload = $body })
    $item = @{ Kind = 'ai'; Tools = @(); Busy = $true; Big = [bool]$Big }
    [void]$a.Items.Add($item)
    Start-HcAiJob $body $item
}

function Start-HcAiJob {
    param([string]$Body, [hashtable]$Item)
    $w = $script:HcWin
    $a = $w.Ai
    $a.Extra = @()
    $effort = if ($a.NextEffort) { $a.NextEffort } else { $a.Effort }
    $a.NextEffort = $null
    $a.Busy = $true
    $a.StopAsked = $false
    $a.Live = T 'win.ai.thinking'
    $a.LiveStart = Get-Date
    $job = @{ Kind = 'ai'; Text = $Body; Body = @{ Token = $script:HcToken; Expires = $script:HcTokenExpires; Convo = $a.Convo; Effort = $effort }
              Seen = 0; Live = 'Update-HcAiProgress'; Done = 'Complete-HcAi'; Item = $Item }
    $a.Job = $job
    Add-HcJob $job
    Update-HcAiPanel
    Update-HcSide
}

# While the AI works: what it is doing, with the seconds, without redrawing.
function Update-HcAiProgress {
    param([hashtable]$Job)
    $a = $script:HcWin.Ai
    $lines = @($Job.PS.Streams.Information | ForEach-Object { "$($_.MessageData)".Trim() } | Where-Object { $_ })
    if ($lines.Count -ne $Job.Seen) {
        $Job.Seen = $lines.Count
        $last = $lines[-1]
        $running = @($lines | Where-Object { $_ -ne (T 'ai.thinking') })
        $a.Live = if ($last -eq (T 'ai.thinking') -and $running.Count) { T 'win.ai.reading' } elseif ($last -eq (T 'ai.thinking')) { T 'win.ai.thinking' }
                  elseif ($last -match '\b([A-G]\d)\b') { T 'win.ai.checking' $Matches[1] (T "problem.$($Matches[1])") } else { $last }
    }
    if ($a.LiveBlock -and $a.LiveStart) {
        $a.LiveBlock.Text = $a.Live + '   ' + [int]((Get-Date) - $a.LiveStart).TotalSeconds + ' s'
    }
}

function Complete-HcAi {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $a = $w.Ai
    $item = $Job.Item
    $item.Busy = $false
    $a.Busy = $false
    $a.Job = $null
    $a.LiveBlock = $null
    $state = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Answer'] -and $_.PSObject.Properties['Convo'] }) | Select-Object -Last 1
    if ($a.StopAsked) {
        $a.StopAsked = $false
        $item.Text = T 'win.ai.stopped'
    } elseif ($ErrorText -or -not $state) {
        $item.Error = T 'win.error' $(if ($ErrorText) { $ErrorText } else { '-' })
    } elseif ($state.Error) {
        if ($state.Error -eq 'locked_out') { $script:HcToken = $null }
        $item.Error = Get-HcRelayMessage $state.Error
    } elseif ($state.Refused) {
        $item.Error = T 'win.ai.refused'
    } else {
        $a.Convo = $state.Convo
        foreach ($r in @($state.Ran)) {
            $item.Tools += (New-HcAiTool $r.Code $r.Report)
            $a.Reports[$r.Code] = $r.Report
            # The checks the AI ran count as opened this visit, as in the text menu.
            $w.Reports[$r.Code] = $r.Report
            if ($state.Inputs.ContainsKey($r.Code)) { $w.Inputs[$r.Code] = $state.Inputs[$r.Code] }
        }
        if ($state.Question) {
            $item.Question = [string]$state.Question.question
            $item.Options = @($state.Question.options | Where-Object { $_ } | ForEach-Object { [string]$_ })
            $item.Answered = $false
        }
        if ($state.Answer) {
            $answer = $state.Answer
            $item.Answer = $answer
            $problems = @()
            foreach ($p in @(@{ code = $answer.problem_code; fix_ids = $answer.fix_ids }) + @($answer.more_problems)) {
                $code = [string]$p.code
                if ($code -and $a.Reports.ContainsKey($code) -and -not @($problems | Where-Object { $_.Code -eq $code }).Count) {
                    $problems += @{ Code = $code; FixIds = @($p.fix_ids | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
                    Save-HcVisit $code $a.Reports[$code]
                }
            }
            $item.Problems = $problems
            if ($a.ToNote -and -not $item.Big -and "$($answer.summary)".Trim()) { Add-HcAiNote $answer.summary; $item.Noted = $true }
        }
        if (-not $state.Question -and -not $state.Answer) {
            $item.Text = if ($state.Text) { [string]$state.Text } else { T 'win.ai.noAnswer' }
        }
    }
    Update-HcAiPanel
    Update-HcSide
}

# Stop: the worker's pipeline is stopped; the turn is dropped.
function Stop-HcAi {
    $w = $script:HcWin
    $a = $w.Ai
    if (-not $a.Busy) { return }
    $a.StopAsked = $true
    if ($w.Job -and $w.Job -eq $a.Job -and $w.Job.PS) { [void]$w.Job.PS.BeginStop($null, $null) }
    elseif ($a.Job) { $w.Queue.Remove($a.Job); & $a.Job.Done $a.Job @() 'stopped' @() }
}

# "Show the fixes": the report of that problem, in Problemen, with only the
# fixes the AI chose (all of them after a re-check).
function Open-HcAiFixes {
    param([string]$Code, [string[]]$FixIds, [switch]$All)
    $w = $script:HcWin
    $report = $w.Ai.Reports[$Code]
    if (-not $report) { return }
    if (-not $All) { Select-HcActions $report @($FixIds) }
    $w.Tab = 'problems'
    $w.Code = $Code
    $w.Report = $report
    $w.FromAll = $false
    Clear-HcMessages
    $w.View = 'report'
    $script:HcCurrentCode = $Code
    Update-HcTabs
    Update-HcGroups
    Update-HcResult
}

# ------------------------------------------------------------ commands --

function Invoke-HcAiCommand {
    param($Item)
    $w = $script:HcWin
    $a = $w.Ai
    $a.Ui.Box.Text = ''
    $local = { param($text, [string[]]$lines = @()) [void]$a.Items.Add(@{ Kind = 'ai'; Tools = @(); Text = $text; Lines = $lines }) }
    if ($Item.Code) {
        # A check started from the box: run like in Problemen; the AI hears of it with the next message.
        if ($a.Busy -or (Test-HcBusy)) { return }
        [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
        $ai = @{ Kind = 'ai'; Tools = @(); Busy = $true; Direct = $Item.Code }
        [void]$a.Items.Add($ai)
        $a.Busy = $true; $a.Live = T 'win.ai.checking' $Item.Code (T "problem.$($Item.Code)"); $a.LiveStart = Get-Date
        $job = @{ Kind = 'check'; Code = $Item.Code; Text = ''; Item = $ai; Seen = 0; Live = 'Update-HcAiProgress'; Done = 'Complete-HcAiDirect' }
        $a.Job = $job
        Add-HcJob $job
        Update-HcAiPanel
        return
    }
    $last = Get-HcAiLastAnswer $a
    switch ($Item.Name) {
        'nieuw' { Reset-HcAi; return }
        'klant' {
            if (-not $last -or -not $a.Convo) { & $local (T 'win.ai.needAnswer'); break }
            Send-HcAiText $Item.Cmd -Big -Payload ((New-HcAiPayload $a 'Explain your last answer for the client in two or three very short, simple sentences.' $w.Environment))
            return
        }
        'voorlezen' {
            if (-not $last) { & $local (T 'win.ai.needAnswer'); break }
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            & $local $(if (Invoke-HcAiSpeak ([string]$last.summary)) { T 'win.ai.readingAloud' } else { T 'win.ai.noVoice' })
        }
        'stappen' {
            if (-not $last) { & $local (T 'win.ai.needAnswer'); break }
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            $script:HcInvoicePages = @(Get-HcBigSheetLayout (T 'win.ai.stepsTitle') ([string]$last.summary) @($last.steps | ForEach-Object { [string]$_ }))
            Update-HcAiPanel
            Invoke-HcInvoicePrint
            return
        }
        'briefje' {
            if (-not $last) { & $local (T 'win.ai.needAnswer'); break }
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            Add-HcAiNote $last.summary
            & $local (T 'win.ai.notedNow')
        }
        'eerder' {
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            $visits = @($w.Hist.Visits)
            if ($w.Hist.Stage -ne 'list') {
                if (-not (Test-HcUnlocked) -or (Test-HcBusy)) { & $local (T 'win.ai.earlierNone'); break }
                Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'visit_get'; token = $script:HcToken; pc = (Get-HcWindowPcId) }; Done = 'Complete-HcAiEarlier' }
                break
            }
            Add-HcAiEarlier $visits
        }
        { $_ -in @('grondig', 'snel') } {
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            $a.NextEffort = if ($Item.Name -eq 'grondig') { 'high' } else { 'low' }
            & $local (T "win.ai.effortNext.$($a.NextEffort)")
        }
        { $_ -in @('engels', 'nederlands') } {
            [void]$a.Items.Add(@{ Kind = 'me'; Text = $Item.Cmd })
            $a.AnswerLang = if ($Item.Name -eq 'engels') { 'en' } else { 'nl' }
            & $local (T "win.ai.langNow.$($a.AnswerLang)")
        }
    }
    Update-HcAiPanel
}

function Complete-HcAiDirect {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $a = $w.Ai
    $item = $Job.Item
    $item.Busy = $false; $a.Busy = $false; $a.Job = $null; $a.LiveBlock = $null
    $report = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Results'] }) | Select-Object -Last 1
    if ($a.StopAsked) {
        $a.StopAsked = $false
        $item.Text = T 'win.ai.stopped'
    } elseif ($ErrorText -or -not $report) {
        $item.Error = T 'win.error' $(if ($ErrorText) { $ErrorText } else { '-' })
    } else {
        $code = $Job.Code
        $a.Reports[$code] = $report
        $w.Reports[$code] = $report
        Save-HcVisit $code $report
        $item.Tools = @(New-HcAiTool $code $report)
        $item.Text = T 'win.ai.direct' $code
        $item.Problems = @(@{ Code = $code; FixIds = @(@($report.Actions) | ForEach-Object { [string]$_.FixId }); All = $true })
        # The AI hears of it with the technician's next message.
        $a.Extra += "The technician ran check $code himself:`n$(Format-HcReportForAi $report)"
    }
    Update-HcAiPanel
    Update-HcSide
}

function Complete-HcAiEarlier {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $r = Get-HcRelayResult $Output
    Add-HcAiEarlier $(if (-not $ErrorText -and $r -and $r.Ok) { @($r.Data.visits | Where-Object { $_ }) } else { @() })
    Update-HcAiPanel
}

function Add-HcAiEarlier {
    param([object[]]$Visits)
    $a = $script:HcWin.Ai
    $lines = @($Visits | Where-Object { $_ } | Select-Object -First 5 | ForEach-Object {
        $l = Format-HcVisitLine $_
        $codes = @($_.problems | ForEach-Object { $_.code }) -join ', '
        if ($codes) { $l += ': ' + $codes }
        $l })
    [void]$a.Items.Add(@{ Kind = 'ai'; Tools = @(); Text = $(if ($lines.Count) { T 'win.ai.earlier' } else { T 'win.ai.earlierNone' }); Lines = $lines })
}

# Reads a text aloud with Windows' own voice, Dutch when there is one. $false when there is no voice.
function Invoke-HcAiSpeak {
    param([string]$Text)
    $a = $script:HcWin.Ai
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        if (-not $a.Speech) { $a.Speech = New-Object System.Speech.Synthesis.SpeechSynthesizer }
        $voice = @($a.Speech.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like "$script:Lang*" }) | Select-Object -First 1
        if ($voice) { $a.Speech.SelectVoice($voice.VoiceInfo.Name) }
        $a.Speech.Rate = -1
        $a.Speech.SpeakAsyncCancelAll()
        [void]$a.Speech.SpeakAsync($Text)
        $true
    } catch { $false }
}

function Reset-HcAi {
    $w = $script:HcWin
    $old = $w.Ai
    if ($old.Busy) { return }
    try { if ($old.Speech) { $old.Speech.SpeakAsyncCancelAll() } } catch { }
    $new = New-HcAiState
    # The box and the switches stay as they were.
    foreach ($k in @('Ui', 'SendKnown', 'ToNote', 'Effort', 'Speech')) { $new[$k] = $old[$k] }
    $w.Ai = $new
    Start-HcAi
    if ($new.Ui) { $new.Ui.Box.Text = '' }
    Update-HcAiPanel
}

# After the code: the message that was waiting for it goes out.
function Resume-HcAiAfterUnlock {
    $a = $script:HcWin.Ai
    $a.Stage = 'chat'
    $text = $a.PendingSend
    $a.PendingSend = $null
    if ($text) { Send-HcAiText $text } else { Update-HcAiPanel }
}

# ------------------------------------------------------------- painting --

# The house mark of the AI's replies, drawn like the window's own logo.
function New-HcAiMark {
    param([double]$Size = 26)
    $xaml = '<Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="{0}" Height="{0}"><Canvas Width="64" Height="64">' -f $Size
    $xaml += '<Path Data="M6,33 L28,14 L50,33" Stroke="{DynamicResource Text}" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>'
    $xaml += '<Path Data="M13,31 V54 A3,3 0 0 0 16,57 H40 A3,3 0 0 0 43,54 V31" Stroke="{DynamicResource Text}" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>'
    $xaml += '<Rectangle Canvas.Left="23" Canvas.Top="41" Width="10" Height="16" RadiusX="2" RadiusY="2" Fill="{DynamicResource Text}"/>'
    $xaml += '<Path Data="M46,16 A8,8 0 0 1 52,22" Stroke="{DynamicResource Hi}" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>'
    $xaml += '<Path Data="M47,7.5 A16,16 0 0 1 60.5,21" Stroke="{DynamicResource Hi}" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/></Canvas></Viewbox>'
    [Windows.Markup.XamlReader]::Parse($xaml)
}

# The AI's words: a reading font, a little larger, like a chat session.
function New-HcAiText {
    param([string]$Text, [double]$Size = 16, [string]$Brush = 'Text', [switch]$Bold, [double[]]$Margin = @(0, 0, 0, 8))
    $t = New-HcText $Text $Size $Brush -Bold:$Bold -Margin $Margin
    $t.FontFamily = New-Object Windows.Media.FontFamily('Georgia')
    $t.LineHeight = $Size * 1.5
    $t
}

function Update-HcAiPanel {
    $w = $script:HcWin
    $a = $w.Ai
    $thread = $w.Window.FindName('AiThread')
    if (-not $thread) { return }
    if ($a.Stage -eq 'new') { Start-HcAi }
    # Online again, or unlocked from another tab: the stage follows.
    if ($a.Stage -in @('offline', 'chat') -or ($a.Stage -eq 'code' -and (Test-HcUnlocked))) { Start-HcAi }
    $thread.Children.Clear()
    $add = { param($element) [void]$thread.Children.Add($element) }

    if ($a.Items.Count) {
        $top = New-Object Windows.Controls.DockPanel
        $top.Margin = New-HcThickness @(0, 0, 0, 10)
        $new = New-HcButton (T 'win.ai.new') @{ Do = 'aiNew' }
        $new.IsEnabled = -not $a.Busy
        [Windows.Controls.DockPanel]::SetDock($new, 'Right')
        [void]$top.Children.Add($new)
        [void]$top.Children.Add((New-HcText (T 'win.tab.ai') 14 'Soft' -Bold -Margin @(0, 9, 0, 0)))
        & $add $top
    }
    if ($a.Stage -eq 'code') { & $add (New-HcCodeBox 'ai' (T 'win.ai.codeIntro')) }

    if (-not $a.Items.Count) {
        # The welcome: the mark, one question, examples to click.
        $hello = New-Object Windows.Controls.StackPanel
        $hello.HorizontalAlignment = 'Center'
        $hello.Margin = New-HcThickness @(0, 70, 0, 20)
        $row = New-Object Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $row.HorizontalAlignment = 'Center'
        $mark = New-HcAiMark 38
        $mark.Margin = New-HcThickness @(0, 4, 14, 0)
        [void]$row.Children.Add($mark)
        $title = New-HcAiText (T 'win.ai.welcome') 30 -Margin @(0, 0, 0, 0)
        [void]$row.Children.Add($title)
        [void]$hello.Children.Add($row)
        if ($a.Stage -eq 'offline') { [void]$hello.Children.Add((New-HcText (T 'win.ai.offlineHint') 14 'Soft' -Margin @(0, 14, 0, 0))) }
        $chips = New-Object Windows.Controls.WrapPanel
        $chips.HorizontalAlignment = 'Center'
        $chips.Margin = New-HcThickness @(0, 22, 0, 0)
        foreach ($e in @((T 'win.ai.example') -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            [void]$chips.Children.Add((New-HcChip $e @{ Do = 'aiExample'; Text = $e }))
        }
        [void]$hello.Children.Add($chips)
        & $add $hello
    }

    $lastMe = -1; $lastAi = -1
    for ($i = 0; $i -lt $a.Items.Count; $i++) { if ($a.Items[$i].Kind -eq 'me') { $lastMe = $i } else { $lastAi = $i } }
    for ($i = 0; $i -lt $a.Items.Count; $i++) {
        $it = $a.Items[$i]
        if ($it.Kind -eq 'me') { & $add (New-HcAiMine $it $i ($i -eq $lastMe -and -not $a.Busy -and [bool]$it.Payload)) }
        else { & $add (New-HcAiReply $it $i ($i -eq $lastAi -and $lastAi -gt $lastMe -and -not $a.Busy)) }
    }
    Update-HcAiDock
    $scroll = $w.Window.FindName('AiScroll')
    if ($scroll) { $scroll.UpdateLayout(); $scroll.ScrollToEnd() }
}

# The technician's message: a soft bubble on the right; the last one can be edited.
function New-HcAiMine {
    param([hashtable]$Item, [int]$Index, [bool]$CanEdit)
    $stack = New-Object Windows.Controls.StackPanel
    $stack.HorizontalAlignment = 'Right'
    $stack.Margin = New-HcThickness @(80, 4, 0, 12)
    $bubble = New-Object Windows.Controls.Border
    $bubble.CornerRadius = New-Object Windows.CornerRadius(18)
    $bubble.Padding = New-HcThickness @(16, 10, 16, 10)
    $bubble.HorizontalAlignment = 'Right'
    $bubble.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Side')
    $bubble.Child = New-HcText $Item.Text 15.5 'Text' -Margin @(0, 0, 0, 0)
    [void]$stack.Children.Add($bubble)
    if ($CanEdit -and $Item.Payload) {
        $edit = New-HcButton (T 'win.ai.edit') @{ Do = 'aiEdit'; Index = $Index } 'HcQuiet'
        $edit.HorizontalAlignment = 'Right'
        [void]$stack.Children.Add($edit)
    }
    $stack
}

# The AI's reply: the mark, then plain text, check rows, a question with
# answers, the problems with their buttons, steps and next questions.
function New-HcAiReply {
    param([hashtable]$Item, [int]$Index, [bool]$IsLast)
    $a = $script:HcWin.Ai
    $row = New-Object Windows.Controls.DockPanel
    $row.Margin = New-HcThickness @(0, 4, 0, 16)
    $mark = New-HcAiMark 26
    $mark.VerticalAlignment = 'Top'
    $mark.Margin = New-HcThickness @(0, 2, 14, 0)
    [Windows.Controls.DockPanel]::SetDock($mark, 'Left')
    [void]$row.Children.Add($mark)
    $body = New-Object Windows.Controls.StackPanel
    [void]$row.Children.Add($body)
    $put = { param($element) [void]$body.Children.Add($element) }

    for ($t = 0; $t -lt @($Item.Tools).Count; $t++) {
        $tool = $Item.Tools[$t]
        $box = New-Object Windows.Controls.Border
        $box.CornerRadius = New-Object Windows.CornerRadius(10)
        $box.BorderThickness = New-HcThickness @(1, 1, 1, 1)
        $box.Margin = New-HcThickness @(0, 0, 0, 8)
        $box.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
        $box.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
        $inner = New-Object Windows.Controls.StackPanel
        $arrow = if ($tool.Open) { [string][char]0x25BE } else { [string][char]0x25B8 }
        $head = New-HcButton ($arrow + '  ' + $tool.Title) @{ Do = 'aiTool'; Index = $Index; Tool = $t } 'HcQuiet'
        $head.HorizontalAlignment = 'Stretch'
        $head.Padding = New-HcThickness @(10, 6, 10, 6)
        [void]$inner.Children.Add($head)
        if ($tool.Open) {
            foreach ($l in @($tool.Lines)) { [void]$inner.Children.Add((New-HcText ([string][char]0x2022 + '  ' + $l) 13.5 'Text' -Margin @(30, 0, 10, 3))) }
            [void]$inner.Children.Add((New-HcText '' 4 -Margin @(0, 0, 0, 4)))
        }
        $box.Child = $inner
        & $put $box
    }
    if ($Item.Busy) {
        $live = New-HcText ($a.Live + '   0 s') 14.5 'Soft' -Margin @(0, 4, 0, 0)
        $live.FontStyle = 'Italic'
        $a.LiveBlock = $live
        & $put $live
        $row
        return
    }
    if ($Item.Error) { & $put (New-HcText $Item.Error 15 'Warn' -Bold) }
    if ($Item.Text) { & $put (New-HcAiText $Item.Text) }
    foreach ($l in @($Item.Lines | Where-Object { $_ })) { & $put (New-HcAiText ([string][char]0x2022 + '  ' + $l) 15 -Margin @(0, 0, 0, 4)) }
    # Without internet: the nearest problems, straight into Problemen.
    foreach ($code in @($Item.Codes | Where-Object { $_ })) {
        $b = New-HcButton ($code + '   ' + (T "problem.$code")) @{ Do = 'problem'; Code = $code }
        $b.HorizontalAlignment = 'Left'
        & $put $b
    }

    if ($Item.Question) {
        & $put (New-HcAiText $Item.Question -Bold)
        foreach ($o in @($Item.Options)) {
            $b = New-HcButton $o @{ Do = 'aiOption'; Text = $o }
            $b.HorizontalAlignment = 'Stretch'
            $b.IsEnabled = -not $Item.Answered -and -not $a.Busy
            & $put $b
        }
        if (-not $Item.Answered) { & $put (New-HcText (T 'win.ai.orType') 13 'Soft') }
    }

    $answer = $Item.Answer
    if ($answer) {
        if ($Item.Big) {
            $big = New-Object Windows.Controls.Border
            $big.BorderThickness = New-HcThickness @(2, 2, 2, 2)
            $big.CornerRadius = New-Object Windows.CornerRadius(12)
            $big.Padding = New-HcThickness @(20, 16, 20, 16)
            $big.Margin = New-HcThickness @(0, 0, 0, 8)
            $big.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Text')
            $big.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
            $big.Child = New-HcText ([string]$answer.summary) 26 'Text' -Bold -Margin @(0, 0, 0, 0)
            & $put $big
        } else {
            & $put (New-HcAiText ([string]$answer.summary))
            if ($answer.confidence) { & $put (New-HcText (T ('ai.confidence.' + $answer.confidence)) 13 'Soft') }
        }
    }
    foreach ($p in @($Item.Problems | Where-Object { $_ })) {
        $card = New-Object Windows.Controls.Border
        $card.CornerRadius = New-Object Windows.CornerRadius(12)
        $card.BorderThickness = New-HcThickness @(1, 1, 1, 1)
        $card.Padding = New-HcThickness @(14, 8, 8, 0)
        $card.Margin = New-HcThickness @(0, 4, 0, 6)
        $card.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
        $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
        $dock = New-Object Windows.Controls.DockPanel
        $go = New-HcButton (T 'win.ai.look') @{ Do = 'aiFixes'; Code = $p.Code; FixIds = @($p.FixIds); All = [bool]$p.All } 'HcPrimary'
        [Windows.Controls.DockPanel]::SetDock($go, 'Right')
        [void]$dock.Children.Add($go)
        $n = @($p.FixIds).Count
        $what = if ($n -eq 1) { T 'win.ai.fixesOne' } elseif ($n -gt 1) { T 'win.ai.fixesMany' $n } else { T 'win.ai.noFixes' }
        [void]$dock.Children.Add((New-HcText ($p.Code + '   ' + (T "problem.$($p.Code)") + '  ' + [char]0x00B7 + '  ' + $what) 14.5 'Text' -Bold -Margin @(0, 7, 8, 8)))
        $card.Child = $dock
        & $put $card
    }
    if ($answer -and -not $Item.Big) {
        $steps = @($answer.steps | Where-Object { $_ })
        if ($steps.Count) {
            & $put (New-HcAiText (T 'win.ai.selfDo') -Margin @(0, 6, 0, 4))
            for ($s = 0; $s -lt $steps.Count; $s++) { & $put (New-HcAiText ("$($s + 1).  " + [string]$steps[$s]) 15.5 -Margin @(8, 0, 0, 4)) }
        }
        if ($Item.Noted) { & $put (New-HcText ([string][char]0x2713 + '  ' + (T 'win.ai.noted')) 13 'Soft' -Margin @(0, 6, 0, 0)) }
        $follow = @($answer.follow_ups | Where-Object { $_ })
        if ($IsLast -and $follow.Count) {
            $wrap = New-Object Windows.Controls.WrapPanel
            $wrap.Margin = New-HcThickness @(0, 8, 0, 0)
            foreach ($f in $follow) { [void]$wrap.Children.Add((New-HcChip ([string]$f) @{ Do = 'aiSend'; Text = [string]$f })) }
            & $put $wrap
        }
    }
    if ($IsLast -and -not $Item.Direct -and ($answer -or $Item.Error -or $Item.Question)) {
        $again = New-HcButton (T 'win.ai.retry') @{ Do = 'aiRetry' } 'HcQuiet'
        $again.HorizontalAlignment = 'Left'
        & $put $again
    }
    $row
}

# The box at the bottom, built once so what is typed and the cursor stay;
# each update only changes labels, the slash list and the send button.
function Update-HcAiDock {
    $w = $script:HcWin
    $a = $w.Ai
    $dock = $w.Window.FindName('AiDock')
    if (-not $a.Ui -or -not $dock.Children.Contains($a.Ui.Root)) { New-HcAiDock }
    $ui = $a.Ui
    # The "/" list.
    $ui.Slash.Children.Clear()
    $items = @(Get-HcAiSlashItems $ui.Box.Text)
    $a.Slash = $items
    if ($a.SlashSel -ge $items.Count) { $a.SlashSel = 0 }
    $ui.SlashBox.Visibility = if ($items.Count) { 'Visible' } else { 'Collapsed' }
    $heads = @{}
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $kind = if ($it.Code) { 'checks' } else { 'cmds' }
        if (-not $heads[$kind]) { [void]$ui.Slash.Children.Add((New-HcText (T "win.ai.slash.$kind") 11.5 'Soft' -Bold -Margin @(8, 4, 0, 2))); $heads[$kind] = $true }
        $b = New-HcButton ($it.Cmd + '    ' + $it.Text) @{ Do = 'aiSlash'; Index = $i } $(if ($i -eq $a.SlashSel) { 'HcPrimary' } else { 'HcQuiet' })
        $b.HorizontalAlignment = 'Stretch'
        $b.Margin = New-HcThickness @(0, 0, 0, 2)
        $b.Focusable = $false
        [void]$ui.Slash.Children.Add($b)
    }
    # What Housecall already knows.
    $known = @(Get-HcAiKnown $w.Environment)
    $ui.Known.Content = '+  ' + (T 'win.ai.known' $known.Count)
    $ui.Known.Style = $w.Window.FindResource($(if ($a.SendKnown -and $known.Count) { 'HcPrimary' } else { 'HcButton' }))
    $ui.KnownBox.Visibility = if ($a.ShowKnown) { 'Visible' } else { 'Collapsed' }
    $ui.KnownList.Children.Clear()
    if ($known.Count) { foreach ($k in $known) { [void]$ui.KnownList.Children.Add((New-HcText ([string][char]0x2022 + '  ' + $k) 13.5 'Text' -Margin @(0, 0, 0, 3))) } }
    else { [void]$ui.KnownList.Children.Add((New-HcText (T 'win.ai.knownNone') 13.5 'Soft')) }
    $ui.KnownCheck.IsChecked = [bool]$a.SendKnown
    $ui.Note.Content = if ($a.ToNote) { T 'win.ai.note' } else { T 'win.ai.noteOff' }
    $ui.Note.Style = $w.Window.FindResource($(if ($a.ToNote) { 'HcPrimary' } else { 'HcButton' }))
    $ui.Effort.Content = T "win.ai.effort.$($a.Effort)"
    foreach ($b in @($ui.Known, $ui.Note, $ui.Effort)) { $b.Padding = New-HcThickness @(11, 4, 11, 4); $b.Margin = New-HcThickness @(0, 0, 6, 0); $b.FontSize = 13 }
    # Send, or Stop while it works.
    $ui.Send.Content = if ($a.Busy) { [string][char]0x25A0 } else { [string][char]0x2191 }
    $ui.Send.ToolTip = if ($a.Busy) { T 'win.ai.stop' } else { T 'win.ai.send' }
    $ui.Send.Tag = @{ Do = $(if ($a.Busy) { 'aiStop' } else { 'aiSendBox' }) }
    $ui.Send.IsEnabled = $a.Busy -or [bool]"$($ui.Box.Text)".Trim()
    $ui.Hint.Text = if ($a.Items.Count) { T 'win.ai.placeholderNext' } else { T 'win.ai.placeholderFirst' }
    $ui.Hint.Visibility = if ("$($ui.Box.Text)") { 'Collapsed' } else { 'Visible' }
}

function New-HcAiDock {
    $w = $script:HcWin
    $a = $w.Ai
    $dock = $w.Window.FindName('AiDock')
    $dock.Children.Clear()
    $root = New-Object Windows.Controls.StackPanel
    $ui = @{ Root = $root }

    $slashBox = New-Object Windows.Controls.Border
    $slashBox.CornerRadius = New-Object Windows.CornerRadius(14)
    $slashBox.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $slashBox.Padding = New-HcThickness @(6, 6, 6, 6)
    $slashBox.Margin = New-HcThickness @(0, 0, 0, 6)
    $slashBox.MaxHeight = 280
    $slashBox.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
    $slashBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $slashScroll = New-Object Windows.Controls.ScrollViewer
    $slashScroll.VerticalScrollBarVisibility = 'Auto'
    $ui.Slash = New-Object Windows.Controls.StackPanel
    $slashScroll.Content = $ui.Slash
    $slashBox.Child = $slashScroll
    $ui.SlashBox = $slashBox
    [void]$root.Children.Add($slashBox)

    $knownBox = New-Object Windows.Controls.Border
    $knownBox.CornerRadius = New-Object Windows.CornerRadius(14)
    $knownBox.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $knownBox.Padding = New-HcThickness @(14, 10, 14, 8)
    $knownBox.Margin = New-HcThickness @(0, 0, 0, 6)
    $knownBox.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
    $knownBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $knownStack = New-Object Windows.Controls.StackPanel
    $ui.KnownList = New-Object Windows.Controls.StackPanel
    [void]$knownStack.Children.Add($ui.KnownList)
    $check = New-Object Windows.Controls.CheckBox
    $check.Content = T 'win.ai.knownSend'
    $check.Margin = New-HcThickness @(0, 6, 0, 4)
    $check.Tag = @{ Do = 'aiKnownSend' }
    $check.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $check.Add_Click({ Invoke-HcClick $this })
    $ui.KnownCheck = $check
    [void]$knownStack.Children.Add($check)
    [void]$knownStack.Children.Add((New-HcText (T 'win.ai.knownNote') 12.5 'Soft' -Margin @(0, 0, 0, 2)))
    $knownBox.Child = $knownStack
    $ui.KnownBox = $knownBox
    [void]$root.Children.Add($knownBox)

    # The rounded box: what is typed, then the switches and the send button.
    $composer = New-Object Windows.Controls.Border
    $composer.CornerRadius = New-Object Windows.CornerRadius(20)
    $composer.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $composer.Padding = New-HcThickness @(16, 12, 10, 10)
    $composer.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
    $composer.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $stack = New-Object Windows.Controls.StackPanel
    $grid = New-Object Windows.Controls.Grid
    $hint = New-HcText '' 16 'Soft' -Margin @(2, 1, 0, 0)
    $hint.IsHitTestVisible = $false
    $ui.Hint = $hint
    $box = New-Object Windows.Controls.TextBox
    $box.FontSize = 16
    $box.TextWrapping = 'Wrap'
    $box.AcceptsReturn = $true
    $box.MinHeight = 28
    $box.MaxHeight = 160
    $box.VerticalScrollBarVisibility = 'Auto'
    $box.BorderThickness = New-HcThickness @(0, 0, 0, 0)
    $box.Background = [Windows.Media.Brushes]::Transparent
    $box.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $box.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Text')
    $box.Add_TextChanged({ $script:HcWin.Ai.SlashSel = 0; Update-HcAiDock })
    $box.Add_PreviewKeyDown({ Invoke-HcAiKey $_ })
    $ui.Box = $box
    [void]$grid.Children.Add($hint)
    [void]$grid.Children.Add($box)
    [void]$stack.Children.Add($grid)

    $tools = New-Object Windows.Controls.DockPanel
    $tools.Margin = New-HcThickness @(0, 8, 0, 0)
    $send = New-HcButton ([string][char]0x2191) @{ Do = 'aiSendBox' } 'HcPrimary'
    $send.Width = 40
    $send.Height = 38
    $send.Margin = New-HcThickness @(0, 0, 0, 0)
    $send.Padding = New-HcThickness @(0, 0, 0, 0)
    $send.FontSize = 18
    $send.HorizontalContentAlignment = 'Center'
    [Windows.Controls.DockPanel]::SetDock($send, 'Right')
    $ui.Send = $send
    [void]$tools.Children.Add($send)
    $pills = New-Object Windows.Controls.WrapPanel
    $pills.VerticalAlignment = 'Center'
    $ui.Known = New-HcButton '' @{ Do = 'aiKnown' }
    $ui.Note = New-HcButton '' @{ Do = 'aiNote' }
    $ui.Effort = New-HcButton '' @{ Do = 'aiEffort' }
    foreach ($b in @($ui.Known, $ui.Note, $ui.Effort)) { [void]$pills.Children.Add($b) }
    [void]$tools.Children.Add($pills)
    [void]$stack.Children.Add($tools)
    $composer.Child = $stack
    [void]$root.Children.Add($composer)
    [void]$root.Children.Add((New-HcText (T 'win.ai.fine') 12.5 'Soft' -Margin @(0, 6, 0, 0)))
    $root.Children[$root.Children.Count - 1].HorizontalAlignment = 'Center'
    [void]$dock.Children.Add($root)
    $a.Ui = $ui
}

# Enter sends (Shift+Enter is a new line); with the "/" list open the arrows
# move through it, Enter or Tab picks, Esc closes it.
function Invoke-HcAiKey {
    param($E)
    $a = $script:HcWin.Ai
    $shift = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) -ne 0
    if ($a.Slash.Count) {
        switch ($E.Key) {
            'Down'   { $a.SlashSel = ($a.SlashSel + 1) % $a.Slash.Count; Update-HcAiDock; $E.Handled = $true; return }
            'Up'     { $a.SlashSel = ($a.SlashSel - 1 + $a.Slash.Count) % $a.Slash.Count; Update-HcAiDock; $E.Handled = $true; return }
            'Escape' { $a.Ui.Box.Text = ''; $E.Handled = $true; return }
            { $_ -in @('Return', 'Tab') } { $E.Handled = $true; Invoke-HcAiCommand $a.Slash[$a.SlashSel]; return }
        }
    }
    if ($E.Key -eq 'Return' -and -not $shift) {
        $E.Handled = $true
        Send-HcAiBox
    }
}

# What is in the box goes out; a typed "/command" runs as if picked.
function Send-HcAiBox {
    $a = $script:HcWin.Ai
    $text = "$($a.Ui.Box.Text)".Trim()
    if (-not $text) { return }
    $exact = @(Get-HcAiSlashItems $text | Where-Object { $_.Cmd -eq $text.ToLowerInvariant() })
    if ($exact.Count) { Invoke-HcAiCommand $exact[0]; return }
    if ($a.Busy -or (Test-HcBusy)) { return }
    $a.Ui.Box.Text = ''
    Send-HcAiText $text
}

function Invoke-HcAiClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    $a = $w.Ai
    switch ($Tag.Do) {
        'aiSendBox' { Send-HcAiBox }
        'aiStop'    { Stop-HcAi }
        'aiSend'    { Send-HcAiText $Tag.Text }
        'aiOption'  { Send-HcAiText $Tag.Text }
        'aiExample' { $a.Ui.Box.Text = $Tag.Text; $a.Ui.Box.CaretIndex = $Tag.Text.Length; [void]$a.Ui.Box.Focus() }
        'aiFixes'   { Open-HcAiFixes $Tag.Code @($Tag.FixIds) -All:([bool]$Tag.All) }
        'aiNew'     { Reset-HcAi }
        'aiTool'    { $t = $a.Items[$Tag.Index].Tools[$Tag.Tool]; $t.Open = -not $t.Open; Update-HcAiPanel }
        'aiSlash'   { Invoke-HcAiCommand $a.Slash[$Tag.Index] }
        'aiKnown'   { $a.ShowKnown = -not $a.ShowKnown; Update-HcAiDock }
        'aiKnownSend' { $a.SendKnown = [bool]$a.Ui.KnownCheck.IsChecked; Update-HcAiDock }
        'aiNote'    { $a.ToNote = -not $a.ToNote; Update-HcAiDock }
        'aiEffort'  { $a.Effort = switch ($a.Effort) { 'medium' { 'high' } 'high' { 'low' } default { 'medium' } }; Update-HcAiDock }
        'aiEdit'    {
            # The message back in the box; sending replaces it and all after it.
            $a.Editing = $Tag.Index
            $a.Ui.Box.Text = $a.Items[$Tag.Index].Text
            $a.Ui.Box.CaretIndex = $a.Ui.Box.Text.Length
            [void]$a.Ui.Box.Focus()
        }
        'aiRetry'   {
            # The last message again, from the conversation as it was before it.
            for ($i = $a.Items.Count - 1; $i -ge 0; $i--) {
                $me = $a.Items[$i]
                if ($me.Kind -ne 'me' -or -not $me.Payload) { continue }
                $a.Convo = $me.Before
                while ($a.Items.Count -gt $i + 1) { $a.Items.RemoveAt($a.Items.Count - 1) }
                $item = @{ Kind = 'ai'; Tools = @(); Busy = $true; Big = ($me.Text -eq '/klant') }
                [void]$a.Items.Add($item)
                Start-HcAiJob $me.Payload $item
                break
            }
        }
        default     { return $false }
    }
    $true
}
