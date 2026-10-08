<#
    Phase 7, batch 1 (6 Oct 2026): four everyday annoyances of older clients.

      B4  the screen goes dark too fast, or the PC falls asleep
                                  screen-off and sleep times, on mains and on
                                  battery (powercfg; only its numbers are read,
                                  since its words follow the Windows language)
      B5  make everything bigger and easier to read
                                  text size, display scale, mouse pointer size,
                                  Magnifier; the fixes open the Settings pages
                                  (text size only changes with a sign-out when
                                  set by script, so the client picks it there)
      C5  the touchpad does nothing
                                  a laptop?, the touchpad in Device Manager
                                  (switched off, error), the touchpad switch,
                                  and "off when a mouse is connected"
      E5  too many messages and ads from Windows itself
                                  tips, suggestions in Start and Settings, the
                                  welcome screens after updates, "let's finish
                                  setting up", lock-screen tips, OneDrive ads
                                  in File Explorer

    Read-only here; the fixes in src\fixes.ps1 ask first and can be undone.
#>

# --------------------------------------------------- B4: screen and sleep --

# Below these a client sees the screen go dark while reading (seconds).
$script:ScreenOffShort = @{ Ac = 300; Dc = 120 }
$script:SleepShort = @{ Ac = 900; Dc = 300 }
# What the fix sets, only where the time now is shorter (seconds).
$script:ScreenOffLonger = @{ Ac = 900; Dc = 300 }
$script:SleepLonger = @{ Ac = 3600; Dc = 1200 }

# Pure: the last two hexadecimal numbers of "powercfg /query" are the
# current value on mains (AC) and on battery (DC), whatever the language.
function ConvertFrom-HcPowerQuery {
    param([string]$Text)
    $hex = @([regex]::Matches("$Text", '0x([0-9a-fA-F]{8})') | ForEach-Object { [Convert]::ToInt64($_.Groups[1].Value, 16) })
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject]@{ Ac = $hex[$hex.Count - 2]; Dc = $hex[$hex.Count - 1] }
}

function Get-HcPowerTimeout {
    param([string]$Sub, [string]$Setting)
    try { ConvertFrom-HcPowerQuery ((& powercfg.exe /query SCHEME_CURRENT $Sub $Setting) | Out-String) } catch { $null }
}

function Get-HcPowerTimesFacts {
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    [pscustomobject]@{
        Laptop = [bool]@($chassis | Where-Object { $_ -in $script:LaptopChassis }).Count
        Screen = Get-HcPowerTimeout 'SUB_VIDEO' 'VIDEOIDLE'
        Sleep  = Get-HcPowerTimeout 'SUB_SLEEP' 'STANDBYIDLE'
    }
}

# "never", "45 seconds", "5 min", "2 hours".
function Format-HcSeconds {
    param([long]$Seconds)
    if ($Seconds -le 0) { return T 'cmf.never' }
    if ($Seconds -lt 60) { return T 'cmf.sec' $Seconds }
    if ($Seconds -lt 3600 -or $Seconds % 3600) { return T 'cmf.min' ([int][Math]::Round($Seconds / 60)) }
    T 'cmf.hours' ([int]($Seconds / 3600))
}

