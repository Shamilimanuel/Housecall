<#
    Fixes: the only code in Housecall that changes the PC.

    Every fix is on this list; nothing else, and never the AI, may change
    anything. A report offers fixes (Add-HcAction), the person picks one and
    confirms it, and only then does Apply run. Each fix says:

      Label    fix.<id> in strings.ps1, filled from the target, and
               fix.<id>.done for the note and undo ("Disabled task X")
      Note     undo = can be undone, safe = harmless and needs no undo,
               restart = closes a program, which can simply be started again,
               reprint = removes stuck print jobs, which need printing again,
               temp = only temporary files, noundo = cannot be undone,
               unsaved = closes a program, and its unsaved work,
               redownload = Windows downloads again, long = takes a while,
               restartNeeded = works after a restart, uninstaller = opens the
               program's own uninstaller
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

    # Clears Windows' network settings back to how they were installed.
    # Only takes effect after a restart; the note on the fix says so.
    resetWinsock = @{
        Note = 'restartNeeded'; Admin = $true
        Apply = {
            param($t)
            & netsh.exe winsock reset | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "netsh winsock reset: $LASTEXITCODE" }
            & netsh.exe int ip reset | Out-Null
        }
        Undo = $null
    }
    restartAdapter = @{
        Note = 'safe'; Admin = $true
        Apply = { param($t) Restart-NetAdapter -Name $t.Name -Confirm:$false -ErrorAction Stop }
        Undo  = $null
    }

    # ---- F: remote tools and notification sites
    # Runs the program's own uninstaller (it may ask for permission itself).
    uninstallProgram = @{
        Note = 'uninstaller'; Admin = $false
        Apply = {
            param($t)
            $command = [string]$t.Command
            if ($command -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $arguments = $Matches[2] }
            elseif ($command -match '^\s*(\S+\.exe)\s*(.*)$') { $exe = $Matches[1]; $arguments = $Matches[2] }
            else { throw "Unknown uninstall command: $command" }
            if ($arguments) { Start-Process -FilePath $exe -ArgumentList $arguments -Wait -ErrorAction Stop }
            else { Start-Process -FilePath $exe -Wait -ErrorAction Stop }
        }
        Undo = $null
    }
    # Opens the browser straight at its notification settings, where a site
    # is blocked in two clicks. Housecall does not edit the browser's own
    # settings file: a browser that is open overwrites it, and a damaged one
    # can reset the client's whole profile.
    openNotifySettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = {
            param($t)
            $exe = $script:BrowserExe[$t.Browser]
            $scheme = $script:BrowserScheme[$t.Browser]
            Start-Process -FilePath $exe -ArgumentList "$($scheme)://settings/content/notifications" -ErrorAction Stop
        }
        Undo = $null
    }

    # Opens the provider's webmail in the browser: a check more than a change.
    openWebmail = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process $t.Url }
        Undo  = $null
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

    # ---- D: slow or freezing
    # The same switch Task Manager's Startup tab flips: first byte 03 = off.
    disableStartup = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            if (-not (Test-Path $t.Approved)) { New-Item $t.Approved -Force | Out-Null }
            $t.Saved = (Get-ItemProperty $t.Approved -ErrorAction SilentlyContinue).($t.Value)
            Set-ItemProperty $t.Approved -Name $t.Value -Value ([byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary -ErrorAction Stop
        }
        Undo = {
            param($t)
            if ($null -eq $t.Saved) { Remove-ItemProperty $t.Approved -Name $t.Value -ErrorAction Stop }
            else { Set-ItemProperty $t.Approved -Name $t.Value -Value ([byte[]]$t.Saved) -Type Binary -ErrorAction Stop }
        }
    }
    disableStartupMachine = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) & $script:Fixes.disableStartup.Apply $t }
        Undo  = { param($t) & $script:Fixes.disableStartup.Undo $t }
    }
    closeProcess = @{
        Note = 'unsaved'; Admin = $false
        Apply = { param($t) Get-Process -Name $t.Name -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop }
        Undo  = $null
    }
    # Only files untouched for a day: whatever is in use right now stays.
    emptyTemp = @{
        Note = 'temp'; Admin = $false
        Apply = {
            param($t)
            $cutoff = (Get-Date).AddDays(-1)
            Get-ChildItem -LiteralPath $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force -ErrorAction SilentlyContinue
        }
        Undo = $null
    }
    emptyRecycleBin = @{
        Note = 'noundo'; Admin = $false
        Apply = { param($t) Clear-RecycleBin -Force -ErrorAction Stop }
        Undo  = $null
    }

    # ---- E: Windows and updates
    enableUpdateService = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $t.Saved = [string](Get-Service wuauserv).StartType
            Set-Service wuauserv -StartupType Manual -ErrorAction Stop
            Start-Service wuauserv -ErrorAction Stop
        }
        Undo = { param($t) Stop-Service wuauserv -Force -ErrorAction SilentlyContinue; Set-Service wuauserv -StartupType $t.Saved -ErrorAction Stop }
    }
    # The same values the "Resume updates" button in Settings clears.
    resumeUpdates = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
            $names = 'PauseUpdatesExpiryTime', 'PauseUpdatesStartTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime'
            $now = Get-ItemProperty $key -ErrorAction Stop
            $t.Saved = @{}
            foreach ($n in $names) {
                if ($null -ne $now.$n) { $t.Saved[$n] = $now.$n; Remove-ItemProperty $key -Name $n -ErrorAction Stop }
            }
        }
        Undo = {
            param($t)
            foreach ($n in $t.Saved.Keys) { Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name $n -Value $t.Saved[$n] -ErrorAction Stop }
        }
    }
    # The classic cure for stuck updates: a fresh download folder. The old
    # one is renamed, not deleted, so nothing is lost if it matters.
    resetUpdates = @{
        Note = 'redownload'; Admin = $true
        Apply = {
            param($t)
            $services = 'wuauserv', 'bits', 'cryptsvc'
            foreach ($s in $services) { Stop-Service $s -Force -ErrorAction SilentlyContinue }
            $folder = Join-Path $env:SystemRoot 'SoftwareDistribution'
            if (Test-Path $folder) { Rename-Item $folder ('SoftwareDistribution.old-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -ErrorAction Stop }
            foreach ($s in $services) { Start-Service $s -ErrorAction SilentlyContinue }
        }
        Undo = $null
    }
    syncClock = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service w32time).StartType -eq 'Disabled') { Set-Service w32time -StartupType Manual -ErrorAction Stop }
            Start-Service w32time -ErrorAction SilentlyContinue
            & w32tm.exe /resync /force | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "w32tm /resync: $LASTEXITCODE" }
        }
        Undo = $null
    }
    # DISM repairs Windows' own store of system files (from Windows Update),
    # then SFC repairs the files in use from that store. Their progress shows
    # in the window while they run.
    repairWindows = @{
        Note = 'long'; Admin = $true
        Apply = {
            param($t)
            & dism.exe /Online /Cleanup-Image /RestoreHealth
            & sfc.exe /scannow
        }
        Undo = $null
    }
    disableFastStartup = @{
        Note = 'undo'; Admin = $true
        Apply = {
            param($t)
            $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
            $t.Saved = (Get-ItemProperty $key).HiberbootEnabled
            Set-ItemProperty $key -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
        }
        Undo = { param($t) Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value $t.Saved -Type DWord -ErrorAction Stop }
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

    # ---- G: desktop, taskbar and folders
    # Explorer draws the desktop, the taskbar and the folder windows.
    # Restarting it is harmless: the taskbar is gone for a few seconds, open
    # folder windows close, and files are untouched.
    restartExplorer = @{
        Note = 'explorer'; Admin = $false
        Apply = { param($t) Restart-HcExplorer }
        Undo  = $null
    }
    # The settings below only take effect once Explorer restarts, so each
    # one restarts it, and so does its undo.
    # Both the desktop's view flags (the real setting) and HideIcons (the copy).
    showDesktopIcons = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $t.SavedHide = (Get-ItemProperty "$script:ExplorerKey\Advanced" -ErrorAction SilentlyContinue).HideIcons
            $t.SavedFlags = (Get-ItemProperty $script:DesktopBagKey -ErrorAction SilentlyContinue).FFlags
            New-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            if ($null -ne $t.SavedFlags) {
                $shown = (ConvertTo-HcUInt32 $t.SavedFlags) -band (-bnot [uint32]$script:NoIconsFlag)
                New-ItemProperty $script:DesktopBagKey -Name FFlags -Value (ConvertTo-HcInt32 $shown) -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            }
            Restart-HcExplorer
        }
        Undo = {
            param($t)
            if ($null -eq $t.SavedHide) { Remove-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -ErrorAction SilentlyContinue }
            else { New-ItemProperty "$script:ExplorerKey\Advanced" -Name HideIcons -Value $t.SavedHide -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
            if ($null -ne $t.SavedFlags) { New-ItemProperty $script:DesktopBagKey -Name FFlags -Value $t.SavedFlags -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
            Restart-HcExplorer
        }
    }
    showRecycleBin = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcShellValue $t "$script:ExplorerKey\HideDesktopIcons\NewStartPanel" $script:RecycleBinId 0 }
        Undo  = { param($t) Undo-HcShellValue $t }
    }
    showSearch = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcShellValue $t 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 2 }
        Undo  = { param($t) Undo-HcShellValue $t }
    }
    taskbarStay = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $key = "$script:ExplorerKey\StuckRects3"
            $t.Saved = [byte[]](Get-ItemProperty $key -ErrorAction Stop).Settings
            Set-ItemProperty $key -Name Settings -Value (ConvertTo-HcTaskbarSetting $t.Saved $false) -Type Binary -ErrorAction Stop
            Restart-HcExplorer
        }
        Undo = {
            param($t)
            Set-ItemProperty "$script:ExplorerKey\StuckRects3" -Name Settings -Value ([byte[]]$t.Saved) -Type Binary -ErrorAction Stop
            Restart-HcExplorer
        }
    }
}

