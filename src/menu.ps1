<#
    The menu: letter = area, number = problem. A opens an area, A1 jumps
    straight to a problem, and inside an area a bare 1 means the same as A1.

    Reserved keys, never to be used as an area letter:
        ?  AI chat    0  back    L  language    U  undo this session's fixes    Q  quit
#>

$script:Areas = [ordered]@{
    A = @('A1', 'A2', 'A3', 'A4')
    B = @('B1', 'B2', 'B3')
    C = @('C1', 'C2', 'C3')
    D = @('D1', 'D2', 'D3', 'D4')
    E = @('E1', 'E2', 'E3')
    F = @('F1', 'F2', 'F3')
}

<#
    Turn what was typed into one decision. Pure: no output, no state, so the
    tests can cover every kind of input.

    Kind is one of: empty, area, problem, ai, back, language, undo, quit,
    freetext (a sentence, which the AI chat will take), unknown.
#>
function Resolve-HcChoice {
    param(
        [AllowEmptyString()][string]$Text,
        # The letter of the area on screen, or '' on the home menu.
        [string]$CurrentArea = ''
    )

    $raw = if ($null -eq $Text) { '' } else { $Text.Trim() }
    $key = $raw.ToUpperInvariant()
    $result = { param($kind, $value) [pscustomobject]@{ Kind = $kind; Value = $value } }

    if ($key -eq '') { return & $result 'empty' $null }
    if ($key -eq '?') { return & $result 'ai' $null }
    if ($key -eq '0') { return & $result 'back' $null }
    if ($key -eq 'L') { return & $result 'language' $null }
    if ($key -eq 'Q') { return & $result 'quit' $null }
    if ($key -eq 'U') { return & $result 'undo' $null }

    if ($script:Areas.Contains($key)) { return & $result 'area' $key }

    if ($key -match '^([A-Z])(\d)$' -and $script:Areas.Contains($Matches[1])) {
        if ($script:Areas[$Matches[1]] -contains $key) { return & $result 'problem' $key }
        return & $result 'unknown' $raw
    }

    if ($key -match '^\d$' -and $CurrentArea) {
        $code = $CurrentArea + $key
        if ($script:Areas[$CurrentArea] -contains $code) { return & $result 'problem' $code }
        return & $result 'unknown' $raw
    }

    # Three words or more reads as someone describing the problem.
    if (($raw -split '\s+').Count -ge 3) { return & $result 'freetext' $raw }

    & $result 'unknown' $raw
}

# ------------------------------------------------------------------ screens --

function Show-HcHome {
    param([pscustomobject]$Environment, [string]$Message)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'menu.question')) -ForegroundColor Yellow
    Write-Host ''
    foreach ($letter in $script:Areas.Keys) {
        Write-Option $letter (T "area.$letter")
    }
    Write-Host ''
    if (-not $script:NoAI) { Write-Option '?' (T 'menu.ai'); Write-Host '' }
    Write-OptionRow (Get-HcFooter)
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'menu.hintHome') }
}

function Show-HcArea {
    param([pscustomobject]$Environment, [string]$Letter, [string]$Message)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'area.question' $Letter (T "area.$Letter"))) -ForegroundColor Yellow
    Write-Host ''
    foreach ($code in $script:Areas[$Letter]) {
        Write-Option $code (T "problem.$code")
    }
    Write-Host ''
    if (-not $script:NoAI) { Write-Option '?' (T 'area.ai'); Write-Host '' }
    Write-OptionRow (@(, @('0', (T 'menu.back'))) + (Get-HcFooter))
    Write-Host ''
    if ($Message) { Write-Warn2 $Message } else { Write-Dim (T 'area.hint') }
}

# The footer keys shared by every menu screen. U only shows once something
# was changed in this session.
function Get-HcFooter {
    $row = @(, @('L', (T 'menu.language')))
    if ($script:HcChanges.Count -gt 0) { $row += , @('U', (T 'menu.undo')) }
    $row + (, @('Q', (T 'menu.quit')))
}

<#
    Runs the handler registered for $Code (see src\checks\), or says which
    checks will run once it is built.

    The handler returns a scriptblock that checks the PC and returns a
    report. After the report come the fixes it offers; once one is applied,
    the same check runs again, so the screen shows whether it worked.
