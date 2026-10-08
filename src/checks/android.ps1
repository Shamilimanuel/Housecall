<#
    Area M: a phone, tablet or car screen, read from this laptop.

      M1  overview of the device      model, Android version and security
                                      update, memory, storage, battery, last
                                      restart, number of apps
      M2  slow                        storage nearly full, memory in use,
                                      last restart, total memory, Android version
      M3  storage full                free space, and what takes it (photos,
                                      videos, apps, app data, downloads, ...)
      M4  battery                     condition, temperature, charging, charge
                                      cycles, screen timeout, battery saver
      M5  Google sign-in / no connection
                                      airplane mode, Wi-Fi and mobile data,
                                      internet and website names, private DNS,
                                      date, time and time zone (a wrong date
                                      makes Google's sign-in fail)
      M6  updates                     Android version and how old the last
                                      security update is

    Everything goes through Google's own Android tool, ADB, which Housecall
    downloads once (the getAdb fix, with a yes) into its own folder and checks
    Google's signature on. The device must have USB debugging switched on;
    the steps say how. Every ADB command is checked against $script:AdbAllowed
    first, so nothing else can ever run on the device: no messages, photos,
    contacts, accounts or passwords are read. phoneDebugOff switches USB
    debugging off again at the end.

    The device is not this PC: its codes are left out of "check everything"
    and out of this PC's visit history (New-HcVisitBody).
#>

$script:AdbHome = Join-Path "$env:LOCALAPPDATA" 'Housecall\platform-tools'
# The device the window's phone tab has chosen (its serial), read first when
# it is connected; $null = the first device that is ready.
$script:HcPhonePrefer = $null
$script:AdbZipUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
# All adb.exe needs from platform-tools; each is signed by Google.
$script:AdbFiles = @('adb.exe', 'AdbWinApi.dll', 'AdbWinUsbApi.dll')

# The only ADB commands Housecall runs. Reading: properties, settings,
# battery and storage figures, memory, uptime, the device's clock, the
# number of apps, two pings. Changing (fixes only): automatic time and time
# zone, private DNS, USB debugging off, and opening a Settings page.
$script:AdbAllowed = @(
    '^devices -l$'
    '^kill-server$'
    '^shell getprop$'
    '^shell settings get (global|system) [a-z_]+$'
    '^shell settings put global (auto_time|auto_time_zone) [01]$'
    '^shell settings put global adb_enabled 0$'
    '^shell settings put global private_dns_mode (off|opportunistic|hostname)$'
    '^shell dumpsys (battery|diskstats)$'
    '^shell cat /proc/(meminfo|uptime)$'
    '^shell df -k /data$'
    '^shell date \+%s$'
    '^shell pm list packages -3$'
    '^shell ping -c 1 -W 3 (8\.8\.8\.8|google\.com)$'
    '^shell am start -a android\.(settings|intent\.action)\.[A-Z_]+$'
    # Tools on M1: a screenshot goes through one fixed file on the phone,
    # which is removed again; restart; waiting for the phone to be back.
    '^shell screencap -p /sdcard/housecall-screen\.png$'
    '^pull /sdcard/housecall-screen\.png housecall-screen\.png$'
    '^shell rm /sdcard/housecall-screen\.png$'
    '^reboot$'
    '^shell getprop sys\.boot_completed$'
    # M7: which apps have dangerous access, and where each app came from.
    '^shell settings get secure (enabled_accessibility_services|enabled_notification_listeners)$'
    '^shell pm list packages -3 -i$'
    '^shell dumpsys device_policy$'
    '^shell appops query-op REQUEST_INSTALL_PACKAGES allow$'
    # M8: over Wi-Fi (Android 11+ "Wireless debugging"): pair with the code
    # the device shows, connect, and switch Wireless debugging off at the end.
    '^pair \d{1,3}(\.\d{1,3}){3}:\d{2,5} \d{6}$'
    '^mdns services$'
    '^connect \d{1,3}(\.\d{1,3}){3}:\d{2,5}$'
    '^shell settings put global adb_wifi_enabled 0$'
    # An app's own page in Settings, where the client can uninstall it.
    '^shell am start -a android\.settings\.APPLICATION_DETAILS_SETTINGS -d package:[A-Za-z]\w*(\.\w+)+$'
)

# ------------------------------------------------------ M7: safety lists --
# Not a virus scanner: Housecall looks at what harmful apps need (reading the
# screen, the notifications, being device admin, coming from outside a
# store), whatever they are called. Play Protect is the phone's own scanner.

# App stores; an app from any of these counts as "from a store".
$script:PhoneStores = @(
    'com.android.vending', 'com.sec.android.app.samsungapps', 'com.huawei.appmarket', 'com.xiaomi.market',
    'com.xiaomi.mipicks', 'com.heytap.market', 'com.oppo.market', 'com.amazon.venezia',
    # Facebook's own installer for the copy phone makers preinstall.
    'com.facebook.system', 'com.facebook.appmanager'
)
# The phone maker's and Google's own parts (TalkBack, Find My Device, the
# keyboard, the watch app of the maker): never flagged for their access.
$script:PhoneMakerPrefixes = @(
    'android', 'com.android.', 'com.google.android.', 'com.samsung.', 'com.sec.', 'com.miui.', 'com.xiaomi.',
    'com.oneplus.', 'com.oplus.', 'com.coloros.', 'com.heytap.', 'com.huawei.', 'com.hihonor.', 'com.motorola.',
    'com.sonymobile.', 'com.sony.', 'com.lge.', 'com.nothing.'
)
# Apps that let someone else see and control the phone (like F's list on PCs).
$script:PhoneRemoteApps = [ordered]@{
    'com.anydesk.anydeskandroid'        = 'AnyDesk'
    'com.teamviewer.quicksupport.market' = 'TeamViewer QuickSupport'
    'com.teamviewer.host.market'        = 'TeamViewer Host'
    'com.rustdesk.rustdesk'             = 'RustDesk'
    'com.carriez.flutter_hbb'           = 'RustDesk'
    'com.sand.airdroid'                 = 'AirDroid'
}
# At most this many "open the app's page" buttons, so the list stays short.
$script:PhoneMaxAppButtons = 6

function Test-HcMakerPackage {
    param([string]$Package)
    foreach ($p in $script:PhoneMakerPrefixes) { if ($Package -eq $p -or $Package.StartsWith($p)) { return $true } }
    $false
}

# Pure: installed from outside a store? No installer, the package installer
# (a downloaded file), or another app such as a browser or WhatsApp.
function Test-HcSideloaded {
    param([string]$Installer)
    if (-not $Installer -or $Installer -eq 'null') { return $true }
    # A download through a browser, a file manager or a message is the way
    # in for fake apps, also when that app is the maker's own.
    if ($Installer -match 'packageinstaller|chrome|browser|files|filemanager|documentsui|messag|email|whatsapp|downloads') { return $true }
    if ($script:PhoneStores -contains $Installer) { return $false }
    -not (Test-HcMakerPackage $Installer)
}

# scrcpy (github.com/Genymobile/scrcpy, free and open source) shows the
# phone's screen in a window on this laptop, worked with mouse and keyboard.
# A fixed version with its published SHA-256: scrcpy itself is not signed,
# so the fingerprint is what proves the download is the real one. 4.1 had
# three months behind it on 5 Oct 2026; 5.0 came out that same day.
$script:ScrcpyZipUrl = 'https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-win64-v4.1.zip'
$script:ScrcpySha256 = '5b12172b3264b2889f4583ee64752ce832e29bc8b1089dca81093459697165db'
$script:ScrcpyHome = Join-Path "$env:LOCALAPPDATA" 'Housecall\scrcpy-v4.1'

# Limits, the same spirit as the PC checks.
$script:PhoneStorageFullPercent = 10
$script:PhoneStorageFullGB = 1
$script:PhoneStorageLowPercent = 20
$script:PhoneLowRamGB = 3
$script:PhoneMemoryFullPercent = 10
$script:PhoneUptimeDays = 14
$script:PhonePatchStaleMonths = 6
$script:PhonePatchOldMonths = 24
# Android 10 = SDK 29. Below it, more and more apps (banking apps first) stop.
$script:PhoneOldSdk = 29
$script:PhoneHotCelsius = 45
$script:PhoneWornCycles = 800
$script:PhoneScreenLongMs = 120000
$script:PhoneClockOffSeconds = 300

# --------------------------------------------------------------- the tool --

# Housecall's own copy first, then one already on the PATH.
function Get-HcAdbPath {
    $own = Join-Path $script:AdbHome 'adb.exe'
    if (Test-Path -LiteralPath $own) { return $own }
    $found = Get-Command adb.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
    $null
}

# Pure: is this exact command on the list? A line break or a shell sign
# could add a second command behind an allowed one, so those never pass.
function Test-HcAdbAllowed {
    param([string]$Command)
    if ($Command -match '[\r\n;&|`$<>(){}"''\\]') { return $false }
    foreach ($pattern in $script:AdbAllowed) { if ($Command -cmatch $pattern) { return $true } }
    $false
}

<#
    Runs one allowed ADB command and returns Ok, ExitCode, Out and Err. Throws
    when the command is not on the list. A device that hangs is stopped after
    $TimeoutSec, so a check never freezes.
#>
function Invoke-HcAdb {
    param([string]$Command, [string]$Serial, [int]$TimeoutSec = 15, [string]$WorkingDirectory)
    if (-not (Test-HcAdbAllowed $Command)) { throw "ADB command not allowed: $Command" }
    if ($Serial -and $Serial -notmatch '^[\w.:\-]+$') { throw "Bad device serial: $Serial" }
    $adb = Get-HcAdbPath
    if (-not $adb) { throw (T 'and.adbMissing') }

    $psi = New-Object Diagnostics.ProcessStartInfo $adb
    $psi.Arguments = $(if ($Serial) { "-s $Serial $Command" } else { $Command })
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $p = [Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ Ok = $false; ExitCode = -1; Out = ''; Err = 'timeout' }
    }
    [void]$out.Wait(3000)
    [void]$err.Wait(3000)
    [pscustomobject]@{
        Ok       = ($p.ExitCode -eq 0)
        ExitCode = $p.ExitCode
        Out      = $(if ($out.IsCompleted) { "$($out.Result)" } else { '' })
        Err      = $(if ($err.IsCompleted) { "$($err.Result)" } else { '' })
    }
}

