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
# Every change of this visit, the undone ones too, oldest first: the
# window's history, where each can be undone and done again. $HcChanges
# holds the active ones (the note, the invoice and U use those).
$script:HcChangeLog = New-Object System.Collections.ArrayList

function Add-HcChange {
    param([string]$FixId, [hashtable]$Target, [string]$Label)
    $change = [pscustomobject]@{ FixId = $FixId; Target = $Target; Label = $Label; Time = (Get-Date); State = 'active' }
    [void]$script:HcChanges.Add($change)
    [void]$script:HcChangeLog.Add($change)
    $change
}

function Set-HcChangeUndone {
    param([pscustomobject]$Change)
    $script:HcChanges.Remove($Change)
    # -Force: also for a change made before the history existed (no State yet).
    $Change | Add-Member -NotePropertyName State -NotePropertyValue 'undone' -Force
}

function Set-HcChangeRedone {
    param([pscustomobject]$Change)
    $Change | Add-Member -NotePropertyName State -NotePropertyValue 'active' -Force
    $Change | Add-Member -NotePropertyName Time -NotePropertyValue (Get-Date) -Force
    if (-not $script:HcChanges.Contains($Change)) { [void]$script:HcChanges.Add($Change) }
}

<#
    Pure: may this change be undone now? Not while a later active change
    made the same fix on the same thing: undoing the older one first would
    put back a value that is no longer the one from before.
