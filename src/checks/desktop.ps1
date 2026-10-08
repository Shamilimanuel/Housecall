<#
    Area G: files, desktop & accounts.

      G1  the desktop, taskbar or folders act strange
                                  temporary profile, File Explorer running and
                                  responding, desktop icons and Recycle Bin
                                  shown, Desktop moved into OneDrive, taskbar
                                  auto-hide, search box, tablet mode (Windows 10)
      G2  files gone or not everywhere
                                  temporary profile, Desktop / Documents /
                                  Pictures (where, whether they exist, how
                                  many items), OneDrive installed, signed in
                                  and running, free disk space, Recycle Bin
      G3  a file cannot be found or opens wrong
                                  Downloads (count, newest: when and what type,
                                  never names), where Edge and Chrome save and
                                  whether they ask, which program opens PDFs,
                                  photos, Word files and videos, Windows Search

    What an older client says on the phone: "my desktop is empty", "the bar at
    the bottom is gone", "my folders won't open", "everything suddenly looks
    different". One check looks at all of it, because the client cannot tell
    these apart. Everything here reads the current user's own settings; only
    the fixes in src\fixes.ps1 change them, and each can be undone.
#>

$script:ExplorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$script:RecycleBinId = '{645FF040-5081-101B-9F08-00AA002F954E}'
# Where Windows really keeps "Show desktop icons": the desktop's own view
# settings. Bit 0x1000 of FFlags means no icons. HideIcons under Advanced is
# only a copy, which Explorer overwrites from FFlags when it starts (found
# on Shamil's PC, 27 Sep: setting HideIcons alone came back within seconds).
$script:DesktopBagKey = 'HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop'
$script:NoIconsFlag = 0x1000

# ------------------------------------------------------------------- facts --

# A temporary profile: Windows could not load the user's own profile and
# signed in with an empty one, so the desktop and files seem gone.
function Test-HcTempProfile {
    if ("$env:USERPROFILE" -match '\\TEMP(\.[^\\]*)?$') { return $true }
    try {
        $mine = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { $_.LocalPath -eq $env:USERPROFILE } | Select-Object -First 1
        if ($mine -and ([int]$mine.Status -band 1)) { return $true }
    } catch { }
    $false
}

function Get-HcShellFacts {
    $advanced = Get-ItemProperty "$script:ExplorerKey\Advanced" -ErrorAction SilentlyContinue
    $flags = (Get-ItemProperty $script:DesktopBagKey -ErrorAction SilentlyContinue).FFlags
    $icons = Get-ItemProperty "$script:ExplorerKey\HideDesktopIcons\NewStartPanel" -ErrorAction SilentlyContinue
    $taskbar = (Get-ItemProperty "$script:ExplorerKey\StuckRects3" -ErrorAction SilentlyContinue).Settings
    $search = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -ErrorAction SilentlyContinue).SearchboxTaskbarMode
    $tablet = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell' -ErrorAction SilentlyContinue).TabletMode
    # The shell's explorer has a window (the taskbar); a folder window's
    # explorer may not. Frozen = a windowed explorer that stopped responding.
    $explorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
    $desktop = [Environment]::GetFolderPath('Desktop')
    $items = 0
    foreach ($folder in @($desktop, [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        if ($folder -and (Test-Path -LiteralPath $folder)) {
            $items += @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count
        }
    }
    [pscustomobject]@{
        TempProfile      = Test-HcTempProfile
        ExplorerRunning  = ($explorer.Count -gt 0)
        ExplorerHung     = [bool]@($explorer | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and -not $_.Responding }).Count
        IconsHidden      = (Test-HcIconsHidden $advanced.HideIcons $flags)
        RecycleBinHidden = ($icons -and $icons.$script:RecycleBinId -eq 1)
        DesktopItems     = $items
        DesktopInOneDrive = ("$desktop" -match '\\OneDrive[^\\]*\\')
        OneDriveRunning  = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        TaskbarAutoHide  = $(if ($null -ne ($live = Get-HcTaskbarState)) { [bool]($live -band 1) } else { Test-HcTaskbarAutoHide $taskbar })
        SearchHidden     = ($null -ne $search -and [int]$search -eq 0)
        TabletMode       = ($tablet -eq 1)
        Windows10        = ([Environment]::OSVersion.Version.Build -lt 22000)
    }
}