# The output of a shell command, or $null when it failed.
function Get-HcAdbText {
    param([string]$Serial, [string]$Command, [int]$TimeoutSec = 15)
    try {
        $r = Invoke-HcAdb "shell $Command" -Serial $Serial -TimeoutSec $TimeoutSec
        if ($r.Ok) { return $r.Out }
    } catch { }
    $null
}

# One setting, as text; $null when it is not set ("null").
function Get-HcPhoneSetting {
    param([string]$Serial, [string]$Table, [string]$Name)
    $v = "$(Get-HcAdbText $Serial "settings get $Table $Name")".Trim()
    if ($v -eq '' -or $v -eq 'null') { return $null }
    $v
}

function Set-HcPhoneSetting {
    param([string]$Serial, [string]$Name, [string]$Value)
    $r = Invoke-HcAdb "shell settings put global $Name $Value" -Serial $Serial
    if (-not $r.Ok) { throw (T 'and.settingFailed' (("$($r.Err) $($r.Out)").Trim())) }
}

# Opens a Settings page on the device's own screen; the first action that
# exists there wins (not every brand has every page).
function Open-HcPhoneScreen {
    param([string]$Serial, [string[]]$Actions)
    foreach ($a in $Actions) {
        $r = Invoke-HcAdb "shell am start -a $a" -Serial $Serial
        if ($r.Ok -and "$($r.Out)$($r.Err)" -notmatch 'Error') { return }
    }
    throw (T 'and.screenFailed')
}

<#
    The getAdb fix: downloads platform-tools from Google, checks that the
    three files carry Google's valid signature, and keeps only those in
    %LOCALAPPDATA%\Housecall\platform-tools. Nothing is installed; undo
    (Remove-HcAdb) deletes the folder.