#>
function Test-HcChangeBlocked {
    param([pscustomobject]$Change, [object[]]$Log)
    $key = { param($c) "$($c.FixId)|$($c.Target.Label)|$($c.Target.Serial)" }
    foreach ($c in $Log) {
        if ($c -ne $Change -and $c.State -eq 'active' -and (& $key $c) -eq (& $key $Change) -and $c.Time -gt $Change.Time) { return $true }
    }
    $false
}

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
    # Needs admin: Set-TimeZone from a normal PowerShell failed on Shamil's PC
    # with "a required privilege is not held" (27 Sep). Undo puts the old one back.
    setTimeZone = @{
        Note = 'undo'; Admin = $true
        Apply = { param($t) Set-TimeZone -Id $t.Id -ErrorAction Stop }
        Undo  = { param($t) Set-TimeZone -Id $t.Previous -ErrorAction Stop }
    }
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
    # OneDrive's own program; it signs in or picks up syncing by itself.
    startOneDrive = @{
        Note = 'safe'; Admin = $false
        Apply = { param($t) Start-Process -FilePath $t.Exe -ErrorAction Stop }
        Undo  = $null
    }
    # Takes one keyboard layout off a language, never its last one. The whole
    # list is remembered first, so undo puts it back exactly.
    removeLayout = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $list = Get-WinUserLanguageList
            $t.Saved = @($list | ForEach-Object { [pscustomobject]@{ Tag = $_.LanguageTag; Tips = @($_.InputMethodTips) } })
            $lang = @($list | Where-Object { $_.LanguageTag -eq $t.Tag }) | Select-Object -First 1
            # Never a language's last layout: that would remove the language,
            # which can change the Windows display language too.
            if (-not $lang -or $lang.InputMethodTips.Count -lt 2) { throw (T 'dev.lastLayout') }
            [void]$lang.InputMethodTips.Remove($t.Tip)
            Set-WinUserLanguageList $list -Force -ErrorAction Stop
        }
        Undo = {
            param($t)
            $list = New-WinUserLanguageList $t.Saved[0].Tag
            $list[0].InputMethodTips.Clear()
            foreach ($tip in $t.Saved[0].Tips) { $list[0].InputMethodTips.Add($tip) }
            foreach ($l in @($t.Saved | Select-Object -Skip 1)) {
                $list.Add($l.Tag)
                $added = $list[$list.Count - 1]
                $added.InputMethodTips.Clear()
                foreach ($tip in $l.Tips) { $added.InputMethodTips.Add($tip) }
            }
            Set-WinUserLanguageList $list -Force -ErrorAction Stop
        }
    }
    # The same as pressing the NumLock key.
    numLockOn = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) if (-not [Console]::NumberLock) { (New-Object -ComObject WScript.Shell).SendKeys('{NUMLOCK}') } }
        Undo  = { param($t) if ([Console]::NumberLock) { (New-Object -ComObject WScript.Shell).SendKeys('{NUMLOCK}') } }
    }
    # Settings > Power & battery, through explorer.exe like Default apps.
    openBatterySettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:batterysaver' -ErrorAction Stop }
        Undo  = $null
    }
    # ---- Phase 7, batch 1 (src\checks\comfort.ps1)
    # B4: screen-off and sleep times longer where they are short, never shorter.
    longerTimeouts = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcLongerTimeouts $t }
        Undo  = { param($t) Undo-HcLongerTimeouts $t }
    }
    # B5: the Settings pages where the client picks a size that suits them.
    openTextSize = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:easeofaccess-display' -ErrorAction Stop }
        Undo  = $null
    }
    openPointerSize = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:easeofaccess-mousepointer' -ErrorAction Stop }
        Undo  = $null
    }
    startMagnifier = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process magnify.exe -ErrorAction Stop }
        Undo  = $null
    }
    # C5: Settings > Bluetooth & devices > Touchpad, with its own on/off switch.
    openTouchpadSettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:devices-touchpad' -ErrorAction Stop }
        Undo  = $null
    }
    # E5: every switch behind Windows' own tips and ads off; undo puts each back.
    tipsOff = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcTipsOff $t }
        Undo  = { param($t) Undo-HcTipsOff $t }
    }
    # ---- B7 (src\checks\trouble.ps1): the maker's driver page, the refresh
    # rate per screen, and Windows' graphics settings.
    openGpuDriverSite = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process $script:GpuDriverSites[$t.Vendor] -ErrorAction Stop }
        Undo  = $null
    }
    openAdvancedDisplay = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:display-advanced' -ErrorAction Stop }
        Undo  = $null
    }
    openGraphicsSettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:display-advancedgraphics' -ErrorAction Stop }
        Undo  = $null
    }
    # ---- Phase 7, batch 3 (src\checks\trouble.ps1)
    # D5: Windows Update's active hours, when it may not restart by itself.
    openActiveHours = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:windowsupdate-activehours' -ErrorAction Stop }
        Undo  = $null
    }
    # D6: Settings > Power, for a calmer power mode on a laptop.
    openPowerSettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:powersleep' -ErrorAction Stop }
        Undo  = $null
    }
    # E6: Settings > Apps, with "Choose where to get apps".
    openAppSource = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:appsfeatures' -ErrorAction Stop }
        Undo  = $null
    }
    # E6: the Windows Installer service back from Disabled to its normal Manual.
    enableInstaller = @{
        Note = 'safe'; Admin = $true
        Apply = { param($t) Set-Service msiserver -StartupType Manual -ErrorAction Stop }
        Undo  = { param($t) Set-Service msiserver -StartupType Disabled -ErrorAction Stop }
    }
    # F5: the browser's own reset and extension pages; the client confirms there.
    openBrowserReset = @{
        Note = 'browserPage'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process -FilePath $script:BrowserExe[$t.Browser] -ArgumentList "$($script:BrowserScheme[$t.Browser])://settings/resetProfileSettings" -ErrorAction Stop }
        Undo  = $null
    }
    openBrowserExtensions = @{
        Note = 'browserPage'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process -FilePath $script:BrowserExe[$t.Browser] -ArgumentList "$($script:BrowserScheme[$t.Browser])://extensions" -ErrorAction Stop }
        Undo  = $null
    }
    # ---- Phase 7, batch 2 (src\checks\daily.ps1)
    # F4: the privacy pages, where each app's access to camera and microphone is switched.
    openCamPrivacy = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:privacy-webcam' -ErrorAction Stop }
        Undo  = $null
    }
    openMicPrivacy = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:privacy-microphone' -ErrorAction Stop }
        Undo  = $null
    }
    # G4: Settings > Accounts > Windows Backup (Windows 10: Backup).
    openBackupSettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:backup' -ErrorAction Stop }
        Undo  = $null
    }
    # B6: Settings > Display, and the screen modes of Windows + P.
    openDisplaySettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:display' -ErrorAction Stop }
        Undo  = $null
    }
    displayExtend = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcDisplayTopology $t 'Extend' }
        Undo  = { param($t) Undo-HcDisplayTopology $t }
    }
    displayClone = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcDisplayTopology $t 'Clone' }
        Undo  = { param($t) Undo-HcDisplayTopology $t }
    }
    # E4: Windows Update, where the free Windows 11 upgrade is offered.
    openWindowsUpdate = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:windowsupdate' -ErrorAction Stop }
        Undo  = $null
    }
    # E4: Microsoft's own page with the Windows 11 Installation Assistant.
    openWin11Download = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process $script:Win11DownloadUrl -ErrorAction Stop }
        Undo  = $null
    }
    # Settings > Time & language > Language & region, for the keyboard layouts.
    openKeyboardSettings = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:regionlanguage' -ErrorAction Stop }
        Undo  = $null
    }
    # Opens a folder in File Explorer (Downloads, or where a browser saves).
    openFolder = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process explorer.exe -ArgumentList ('"' + $t.Path + '"') -ErrorAction Stop }
        Undo  = $null
    }
    # Settings > Default apps: which program opens a file type is protected,
    # so the client chooses it there.
    openDefaultApps = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        # Through explorer.exe: a bare Start-Process of the ms-settings link did
        # not reliably open Settings on Shamil's PC (27 Sep); this route did.
        Apply = { param($t) Start-Process explorer.exe -ArgumentList 'ms-settings:defaultapps' -ErrorAction Stop }
        Undo  = $null
    }
    startSearch = @{
        Note = 'safe'; Admin = $true
        Apply = {
            param($t)
            if ([string](Get-Service WSearch).StartType -eq 'Disabled') { Set-Service WSearch -StartupType Automatic -ErrorAction Stop }
            Start-Service WSearch -ErrorAction Stop
        }
        Undo = $null
    }
    # Only opens the Recycle Bin, so the client can pick what to put back.
    openRecycleBin = @{
        Note = 'safe'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-Process 'shell:RecycleBinFolder' -ErrorAction Stop }
        Undo  = $null
    }
    # Live, through the same call as the Settings switch; no Explorer restart.
    taskbarStay = @{
        Note = 'undo'; Admin = $false
        Apply = {
            param($t)
            $t.Saved = Get-HcTaskbarState
            if ($null -eq $t.Saved) { throw (T 'shell.taskbarUnknown') }
            Set-HcTaskbarState ($t.Saved -band -bnot 1)
        }
        Undo = { param($t) Set-HcTaskbarState $t.Saved }
    }

    # ---- M: a phone or tablet, through this laptop (src\checks\android.ps1)
    # Google's Android tool into Housecall's own folder, signature checked;
    # undo deletes the folder again.
    getAdb = @{
        Note = 'adb'; Admin = $false
        Apply = { param($t) Install-HcAdb }
        Undo  = { param($t) Remove-HcAdb }
    }
    phoneAutoTime = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcPhoneSetting $t.Serial 'auto_time' '1' }
        Undo  = { param($t) Set-HcPhoneSetting $t.Serial 'auto_time' '0' }
    }
    phoneAutoZone = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcPhoneSetting $t.Serial 'auto_time_zone' '1' }
        Undo  = { param($t) Set-HcPhoneSetting $t.Serial 'auto_time_zone' '0' }
    }
    # A private DNS server that does not answer breaks every website name.
    # Automatic keeps the encryption where the network offers it.
    privateDnsAuto = @{
        Note = 'undo'; Admin = $false
        Apply = { param($t) Set-HcPhoneSetting $t.Serial 'private_dns_mode' 'opportunistic' }
        Undo  = { param($t) Set-HcPhoneSetting $t.Serial 'private_dns_mode' 'hostname' }
    }
    # Settings pages on the device's own screen, so the client sees where.
    phoneOpenStorage = @{
        Note = 'phoneScreen'; Admin = $false; NoLog = $true
        Apply = { param($t) Open-HcPhoneScreen $t.Serial @('android.settings.INTERNAL_STORAGE_SETTINGS') }
        Undo  = $null
    }
    phoneOpenBattery = @{
        Note = 'phoneScreen'; Admin = $false; NoLog = $true
        Apply = { param($t) Open-HcPhoneScreen $t.Serial @('android.intent.action.POWER_USAGE_SUMMARY', 'android.settings.BATTERY_SAVER_SETTINGS') }
        Undo  = $null
    }
    phoneOpenUpdates = @{
        Note = 'phoneScreen'; Admin = $false; NoLog = $true
        Apply = { param($t) Open-HcPhoneScreen $t.Serial @('android.settings.SYSTEM_UPDATE_SETTINGS', 'android.settings.DEVICE_INFO_SETTINGS') }
        Undo  = $null
    }
    # M7: an app's own page in Settings, where the client can uninstall it.
    # Housecall itself never removes an app.
    phoneOpenApp = @{
        Note = 'appPage'; Admin = $false; NoLog = $true
        Apply = {
            param($t)
            if ($t.Package -notmatch '^[A-Za-z]\w*(\.\w+)+$') { throw "Bad package name: $($t.Package)" }
            Open-HcPhoneScreen $t.Serial @("android.settings.APPLICATION_DETAILS_SETTINGS -d package:$($t.Package)")
        }
        Undo  = $null
    }
    # The tools on M1. The phone's screen in a window on this laptop (scrcpy,
    # downloaded once and checked against its fingerprint).
    phoneMirror = @{
        Note = 'mirror'; Admin = $false; NoLog = $true
        Apply = { param($t) Start-HcPhoneMirror $t.Serial $t.Label }
        Undo  = $null
    }
    phoneScreenshot = @{
        Note = 'screenshot'; Admin = $false; NoLog = $true
        Apply = { param($t) Save-HcPhoneScreenshot $t.Serial }
        Undo  = $null
    }
    phoneRestart = @{
        Note = 'phoneRestart'; Admin = $false
        Apply = { param($t) Restart-HcPhone $t.Serial }
        Undo  = $null
    }
    # The last step of a phone visit: USB debugging gives a computer a lot of
    # access, so it goes off again. The connection drops at once, which can
    # make the command itself report an error; only a refusal counts.
    phoneDebugOff = @{
        Note = 'debugOff'; Admin = $false
        Apply = { param($t) Disable-HcPhoneDebugging $t.Serial }
        Undo  = $null
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
        [void](Add-HcChange $action.FixId $action.Target $done)
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
    if (-not $script:HcWindowMode) { $options += ' -Console' }
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
            Set-HcChangeUndone $change
            $messages += T 'undo.done' $change.Label
        } catch {
            $messages += T 'undo.failed' $change.Label
        }
    }
    $messages -join ' / '
}