function Test-HcPowerTimes {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $sides = if ($Facts.Laptop) { @('Ac', 'Dc') } else { @('Ac') }
    foreach ($side in $sides) {
        $where = T "cmf.on$side"
        if ($Facts.Screen) {
            $s = $Facts.Screen.$side
            $line = if ($s -le 0) { T 'cmf.screenNever' $where } else { T 'cmf.screenOff' $where (Format-HcSeconds $s) }
            if ($s -gt 0 -and $s -lt $script:ScreenOffShort[$side]) { Add-HcLine $r warn $line; if (-not $found['screenOffFast']) { $found['screenOffFast'] = @(Format-HcSeconds $s) } }
            else { Add-HcLine $r ok $line }
        }
        if ($Facts.Sleep) {
            $s = $Facts.Sleep.$side
            $line = if ($s -le 0) { T 'cmf.sleepNever' $where } else { T 'cmf.sleep' $where (Format-HcSeconds $s) }
            if ($s -gt 0 -and $s -lt $script:SleepShort[$side]) { Add-HcLine $r warn $line; if (-not $found['sleepFast']) { $found['sleepFast'] = @(Format-HcSeconds $s) } }
            else { Add-HcLine $r ok $line }
        }
    }
    if (-not $Facts.Screen -and -not $Facts.Sleep) { Add-HcLine $r skipped (T 'cmf.powerUnknown') }
    if ($found.Count) { Add-HcAction $r 'longerTimeouts' }
    Select-HcFinding $r $found @('screenOffFast', 'sleepFast') 'powerTimesOk'
    $r
}

# The fix: longer where shorter, never shorter; the old values kept for undo.
function Set-HcLongerTimeouts {
    param([hashtable]$Target)
    $now = @{ Screen = (Get-HcPowerTimeout 'SUB_VIDEO' 'VIDEOIDLE'); Sleep = (Get-HcPowerTimeout 'SUB_SLEEP' 'STANDBYIDLE') }
    if (-not $now.Screen -or -not $now.Sleep) { throw (T 'cmf.powerUnknown') }
    $Target.Saved = $now
    foreach ($side in @('Ac', 'Dc')) {
        $screen = $now.Screen.$side
        if ($screen -gt 0 -and $screen -lt $script:ScreenOffLonger[$side]) { Set-HcPowerValue $side 'SUB_VIDEO' 'VIDEOIDLE' $script:ScreenOffLonger[$side] }
        $sleep = $now.Sleep.$side
        if ($sleep -gt 0 -and $sleep -lt $script:SleepLonger[$side]) { Set-HcPowerValue $side 'SUB_SLEEP' 'STANDBYIDLE' $script:SleepLonger[$side] }
    }
    & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
}

function Undo-HcLongerTimeouts {
    param([hashtable]$Target)
    foreach ($side in @('Ac', 'Dc')) {
        Set-HcPowerValue $side 'SUB_VIDEO' 'VIDEOIDLE' $Target.Saved.Screen.$side
        Set-HcPowerValue $side 'SUB_SLEEP' 'STANDBYIDLE' $Target.Saved.Sleep.$side
    }
    & powercfg.exe /setactive SCHEME_CURRENT | Out-Null
}

function Set-HcPowerValue {
    param([string]$Side, [string]$Sub, [string]$Setting, [long]$Seconds)
    $switch = if ($Side -eq 'Ac') { '/setacvalueindex' } else { '/setdcvalueindex' }
    & powercfg.exe $switch SCHEME_CURRENT $Sub $Setting $Seconds | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg $switch $Setting : $LASTEXITCODE" }
}

# ------------------------------------------------- B5: bigger and readable --

function Get-HcReadFacts {
    $access = Get-ItemProperty 'HKCU:\Software\Microsoft\Accessibility' -ErrorAction SilentlyContinue
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
    [pscustomobject]@{
        TextSize  = $(if ($access.TextScaleFactor) { [int]$access.TextScaleFactor } else { 100 })
        Scale     = $(if ($dpi) { [int]([int]$dpi * 100 / 96) } else { 100 })
        Pointer   = $(if ($access.CursorSize) { [int]$access.CursorSize } else { 1 })
        Magnifier = [bool](Get-Process -Name Magnify -ErrorAction SilentlyContinue)
    }
}

