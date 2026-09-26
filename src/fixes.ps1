<#
    Fixes: the only code in Housecall that changes the PC.

    Every fix is on this list; nothing else, and never the AI, may change
    anything. A report offers fixes (Add-HcAction), the person picks one and
    confirms it, and only then does Apply run. Each fix says:

      Label    fix.<id> in strings.ps1, filled from the target, and
               fix.<id>.done for the note and undo ("Disabled task X")
      Note     undo = can be undone, safe = harmless and needs no undo,
               restart = closes a program, which can simply be started again,
               reprint = removes stuck print jobs, which need printing again
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

    # ---- C: printer and devices
    startSpooler = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service Spooler).StartType -eq 'Disabled') { Set-Service Spooler -StartupType Automatic -ErrorAction Stop }
            Start-Service Spooler -ErrorAction Stop
        }
        Undo = $null
    }
    # Stuck documents are gone afterwards; the note on this fix says so.
    restartSpooler = @{
        Note = 'reprint'; Admin = $true
        Apply = {
            param($t)
            Stop-Service Spooler -Force -ErrorAction Stop
            Get-ChildItem (Join-Path $env:SystemRoot 'System32\spool\PRINTERS') -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Start-Service Spooler -ErrorAction Stop
        }
        Undo = $null
    }
    # Without admin, Windows lets people cancel their own documents.
    clearJobs = @{
        Note = 'reprint'; Admin = $false
        Apply = { param($t) Get-CimInstance Win32_PrintJob | Remove-CimInstance -ErrorAction Stop }
        Undo  = $null
    }
    # Also stops "let Windows manage my default printer", which would
    # otherwise switch it back to whatever was used last.
    setDefault = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
            $t.SavedMode = (Get-ItemProperty $key -ErrorAction SilentlyContinue).LegacyDefaultPrinterMode
            Set-ItemProperty $key -Name LegacyDefaultPrinterMode -Value 1 -Type DWord -ErrorAction Stop
            $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Name -replace "'", "''"))
            $result = Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop
            if ($result.ReturnValue -ne 0) { throw "SetDefaultPrinter: $($result.ReturnValue)" }
        }
        Undo = {
            param($t)
            $key = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
            if ($t.Previous) {
                $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Previous -replace "'", "''"))
                if ($printer) { [void](Invoke-CimMethod -InputObject $printer -MethodName SetDefaultPrinter -ErrorAction Stop) }
            }
            if ($null -eq $t.SavedMode) { Remove-ItemProperty $key -Name LegacyDefaultPrinterMode -ErrorAction SilentlyContinue }
            else { Set-ItemProperty $key -Name LegacyDefaultPrinterMode -Value $t.SavedMode -Type DWord }
        }
    }
    printTestPage = @{
        Note = 'safe'; Admin = $false
        Apply = {
            param($t)
            $printer = Get-CimInstance Win32_Printer -Filter ("Name='{0}'" -f ($t.Name -replace "'", "''"))
            $result = Invoke-CimMethod -InputObject $printer -MethodName PrintTestPage -ErrorAction Stop
            if ($result.ReturnValue -ne 0) { throw "PrintTestPage: $($result.ReturnValue)" }
        }
        Undo = $null
    }
    enableDevice = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) Enable-PnpDevice -InstanceId $t.InstanceId -Confirm:$false -ErrorAction Stop }
        Undo  = { param($t) Disable-PnpDevice -InstanceId $t.InstanceId -Confirm:$false -ErrorAction Stop }
    }
    restartDevice = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            & pnputil.exe /restart-device $t.InstanceId | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "pnputil /restart-device: $LASTEXITCODE" }
        }
        Undo = $null
    }
    # ---- B: sound, video calls, screen
    # Restarting the endpoint builder restarts Windows Audio with it.
    restartAudio = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            foreach ($name in 'AudioEndpointBuilder', 'Audiosrv') {
                if ([string](Get-Service $name).StartType -eq 'Disabled') { Set-Service $name -StartupType Automatic -ErrorAction Stop }
            }
            Restart-Service AudioEndpointBuilder -Force -ErrorAction Stop
            Start-Service Audiosrv -ErrorAction Stop
        }
        Undo = $null
    }
    setDefaultAudio = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetDefault($t.Id) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetDefault($t.PreviousId) }
    }
    unmute = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetMute($t.Id, $false) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetMute($t.Id, $true) }
    }
    setVolume = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetVolume($t.Id, $t.Percent) }
        Undo  = { param($t) Initialize-HcAudio; [Housecall.Audio]::SetVolume($t.Id, $t.Previous) }
    }
    # A check more than a change: it is not listed on the note.
    testSound = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = {
            param($t)
            $wav = Join-Path $env:WINDIR 'Media\Windows Notify System Generic.wav'
            if (-not (Test-Path $wav)) { $wav = Join-Path $env:WINDIR 'Media\chimes.wav' }
            (New-Object Media.SoundPlayer $wav).PlaySync()
        }
        Undo = $null
    }
    allowAccess = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) $t.Saved = (Get-ItemProperty $t.Key).Value; Set-ItemProperty $t.Key -Name Value -Value 'Allow' -ErrorAction Stop }
        Undo  = { param($t) Set-ItemProperty $t.Key -Name Value -Value $t.Saved -ErrorAction Stop }
    }
    allowAccessMachine = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) $t.Saved = (Get-ItemProperty $t.Key).Value; Set-ItemProperty $t.Key -Name Value -Value 'Allow' -ErrorAction Stop }
        Undo  = { param($t) Set-ItemProperty $t.Key -Name Value -Value $t.Saved -ErrorAction Stop }
    }
    setBrightness = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop | Select-Object -First 1
            [void](Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$t.Percent } -ErrorAction Stop)
        }
        Undo = {
            param($t)
            $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop | Select-Object -First 1
            [void](Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]$t.Previous } -ErrorAction Stop)
        }
    }
    closeMagnifier = @{
        Note = 'restart'; Admin = $false
        Apply = { param($t) Get-Process -Name Magnify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }

    startBtService = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service bthserv).StartType -eq 'Disabled') { Set-Service bthserv -StartupType Manual -ErrorAction Stop }
            Start-Service bthserv -ErrorAction Stop
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

    if ($fix.Admin -and -not $script:IsAdmin -and -not $script:DryRun) {
        if (-not $script:HcSource) {
            Write-Warn2 (T 'fix.adminHow')
            return 'none'
        }
        if (-not (Test-HcYes (Read-HcLine (T 'fix.elevateAsk')))) {
            Write-Dim (T 'fix.cancelled')
            return 'none'
        }
        if (Start-HcElevated $script:HcCurrentCode) {
            $script:HandedOff = $true
            Write-Ok (T 'fix.elevated')
            return 'back'
        }
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
    if (-not $fix.NoLog) {
        $done = T ('fix.' + $action.FixId + '.done') $action.Target.Label
        [void]$script:HcChanges.Add([pscustomobject]@{ FixId = $action.FixId; Target = $action.Target; Label = $done })
    }
    Write-Ok (T 'fix.done')
    'changed'
}