#>
function Install-HcAdb {
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $work = Join-Path $env:TEMP ('housecall-adb-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'platform-tools.zip'
        Invoke-WebRequest -Uri $script:AdbZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
        Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
        foreach ($f in $script:AdbFiles) {
            $sig = Get-AuthenticodeSignature -FilePath (Join-Path $work "platform-tools\$f")
            if ("$($sig.Status)" -ne 'Valid' -or "$($sig.SignerCertificate.Subject)" -notmatch 'O=Google LLC') { throw (T 'and.badSignature' $f) }
        }
        New-Item -ItemType Directory -Path $script:AdbHome -Force | Out-Null
        foreach ($f in $script:AdbFiles) { Copy-Item -LiteralPath (Join-Path $work "platform-tools\$f") -Destination $script:AdbHome -Force }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Remove-HcAdb {
    Stop-HcAdb
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $script:AdbHome -Recurse -Force -ErrorAction Stop
    $parent = Split-Path $script:AdbHome -Parent
    if ((Test-Path -LiteralPath $parent) -and -not @(Get-ChildItem -LiteralPath $parent -Force).Count) {
        Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
    }
}

# ADB leaves a helper running in the background once it has been used. When
# Housecall closes it is stopped, if it is Housecall's own copy, and so is a
# phone screen window that is still open.
function Stop-HcAdb {
    Get-Process -Name scrcpy -ErrorAction SilentlyContinue | Where-Object { "$($_.Path)" -like "$script:ScrcpyHome\*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $own = Join-Path $script:AdbHome 'adb.exe'
    if (-not (Test-Path -LiteralPath $own)) { return }
    $running = @(Get-Process -Name adb -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $own })
    if ($running.Count) { try { [void](Invoke-HcAdb 'kill-server' -TimeoutSec 5) } catch { } }
}

# USB debugging and Wireless debugging off, the connection in use last, or
# the second command would never arrive. The connection drops at once,
# which can make that last command itself report an error: only a refusal
# counts as failing.
function Disable-HcPhoneDebugging {
    param([string]$Serial)
    $off = {
        param($name)
        $r = Invoke-HcAdb "shell settings put global $name 0" -Serial $Serial
        if (-not $r.Ok -and "$($r.Out)$($r.Err)" -match 'Exception|denied|not allowed') { throw (T 'and.settingFailed' (("$($r.Err) $($r.Out)").Trim())) }
    }
    if (Test-HcWifiSerial $Serial) {
        & $off 'adb_enabled'
        & $off 'adb_wifi_enabled'
    } else {
        if ((Get-HcPhoneSetting $Serial global adb_wifi_enabled) -eq '1') { & $off 'adb_wifi_enabled' }
        & $off 'adb_enabled'
    }
    Stop-HcAdb
}

# A device on Wi-Fi: "192.168.1.50:38497", or the name ADB gives a device it
# found on the network itself ("adb-R58N...._adb-tls-connect._tcp").
function Test-HcWifiSerial {
    param([string]$Serial)
    $Serial -match ':\d+$' -or $Serial -match '\._adb-tls-connect\.'
}

# ----------------------------------------------------------------- tools --
# The buttons on M1: a screenshot, a restart, and the phone's screen on
# this laptop. They live here, next to the ADB code; src\fixes.ps1 calls them.

# Saved in Pictures\Housecall on this laptop and opened. The picture is made
# on the phone in one fixed file, fetched, and removed from the phone again.
function Save-HcPhoneScreenshot {
    param([string]$Serial)
    $dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Housecall'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $r = Invoke-HcAdb 'shell screencap -p /sdcard/housecall-screen.png' -Serial $Serial -TimeoutSec 20
    if (-not $r.Ok) { throw (T 'and.screenshotFailed') }
    try {
        $r = Invoke-HcAdb 'pull /sdcard/housecall-screen.png housecall-screen.png' -Serial $Serial -TimeoutSec 30 -WorkingDirectory $dir
        if (-not $r.Ok) { throw (T 'and.screenshotFailed') }
    } finally {
        [void](Invoke-HcAdb 'shell rm /sdcard/housecall-screen.png' -Serial $Serial)
    }
    $file = Join-Path $dir ('phone ' + (Get-Date -Format 'yyyy-MM-dd HH.mm.ss') + '.png')
    Move-Item -LiteralPath (Join-Path $dir 'housecall-screen.png') -Destination $file -Force
    Start-Process -FilePath $file
}

# Restarts the phone and waits until it is back and started up (at most
# 3 minutes), so the check that runs after the fix reads the phone again
# instead of reporting it missing.
function Restart-HcPhone {
    param([string]$Serial, [int]$TimeoutSec = 180)
    [void](Invoke-HcAdb 'reboot' -Serial $Serial -TimeoutSec 20)
    Start-Sleep -Seconds 10
    $until = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $until) {
        $list = Invoke-HcAdb 'devices -l' -TimeoutSec 10
        $back = @(ConvertFrom-HcAdbDevices $list.Out | Where-Object { $_.Serial -eq $Serial -and $_.State -eq 'device' })
        if ($back.Count -and "$(Get-HcAdbText $Serial 'getprop sys.boot_completed')".Trim() -eq '1') { return }
        Start-Sleep -Seconds 3
    }
    throw (T 'and.restartSlow')
}

function Install-HcScrcpy {
    $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $work = Join-Path $env:TEMP ('housecall-scrcpy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $zip = Join-Path $work 'scrcpy.zip'
        Invoke-WebRequest -Uri $script:ScrcpyZipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $script:ScrcpySha256) { throw (T 'and.badHash') }
        Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
        $inner = Get-ChildItem -LiteralPath $work -Directory | Where-Object { $_.Name -like 'scrcpy-*' } | Select-Object -First 1
        if (-not $inner) { throw (T 'and.badHash') }
        New-Item -ItemType Directory -Path $script:ScrcpyHome -Force | Out-Null
        Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $script:ScrcpyHome -Recurse -Force
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The phone's screen in its own window, with Housecall's ADB, so two ADB
# versions do not fight over the phone. Closing the window stops it.
function Start-HcPhoneMirror {
    param([string]$Serial, [string]$Name)
    if ($Serial -notmatch '^[\w.:\-]+$') { throw "Bad device serial: $Serial" }
    $exe = Join-Path $script:ScrcpyHome 'scrcpy.exe'
    if (-not (Test-Path -LiteralPath $exe)) { Install-HcScrcpy }
    $title = 'Housecall - ' + ("$Name" -replace '[^\w .()\-]', '')
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = "-s $Serial --stay-awake --window-title `"$title`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $script:ScrcpyHome
    $adb = Get-HcAdbPath
    if ($adb) { $psi.EnvironmentVariables['ADB'] = $adb }
    $p = [Diagnostics.Process]::Start($psi)
    # A phone that refuses stops scrcpy within a few seconds.
    if ($p.WaitForExit(4000) -and $p.ExitCode -ne 0) { throw (T 'and.mirrorFailed') }
}

# ------------------------------------------------- the phone on the cable --
# Windows sees a phone on the USB cable even before USB debugging is on, by
# the maker's USB number (VID). That gives the brand, so the steps can name
# that brand's own menus. A product number (PID) pattern keeps out other
# devices of the same maker (a Samsung SSD, an Apple keyboard).
$script:PhoneVendors = @(
    @{ Vid = '04E8'; Pid = '^68'; Brand = 'Samsung'; Family = 'samsung' }
    @{ Vid = '18D1'; Pid = '^4E'; Brand = 'Google'; Family = 'pixel' }
    @{ Vid = '2717'; Pid = '.'; Brand = 'Xiaomi'; Family = 'xiaomi' }
    @{ Vid = '22D9'; Pid = '.'; Brand = 'OPPO / realme'; Family = 'oppo' }
    @{ Vid = '2A70'; Pid = '.'; Brand = 'OnePlus'; Family = 'oppo' }
    @{ Vid = '12D1'; Pid = '.'; Brand = 'Huawei'; Family = 'other' }
    @{ Vid = '0FCE'; Pid = '.'; Brand = 'Sony'; Family = 'other' }
    @{ Vid = '22B8'; Pid = '.'; Brand = 'Motorola'; Family = 'other' }
    @{ Vid = '1004'; Pid = '.'; Brand = 'LG'; Family = 'other' }
    @{ Vid = '2D95'; Pid = '.'; Brand = 'vivo'; Family = 'other' }
    @{ Vid = '2E04'; Pid = '.'; Brand = 'Nokia'; Family = 'other' }
    @{ Vid = '0BB4'; Pid = '.'; Brand = 'HTC'; Family = 'other' }
    @{ Vid = '05AC'; Pid = '^12'; Brand = 'Apple'; Family = 'apple' }
)
# The finding, and with it the steps, for each brand family.
$script:PhoneDebugFindings = @{
    samsung = 'phoneDebuggingOffSamsung'
    pixel   = 'phoneDebuggingOffPixel'
    xiaomi  = 'phoneDebuggingOffXiaomi'
    oppo    = 'phoneDebuggingOffOppo'
    other   = 'phoneDebuggingOff'
}

<#
    Pure: the first phone among Windows' USB devices (each with DeviceId and
    ErrorCode), or $null. NoDriver: a part of it has no driver (code 28),
    which with USB debugging on is the debug connection itself.
#>
function Find-HcUsbPhone {
    param([object[]]$Devices)
    foreach ($v in $script:PhoneVendors) {
        $mine = @($Devices | Where-Object { "$($_.DeviceId)" -match ('^USB\\VID_' + $v.Vid + '&PID_([0-9A-F]{4})') -and $Matches[1] -match $v.Pid })
        if ($mine.Count) {
            return [pscustomobject]@{
                Brand    = $v.Brand
                Family   = $v.Family
                NoDriver = [bool]@($mine | Where-Object { $_.ErrorCode -eq 28 }).Count
            }
        }
    }
    $null
}

function Get-HcUsbPhone {
    try {
        $all = @(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'USB%'" -ErrorAction Stop |
            ForEach-Object { [pscustomobject]@{ DeviceId = "$($_.PNPDeviceID)".ToUpperInvariant(); ErrorCode = [int]$_.ConfigManagerErrorCode } })
    } catch { return $null }
    Find-HcUsbPhone $all
}

# --------------------------------------------------------- reading output --
# Pure, so the tests feed them recorded output.

# "R58N12ABCDE  device usb:1-1 product:a52qnsxx model:SM_A525F device:a52q"
function ConvertFrom-HcAdbDevices {
    param([string]$Text)
    foreach ($line in ("$Text" -split "`r?`n")) {
        if ($line -match '^\s*$' -or $line -match '^List of devices' -or $line -match '^\*') { continue }
        $parts = @($line.Trim() -split '\s+')
        if ($parts.Count -lt 2) { continue }
        $model = ''
        foreach ($p in $parts) { if ($p -match '^model:(.+)$') { $model = $Matches[1] -replace '_', ' ' } }
        [pscustomobject]@{ Serial = $parts[0]; State = $parts[1]; Model = $model }
    }
}

# "[ro.product.model]: [SM-A525F]"
function ConvertFrom-HcGetprop {
    param([string]$Text)
    $props = @{}
    foreach ($line in ("$Text" -split "`r?`n")) {
        if ($line -match '^\[([^\]]+)\]: \[(.*)\]\s*$') { $props[$Matches[1]] = $Matches[2] }
    }
    $props
}

function ConvertFrom-HcMeminfo {
    param([string]$Text)
    $total = $null; $free = $null
    if ($Text -match 'MemTotal:\s+(\d+)') { $total = [int64]$Matches[1] }
    if ($Text -match 'MemAvailable:\s+(\d+)') { $free = [int64]$Matches[1] }
    [pscustomobject]@{ TotalKB = $total; AvailableKB = $free }
}

# "/dev/block/dm-6  113000000 50000000 63000000  45% /data"; a long device
# name can push the numbers onto the next line, so the whole text is matched.
function ConvertFrom-HcDf {
    param([string]$Text)
    if ($Text -match '(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+/data') {
        return [pscustomobject]@{ TotalKB = [int64]$Matches[1]; FreeKB = [int64]$Matches[3] }
    }
    $null
}

# Settings > Storage's own figures, in bytes.
$script:PhoneStorageKinds = [ordered]@{
    'Photos Size'    = 'photos'
    'Videos Size'    = 'videos'
    'App Size'       = 'apps'
    'App Data Size'  = 'appData'
    'App Cache Size' = 'cache'
    'Audio Size'     = 'audio'
    'Downloads Size' = 'downloads'
    'Other Size'     = 'other'
}
function ConvertFrom-HcDiskstats {
    param([string]$Text)
    $sizes = [ordered]@{}
    foreach ($key in $script:PhoneStorageKinds.Keys) {
        if ($Text -match ('(?m)^' + [regex]::Escape($key) + ':\s*(\d+)')) { $sizes[$script:PhoneStorageKinds[$key]] = [int64]$Matches[1] }
    }
    $sizes
}

function ConvertFrom-HcBattery {
    param([string]$Text)
    $get = { param($name) if ($Text -match ('(?m)^\s*' + $name + ':\s*(\S+)')) { $Matches[1] } else { $null } }
    $level = & $get 'level'
    $health = & $get 'health'
    $temp = & $get 'temperature'
    $status = & $get 'status'
    $plugged = $false
    foreach ($source in @('AC powered', 'USB powered', 'Wireless powered', 'Dock powered')) {
        if ((& $get $source) -eq 'true') { $plugged = $true }
    }
    # 0 means "not known": Shamil's Galaxy S24 Ultra reported 0 (5 Oct).
    $cycles = $null
    if ($Text -match '(?im)cycle[ _]?count:\s*(\d+)' -and [int]$Matches[1] -gt 0) { $cycles = [int]$Matches[1] }
    [pscustomobject]@{
        Level   = $(if ($level -match '^\d+$') { [int]$level })
        Health  = $(if ($health -match '^\d+$') { [int]$health })
        TempC   = $(if ($temp -match '^-?\d+$') { [Math]::Round([int]$temp / 10, 1) })
        Status  = $(if ($status -match '^\d+$') { [int]$status })
        Plugged = $plugged
        Cycles  = $cycles
    }
}

# "com.a/com.a.Service:com.b/.Other" -> com.a, com.b
function ConvertFrom-HcComponentList {
    param([string]$Text)
    if (-not $Text -or $Text -eq 'null') { return @() }
    @($Text -split ':' | ForEach-Object { ($_ -split '/')[0].Trim() } | Where-Object { $_ -match '^[A-Za-z]\w*(\.\w+)+$' } | Select-Object -Unique)
}

# "package:com.x  installer=com.android.vending"
function ConvertFrom-HcPackageInstallers {
    param([string]$Text)
    foreach ($line in ("$Text" -split "`r?`n")) {
        if ($line -match '^package:(\S+)(?:\s+installer=(\S*))?') {
            [pscustomobject]@{ Package = $Matches[1]; Installer = $(if ($Matches[2] -and $Matches[2] -ne 'null') { $Matches[2] } else { $null }) }
        }
    }
}

# The device admin apps: "ComponentInfo{com.x/com.x.Admin}" on older Android,
# "    com.x/.Admin:" under "Enabled Device Admins" on newer.
function ConvertFrom-HcDevicePolicy {
    param([string]$Text)
    $found = @([regex]::Matches("$Text", 'ComponentInfo\{([A-Za-z]\w*(?:\.\w+)+)/') | ForEach-Object { $_.Groups[1].Value })
    $inAdmins = $false
    foreach ($line in ("$Text" -split "`r?`n")) {
        if ($line -match 'Enabled Device Admins') { $inAdmins = $true; continue }
        if ($inAdmins -and $line -match '^\s+([A-Za-z]\w*(?:\.\w+)+)/[\w.$]+:\s*$') { $found += $Matches[1]; continue }
        if ($inAdmins -and $line -match '^\S') { $inAdmins = $false }
    }
    @($found | Select-Object -Unique)
}

# One package name per line (appops query-op).
function ConvertFrom-HcPackageLines {
    param([string]$Text)
    @("$Text" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z]\w*(\.\w+)+$' } | Select-Object -Unique)
}

# $true = an answer came back, $false = none, $null = the test could not run.
function ConvertFrom-HcPing {
    param([string]$Text)
    if ($null -eq $Text) { return $null }
    if ($Text -match '\b1 (packets )?received' -or $Text -match '\s0% packet loss') { return $true }
    if ($Text -match '100% packet loss' -or $Text -match 'unknown host' -or $Text -match '0 received') { return $false }
    $null
}

# The name the owner knows, with the model code after it: "Samsung Galaxy
# S24 Ultra (SM-S928B)". Samsung keeps the sales name out of the build
# properties but puts it in the device name (Settings > About phone), which
# the owner can also have changed: "Phone of Gerda (Samsung SM-S928B)".
$script:PhoneSeries = '^(Galaxy|Pixel|Redmi|POCO|Mi |Xiaomi|Xperia|moto|Nokia|OnePlus|realme|OPPO|Find|Reno|vivo|HUAWEI|nova|P\d)'
function Get-HcPhoneName {
    param([hashtable]$Props, [string]$DeviceName)
    $base = Get-HcPhoneBaseName $Props
    $code = "$($Props['ro.product.model'])"
    $DeviceName = "$DeviceName".Trim()
    if (-not $DeviceName -or $DeviceName -eq $code -or $base -like "*$DeviceName*") { return $base }
    $maker = "$($Props['ro.product.manufacturer'])"
    if ($maker) { $maker = $maker.Substring(0, 1).ToUpperInvariant() + $maker.Substring(1) }
    if ($DeviceName -match $script:PhoneSeries) {
        $friendly = if ($maker -and $DeviceName -notlike "$maker*") { "$maker $DeviceName" } else { $DeviceName }
        if ($code) { return "$friendly ($code)" }
        return $friendly
    }
    "$DeviceName ($(("$maker $code").Trim()))"
}

# "Samsung SM-A525F", or the marketing name when the maker sets one.
function Get-HcPhoneBaseName {
    param([hashtable]$Props)
    $maker = "$($Props['ro.product.manufacturer'])"
    if (-not $maker) { $maker = "$($Props['ro.product.brand'])" }
    if ($maker) { $maker = $maker.Substring(0, 1).ToUpperInvariant() + $maker.Substring(1) }
    $market = ''
    foreach ($key in @('ro.product.marketname', 'ro.product.vendor.marketname', 'ro.config.marketing_name')) {
        if ($Props[$key]) { $market = $Props[$key]; break }
    }
    $model = if ($market) { $market } else { "$($Props['ro.product.model'])" }
    if (-not $maker) { return $model }
    if ($model -like "$maker*") { return $model }
    ("$maker $model").Trim()
}

# ------------------------------------------------------------------ facts --

<#
    Everything the M checks look at. With no tool, no device, or a device
    that has not allowed this laptop yet, only the connection part is filled
    in. -Network adds the two pings (M5), which take a few seconds.
#>
function Get-HcPhoneFacts {
    # -Safety adds M7's lists: apps and where they came from, and which apps
    # have Accessibility, notification access or device admin. -Prefer reads
    # that device when it is ready (M8: the one just connected over Wi-Fi).
    param([switch]$Network, [switch]$Safety, [string]$Prefer = $script:HcPhonePrefer)
    $facts = [pscustomobject]@{
        AdbFound = $false; Devices = @(); Serial = $null; Name = $null; Now = (Get-Date)
        Android = $null; Sdk = $null; Patch = $null; RamKB = $null; RamFreeKB = $null; UptimeSec = $null
        DataTotalKB = $null; DataFreeKB = $null; Storage = [ordered]@{}; Battery = $null; Apps = $null
        AutoTime = $null; AutoZone = $null; Airplane = $null; WifiOn = $null; MobileData = $null
        PrivateDns = $null; PrivateDnsHost = $null; ScreenTimeoutMs = $null; PowerSave = $null
        ClockOffsetSec = $null; PingIp = $null; PingName = $null; CablePhone = $null
        Packages = $null; Accessibility = @(); Listeners = @(); Admins = $null; InstallAllowed = $null; PlayProtect = $null
    }
    if (-not (Get-HcAdbPath)) { $facts.CablePhone = Get-HcUsbPhone; return $facts }
    $facts.AdbFound = $true

    try { $list = Invoke-HcAdb 'devices -l' -TimeoutSec 20 } catch { $list = $null }
    if ($list -and $list.Ok) { $facts.Devices = @(ConvertFrom-HcAdbDevices $list.Out) }
    $ready = @($facts.Devices | Where-Object { $_.State -eq 'device' })
    if (-not $ready.Count) { $facts.CablePhone = Get-HcUsbPhone; return $facts }
    $preferred = @($ready | Where-Object { $_.Serial -eq $Prefer })
    if ($preferred.Count) { $ready = @($preferred) + @($ready | Where-Object { $_.Serial -ne $Prefer }) }
    $serial = $ready[0].Serial
    $facts.Serial = $serial

    $props = ConvertFrom-HcGetprop (Get-HcAdbText $serial 'getprop')
    $facts.Name = Get-HcPhoneName $props (Get-HcPhoneSetting $serial global device_name)
    if (-not $facts.Name) { $facts.Name = $ready[0].Model }
    $facts.Android = $props['ro.build.version.release']
    if ($props['ro.build.version.sdk'] -match '^\d+$') { $facts.Sdk = [int]$props['ro.build.version.sdk'] }
    try { $facts.Patch = [datetime]::ParseExact($props['ro.build.version.security_patch'], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } catch { }

    $mem = ConvertFrom-HcMeminfo (Get-HcAdbText $serial 'cat /proc/meminfo')
    $facts.RamKB = $mem.TotalKB
    $facts.RamFreeKB = $mem.AvailableKB
    if ("$(Get-HcAdbText $serial 'cat /proc/uptime')" -match '^(\d+)') { $facts.UptimeSec = [int64]$Matches[1] }
    $df = ConvertFrom-HcDf (Get-HcAdbText $serial 'df -k /data')
    if ($df) { $facts.DataTotalKB = $df.TotalKB; $facts.DataFreeKB = $df.FreeKB }
    $facts.Storage = ConvertFrom-HcDiskstats (Get-HcAdbText $serial 'dumpsys diskstats')
    $facts.Battery = ConvertFrom-HcBattery (Get-HcAdbText $serial 'dumpsys battery')
    $apps = Get-HcAdbText $serial 'pm list packages -3'
    if ($null -ne $apps) { $facts.Apps = @("$apps" -split "`r?`n" | Where-Object { $_ -match '^package:' }).Count }

    $facts.AutoTime = Get-HcPhoneSetting $serial global auto_time
    $facts.AutoZone = Get-HcPhoneSetting $serial global auto_time_zone
    $facts.Airplane = Get-HcPhoneSetting $serial global airplane_mode_on
    $facts.WifiOn = Get-HcPhoneSetting $serial global wifi_on
    $facts.MobileData = Get-HcPhoneSetting $serial global mobile_data
    $facts.PrivateDns = Get-HcPhoneSetting $serial global private_dns_mode
    $facts.PrivateDnsHost = Get-HcPhoneSetting $serial global private_dns_specifier
    $facts.PowerSave = Get-HcPhoneSetting $serial global low_power
    $timeout = Get-HcPhoneSetting $serial system screen_off_timeout
    if ($timeout -match '^\d+$') { $facts.ScreenTimeoutMs = [int64]$timeout }

    $deviceTime = "$(Get-HcAdbText $serial 'date +%s')".Trim()
    if ($deviceTime -match '^\d+$') {
        $laptop = [int64]([DateTime]::UtcNow - [datetime]'1970-01-01').TotalSeconds
        $facts.ClockOffsetSec = [int64]$deviceTime - $laptop
    }
    if ($Network) {
        $facts.PingIp = ConvertFrom-HcPing (Invoke-HcAdbPing $serial '8.8.8.8')
        $facts.PingName = ConvertFrom-HcPing (Invoke-HcAdbPing $serial 'google.com')
    }
    if ($Safety) {
        $list = Get-HcAdbText $serial 'pm list packages -3 -i'
        if ($null -ne $list) { $facts.Packages = @(ConvertFrom-HcPackageInstallers $list) }
        $facts.Accessibility = ConvertFrom-HcComponentList (Get-HcPhoneSetting $serial secure enabled_accessibility_services)
        $facts.Listeners = ConvertFrom-HcComponentList (Get-HcPhoneSetting $serial secure enabled_notification_listeners)
        $policy = Get-HcAdbText $serial 'dumpsys device_policy'
        if ($null -ne $policy) { $facts.Admins = ConvertFrom-HcDevicePolicy $policy }
        $allowed = Get-HcAdbText $serial 'appops query-op REQUEST_INSTALL_PACKAGES allow'
        if ($null -ne $allowed) { $facts.InstallAllowed = ConvertFrom-HcPackageLines $allowed }
        # -1 = the owner switched Play Protect's scanning off.
        $facts.PlayProtect = Get-HcPhoneSetting $serial global package_verifier_user_consent
    }
    $facts
}

# ping exits with 1 when nothing comes back, so its text is used either way.
function Invoke-HcAdbPing {
    param([string]$Serial, [string]$Target)
    try { $r = Invoke-HcAdb "shell ping -c 1 -W 3 $Target" -Serial $Serial -TimeoutSec 10 } catch { return $null }
    if ($r.ExitCode -lt 0) { return $null }
    "$($r.Out)$($r.Err)"
}

# ---------------------------------------------------------------- verdict --

function Format-HcPhoneSize {
    param([double]$KB)
    $gb = $KB * 1024 / 1e9
    $sep = if ($script:Lang -eq 'nl') { ',' } else { '.' }
    if ($gb -lt 10) { return ('{0:0.0} GB' -f $gb).Replace('.', $sep) }
    '{0:0} GB' -f $gb
}

function Format-HcPhoneOffset {
    param([double]$Seconds)
    $s = [Math]::Abs($Seconds)
    if ($s -ge 86400) { return T 'and.days' ([int][Math]::Round($s / 86400)) }
    if ($s -ge 3600) { return T 'and.hours' ([int][Math]::Round($s / 3600)) }
    T 'and.minutes' ([int][Math]::Round($s / 60))
}

function Get-HcPatchMonths {
    param([pscustomobject]$Facts)
    if (-not $Facts.Patch) { return $null }
    [int][Math]::Floor(($Facts.Now - $Facts.Patch).TotalDays / 30.44)
}

<#
    The connection, first in every M check. Returns $true when a device is
    ready to read; otherwise the report already holds the reason.
#>
function Test-HcPhoneConnection {
    param([pscustomobject]$Report, [pscustomobject]$Facts)
    $cable = $Facts.CablePhone
    if ($cable -and $cable.Family -eq 'apple') {
        Add-HcLine $Report problem (T 'and.iphone')
        Set-HcFinding $Report 'iphoneFound'
        return $false
    }
    if (-not $Facts.AdbFound) {
        Add-HcLine $Report problem (T 'and.adbMissing')
        if ($cable) { Add-HcLine $Report ok (T 'and.cablePhone' $cable.Brand) }
        Add-HcAction $Report 'getAdb'
        Set-HcFinding $Report 'adbMissing'
        Add-HcLine $Report skipped (T 'net.skipped')
        return $false
    }
    Add-HcLine $Report ok (T 'and.adbFound')
    $devices = @($Facts.Devices)
    $ready = @($devices | Where-Object { $_.State -eq 'device' })
    if (-not $ready.Count) {
        $locked = @($devices | Where-Object { $_.State -eq 'unauthorized' }) | Select-Object -First 1
        $silent = @($devices | Where-Object { $_.State -ne 'unauthorized' }) | Select-Object -First 1
        if ($locked) {
            Add-HcLine $Report problem (T 'and.unauthorized' $(if ($locked.Model) { $locked.Model } else { $locked.Serial }))
            Set-HcFinding $Report 'phoneUnauthorized'
        } elseif ($silent) {
            Add-HcLine $Report problem (T 'and.offline' $(if ($silent.Model) { $silent.Model } else { $silent.Serial }))
            Set-HcFinding $Report 'phoneOffline'
        } elseif ($cable -and $cable.NoDriver) {
            Add-HcLine $Report problem (T 'and.noDriver' $cable.Brand)
            Set-HcFinding $Report 'phoneNoDriver' @($cable.Brand)
        } elseif ($cable) {
            # Android never lets a computer switch this on: it is done on the
            # phone, once. The brand picks the steps with that brand's menus.
            Add-HcLine $Report problem (T 'and.debugOff' $cable.Brand)
            Set-HcFinding $Report $script:PhoneDebugFindings[$cable.Family] @($cable.Brand)
        } else {
            Add-HcLine $Report problem (T 'and.noDevice')
            Set-HcFinding $Report 'phoneNotFound'
        }
        Add-HcLine $Report skipped (T 'net.skipped')
        return $false
    }
    $version = if ($Facts.Android) { $Facts.Android } else { '?' }
    Add-HcLine $Report ok (T 'and.connected' $Facts.Name $version)
    if ($ready.Count -gt 1) { Add-HcLine $Report warn (T 'and.several' $ready.Count $Facts.Name) }
    $true
}

# The fix offered at the end of every report on a connected device.
function Add-HcPhoneDoneAction {
    param([pscustomobject]$Report, [pscustomobject]$Facts)
    Add-HcAction $Report 'phoneDebugOff' @{ Serial = $Facts.Serial; Label = $Facts.Name }
}

function Add-HcPhoneStorageLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    if (-not $Facts.DataTotalKB) { Add-HcLine $Report skipped (T 'and.storageUnknown'); return }
    $pct = [int][Math]::Round(100 * $Facts.DataFreeKB / $Facts.DataTotalKB)
    $line = T 'and.storage' (Format-HcPhoneSize $Facts.DataFreeKB) (Format-HcPhoneSize $Facts.DataTotalKB) $pct
    $freeGB = $Facts.DataFreeKB * 1024 / 1e9
    if ($pct -lt $script:PhoneStorageFullPercent -or $freeGB -lt $script:PhoneStorageFullGB) {
        Add-HcLine $Report problem $line
        $Found['phoneStorageFull'] = @(Format-HcPhoneSize $Facts.DataFreeKB)
    } elseif ($pct -lt $script:PhoneStorageLowPercent) {
        Add-HcLine $Report warn $line
        $Found['phoneStorageLow'] = @(Format-HcPhoneSize $Facts.DataFreeKB)
    } else {
        Add-HcLine $Report ok $line
    }
}

function Add-HcPhoneMemoryLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    if (-not $Facts.RamKB) { return }
    $line = T 'and.ram' (Format-HcPhoneSize $Facts.RamKB) (Format-HcPhoneSize $Facts.RamFreeKB)
    $totalGB = $Facts.RamKB * 1024 / 1e9
    $freePct = if ($Facts.RamFreeKB) { 100 * $Facts.RamFreeKB / $Facts.RamKB } else { 100 }
    if ($freePct -lt $script:PhoneMemoryFullPercent) {
        Add-HcLine $Report warn $line
        $Found['phoneMemoryFull'] = @()
    } elseif ($totalGB -lt $script:PhoneLowRamGB) {
        Add-HcLine $Report warn $line
        $Found['phoneLowRam'] = @(Format-HcPhoneSize $Facts.RamKB)
    } else {
        Add-HcLine $Report ok $line
    }
}

function Add-HcPhoneUptimeLine {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    if ($null -eq $Facts.UptimeSec) { return }
    $days = [int][Math]::Floor($Facts.UptimeSec / 86400)
    if ($days -ge $script:PhoneUptimeDays) {
        Add-HcLine $Report warn (T 'and.uptime' $days)
        $Found['phoneLongUptime'] = @($days)
    } else {
        Add-HcLine $Report ok (T 'and.uptime' $days)
    }
}

function Add-HcPhoneVersionLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    if ($Facts.Sdk -and $Facts.Sdk -lt $script:PhoneOldSdk) {
        Add-HcLine $Report problem (T 'and.androidOld' $Facts.Android)
        $Found['androidOld'] = @($Facts.Android)
    }
    $months = Get-HcPatchMonths $Facts
    if ($null -eq $months) { Add-HcLine $Report skipped (T 'and.patchUnknown'); return }
    $line = T 'and.patch' ($Facts.Patch.ToString('MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))) $months
    if ($months -ge $script:PhonePatchOldMonths) {
        Add-HcLine $Report problem $line
        $Found['phonePatchOld'] = @($months)
    } elseif ($months -ge $script:PhonePatchStaleMonths) {
        Add-HcLine $Report warn $line
        $Found['phonePatchStale'] = @($months)
    } else {
        Add-HcLine $Report ok $line
    }
}

function Add-HcPhoneBatteryLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    $b = $Facts.Battery
    if (-not $b -or $null -eq $b.Level) { Add-HcLine $Report skipped (T 'and.batteryUnknown'); return }
    $state = switch ($b.Status) { 2 { 'charging' } 5 { 'full' } 4 { 'notCharging' } default { if ($b.Plugged) { 'plugged' } else { 'onBattery' } } }
    $line = T 'and.battery' $b.Level (T "and.bat.$state")
    if ($b.Plugged -and $state -eq 'notCharging' -and $b.Level -lt 95) {
        Add-HcLine $Report problem $line
        $Found['phoneNotCharging'] = @($b.Level)
    } else {
        Add-HcLine $Report ok $line
    }
    # 2 = good, 7 = cold; the rest (overheat, dead, over voltage, failure) is a fault.
    if ($null -ne $b.Health) {
        $text = T 'and.health' (T $(if ($b.Health -in 2..7) { "and.health.$($b.Health)" } else { 'and.health.1' }))
        if ($b.Health -in 3..6) {
            Add-HcLine $Report problem $text
            $Found['phoneBatteryBad'] = @(T "and.health.$($b.Health)")
        } elseif ($b.Health -eq 7) {
            Add-HcLine $Report warn $text
        } else {
            Add-HcLine $Report ok $text
        }
    }
    if ($null -ne $b.TempC) {
        $temp = T 'and.temp' ("$($b.TempC)" -replace '\.', $(if ($script:Lang -eq 'nl') { ',' } else { '.' }))
        if ($b.TempC -ge $script:PhoneHotCelsius) {
            Add-HcLine $Report problem $temp
            $Found['phoneHot'] = @($b.TempC)
        } else {
            Add-HcLine $Report ok $temp
        }
    }
    if ($null -ne $b.Cycles) {
        if ($b.Cycles -ge $script:PhoneWornCycles) {
            Add-HcLine $Report warn (T 'and.cycles' $b.Cycles)
            $Found['phoneBatteryWorn'] = @($b.Cycles)
        } else {
            Add-HcLine $Report ok (T 'and.cycles' $b.Cycles)
        }
    }
}

# M1.
function Test-HcPhoneOverview {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    Add-HcPhoneVersionLines $r $found $Facts
    Add-HcPhoneMemoryLines $r $found $Facts
    Add-HcPhoneStorageLines $r $found $Facts
    Add-HcPhoneBatteryLines $r $found $Facts
    Add-HcPhoneUptimeLine $r $found $Facts
    if ($null -ne $Facts.Apps) { Add-HcLine $r ok (T 'and.apps' $Facts.Apps) }
    # The tools, as buttons under the overview.
    $device = @{ Serial = $Facts.Serial; Label = $Facts.Name }
    Add-HcAction $r 'phoneMirror' $device
    Add-HcAction $r 'phoneScreenshot' $device
    Add-HcAction $r 'phoneRestart' $device
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('phoneStorageFull', 'phoneBatteryBad', 'phoneHot', 'phoneNotCharging', 'androidOld', 'phonePatchOld', 'phoneMemoryFull', 'phoneStorageLow', 'phonePatchStale', 'phoneLowRam', 'phoneBatteryWorn', 'phoneLongUptime') 'phoneOverviewOk'
    $r
}

# M2.
function Test-HcPhoneSlow {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    Add-HcPhoneStorageLines $r $found $Facts
    Add-HcPhoneMemoryLines $r $found $Facts
    Add-HcPhoneUptimeLine $r $found $Facts
    if ($Facts.Sdk -and $Facts.Sdk -lt $script:PhoneOldSdk) {
        Add-HcLine $r warn (T 'and.androidOld' $Facts.Android)
        $found['androidOld'] = @($Facts.Android)
    }
    if ($null -ne $Facts.Apps) { Add-HcLine $r ok (T 'and.apps' $Facts.Apps) }
    if ($found['phoneStorageFull'] -or $found['phoneStorageLow']) { Add-HcAction $r 'phoneOpenStorage' @{ Serial = $Facts.Serial } }
    if ($found['phoneLongUptime'] -or $found['phoneMemoryFull']) { Add-HcAction $r 'phoneRestart' @{ Serial = $Facts.Serial; Label = $Facts.Name } }
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('phoneStorageFull', 'phoneMemoryFull', 'phoneLongUptime', 'phoneLowRam', 'phoneStorageLow', 'androidOld') 'phoneSpeedOk'
    $r
}

# M3.
function Test-HcPhoneStorage {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    Add-HcPhoneStorageLines $r $found $Facts
    # The biggest kinds first, as Settings > Storage shows them; tiny ones left out.
    $kinds = @($Facts.Storage.Keys | ForEach-Object { [pscustomobject]@{ Kind = $_; Bytes = $Facts.Storage[$_] } } |
        Where-Object { $_.Bytes -ge 100MB } | Sort-Object Bytes -Descending)
    foreach ($k in $kinds) {
        Add-HcLine $r ok (T 'and.kind' (T "and.kind.$($k.Kind)") (Format-HcPhoneSize ($k.Bytes / 1024)))
    }
    Add-HcAction $r 'phoneOpenStorage' @{ Serial = $Facts.Serial }
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('phoneStorageFull', 'phoneStorageLow') 'phoneStorageOk'
    $r
}

# M4.
function Test-HcPhoneBattery {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    Add-HcPhoneBatteryLines $r $found $Facts
    if ($null -ne $Facts.ScreenTimeoutMs) {
        $text = T 'and.screenOff' $(if ($Facts.ScreenTimeoutMs -ge 3600000) { T 'and.never' } elseif ($Facts.ScreenTimeoutMs -ge 60000) { T 'and.min' ([int]($Facts.ScreenTimeoutMs / 60000)) } else { T 'and.sec' ([int]($Facts.ScreenTimeoutMs / 1000)) })
        if ($Facts.ScreenTimeoutMs -gt $script:PhoneScreenLongMs) {
            Add-HcLine $r warn $text
            $found['phoneScreenLong'] = @()
        } else {
            Add-HcLine $r ok $text
        }
    }
    if ($Facts.PowerSave -eq '1') { Add-HcLine $r ok (T 'and.powerSave') }
    Add-HcAction $r 'phoneOpenBattery' @{ Serial = $Facts.Serial }
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('phoneBatteryBad', 'phoneHot', 'phoneNotCharging', 'phoneBatteryWorn', 'phoneScreenLong') 'phoneBatteryOk'
    $r
}

# M5. A wrong date is the classic cause of "cannot sign in to Google": the
# secure connection checks certificates against the clock.
function Test-HcPhoneOnline {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    $target = @{ Serial = $Facts.Serial }

    if ($Facts.Airplane -eq '1') {
        Add-HcLine $r problem (T 'and.airplane')
        $found['airplaneOn'] = @()
    }
    $wifi = $Facts.WifiOn -in @('1', '2', '3')
    $data = $Facts.MobileData -eq '1'
    if (-not $wifi -and -not $data -and $null -ne $Facts.WifiOn) {
        Add-HcLine $r problem (T 'and.noNetwork')
        $found['phoneNoNetwork'] = @()
    } else {
        if ($wifi) { Add-HcLine $r ok (T 'and.wifiOn') }
        if ($data) { Add-HcLine $r ok (T 'and.dataOn') }
    }

    $dnsHost = if ($Facts.PrivateDns -eq 'hostname' -and $Facts.PrivateDnsHost) { $Facts.PrivateDnsHost } else { $null }
    if ($null -eq $Facts.PingIp) {
        Add-HcLine $r skipped (T 'and.pingUnknown')
    } elseif (-not $Facts.PingIp) {
        Add-HcLine $r problem (T 'and.noInternet')
        $found['phoneNoInternet'] = @()
    } else {
        Add-HcLine $r ok (T 'and.internetOk')
        if ($Facts.PingName -eq $false) {
            Add-HcLine $r problem (T 'and.dnsFail')
            if ($dnsHost) {
                Add-HcAction $r 'privateDnsAuto' @{ Serial = $Facts.Serial; Label = $dnsHost }
                $found['privateDnsBroken'] = @($dnsHost)
            } else {
                $found['phoneDnsFail'] = @()
            }
        } elseif ($Facts.PingName) {
            Add-HcLine $r ok (T 'and.dnsOk')
        }
    }
    if ($dnsHost -and -not $found['privateDnsBroken']) { Add-HcLine $r ok (T 'and.privateDns' $dnsHost) }

    if ($null -ne $Facts.ClockOffsetSec) {
        if ([Math]::Abs($Facts.ClockOffsetSec) -gt $script:PhoneClockOffSeconds) {
            Add-HcLine $r problem (T 'and.clockWrong' (Format-HcPhoneOffset $Facts.ClockOffsetSec))
            $found['phoneClockWrong'] = @(Format-HcPhoneOffset $Facts.ClockOffsetSec)
        } else {
            Add-HcLine $r ok (T 'and.clockOk')
        }
    }
    if ($Facts.AutoTime -eq '0') {
        Add-HcLine $r warn (T 'and.autoTimeOff')
        Add-HcAction $r 'phoneAutoTime' $target
        $found['phoneAutoTimeOff'] = @()
    } elseif ($Facts.AutoTime -eq '1') {
        Add-HcLine $r ok (T 'and.autoTimeOn')
    }
    if ($Facts.AutoZone -eq '0') {
        Add-HcLine $r warn (T 'and.autoZoneOff')
        Add-HcAction $r 'phoneAutoZone' $target
        $found['phoneAutoZoneOff'] = @()
    }
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('airplaneOn', 'phoneNoNetwork', 'phoneNoInternet', 'privateDnsBroken', 'phoneDnsFail', 'phoneClockWrong', 'phoneAutoTimeOff', 'phoneAutoZoneOff') 'phoneOnlineOk'
    $r
}

# M6.
function Test-HcPhoneUpdates {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    Add-HcPhoneVersionLines $r $found $Facts
    Add-HcAction $r 'phoneOpenUpdates' @{ Serial = $Facts.Serial }
    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('androidOld', 'phonePatchOld', 'phonePatchStale') 'phoneUpdatesOk'
    $r
}

<#
    M7. What harmful apps need, not their names: an app from outside a store
    that can read the screen or the notifications is how banking malware
    works, so that is the strongest finding. Everything else is "ask the
    client": a grandchild's AnyDesk or a password manager is fine. Nothing is
    removed; a button opens the app's own page, where the client can.
#>
function Test-HcPhoneSafety {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    if (-not (Test-HcPhoneConnection $r $Facts)) { return $r }
    $found = @{}
    $buttons = New-Object System.Collections.ArrayList
    $button = {
        param($pkg, $name)
        if ($buttons.Count -lt $script:PhoneMaxAppButtons -and -not $buttons.Contains($pkg)) {
            [void]$buttons.Add($pkg)
            Add-HcAction $r 'phoneOpenApp' @{ Serial = $Facts.Serial; Package = $pkg; Label = $name }
        }
    }
    # A website added to the home screen through Chrome (a "web app") and the
    # maker's own preinstalled apps are not apps from outside a store.
    $outside = @()
    if ($null -ne $Facts.Packages) {
        $outside = @($Facts.Packages | Where-Object { $_ -and (Test-HcSideloaded $_.Installer) -and $_.Package -notlike 'org.chromium.webapk.*' -and -not (Test-HcMakerPackage $_.Package) } | ForEach-Object { $_.Package })
    }

    if ($Facts.PlayProtect -eq '-1') {
        Add-HcLine $r problem (T 'and.protectOff')
        $found['playProtectOff'] = @()
    } elseif ($Facts.PlayProtect -eq '1') {
        Add-HcLine $r ok (T 'and.protectOn')
    }

    # Reading the screen or the notifications: from outside a store = malware's way in.
    foreach ($kind in @(@{ List = $Facts.Accessibility; Line = 'and.accessApp'; Id = 'phoneAccessibilityApp'; None = 'and.accessNone' },
                        @{ List = $Facts.Listeners; Line = 'and.notifyApp'; Id = 'phoneNotifyApp'; None = 'and.notifyNone' })) {
        # "$_ -and": an empty setting ("null") came through as one empty entry
        # and showed as a nameless warning on Shamil's phone (5 Oct).
        $apps = @($kind.List | Where-Object { $_ -and -not (Test-HcMakerPackage $_) })
        foreach ($pkg in $apps) {
            if ($outside -contains $pkg) {
                Add-HcLine $r problem (T 'and.outsideStrong' $pkg)
                if (-not $found['phoneMalwareLikely']) { $found['phoneMalwareLikely'] = @($pkg) }
            } else {
                Add-HcLine $r warn (T $kind.Line $pkg)
                if (-not $found[$kind.Id]) { $found[$kind.Id] = @($pkg) }
            }
            & $button $pkg $pkg
        }
        if (-not $apps.Count) { Add-HcLine $r ok (T $kind.None) }
    }

    $remote = @($Facts.Packages | Where-Object { $_ -and $script:PhoneRemoteApps.Contains($_.Package) })
    foreach ($app in $remote) {
        $name = $script:PhoneRemoteApps[$app.Package]
        Add-HcLine $r warn (T 'and.remoteApp' $name)
        if (-not $found['phoneRemoteApp']) { $found['phoneRemoteApp'] = @($name) }
        & $button $app.Package $name
    }
    if ($null -ne $Facts.Packages -and -not $remote.Count) { Add-HcLine $r ok (T 'and.remoteNone') }

    if ($null -ne $Facts.Admins) {
        $admins = @($Facts.Admins | Where-Object { $_ -and -not (Test-HcMakerPackage $_) })
        foreach ($pkg in $admins) {
            if ($outside -contains $pkg) {
                Add-HcLine $r problem (T 'and.outsideStrong' $pkg)
                if (-not $found['phoneMalwareLikely']) { $found['phoneMalwareLikely'] = @($pkg) }
            } else {
                Add-HcLine $r warn (T 'and.adminApp' $pkg)
                if (-not $found['phoneDeviceAdmin']) { $found['phoneDeviceAdmin'] = @($pkg) }
            }
            & $button $pkg $pkg
        }
        if (-not $admins.Count) { Add-HcLine $r ok (T 'and.adminNone') }
    }

    if ($null -eq $Facts.Packages) {
        Add-HcLine $r skipped (T 'and.appsUnknown')
    } elseif ($outside.Count) {
        $shown = @($outside | Select-Object -First 5) -join ', '
        if ($outside.Count -gt 5) { $shown += ', ...' }
        Add-HcLine $r warn (T 'and.outside' $outside.Count $shown)
        $found['phoneSideloaded'] = @($outside.Count)
        foreach ($pkg in $outside) { & $button $pkg $pkg }
    } else {
        Add-HcLine $r ok (T 'and.outsideNone')
    }

    if ($null -ne $Facts.InstallAllowed) {
        $may = @($Facts.InstallAllowed | Where-Object { $_ -and $script:PhoneStores -notcontains $_ })
        if ($may.Count) {
            $shown = @($may | Select-Object -First 5) -join ', '
            Add-HcLine $r warn (T 'and.mayInstall' $shown)
            $found['phoneUnknownSources'] = @($shown)
        } else {
            Add-HcLine $r ok (T 'and.mayInstallNone')
        }
    }

    Add-HcPhoneDoneAction $r $Facts
    Select-HcFinding $r $found @('phoneMalwareLikely', 'phoneRemoteApp', 'playProtectOff', 'phoneAccessibilityApp', 'phoneNotifyApp', 'phoneDeviceAdmin', 'phoneUnknownSources', 'phoneSideloaded') 'phoneSafeOk'
    $r
}

# ------------------------------------------------------ M8: over Wi-Fi --
# For a car screen, or a tablet without its cable. Android 11 and newer:
# Developer options > Wireless debugging > Pair device with pairing code
# shows an address with a port and a 6-digit code. After pairing, ADB finds
# the device on the network by itself; when it does not, the address and
# port on the Wireless debugging screen itself connect it. This laptop and
# the device must be on the same Wi-Fi (for a car: the same phone hotspot).

<#
    Pure: what was typed. "482915" = only the code: Housecall finds the
    device's pairing address on the network itself (Shamil's wish, 6 Oct).
    "192.168.1.50:41235 482915" = pair at that address, for networks where
    finding does not work; "192.168.1.50:38497" = connect only (already
    paired). Returns Address ($null = find it), Port, Code ($null = connect
    only), or $null when it is none of these.
#>
function ConvertFrom-HcPairInput {
    param([string]$Text)
    $t = "$Text".Trim() -replace '\s+', ' '
    if ($t -match '^\d{6}$') { return [pscustomobject]@{ Address = $null; Port = 0; Code = $t } }
    if ($t -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})(?: (\d{6}))?$') { return $null }
    $address = $Matches[1]; $port = [int]$Matches[2]; $code = $Matches[3]
    foreach ($part in $address -split '\.') { if ([int]$part -gt 255) { return $null } }
    if ($port -lt 1 -or $port -gt 65535) { return $null }
    [pscustomobject]@{ Address = $address; Port = $port; Code = $(if ($code) { $code } else { $null }) }
}

# Pure: "adb mdns services", the devices that announce themselves on the
# network. _adb-tls-pairing = a pairing window is open on it; _adb-tls-connect
# = Wireless debugging is on, ready to connect.
# "adb-R58N12ABCDE-AbCdEf  _adb-tls-pairing._tcp.  192.168.1.50:41235"
function ConvertFrom-HcMdnsServices {
    param([string]$Text)
    foreach ($line in ("$Text" -split "`r?`n")) {
        if ($line -match '^\s*(\S+)\s+_adb-tls-(pairing|connect)\._tcp\.?\s+(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})\s*$') {
            [pscustomobject]@{ Name = $Matches[1]; Kind = $Matches[2]; Address = $Matches[3]; Port = [int]$Matches[4] }
        }
    }
}

# Looks up to $Seconds for a device announcing $Kind (pairing or connect),
# at $Address when given.
function Find-HcMdnsDevice {
    param([string]$Kind, [string]$Address, [int]$Seconds = 8)
    for ($i = 0; $i -lt $Seconds; $i++) {
        try { $r = Invoke-HcAdb 'mdns services' -TimeoutSec 10 } catch { return $null }
        $found = @(ConvertFrom-HcMdnsServices $r.Out | Where-Object { $_.Kind -eq $Kind -and (-not $Address -or $_.Address -eq $Address) }) | Select-Object -First 1
        if ($found) { return $found }
        Start-Sleep -Seconds 1
    }
    $null
}

# Pure: what adb pair / adb connect answered.
function Test-HcAdbAnswer {
    param([string]$Kind, [string]$Text)
    if ($Kind -eq 'pair') { return ($Text -match 'Successfully paired') }
    $Text -match '(^|\s)(already )?connected to '
}

<#
    Pure: the lines and the finding for the Wi-Fi step. Ok = a device is
    ready to read. Outcome: PairText / ConnectText (adb's answers, $null when
    that step did not run) and Serial (the device that came up, or $null).
#>
function Test-HcPairOutcome {
    param([pscustomobject]$Request, [pscustomobject]$Outcome)
    $r = New-HcReport
    # Only the code typed: the address is the one found on the network.
    $target = if ($Outcome.Address) { "$($Outcome.Address):$($Outcome.Port)" } else { "$($Request.Address):$($Request.Port)" }
    $short = { param($text) $line = @("$text" -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1; if ($line) { "$line".Trim() } else { '?' } }
    if ($Outcome.Already) {
        # nothing to pair or connect: the device is on Wi-Fi already
    } elseif ($Outcome.NotFound) {
        Add-HcLine $r problem (T 'and.pairNotFound')
        Set-HcFinding $r 'pairNotFound'
        return [pscustomobject]@{ Ok = $false; Report = $r }
    } elseif ($Request.Code) {
        if (-not (Test-HcAdbAnswer 'pair' $Outcome.PairText)) {
            Add-HcLine $r problem (T 'and.pairFailed' $target (& $short $Outcome.PairText))
            Set-HcFinding $r 'pairFailed'
            return [pscustomobject]@{ Ok = $false; Report = $r }
        }
        Add-HcLine $r ok (T 'and.paired' $target)
        if (-not $Outcome.Serial) {
            Add-HcLine $r problem (T 'and.pairedNoDevice')
            Set-HcFinding $r 'pairedNoConnect'
            return [pscustomobject]@{ Ok = $false; Report = $r }
        }
    } else {
        if (-not (Test-HcAdbAnswer 'connect' $Outcome.ConnectText) -or -not $Outcome.Serial) {
            Add-HcLine $r problem (T 'and.connectFailed' $target (& $short $Outcome.ConnectText))
            Set-HcFinding $r 'connectFailed'
            return [pscustomobject]@{ Ok = $false; Report = $r }
        }
    }
    Add-HcLine $r ok (T 'and.wifiConnected')
    [pscustomobject]@{ Ok = $true; Report = $r }
}

function Get-HcReadySerials {
    try { $list = Invoke-HcAdb 'devices -l' -TimeoutSec 15 } catch { return @() }
    @(ConvertFrom-HcAdbDevices $list.Out | Where-Object { $_.State -eq 'device' } | ForEach-Object { $_.Serial })
}

# Pairs (when there is a code) and connects, then shows M1's overview of
# that device, with the Wi-Fi lines on top.
function Invoke-HcPairCheck {
    param([string]$Address, [int]$Port, [string]$Code)
    $request = [pscustomobject]@{ Address = $Address; Port = $Port; Code = $(if ($Code) { $Code } else { $null }) }
    $facts = Get-HcPhoneFacts
    if (-not $facts.AdbFound) { return (Test-HcPhoneOverview $facts) }
    $before = Get-HcReadySerials
    $outcome = [pscustomobject]@{ PairText = $null; ConnectText = $null; Serial = $null; Already = $false; NotFound = $false; Address = $null; Port = 0 }
    $target = "${Address}:$Port"
    # Already on Wi-Fi (the check runs again after every fix, and a pairing
    # code works only once): read that device instead of pairing again.
    $onWifi = @($before | Where-Object { Test-HcWifiSerial $_ })
    if ($onWifi.Count) {
        $outcome.Already = $true
        $outcome.Serial = $(if ($onWifi -contains $target) { $target } else { $onWifi[0] })
    } elseif ($Code) {
        if (-not $Address) {
            # Only the code: the device with its pairing window open
            # announces itself on the network.
            $found = Find-HcMdnsDevice 'pairing' -Seconds 8
            if ($found) { $Address = $found.Address; $Port = $found.Port; $target = "${Address}:$Port"; $outcome.Address = $Address; $outcome.Port = $Port }
            else { $outcome.NotFound = $true }
        }
        if (-not $outcome.NotFound) {
            $r = Invoke-HcAdb "pair $target $Code" -TimeoutSec 30
            $outcome.PairText = "$($r.Out) $($r.Err)"
        }
        if ($outcome.PairText -and (Test-HcAdbAnswer 'pair' $outcome.PairText)) {
            # ADB finds the paired device on the network by itself.
            for ($i = 0; $i -lt 10 -and -not $outcome.Serial; $i++) {
                Start-Sleep -Seconds 1
                $outcome.Serial = @(Get-HcReadySerials | Where-Object { $before -notcontains $_ }) | Select-Object -First 1
            }
            # It did not: connect to the address it announces for that.
            if (-not $outcome.Serial) {
                $ready = Find-HcMdnsDevice 'connect' $Address -Seconds 5
                if ($ready) {
                    $c = "$($ready.Address):$($ready.Port)"
                    [void](Invoke-HcAdb "connect $c" -TimeoutSec 20)
                    $outcome.Serial = @(Get-HcReadySerials | Where-Object { $_ -eq $c -or $before -notcontains $_ }) | Select-Object -First 1
                }
            }
        }
    } else {
        $r = Invoke-HcAdb "connect $target" -TimeoutSec 20
        $outcome.ConnectText = "$($r.Out) $($r.Err)"
        if (Test-HcAdbAnswer 'connect' $outcome.ConnectText) {
            $ready = Get-HcReadySerials
            $outcome.Serial = @($ready | Where-Object { $_ -eq $target -or $before -notcontains $_ }) | Select-Object -First 1
        }
    }
    $step = Test-HcPairOutcome $request $outcome
    if (-not $step.Ok) { return $step.Report }
    $report = Test-HcPhoneOverview (Get-HcPhoneFacts -Prefer $outcome.Serial)
    $i = 0
    foreach ($line in $step.Report.Results) { $report.Results.Insert($i, $line); $i++ }
    $report
}

# Console: asks for the address and code, like A3 asks for a website.
function Invoke-HcM8 {
    $parsed = $null
    while (-not $parsed) {
        $typed = Read-HcLine (T 'pair.ask')
        if (-not "$typed".Trim() -or "$typed".Trim().ToUpperInvariant() -eq 'Q') { return }
        $parsed = ConvertFrom-HcPairInput $typed
        if (-not $parsed) { Write-Warn2 (T 'pair.invalid' $typed) }
    }
    Write-Host ''
    New-HcPairCheck $parsed
}

# The check as a scriptblock built from validated digits and dots only.
function New-HcPairCheck {
    param([pscustomobject]$Parsed)
    if (-not $Parsed) { return $null }
    $code = if ($Parsed.Code) { "'$($Parsed.Code)'" } else { "''" }
    if ($Parsed.Address -and $Parsed.Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $null }
    if ($code -notmatch "^'\d{0,6}'$") { return $null }
    [scriptblock]::Create("Invoke-HcPairCheck '$($Parsed.Address)' $([int]$Parsed.Port) $code")
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcM1 { { Test-HcPhoneOverview (Get-HcPhoneFacts) } }
function Invoke-HcM2 { { Test-HcPhoneSlow (Get-HcPhoneFacts) } }
function Invoke-HcM3 { { Test-HcPhoneStorage (Get-HcPhoneFacts) } }
function Invoke-HcM4 { { Test-HcPhoneBattery (Get-HcPhoneFacts) } }
function Invoke-HcM5 { { Test-HcPhoneOnline (Get-HcPhoneFacts -Network) } }
function Invoke-HcM6 { { Test-HcPhoneUpdates (Get-HcPhoneFacts) } }
function Invoke-HcM7 { { Test-HcPhoneSafety (Get-HcPhoneFacts -Safety) } }

$script:ProblemHandlers['M1'] = 'Invoke-HcM1'
$script:ProblemHandlers['M2'] = 'Invoke-HcM2'
$script:ProblemHandlers['M3'] = 'Invoke-HcM3'
$script:ProblemHandlers['M4'] = 'Invoke-HcM4'
$script:ProblemHandlers['M5'] = 'Invoke-HcM5'
$script:ProblemHandlers['M6'] = 'Invoke-HcM6'
$script:ProblemHandlers['M7'] = 'Invoke-HcM7'
$script:ProblemHandlers['M8'] = 'Invoke-HcM8'
