<#
    Phase 7, batch 2 (6 Oct 2026).

      F4  is something using my camera or microphone?
                                  Windows' own record per app (CapabilityAccess-
                                  Manager): when each last used the camera or
                                  microphone, and whether one is using it now.
                                  Remote-access tools and programs run from
                                  Downloads or a temp folder are flagged.
      G4  is there a backup of my photos?
                                  the Pictures folder (where, how many photos:
                                  counted, never listed), OneDrive (installed,
                                  signed in, running), File History, Google
                                  Drive / iCloud
      G5  links or email open in the wrong program
                                  the program for web links and for email
                                  links (mailto), the old retired Mail app,
                                  Internet Explorer
      B6  a second screen or TV shows nothing
                                  the screens Windows sees (by name) against
                                  the desktops it shows: the same picture on
                                  both, one switched off, or none found

    Read-only; the fixes open Settings, start OneDrive, or switch the screen
    mode the way Windows + P does.
#>

# ----------------------------------------------- F4: camera and microphone --

$script:CamMicRecentDays = 14

function ConvertFrom-HcFileTime {
    param($Value)
    if (-not $Value -or [int64]$Value -le 0) { return $null }
    try { [DateTime]::FromFileTime([int64]$Value) } catch { $null }
}

# Pure: an app's name from its consent-store key. "5319275A.WhatsAppDesktop_cv1g..."
# -> "WhatsAppDesktop"; "C:#Program Files#Zoom#bin#Zoom.exe" -> "Zoom".
function Get-HcConsentAppName {
    param([string]$Key, [string]$Description)
    if ($Key -match '#') {
        if ($Description) { return $Description }
        return [IO.Path]::GetFileNameWithoutExtension(($Key -replace '#', '\'))
    }
    $name = ($Key -split '_')[0]
    @($name -split '\.')[-1]
}

function Get-HcCamMicFacts {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    $uses = foreach ($kind in @('webcam', 'microphone')) {
        $keys = @(Get-ChildItem "$base\$kind" -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' }) +
                @(Get-ChildItem "$base\$kind\NonPackaged" -ErrorAction SilentlyContinue)
        foreach ($k in $keys) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            $start = ConvertFrom-HcFileTime $p.LastUsedTimeStart
            if (-not $start) { continue }
            $path = if ($k.PSChildName -match '#') { $k.PSChildName -replace '#', '\' } else { $null }
            $desc = $null
            if ($path -and (Test-Path -LiteralPath $path)) { $desc = (Get-Item -LiteralPath $path -ErrorAction SilentlyContinue).VersionInfo.FileDescription }
            [pscustomobject]@{
                Kind  = $kind
                App   = Get-HcConsentAppName $k.PSChildName "$desc".Trim()
                Path  = $path
                Last  = $start
                InUse = ([int64]$p.LastUsedTimeStop -eq 0)
            }
        }
    }
    [pscustomobject]@{ Now = (Get-Date); Uses = @($uses) }
}

# Pure: a use worth a closer look: a remote-access tool, or a program run
# from Downloads or a temporary folder.
function Test-HcSuspiciousUse {
    param([pscustomobject]$Use)
    $text = "$($Use.App) $($Use.Path)"
    # Quick Assist has no name pattern (it is part of Windows): an empty
    # pattern would match everything, so it is skipped.
    foreach ($tool in $script:RemoteToolList) { if ($tool.Pattern -and $text -match $tool.Pattern) { return $true } }
    "$($Use.Path)" -match '\\Downloads\\|\\AppData\\Local\\Temp\\|\\Windows\\Temp\\'
}

function Test-HcCamMic {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $culture = [Globalization.CultureInfo]::GetCultureInfo($(if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }))
    $uses = @($Facts.Uses | Sort-Object Last -Descending)
    $since = $Facts.Now.AddDays(-$script:CamMicRecentDays)
    foreach ($u in $uses) {
        $what = T "cam.kind.$($u.Kind)"
        $when = $u.Last.ToString('d MMM HH:mm', $culture)
        if (Test-HcSuspiciousUse $u) {
            Add-HcLine $r problem (T 'cam.suspicious' $u.App $what $when)
            if (-not $found['camMicSuspicious']) { $found['camMicSuspicious'] = @($u.App, $what) }
        } elseif ($u.InUse) {
            Add-HcLine $r warn (T 'cam.inUse' $u.App $what)
            if (-not $found['camMicInUse']) { $found['camMicInUse'] = @($u.App, $what) }
        } elseif ($u.Last -ge $since) {
            Add-HcLine $r ok (T 'cam.recent' $u.App $what $when)
        }
    }
    $older = @($uses | Where-Object { $_.Last -lt $since -and -not (Test-HcSuspiciousUse $_) -and -not $_.InUse }).Count
    if ($older) { Add-HcLine $r ok (T 'cam.older' $older $script:CamMicRecentDays) }
    if (-not $uses.Count) { Add-HcLine $r ok (T 'cam.none') }
    Add-HcAction $r 'openCamPrivacy'
    Add-HcAction $r 'openMicPrivacy'
    Select-HcFinding $r $found @('camMicSuspicious', 'camMicInUse') $(if ($uses.Count) { 'camMicOk' } else { 'camMicNone' })
    $r
}

# ------------------------------------------------ G4: a backup of photos --

$script:PhotoExtensions = @('.jpg', '.jpeg', '.png', '.heic', '.gif', '.mp4', '.mov')
$script:PhotoCountLimit = 50000

# How many photos and videos are in a folder and below it; counted only,
# never listed, and stopped at $PhotoCountLimit so a huge folder stays quick.
function Get-HcPhotoCount {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0 }
    $n = 0
    try {
        foreach ($file in [IO.Directory]::EnumerateFiles($Path, '*', [IO.SearchOption]::AllDirectories)) {
            if ($script:PhotoExtensions -contains [IO.Path]::GetExtension($file).ToLowerInvariant()) { $n++ }
            if ($n -ge $script:PhotoCountLimit) { break }
        }
    } catch { }
    $n
}

function Get-HcPhotoBackupFacts {
    $pictures = [Environment]::GetFolderPath('MyPictures')
    $exe = Get-HcOneDriveExe
    $googleDrive = [bool](Get-Process -Name GoogleDriveFS -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Google\Drive File Stream'))
    $icloud = [bool](Get-Process -Name iCloudPhotos, iCloudDrive, iCloudServices -ErrorAction SilentlyContinue) -or [bool](Get-AppxPackage -Name 'AppleInc.iCloud' -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Pictures        = $pictures
        InOneDrive      = ("$pictures" -match '\\OneDrive[^\\]*(\\|$)')
        Photos          = Get-HcPhotoCount $pictures
        OneDriveExe     = $exe
        OneDriveRunning = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        SignedIn        = Test-HcOneDriveSignedIn
        FileHistory     = (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration\Config1.xml'))
        Other           = @($(if ($googleDrive) { 'Google Drive' }), $(if ($icloud) { 'iCloud' }) | Where-Object { $_ })
    }
}

function Test-HcPhotoBackup {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $f = $Facts
    $count = if ($f.Photos -ge $script:PhotoCountLimit) { "$($script:PhotoCountLimit)+" } else { "$($f.Photos)" }
    Add-HcLine $r ok (T 'pho.folder' $f.Pictures $count)
    $oneDriveWorks = $f.InOneDrive -and $f.OneDriveExe -and $f.SignedIn -and $f.OneDriveRunning
    if ($f.InOneDrive) {
        if ($oneDriveWorks) { Add-HcLine $r ok (T 'pho.oneDriveOk') }
        elseif (-not $f.OneDriveExe) { Add-HcLine $r problem (T 'pho.oneDriveGone') }
        elseif (-not $f.SignedIn) { Add-HcLine $r problem (T 'pho.oneDriveSignedOut') }
        else { Add-HcLine $r problem (T 'pho.oneDriveStopped'); Add-HcAction $r 'startOneDrive' @{ Label = ''; Exe = $f.OneDriveExe } }
    } else {
        Add-HcLine $r $(if ($f.Photos) { 'warn' } else { 'ok' }) (T 'pho.notInOneDrive')
    }
    Add-HcLine $r $(if ($f.FileHistory) { 'ok' } else { 'skipped' }) $(if ($f.FileHistory) { T 'pho.fileHistoryOn' } else { T 'pho.fileHistoryOff' })
    foreach ($o in @($f.Other)) { Add-HcLine $r ok (T 'pho.other' $o) }

    Add-HcAction $r 'openBackupSettings'
    if ($f.Pictures) { Add-HcAction $r 'openFolder' @{ Label = (T 'pho.picturesName'); Path = $f.Pictures } }
    $safe = $oneDriveWorks -or $f.FileHistory -or @($f.Other).Count
    if (-not $f.Photos) { Set-HcFinding $r 'photosNone' }
    elseif ($f.InOneDrive -and -not $oneDriveWorks -and -not $safe) { Set-HcFinding $r 'photosOneDriveBroken' @($count) }
    elseif (-not $safe) { Set-HcFinding $r 'photosNoBackup' @($count) }
    else { Set-HcFinding $r 'photosBackedUp' }
    $r
}

# ------------------------------------------------- G5: links and email --

function Get-HcLinkFacts {
    $choice = { param($scheme) (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\$scheme\UserChoice" -ErrorAction SilentlyContinue).ProgId }
    $web = & $choice 'https'
    $mail = & $choice 'mailto'
    [pscustomobject]@{
        WebProgId  = $web
        WebName    = $(if ($web) { Get-HcProgIdName $web })
        MailProgId = $mail
        MailName   = $(if ($mail) { Get-HcProgIdName $mail })
    }
}

# Pure: Windows' own Mail app, retired at the end of 2024 (A4 knows it too).
function Test-HcRetiredMail {
    param([string]$ProgId, [string]$Name)
    ("$Name" -match '^(Mail|Mail and Calendar|E-mail|Mail en agenda)$') -or ("$ProgId" -match 'windowscommunicationsapps')
}

function Test-HcLinks {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $web = if ($Facts.WebName) { $Facts.WebName } elseif ($Facts.WebProgId) { $Facts.WebProgId } else { $null }
    if (-not $web) { Add-HcLine $r warn (T 'lnk.webNone'); $found['linksNoBrowser'] = @() }
    elseif ("$($Facts.WebProgId)" -match '^IE\.' -or $web -match 'Internet Explorer') { Add-HcLine $r problem (T 'lnk.webIe'); $found['linksOldBrowser'] = @() }
    else { Add-HcLine $r ok (T 'lnk.web' $web) }

    $mail = if ($Facts.MailName) { $Facts.MailName } elseif ($Facts.MailProgId) { $Facts.MailProgId } else { $null }
    if (-not $mail) { Add-HcLine $r warn (T 'lnk.mailNone'); $found['mailLinksNone'] = @() }
    elseif (Test-HcRetiredMail $Facts.MailProgId $Facts.MailName) { Add-HcLine $r problem (T 'lnk.mailRetired' $mail); $found['mailLinksRetired'] = @($mail) }
    else { Add-HcLine $r ok (T 'lnk.mail' $mail) }

    Add-HcAction $r 'openDefaultApps'
    Select-HcFinding $r $found @('linksOldBrowser', 'mailLinksRetired', 'linksNoBrowser', 'mailLinksNone') 'linksOk'
    $r
}

# ------------------------------------------------ B6: second screen or TV --

function Get-HcScreensFacts {
    $monitors = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue | Where-Object { $_.Active } | ForEach-Object {
        $n = (@($_.UserFriendlyName | Where-Object { $_ -ne 0 }) | ForEach-Object { [char]$_ }) -join ''
        $(if ($n) { $n.Trim() } else { '?' })
    })
    $desktops = $null
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop; $desktops = [Windows.Forms.Screen]::AllScreens.Count } catch { }
    [pscustomobject]@{ Monitors = $monitors; Desktops = $desktops }
}

# The Windows+P choice, set through SetDisplayConfig. DisplaySwitch.exe
# only opens the Windows+P panel on newer Windows 11 (found 6 Oct), so the
# click never happened. Windows' own topology ids: 1 this screen only,
# 2 duplicate, 4 extend, 8 second screen only.
$script:DisplayTopology = @{ Internal = 1; Clone = 2; Extend = 4; External = 8 }

function Initialize-HcDisplayConfig {
    if ('Housecall.DisplayConfig' -as [type]) { return }
    Add-Type -Namespace Housecall -Name DisplayConfig -MemberDefinition @"
[DllImport("user32.dll")]
static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
[DllImport("user32.dll")]
static extern int QueryDisplayConfig(uint flags, ref uint paths, System.IntPtr pathArray, ref uint modes, System.IntPtr modeArray, out uint topology);
[DllImport("user32.dll")]
static extern int SetDisplayConfig(uint paths, System.IntPtr pathArray, uint modes, System.IntPtr modeArray, uint flags);
public static int GetTopology() {
    uint p, m, t;
    if (GetDisplayConfigBufferSizes(4, out p, out m) != 0) return 0;
    System.IntPtr pa = Marshal.AllocHGlobal((int)Math.Max(1, p) * 72), ma = Marshal.AllocHGlobal((int)Math.Max(1, m) * 64);
    try { return QueryDisplayConfig(4, ref p, pa, ref m, ma, out t) == 0 ? (int)t : 0; }
    finally { Marshal.FreeHGlobal(pa); Marshal.FreeHGlobal(ma); }
}
public static int SetTopology(int topology) { return SetDisplayConfig(0, System.IntPtr.Zero, 0, System.IntPtr.Zero, 0x80 | (uint)topology); }
"@
}

# 0 when Windows cannot say.
function Get-HcDisplayTopology {
    try { Initialize-HcDisplayConfig; [Housecall.DisplayConfig]::GetTopology() } catch { 0 }
}

# Remembers the mode it replaces in $Target.Saved, for the undo.
function Set-HcDisplayTopology {
    param([hashtable]$Target, [string]$Mode)
    Initialize-HcDisplayConfig
    $Target.Saved = Get-HcDisplayTopology
    $code = [Housecall.DisplayConfig]::SetTopology($script:DisplayTopology[$Mode])
    if ($code -ne 0) { throw (T 'scn.modeFailed' $code) }
}

function Undo-HcDisplayTopology {
    param([hashtable]$Target)
    if (-not $Target.Saved) { throw (T 'scn.modeUnknown') }
    Initialize-HcDisplayConfig
    $code = [Housecall.DisplayConfig]::SetTopology([int]$Target.Saved)
    if ($code -ne 0) { throw (T 'scn.modeFailed' $code) }
}

function Test-HcScreens {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $monitors = @($Facts.Monitors)
    Add-HcLine $r ok (T 'scn.seen' $monitors.Count $(if ($monitors.Count) { $monitors -join ', ' } else { '-' }))
    if ($null -ne $Facts.Desktops) { Add-HcLine $r ok (T 'scn.desktops' $Facts.Desktops) }
    if ($monitors.Count -le 1) {
        Add-HcAction $r 'openDisplaySettings'
        Set-HcFinding $r 'screenNotSeen'
    } elseif ($null -ne $Facts.Desktops -and $Facts.Desktops -lt $monitors.Count) {
        Add-HcLine $r warn (T 'scn.samePicture')
        Add-HcAction $r 'displayExtend'
        Add-HcAction $r 'displayClone'
        Set-HcFinding $r 'screensOneDesktop'
    } else {
        Add-HcAction $r 'displayClone'
        Add-HcAction $r 'openDisplaySettings'
        Set-HcFinding $r 'screensExtended'
    }
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcF4 { { Test-HcCamMic (Get-HcCamMicFacts) } }
function Invoke-HcG4 { { Test-HcPhotoBackup (Get-HcPhotoBackupFacts) } }
function Invoke-HcG5 { { Test-HcLinks (Get-HcLinkFacts) } }
function Invoke-HcB6 { { Test-HcScreens (Get-HcScreensFacts) } }

$script:ProblemHandlers['F4'] = 'Invoke-HcF4'
$script:ProblemHandlers['G4'] = 'Invoke-HcG4'
$script:ProblemHandlers['G5'] = 'Invoke-HcG5'
$script:ProblemHandlers['B6'] = 'Invoke-HcB6'