<#
    Restarts Housecall as administrator, at the same problem, when a fix
    needs it. Housecall's own code ($script:HcSource) goes into a temporary
    file; the new window reads it, deletes it straight away and runs it. So
    it works after `irm | iex` (no file on disk) and without internet --
    which matters, since renewing the IP is a fix for having no internet.
    The small start-up command travels -EncodedCommand, so no path or quote
    in it can break.
#>
function Start-HcElevated {
    param([string]$Code)
    if (-not $script:HcSource) { return $false }
    $file = Join-Path $env:TEMP ('housecall-' + [guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($file, $script:HcSource, (New-Object Text.ASCIIEncoding))

    $options = "-Start '$Code' -Lang '$script:Lang'"
    if ($script:DryRun) { $options += ' -DryRun' }
    $quoted = $file.Replace("'", "''")
    $boot = "`$f = '$quoted'; `$s = [IO.File]::ReadAllText(`$f); Remove-Item -LiteralPath `$f -Force; " +
            "`$ErrorActionPreference = 'Stop'; . ([scriptblock]::Create(`$s)); `$script:HcSource = `$s; Start-Housecall $options"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
    try {
        Start-Process powershell.exe -Verb RunAs -ErrorAction Stop `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)
    } catch {
        # Most often: the person said No to Windows' permission question.
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Write-Warn2 (T 'fix.elevateFailed' $_.Exception.Message)
        return $false
    }
    $true
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