# The desktop's view flags decide; HideIcons only counts when they are missing.
function Test-HcIconsHidden {
    param($HideIcons, $Flags)
    if ($null -ne $Flags) { return [bool]((ConvertTo-HcUInt32 $Flags) -band $script:NoIconsFlag) }
    ($HideIcons -eq 1)
}

# Registry DWORDs come back as signed Int32; the flag maths needs them unsigned.
function ConvertTo-HcUInt32 {
    param($Value)
    [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0)
}

function ConvertTo-HcInt32 {
    param([uint32]$Value)
    [BitConverter]::ToInt32([BitConverter]::GetBytes($Value), 0)
}

<#
    Taskbar auto-hide, through the same call the Settings switch uses
    (SHAppBarMessage). It changes it live, without restarting Explorer, and
    Explorer stores it itself. Changing the stored copy and restarting
    Explorer did not hold on Shamil's PC (27 Sep): a Windhawk taskbar mod,
    reloaded with Explorer, switched auto-hide straight back on.
#>
function Initialize-HcAppBar {
    if ('Housecall.AppBar' -as [type]) { return }
    Add-Type -Namespace Housecall -Name AppBar -MemberDefinition @"
[StructLayout(LayoutKind.Sequential)]
public struct APPBARDATA { public int cbSize; public System.IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public int left; public int top; public int right; public int bottom; public System.IntPtr lParam; }
[DllImport("shell32.dll")]
public static extern System.UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);
public static int GetState() { APPBARDATA d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(typeof(APPBARDATA)); return (int)SHAppBarMessage(4, ref d).ToUInt32(); }
public static void SetState(int state) { APPBARDATA d = new APPBARDATA(); d.cbSize = Marshal.SizeOf(typeof(APPBARDATA)); d.lParam = new System.IntPtr(state); SHAppBarMessage(10, ref d); }
"@
}

# 1 = hides itself. $null when Windows cannot say.
function Get-HcTaskbarState {
    try { Initialize-HcAppBar; return [Housecall.AppBar]::GetState() } catch { return $null }
}

function Set-HcTaskbarState {
    param([int]$State)
    Initialize-HcAppBar
    [Housecall.AppBar]::SetState($State)
}

# The stored copy, only used when the live call is not available: byte 8 of
# the taskbar's settings is 3 when it hides itself and 2 when it stays.
function Test-HcTaskbarAutoHide {
    param([byte[]]$Settings)
    [bool]($Settings -and $Settings.Count -gt 8 -and ($Settings[8] -band 1))
}

# ------------------------------------------------------------------ verdict --

# G1.
function Test-HcShell {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.TempProfile) {
        Add-HcLine $r problem (T 'shell.tempProfile')
        $found['tempProfile'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.profileOk')
    }

    if (-not $Facts.ExplorerRunning) {
        Add-HcLine $r problem (T 'shell.explorerMissing')
        $found['explorerMissing'] = @()
    } elseif ($Facts.ExplorerHung) {
        Add-HcLine $r problem (T 'shell.explorerHung')
        $found['explorerHung'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.explorerOk')
    }
    # Restarting Explorer is first when it is the cause.
    $explorerCause = $found.ContainsKey('explorerMissing') -or $found.ContainsKey('explorerHung')
    if ($explorerCause) { Add-HcAction $r 'restartExplorer' }

    if ($Facts.IconsHidden) {
        Add-HcLine $r problem (T 'shell.iconsHidden')
        Add-HcAction $r 'showDesktopIcons'
        $found['iconsHidden'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.iconsShown' $Facts.DesktopItems)
    }
    if ($Facts.DesktopInOneDrive) {
        if ($Facts.OneDriveRunning) {
            Add-HcLine $r ok (T 'shell.desktopOneDrive')
        } else {
            Add-HcLine $r warn (T 'shell.desktopOneDriveOff')
            $found['desktopOneDrive'] = @()
        }
    }
    if ($Facts.RecycleBinHidden) {
        Add-HcLine $r warn (T 'shell.recycleHidden')
        Add-HcAction $r 'showRecycleBin'
        $found['recycleHidden'] = @()
    }

    if ($Facts.TaskbarAutoHide) {
        Add-HcLine $r warn (T 'shell.taskbarAutoHide')
        Add-HcAction $r 'taskbarStay'
        $found['taskbarAutoHide'] = @()
    } else {
        Add-HcLine $r ok (T 'shell.taskbarShown')
    }
    if ($Facts.SearchHidden) {
        Add-HcLine $r warn (T 'shell.searchHidden')
        Add-HcAction $r 'showSearch'
        $found['searchHidden'] = @()
    }
    if ($Facts.Windows10 -and $Facts.TabletMode) {
        Add-HcLine $r warn (T 'shell.tabletMode')
        $found['tabletMode'] = @()
    }

    # Nothing wrong in the settings, yet the client says it acts strange:
    # restarting Explorer is still the harmless first thing to try.
    if (-not $explorerCause) { Add-HcAction $r 'restartExplorer' }

    Select-HcFinding $r $found @('tempProfile', 'explorerMissing', 'explorerHung', 'iconsHidden', 'desktopOneDrive', 'tabletMode', 'taskbarAutoHide', 'searchHidden', 'recycleHidden') 'shellOk'
    $r
}

# ------------------------------------------------------------ G2: facts --

# Below this much free space OneDrive stops syncing.
$script:SyncFreeGB = 2

# OneDrive.exe: where its own startup entry points, then the usual places.
# $null when it is not on this PC (removed, or never installed).
function Get-HcOneDriveExe {
    $run = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).OneDrive
    $candidates = @()
    if ($run -and $run -match '^\s*"?([^"]+?\.exe)') { $candidates += $Matches[1] }
    $candidates += @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDrive.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDrive.exe')
    )
    @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) | Select-Object -First 1
}

