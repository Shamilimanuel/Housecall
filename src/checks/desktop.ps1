<#
    Area G: files, desktop & accounts.

      G1  the desktop, taskbar or folders act strange
                                  temporary profile, File Explorer running and
                                  responding, desktop icons and Recycle Bin
                                  shown, Desktop moved into OneDrive, taskbar
                                  auto-hide, search box, tablet mode (Windows 10)
      G2  files gone or not everywhere      (not built yet)
      G3  a file cannot be found or opens wrong  (not built yet)

    What an older client says on the phone: "my desktop is empty", "the bar at
    the bottom is gone", "my folders won't open", "everything suddenly looks
    different". One check looks at all of it, because the client cannot tell
    these apart. Everything here reads the current user's own settings; only
    the fixes in src\fixes.ps1 change them, and each can be undone.
#>

$script:ExplorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
$script:RecycleBinId = '{645FF040-5081-101B-9F08-00AA002F954E}'

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
        IconsHidden      = ($advanced -and $advanced.HideIcons -eq 1)
        RecycleBinHidden = ($icons -and $icons.$script:RecycleBinId -eq 1)
        DesktopItems     = $items
        DesktopInOneDrive = ("$desktop" -match '\\OneDrive[^\\]*\\')
        OneDriveRunning  = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        TaskbarAutoHide  = (Test-HcTaskbarAutoHide $taskbar)
        SearchHidden     = ($null -ne $search -and [int]$search -eq 0)
        TabletMode       = ($tablet -eq 1)
        Windows10        = ([Environment]::OSVersion.Version.Build -lt 22000)
    }
}

# The taskbar's settings are a binary blob; byte 8 is 3 when it hides itself
# and 2 when it stays. Pure, so the tests can check both ways.
function Test-HcTaskbarAutoHide {
    param([byte[]]$Settings)
    [bool]($Settings -and $Settings.Count -gt 8 -and ($Settings[8] -band 1))
}

function ConvertTo-HcTaskbarSetting {
    param([byte[]]$Settings, [bool]$AutoHide)
    $copy = [byte[]]$Settings.Clone()
    if ($AutoHide) { $copy[8] = [byte]($copy[8] -bor 1) } else { $copy[8] = [byte]($copy[8] -band 0xFE) }
    , $copy
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

# ---------------------------------------------------------------- handlers --

function Invoke-HcG1 { { Test-HcShell (Get-HcShellFacts) } }

$script:ProblemHandlers['G1'] = 'Invoke-HcG1'