function Test-HcReadable {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    Add-HcLine $r ok (T 'cmf.textSize' $Facts.TextSize)
    Add-HcLine $r ok (T 'cmf.scale' $Facts.Scale)
    Add-HcLine $r ok $(if ($Facts.Pointer -le 1) { T 'cmf.pointerNormal' } else { T 'cmf.pointerBig' $Facts.Pointer })
    if ($Facts.Magnifier) { Add-HcLine $r ok (T 'cmf.magnifierOn') }
    Add-HcAction $r 'openTextSize'
    Add-HcAction $r 'openPointerSize'
    if (-not $Facts.Magnifier) { Add-HcAction $r 'startMagnifier' }
    # Nothing is wrong here: the finding says what is already bigger.
    Set-HcFinding $r $(if ($Facts.TextSize -gt 100 -or $Facts.Scale -gt 125 -or $Facts.Pointer -gt 1) { 'readBigger' } else { 'readNormal' })
    $r
}

# ------------------------------------------------------- C5: the touchpad --

function Get-HcTouchpadFacts {
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $pads = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        "$($_.Name)" -match 'touch\s?pad|precision touch|synaptics|elan|alps' -and "$($_.PNPClass)" -in @('Mouse', 'HIDClass')
    } | ForEach-Object { [pscustomobject]@{ Name = "$($_.Name)"; Code = [int]$_.ConfigManagerErrorCode; InstanceId = "$($_.PNPDeviceID)" } })
    $ptp = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
    $enabled = (Get-ItemProperty "$ptp\Status" -ErrorAction SilentlyContinue).Enabled
    if ($null -eq $enabled) { $enabled = (Get-ItemProperty $ptp -ErrorAction SilentlyContinue).Enabled }
    [pscustomobject]@{
        Laptop          = [bool]@($chassis | Where-Object { $_ -in $script:LaptopChassis }).Count
        Pads            = $pads
        SwitchOff       = ($null -ne $enabled -and [int]$enabled -eq 0)
        OffWithMouse    = ((Get-ItemProperty $ptp -ErrorAction SilentlyContinue).LeaveOnWithMouse -eq 0)
        Mice            = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue).Count
    }
}

function Test-HcTouchpad {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if (-not $Facts.Laptop -and -not @($Facts.Pads).Count) {
        Add-HcLine $r ok (T 'cmf.noPadDesktop')
        Set-HcFinding $r 'touchpadDesktop'
        return $r
    }
    $pads = @($Facts.Pads)
    if (-not $pads.Count) {
        Add-HcLine $r problem (T 'cmf.padNotFound')
        $found['touchpadNotFound'] = @()
    }
    foreach ($p in $pads) {
        if ($p.Code -eq 22) {
            Add-HcLine $r problem (T 'cmf.padDisabled' $p.Name)
            Add-HcAction $r 'enableDevice' @{ Label = $p.Name; InstanceId = $p.InstanceId }
            if (-not $found['touchpadDisabled']) { $found['touchpadDisabled'] = @($p.Name) }
        } elseif ($p.Code -ne 0) {
            Add-HcLine $r problem (T 'cmf.padError' $p.Name)
            Add-HcAction $r 'restartDevice' @{ Label = $p.Name; InstanceId = $p.InstanceId }
            if (-not $found['touchpadError']) { $found['touchpadError'] = @($p.Name) }
        } else {
            Add-HcLine $r ok (T 'cmf.padOk' $p.Name)
        }
    }
    if ($Facts.SwitchOff) {
        Add-HcLine $r problem (T 'cmf.padSwitchOff')
        $found['touchpadOff'] = @()
    }
    if ($Facts.OffWithMouse -and $Facts.Mice -gt 1) {
        Add-HcLine $r warn (T 'cmf.padOffWithMouse')
        $found['touchpadOffWithMouse'] = @()
    }
    Add-HcAction $r 'openTouchpadSettings'
    Select-HcFinding $r $found @('touchpadDisabled', 'touchpadOff', 'touchpadError', 'touchpadOffWithMouse', 'touchpadNotFound') 'touchpadOk'
    $r
}

# --------------------------------------------- E5: messages from Windows --