# Only whether an account is set up, never which: no e-mail address is read.
function Test-HcOneDriveSignedIn {
    [bool]@(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).UserFolder }).Count
}

# The three folders people mean by "my files": where each one is, whether it
# exists, and how many items it holds at the top (counted, never listed).
function Get-HcKnownFolders {
    foreach ($f in @(@('desktop', 'Desktop'), @('documents', 'MyDocuments'), @('pictures', 'MyPictures'))) {
        $path = [Environment]::GetFolderPath($f[1])
        $exists = [bool]($path -and (Test-Path -LiteralPath $path))
        [pscustomobject]@{
            Key       = $f[0]
            Path      = $path
            Exists    = $exists
            InOneDrive = ("$path" -match '\\OneDrive[^\\]*(\\|$)')
            Items     = $(if ($exists) { @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count } else { 0 })
        }
    }
}

function Get-HcRecycleBinCount {
    try { return [int](New-Object -ComObject Shell.Application).Namespace(10).Items().Count } catch { return $null }
}

function Get-HcFilesFacts {
    $exe = Get-HcOneDriveExe
    [pscustomobject]@{
        TempProfile     = Test-HcTempProfile
        Folders         = @(Get-HcKnownFolders)
        OneDriveExe     = $exe
        OneDriveRunning = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        SignedIn        = Test-HcOneDriveSignedIn
        Disk            = Get-HcSystemDisk
        RecycleBin      = Get-HcRecycleBinCount
    }
}

# ---------------------------------------------------------- G2: verdict --

function Test-HcFiles {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.TempProfile) {
        Add-HcLine $r problem (T 'shell.tempProfile')
        $found['tempProfile'] = @()
    }

    $inOneDrive = $false
    foreach ($f in @($Facts.Folders)) {
        $name = T ('files.' + $f.Key)
        if (-not $f.Exists) {
            Add-HcLine $r problem (T 'files.folderMissing' $name $f.Path)
            if (-not $found['folderMissing']) { $found['folderMissing'] = @($name) }
            continue
        }
        if ($f.InOneDrive) { $inOneDrive = $true }
        $where = T $(if ($f.InOneDrive) { 'files.whereOneDrive' } else { 'files.whereLocal' })
        Add-HcLine $r ok (T 'files.folder' $name $where $f.Items)
    }

    $installed = [bool]$Facts.OneDriveExe
    if (-not $installed) {
        if ($inOneDrive) {
            Add-HcLine $r problem (T 'files.oneDriveGone')
            $found['oneDriveRemoved'] = @()
        } else {
            Add-HcLine $r ok (T 'files.noOneDrive')
            $found['filesLocal'] = @()
        }
    } elseif (-not $Facts.SignedIn) {
        Add-HcLine $r $(if ($inOneDrive) { 'problem' } else { 'warn' }) (T 'files.signedOut')
        Add-HcAction $r 'startOneDrive' @{ Label = ''; Exe = $Facts.OneDriveExe }
        $found[$(if ($inOneDrive) { 'oneDriveSignedOut' } else { 'filesLocal' })] = @()
    } elseif (-not $Facts.OneDriveRunning) {
        Add-HcLine $r problem (T 'files.notRunning')
        Add-HcAction $r 'startOneDrive' @{ Label = ''; Exe = $Facts.OneDriveExe }
        $found['oneDriveNotRunning'] = @()
    } else {
        Add-HcLine $r ok (T 'files.oneDriveOk')
    }

    if ($Facts.Disk) {
        if ($Facts.Disk.FreeGB -lt $script:SyncFreeGB) {
            Add-HcLine $r problem (T 'files.diskFull' $Facts.Disk.FreeGB)
            $found['syncDiskFull'] = @($Facts.Disk.FreeGB)
        } else {
            Add-HcLine $r ok (T 'files.diskOk' $Facts.Disk.FreeGB)
        }
    }

    if ($null -ne $Facts.RecycleBin) {
        Add-HcLine $r ok (T 'files.recycleBin' $Facts.RecycleBin)
        if ($Facts.RecycleBin -gt 0) {
            Add-HcAction $r 'openRecycleBin'
            $found['recycleHasItems'] = @($Facts.RecycleBin)
        }
    }

    Select-HcFinding $r $found @('tempProfile', 'oneDriveRemoved', 'folderMissing', 'oneDriveSignedOut', 'oneDriveNotRunning', 'syncDiskFull', 'filesLocal', 'recycleHasItems') 'filesOk'
    $r
}