# Stops Explorer and waits for Windows to start it again (it does so by
# itself); starts it when it does not come back within five seconds.
function Restart-HcExplorer {
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { return }
    }
    Start-Process explorer.exe
}

# One DWORD in the user's Explorer settings, remembered for undo, then
# Explorer restarted so it shows.
function Set-HcShellValue {
    param([hashtable]$Target, [string]$Key, [string]$Name, [int]$Value)
    $Target.Key = $Key
    $Target.Name = $Name
    $Target.Saved = (Get-ItemProperty $Key -ErrorAction SilentlyContinue).$Name
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    New-ItemProperty $Key -Name $Name -Value $Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    Restart-HcExplorer
}

function Undo-HcShellValue {
    param([hashtable]$Target)
    if ($null -eq $Target.Saved) { Remove-ItemProperty $Target.Key -Name $Target.Name -ErrorAction Stop }
    else { New-ItemProperty $Target.Key -Name $Target.Name -Value $Target.Saved -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
    Restart-HcExplorer
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

    if ($fix.Admin) { New-HcRestorePoint }
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
    if ($script:NoAI) { $options += ' -NoAI' }
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

<#
    A Windows restore point before the first admin fix of a session: the
    safety net under Housecall's own undo. Windows allows one per 24 hours
    and only when System Protection is on; both cases are reported and
    Housecall carries on, because the fix itself still asks and undoes.
#>
$script:RestorePointDone = $false

function New-HcRestorePoint {
    if ($script:RestorePointDone -or -not $script:IsAdmin) { return }
    $script:RestorePointDone = $true
    Write-Dim (T 'fix.restorePoint')
    $warnings = $null
    try {
        Checkpoint-Computer -Description ('Housecall ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS `
            -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable warnings
        if ($warnings) { Write-Dim (T 'fix.restorePointRecent') } else { Write-Ok (T 'fix.restorePointOk') }
    } catch {
        Write-Warn2 (T 'fix.restorePointNone')
    }
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