# The switches behind Windows' own tips and ads, per kind; a missing value
# means on (Windows' default).
$script:HcTipSwitches = @(
    @{ Kind = 'start';    Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Names = @('SubscribedContent-338388Enabled', 'SystemPaneSuggestionsEnabled') }
    @{ Kind = 'tips';     Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Names = @('SubscribedContent-338389Enabled', 'SoftLandingEnabled') }
    @{ Kind = 'welcome';  Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Names = @('SubscribedContent-310093Enabled') }
    @{ Kind = 'settings'; Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Names = @('SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') }
    @{ Kind = 'lock';     Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Names = @('RotatingLockScreenOverlayEnabled', 'SubscribedContent-338387Enabled') }
    @{ Kind = 'finish';   Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Names = @('ScoobeSystemSettingEnabled') }
    @{ Kind = 'explorer'; Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Names = @('ShowSyncProviderNotifications') }
)

function Get-HcTipFacts {
    $kinds = foreach ($s in $script:HcTipSwitches) {
        $p = Get-ItemProperty $s.Key -ErrorAction SilentlyContinue
        $on = $false
        foreach ($n in $s.Names) {
            $v = if ($p) { $p.$n } else { $null }
            if ($null -eq $v -or [int]$v -ne 0) { $on = $true }
        }
        [pscustomobject]@{ Kind = $s.Kind; On = $on }
    }
    [pscustomobject]@{ Kinds = @($kinds) }
}

function Test-HcWindowsTips {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $on = @($Facts.Kinds | Where-Object { $_.On })
    foreach ($k in @($Facts.Kinds)) {
        if ($k.On) { Add-HcLine $r warn (T "cmf.tip.$($k.Kind)") } else { Add-HcLine $r ok (T 'cmf.tipOff' (T "cmf.tip.$($k.Kind)")) }
    }
    if ($on.Count) {
        Add-HcAction $r 'tipsOff'
        Set-HcFinding $r 'windowsTipsOn' @($on.Count)
    } else {
        Set-HcFinding $r 'windowsTipsOff'
    }
    $r
}

# The fix: every switch to 0, each old value kept (or "was not there").
function Set-HcTipsOff {
    param([hashtable]$Target)
    $saved = @()
    foreach ($s in $script:HcTipSwitches) {
        $p = Get-ItemProperty $s.Key -ErrorAction SilentlyContinue
        foreach ($n in $s.Names) {
            $saved += [pscustomobject]@{ Key = $s.Key; Name = $n; Value = $(if ($p) { $p.$n } else { $null }) }
        }
    }
    $Target.Saved = $saved
    foreach ($item in $saved) {
        if (-not (Test-Path $item.Key)) { New-Item $item.Key -Force | Out-Null }
        New-ItemProperty $item.Key -Name $item.Name -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    }
}

function Undo-HcTipsOff {
    param([hashtable]$Target)
    foreach ($item in @($Target.Saved)) {
        if ($null -eq $item.Value) { Remove-ItemProperty $item.Key -Name $item.Name -ErrorAction SilentlyContinue }
        else { New-ItemProperty $item.Key -Name $item.Name -Value $item.Value -PropertyType DWord -Force -ErrorAction Stop | Out-Null }
    }
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcB4 { { Test-HcPowerTimes (Get-HcPowerTimesFacts) } }
function Invoke-HcB5 { { Test-HcReadable (Get-HcReadFacts) } }
function Invoke-HcC5 { { Test-HcTouchpad (Get-HcTouchpadFacts) } }
function Invoke-HcE5 { { Test-HcWindowsTips (Get-HcTipFacts) } }

$script:ProblemHandlers['B4'] = 'Invoke-HcB4'
$script:ProblemHandlers['B5'] = 'Invoke-HcB5'
$script:ProblemHandlers['C5'] = 'Invoke-HcC5'
$script:ProblemHandlers['E5'] = 'Invoke-HcE5'