# ------------------------------------------------------------ G3: facts --

# The file types an older client opens most, in the order they are shown.
$script:FindTypes = @('.pdf', '.jpg', '.docx', '.mp4')

# "@{Microsoft.Windows.Photos_...?ms-resource://...}" -> "Photos": Windows'
# own call for app names stored that way. $null when it cannot say.
function Get-HcIndirectString {
    param([string]$Text)
    try {
        if (-not ('Housecall.Indirect' -as [type])) {
            Add-Type -Namespace Housecall -Name Indirect -MemberDefinition @"
[DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
public static extern int SHLoadIndirectString(string source, System.Text.StringBuilder output, int size, System.IntPtr reserved);
public static string Load(string source) { System.Text.StringBuilder sb = new System.Text.StringBuilder(512); return SHLoadIndirectString(source, sb, sb.Capacity, System.IntPtr.Zero) == 0 ? sb.ToString() : null; }
"@
        }
        return [Housecall.Indirect]::Load($Text)
    } catch { return $null }
}

# Which program opens a file type: the user's own choice, else Windows'
# default. Name is $null when no program is set up for it at all.
function Get-HcTypeProgram {
    param([string]$Extension)
    $progId = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice" -ErrorAction SilentlyContinue).ProgId
    if (-not $progId) { $progId = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$Extension" -ErrorAction SilentlyContinue).'(default)' }
    [pscustomobject]@{ Extension = $Extension; Name = (Get-HcProgIdName $progId) }
}

# A program's name from its ProgId ("ChromeHTML" -> "Google Chrome"), the
# way Windows shows it; $null when there is none. Shared with G5 (links).
function Get-HcProgIdName {
    param([string]$ProgId)
    $progId = $ProgId
    $name = $null
    if ($progId) {
        $app = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\Application" -ErrorAction SilentlyContinue).ApplicationName
        if ($app) { $name = if ($app -like '@*') { Get-HcIndirectString $app } else { $app } }
        if (-not $name) {
            $command = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$progId\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
            if ($command -and $command -match '^\s*"?([^"]+?\.exe)') {
                $exe = [Environment]::ExpandEnvironmentVariables($Matches[1])
                if (Test-Path -LiteralPath $exe) {
                    $name = (Get-Item -LiteralPath $exe).VersionInfo.FileDescription
                    if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($exe) }
                }
            }
        }
    }
    $name
}

# Where a browser saves downloads and whether it asks each time; $null when
# the browser has no profile on this PC. Read from its own settings file.
function Get-HcBrowserDownloads {
    param([string]$Name, [string]$Preferences)
    if (-not (Test-Path -LiteralPath $Preferences)) { return $null }
    try { $d = (Get-Content -LiteralPath $Preferences -Raw -ErrorAction Stop | ConvertFrom-Json).download } catch { return $null }
    [pscustomobject]@{ Name = $Name; Folder = $d.default_directory; Ask = [bool]$d.prompt_for_download }
}

function Get-HcFindFacts {
    $downloads = @(Get-HcDownloadFolders | Where-Object { $_ -notlike ([Environment]::GetFolderPath('Desktop') + '*') }) | Select-Object -First 1
    $files = @()
    if ($downloads) { $files = @(Get-ChildItem -LiteralPath $downloads -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) }
    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $search = Get-Service WSearch -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Now        = Get-Date
        Downloads  = $downloads
        Count      = $files.Count
        NewestAt   = $(if ($newest) { $newest.LastWriteTime })
        NewestType = $(if ($newest) { $newest.Extension })
        Browsers   = @(
            Get-HcBrowserDownloads 'Microsoft Edge' (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Preferences')
            Get-HcBrowserDownloads 'Google Chrome' (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Preferences')
        ) | Where-Object { $_ }
        Types      = @($script:FindTypes | ForEach-Object { Get-HcTypeProgram $_ })
        SearchOn   = [bool]($search -and [string]$search.Status -eq 'Running')
        SearchOff  = [bool]($search -and [string]$search.StartType -eq 'Disabled')
    }
}

# "12 minutes ago", "3 hours ago", or the date.
function Format-HcAge {
    param([datetime]$When, [datetime]$Now)
    $minutes = [int][Math]::Max(0, ($Now - $When).TotalMinutes)
    if ($minutes -lt 60) { return (T 'find.ageMinutes' $minutes) }
    if ($minutes -lt 24 * 60) { return (T 'find.ageHours' ([int][Math]::Floor($minutes / 60))) }
    Format-HcDate $When
}

# ---------------------------------------------------------- G3: verdict --

function Test-HcFind {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.SearchOn) {
        Add-HcLine $r problem (T 'find.searchOff')
        Add-HcAction $r 'startSearch'
        $found['searchOff'] = @()
    } else {
        Add-HcLine $r ok (T 'find.searchOn')
    }

    if ($Facts.Downloads) {
        Add-HcAction $r 'openFolder' @{ Label = (T 'find.downloadsName'); Path = $Facts.Downloads }
        if ($Facts.Count -and $Facts.NewestAt) {
            Add-HcLine $r ok (T 'find.downloads' $Facts.Count (Format-HcAge $Facts.NewestAt $Facts.Now) $Facts.NewestType)
        } else {
            Add-HcLine $r ok (T 'find.downloadsEmpty')
        }
    } else {
        Add-HcLine $r problem (T 'find.noDownloads')
        $found['noDownloads'] = @()
    }

    foreach ($b in @($Facts.Browsers)) {
        if ($b.Folder -and $Facts.Downloads -and ($b.Folder.TrimEnd('\') -ne $Facts.Downloads.TrimEnd('\'))) {
            Add-HcLine $r warn (T 'find.browserElsewhere' $b.Name $b.Folder)
            Add-HcAction $r 'openFolder' @{ Label = $b.Folder; Path = $b.Folder }
            if (-not $found['downloadsElsewhere']) { $found['downloadsElsewhere'] = @($b.Name, $b.Folder) }
        } elseif ($b.Ask) {
            Add-HcLine $r warn (T 'find.browserAsks' $b.Name)
            if (-not $found['browserAsks']) { $found['browserAsks'] = @($b.Name) }
        } else {
            Add-HcLine $r ok (T 'find.browserDownloads' $b.Name)
        }
    }

    foreach ($t in @($Facts.Types)) {
        $type = T ('find.type' + $t.Extension)
        if ($t.Name) {
            Add-HcLine $r ok (T 'find.opensWith' $type $t.Name)
        } else {
            Add-HcLine $r problem (T 'find.noProgram' $type)
            if (-not $found['noProgram']) { $found['noProgram'] = @($type) }
        }
    }
    # Which program opens a type is the user's own protected choice: Windows
    # lets no script change it, so this opens the page where the client can.
    Add-HcAction $r 'openDefaultApps'

    Select-HcFinding $r $found @('searchOff', 'noDownloads', 'downloadsElsewhere', 'noProgram', 'browserAsks') 'findOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcG1 { { Test-HcShell (Get-HcShellFacts) } }
function Invoke-HcG2 { { Test-HcFiles (Get-HcFilesFacts) } }
function Invoke-HcG3 { { Test-HcFind (Get-HcFindFacts) } }

$script:ProblemHandlers['G1'] = 'Invoke-HcG1'
$script:ProblemHandlers['G2'] = 'Invoke-HcG2'
$script:ProblemHandlers['G3'] = 'Invoke-HcG3'
