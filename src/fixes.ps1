<#
    Fixes: the only code in Housecall that changes the PC.

    Every fix is on this list; nothing else, and never the AI, may change
    anything. A report offers fixes (Add-HcAction), the person picks one and
    confirms it, and only then does Apply run. Each fix says:

      Label    fix.<id> in strings.ps1, filled from the target
      Note     undo = can be undone, safe = harmless and needs no undo,
               restart = closes a program, which can simply be started again
      Admin    needs an administrator PowerShell
      Apply    does it; throws when it fails
      Undo     puts it back ($null when there is nothing to put back)

    Fixes never delete. A scheduled task is disabled, not removed; a program
    is closed, not uninstalled (uninstalling needs its own uninstaller).

    Every applied fix goes on $script:HcChanges, so U can undo the session.
#>

$script:HcChanges = New-Object System.Collections.ArrayList

$script:Fixes = @{
    disableTask = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null }
        Undo  = { param($t) Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop | Out-Null }
    }
    stopRemote = @{
        Note = 'restart'; Admin = $false
        Apply = { param($t) Get-Process -Name $t.Processes -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }
    proxyOff = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            $now = Get-ItemProperty $key
            $t.Saved = @{ ProxyEnable = $now.ProxyEnable; AutoConfigURL = $now.AutoConfigURL }
            Set-ItemProperty $key -Name ProxyEnable -Value 0 -ErrorAction Stop
            if ($now.AutoConfigURL) { Remove-ItemProperty $key -Name AutoConfigURL -ErrorAction Stop }
        }
        Undo = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
            if ($null -ne $t.Saved.ProxyEnable) { Set-ItemProperty $key -Name ProxyEnable -Value $t.Saved.ProxyEnable -ErrorAction Stop }
            if ($t.Saved.AutoConfigURL) { Set-ItemProperty $key -Name AutoConfigURL -Value $t.Saved.AutoConfigURL -ErrorAction Stop }
        }
    }
    flushDns = @{
        Note = 'safe'; Admin = $false
        Apply = { param($t) & ipconfig.exe /flushdns | Out-Null; if ($LASTEXITCODE -ne 0) { throw "ipconfig /flushdns: $LASTEXITCODE" } }
        Undo  = $null
    }
    renewIp = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            & ipconfig.exe /release | Out-Null
            & ipconfig.exe /renew | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ipconfig /renew: $LASTEXITCODE" }
        }
        Undo = $null
    }
}

# "Disable scheduled task "X" (can be undone)" -- the label with its note.
function Get-HcFixLabel {
    param([pscustomobject]$Action)
    $fix = $script:Fixes[$Action.FixId]
    $label = T ('fix.' + $Action.FixId) $Action.Target.Label
    $note = T ('fix.note.' + $fix.Note)
    if ($fix.Admin -and -not $script:IsAdmin) { $note += ' ' + (T 'fix.needsAdmin') }
    "$label $note"
}

# The step-by-step guide for a report's finding: steps.<id> in strings.ps1,
# steps separated by " | ", filled from the finding's arguments. Empty when
# the finding has no guide (for example "all good").
function Get-HcSteps {
    param([pscustomobject]$Report)
    if (-not $Report.FindingId) { return @() }
    $key = 'steps.' + $Report.FindingId
    if ($null -eq $script:Strings['en'][$key]) { return @() }
    $all = @($key) + @($Report.FindingArgs)
    @((T @all) -split '\s*\|\s*' | Where-Object { $_ })
}

# One step at a time, so it can be done together with the client: Enter
# shows the next step, 0 stops.
function Show-HcSteps {
    param([string[]]$Steps)
    for ($i = 0; $i -lt $Steps.Count; $i++) {
        Write-Host ''
        Write-HcLabelled (T 'fix.stepOf' ($i + 1) $Steps.Count) $Steps[$i] 'Cyan'
        $last = ($i -eq $Steps.Count - 1)
        $answer = "$(Read-HcLine (T $(if ($last) { 'fix.stepLast' } else { 'fix.stepNext' })))".Trim()
        if ($answer -in @('0', 'Q', 'q')) { break }
    }
}

function Test-HcYes {
    param([string]$Answer)
    "$Answer".Trim() -match '^(y|yes|j|ja)$'
}

<#
    Shows the offered fixes under a report and runs the one picked. Returns
    'changed' when something was changed (the caller checks again), 'back'
    when Enter was pressed, and 'none' when it was cancelled or failed (the
    list is shown again).
#>
function Invoke-HcActionMenu {
    param([pscustomobject]$Report)
    $actions = @($Report.Actions)
    $steps = @(Get-HcSteps $Report)
    if ($actions.Count -eq 0 -and $steps.Count -eq 0) { return 'back' }

    Write-Host ''
    Write-Host ('  ' + (T 'fix.heading')) -ForegroundColor Yellow
    for ($i = 0; $i -lt $actions.Count; $i++) {
        Write-Option ([string]($i + 1)) (Get-HcFixLabel $actions[$i])
    }
    if ($steps.Count) { Write-Option 'S' (T 'fix.steps') }
    Write-Dim (T 'fix.enterBack')

    $pick = "$(Read-HcLine (T 'menu.prompt'))".Trim()
    if ($steps.Count -and $pick -match '^[sS]$') {
        Show-HcSteps $steps
        return 'none'
    }
    $n = 0
    if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $actions.Count) { return 'back' }
    $action = $actions[$n - 1]
    $fix = $script:Fixes[$action.FixId]
    $label = T ('fix.' + $action.FixId) $action.Target.Label

    if ($fix.Admin -and -not $script:IsAdmin) {
        Write-Warn2 (T 'fix.adminHow')
        return 'none'
    }
    if (-not (Test-HcYes (Read-HcLine (T 'fix.confirm' $label)))) {
        Write-Dim (T 'fix.cancelled')
        return 'none'
    }
    if ($script:DryRun) {
        Write-Host ('  ' + (T 'fix.dryRun')) -ForegroundColor Magenta
        return 'none'
    }

    try {
        & $fix.Apply $action.Target
    } catch {
        Write-Warn2 (T 'fix.failed' $_.Exception.Message)
        return 'none'
    }
    [void]$script:HcChanges.Add([pscustomobject]@{ FixId = $action.FixId; Target = $action.Target; Label = $label })
    Write-Ok (T 'fix.done')
    'changed'
}

# U on the menu: undo this session's changes, newest first.
function Invoke-HcUndo {
    $undoable = @($script:HcChanges | Where-Object { $script:Fixes[$_.FixId].Undo })
    if ($undoable.Count -eq 0) { return (T 'undo.nothing') }
    if (-not (Test-HcYes (Read-HcLine (T 'undo.confirm' $undoable.Count)))) { return (T 'fix.cancelled') }

    $messages = @()
    for ($i = $undoable.Count - 1; $i -ge 0; $i--) {
        $change = $undoable[$i]
        try {
            & $script:Fixes[$change.FixId].Undo $change.Target
            $script:HcChanges.Remove($change)
            $messages += T 'undo.done' $change.Label
        } catch {
            $messages += T 'undo.failed' $change.Label
        }
    }
    $messages -join ' / '
}