#>
function Invoke-HcProblem {
    param([pscustomobject]$Environment, [string]$Code)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + $Code + '  ' + (T "problem.$Code")) -ForegroundColor Yellow
    Write-Host ''
    $handler = $script:ProblemHandlers[$Code]
    if (-not $handler) {
        Write-Warn2 (T 'problem.notBuilt')
        Write-Dim (T 'problem.willLook')
        Write-Dim ('  ' + (T ('looks.' + $Code.Substring(0, 1))))
        Write-Host ''
        [void](Read-HcLine (T 'pressEnter'))
        return
    }

    $script:HcCurrentCode = $Code
    $check = & $handler
    if (-not $check) { return }      # e.g. A3 when no site was typed
    Write-Dim (T 'run.checking')
    Write-Host ''
    $report = & $check
    Write-HcReport $report
    Save-HcVisit $Code $report

    while (@($report.Actions).Count -gt 0 -or @(Get-HcSteps $report).Count -gt 0) {
        $result = Invoke-HcActionMenu $report
        if ($result -eq 'back') { return }
        if ($result -eq 'changed') {
            Write-Host ''
            Write-Dim (T 'fix.checkingAgain')
            Write-Host ''
            $report = & $check
            Write-HcReport $report
            Save-HcVisit $Code $report
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

# Phase 0 placeholder for the AI chat. It already tells the offline case
# apart, because that answer stays the same once the chat exists.
function Invoke-HcAi {
    param([pscustomobject]$Environment, [string]$Text)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ?  ' + (T 'ai.title')) -ForegroundColor Yellow
    Write-Host ''
    if ($Text) { Write-Dim (T 'ai.youTyped' $Text) }
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
    } else {
        Write-Warn2 (T 'ai.notBuilt')
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

# ---------------------------------------------------------------- main loop --

function Start-Housecall {
    param(
        [switch]$DryRun,
        [string]$Lang,
        # A problem code to open straight away, e.g. after restarting as admin.
        [string]$Start,
        # Leave the AI chat out of the menu.
        [switch]$NoAI,
        # For tests: answers to feed in instead of reading the keyboard.
        [string[]]$Answers
    )

    $script:DryRun = [bool]$DryRun
    $script:NoAI = [bool]$NoAI
    $script:RestorePointDone = $false
    $script:HcChanges.Clear()
    $script:HcVisit.Clear()
    $script:HandedOff = $false
    $script:Lang = if ($script:Strings.ContainsKey("$Lang".ToLowerInvariant())) { "$Lang".ToLowerInvariant() } else { Get-HcDefaultLanguage }
    $script:HcInputQueue = $null
    if ($PSBoundParameters.ContainsKey('Answers')) {
        $script:HcInputQueue = New-Object System.Collections.Queue
        foreach ($a in $Answers) { $script:HcInputQueue.Enqueue($a) }
    }

    $environment = Get-HcEnvironment
    if (-not $environment.IsWindows) { Write-Warn2 (T 'env.notWindows'); return }
    if ($environment.PSVersion.Major -lt 5) {
        Write-Warn2 (T 'env.oldPowerShell' $environment.PSVersion.ToString())
        return
    }
    $script:IsAdmin = [bool]$environment.IsAdmin

    $area = ''          # '' = home menu, otherwise the letter on screen
    $message = $null    # one-off warning shown under the menu

    $first = Resolve-HcChoice $Start
    if ($first.Kind -eq 'problem') {
        $area = $first.Value.Substring(0, 1)
        Invoke-HcProblem $environment $first.Value
    }

    while (-not $script:HandedOff) {
        if ($area) { Show-HcArea $environment $area $message } else { Show-HcHome $environment $message }
        $message = $null

        $choice = Resolve-HcChoice (Read-HcLine (T 'menu.prompt')) -CurrentArea $area
        if ($script:NoAI -and $choice.Kind -in @('ai', 'freetext')) {
            $choice = [pscustomobject]@{ Kind = 'unknown'; Value = $(if ($choice.Value) { $choice.Value } else { '?' }) }
        }
        switch ($choice.Kind) {
            'area'     { $area = $choice.Value }
            'problem'  { $area = $choice.Value.Substring(0, 1); Invoke-HcProblem $environment $choice.Value }
            'ai'       { Invoke-HcAi $environment }
            'freetext' { Invoke-HcAi $environment $choice.Value }
            'back'     { $area = '' }
            'language' { $script:Lang = if ($script:Lang -eq 'nl') { 'en' } else { 'nl' } }
            'undo'     { $message = Invoke-HcUndo }
            'unknown'  { $message = T 'menu.unknown' $choice.Value }
            'quit'     {
                Show-HcNote
                Write-Host ''
                if ($script:HcChanges.Count -gt 0) { Write-Ok (T 'goodbyeChanged' $script:HcChanges.Count) } else { Write-Ok (T 'goodbye') }
                Write-Host ''
                return
            }
        }
    }
}
