<#
    The window's "Telefoon & tablet" tab (6 Oct, layout A of the mockup at
    https://claude.ai/artifact/DAQnEZNLsMhEY1s9p8orZx, chosen by Shamil):
    the devices on the left, the chosen device in the middle (its tools,
    four figures, the checks M2-M7 as tiles), and a check's result on the
    right, in the same result view as Problemen.

    Nothing here reads the device itself: the facts come from the worker
    (job 'phone', Get-HcPhoneFacts), the checks and fixes are area M's
    (src\checks\android.ps1), run through the window's usual jobs.
#>

# The checks shown as tiles; M1 is the device card itself, M8 the connect view.
$script:HcPhoneTiles = @('M2', 'M3', 'M4', 'M5', 'M6', 'M7')
# The tool buttons on the device card, in this order.
$script:HcPhoneTools = @('phoneMirror', 'phoneScreenshot', 'phoneRestart')

function New-HcPhoneState {
    @{ Stage = 'new'; Facts = $null; Serial = $null; Connect = $false; Ask = $null; Banner = $null
       Notice = $null; ShowSteps = $false; Error = $null; PreferWifi = $false; Pending = @{} }
}

# ---------------------------------------------------------------- loading --

function Start-HcPhoneLoad {
    $p = $script:HcWin.Ph
    $p.Stage = 'loading'
    Add-HcJob @{ Kind = 'phone'; Text = "$($p.Serial)"; Done = 'Complete-HcPhoneLoad' }
}

function Complete-HcPhoneLoad {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $p = $w.Ph
    $facts = @($Output | Where-Object { $_ -and $_.PSObject.Properties['AdbFound'] }) | Select-Object -Last 1
    if ($ErrorText -or -not $facts) {
        $p.Stage = 'error'
        $p.Error = $(if ($ErrorText) { $ErrorText } else { '-' })
        Update-HcPhone
        return
    }
    # Just paired over Wi-Fi: show that device, not a phone on the cable.
    if ($p.PreferWifi) {
        $p.PreferWifi = $false
        $wifi = @($facts.Devices | Where-Object { $_.State -eq 'device' -and (Test-HcWifiSerial $_.Serial) }) | Select-Object -First 1
        if ($wifi -and $wifi.Serial -ne $facts.Serial) { $p.Serial = $wifi.Serial; Start-HcPhoneLoad; return }
    }
    # Another device than before: its old check results no longer apply.
    if ($facts.Serial -ne $p.Serial) {
        foreach ($code in @($w.Reports.Keys | Where-Object { $_ -like 'M*' })) { $w.Reports.Remove($code) }
        if ($w.Code -like 'M*' -and $w.Code -ne 'M8') { $w.Code = $null; $w.Report = $null; $w.View = 'empty' }
    }
    $p.Facts = $facts
    $p.Serial = $facts.Serial
    $p.Stage = 'ready'
    if (-not $facts.Serial) { $p.Connect = $true }
    Update-HcPhone
    if ($w.Tab -eq 'phone') { Update-HcResult }
}

# ------------------------------------------------------------- painting --

function Update-HcPhone {
    $w = $script:HcWin
    # Only while the tab is open: its code boxes share $HcWin.Totp with Bezoek's.
    if (-not $w -or -not $w.Ph -or $w.Tab -ne 'phone') { return }
    if ($w.Ph.Stage -eq 'new') { Start-HcPhoneLoad }
    Update-HcPhoneSide
    Update-HcPhoneMain
}

# A rounded card, the way the other tabs draw them.
function New-HcPhoneCard {
    param([object[]]$Children, [string]$Background = 'Panel', [string]$Border = 'Line')
    $stack = New-Object Windows.Controls.StackPanel
    foreach ($c in $Children) { if ($c) { [void]$stack.Children.Add($c) } }
    $card = New-Object Windows.Controls.Border
    $card.CornerRadius = New-Object Windows.CornerRadius(12)
    $card.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $card.Padding = New-HcThickness @(16, 14, 16, 10)
    $card.Margin = New-HcThickness @(0, 0, 0, 14)
    $card.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $Background)
    $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $Border)
    $card.Child = $stack
    $card
}

function Update-HcPhoneSide {
    $w = $script:HcWin
    $p = $w.Ph
    $panel = $w.Window.FindName('PhoneSide')
    $panel.Children.Clear()
    $busy = Test-HcBusy
    [void]$panel.Children.Add((New-HcHeading (T 'ph.devices')))
    $devices = @()
    if ($p.Facts) { $devices = @($p.Facts.Devices) }
    if (-not $devices.Count) { [void]$panel.Children.Add((New-HcText (T 'ph.none') 14 'Soft' -Margin @(2, 0, 0, 10))) }
    foreach ($d in $devices) {
        $chosen = $p.Facts -and $d.Serial -eq $p.Facts.Serial -and -not $p.Connect
        $name = if ($chosen -and $p.Facts.Name) { $p.Facts.Name } elseif ($d.Model) { $d.Model } else { $d.Serial }
        $content = New-Object Windows.Controls.StackPanel
        [void]$content.Children.Add((New-HcText $name 15 '' -Bold -Margin @(0, 0, 0, 2)))
        $state = switch ($d.State) {
            'device'       { @(([string][char]0x25CF + ' ' + $(if (Test-HcWifiSerial $d.Serial) { T 'ph.via.wifi' } else { T 'ph.via.usb' })), 'Ok') }
            'unauthorized' { @((T 'ph.unauthorized'), 'Warn') }
            default        { @((T 'ph.offline'), 'Warn') }
        }
        [void]$content.Children.Add((New-HcText $state[0] 12.5 $state[1] -Bold -Margin @(0, 0, 0, 0)))
        $b = New-HcButton $content @{ Do = 'phSelect'; Serial = $d.Serial }
        $b.HorizontalContentAlignment = 'Left'
        $b.Margin = New-HcThickness @(0, 0, 0, 8)
        $b.IsEnabled = -not $busy -and $d.State -eq 'device'
        if ($chosen) {
            $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'HiSoft')
            $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Hi')
        }
        [void]$panel.Children.Add($b)
    }
    $connect = New-HcButton ('+  ' + (T 'ph.connect')) @{ Do = 'phConnect' } $(if ($p.Facts -and $p.Facts.Serial) { 'HcButton' } else { 'HcPrimary' })
    $connect.IsEnabled = -not $busy
    [void]$panel.Children.Add($connect)
    $again = New-HcButton (T 'ph.refresh') @{ Do = 'phRefresh' }
    $again.IsEnabled = -not $busy
    [void]$panel.Children.Add($again)
    [void]$panel.Children.Add((New-HcText (T 'ph.doneHint') 13 'Soft' -Margin @(0, 16, 0, 0)))
}

function Update-HcPhoneMain {
    $w = $script:HcWin
    $p = $w.Ph
    $panel = $w.Window.FindName('PhoneMain')
    $panel.Children.Clear()
    $add = { param($element) [void]$panel.Children.Add($element) }
    if ($p.Banner) { & $add (New-HcText $p.Banner 14.5 'Ok' -Bold) }
    if ($p.Notice) { & $add (New-HcText $p.Notice 14.5 'Warn' -Bold) }
    switch ($p.Stage) {
        { $_ -in @('new', 'loading') } {
            & $add (New-HcText (T 'ph.loading') 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.MaxWidth = 400
            $bar.HorizontalAlignment = 'Left'
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
            return
        }
        'error' { & $add (New-HcText (T 'ph.error' $p.Error) 15 'Warn' -Bold); return }
    }
    if ($p.Connect -or -not $p.Facts.Serial) { Add-HcPhoneConnect $panel } else { Add-HcPhoneDevice $panel }
}

# No device yet, or "Toestel verbinden": the cable and Wi-Fi side by side.
function Add-HcPhoneConnect {
    param($Panel)
    $w = $script:HcWin
    $p = $w.Ph
    $f = $p.Facts
    $add = { param($element) [void]$Panel.Children.Add($element) }
    if ($f.Serial) { & $add (New-HcButton ([string][char]0x2190 + '  ' + (T 'ph.back')) @{ Do = 'phBack' }) }
    $title = New-HcText (T 'ph.connect') 24 'Text' -Bold -Margin @(0, 4, 0, 4)
    $title.FontFamily = New-Object Windows.Media.FontFamily('Georgia')
    & $add $title
    & $add (New-HcText (T 'ph.connectIntro') 14.5 'Soft' -Margin @(0, 0, 0, 14))

    # The cable: what Housecall sees on it right now, and the steps for that.
    $cable = @((New-HcText (T 'ph.cable') 18 'Text' -Bold -Margin @(0, 0, 0, 2)), (New-HcText (T 'ph.cableSub') 13 'Soft' -Margin @(0, 0, 0, 10)))
    $i = 1
    foreach ($s in @((T 'ph.cableSteps') -split '\s*\|\s*')) { $cable += New-HcText ("$i. $s") 14 'Text' -Margin @(0, 0, 0, 4); $i++ }
    $status = Test-HcPhoneOverview $f
    if (-not $f.Serial) {
        $first = @($status.Results | Where-Object { $_.Status -eq 'problem' }) | Select-Object -First 1
        $stack = @()
        if ($first) { $stack += New-HcText $first.Text 14.5 'Text' -Bold -Margin @(0, 0, 0, 4) }
        if ($status.FindingId) { $stack += New-HcText (T ('advice.' + $status.FindingId)) 13.5 'Soft' -Margin @(0, 0, 0, 8) }
        $buttons = New-Object Windows.Controls.WrapPanel
        if (-not $f.AdbFound) { [void]$buttons.Children.Add((New-HcButton (T 'ph.getAdb') @{ Do = 'phTool'; FixId = 'getAdb' } 'HcPrimary')) }
        $steps = @(Get-HcSteps $status)
        if ($steps.Count) { [void]$buttons.Children.Add((New-HcButton (T 'fix.steps') @{ Do = 'phSteps' })) }
        [void]$buttons.Children.Add((New-HcButton (T 'ph.refresh') @{ Do = 'phRefresh' }))
        foreach ($b in $buttons.Children) { $b.Margin = New-HcThickness @(0, 0, 8, 6) }
        $stack += $buttons
        if ($p.ShowSteps) {
            for ($k = 0; $k -lt $steps.Count; $k++) { $stack += New-HcText ((T 'fix.stepOf' ($k + 1) $steps.Count) + ' ' + $steps[$k]) 14 'Text' -Margin @(2, 6, 0, 2) }
        }
        if ($p.Ask) { $stack += New-HcPhoneAsk }
        $cable += New-HcBox '' $stack 'HiSoft'
    }
    $cableCard = New-HcPhoneCard $cable

    # Wi-Fi: only the 6-digit code; the address as a way out.
    $wifi = @((New-HcText (T 'ph.wifi') 18 'Text' -Bold -Margin @(0, 0, 0, 2)), (New-HcText (T 'ph.wifiSub') 13 'Soft' -Margin @(0, 0, 0, 10)))
    if ($f.AdbFound) {
        $wifi += New-HcCodeBox 'pair' (T 'ph.wifiIntro') -Label (T 'ph.pairLabel') -Hint (T 'ph.wifiNote') -GoText (T 'ph.pair')
        $wifi += New-HcButton (T 'ph.address') @{ Do = 'phAddress' }
    } else {
        $wifi += New-HcText (T 'ph.wifiNeedsAdb') 14 'Soft'
    }
    $wifiCard = New-HcPhoneCard $wifi

    # One above the other: side by side, the six code boxes do not fit.
    & $add $cableCard
    & $add $wifiCard
}

# The question under a tool: "Scherm van X tonen op deze laptop?" Ja / Nee.
function New-HcPhoneAsk {
    $p = $script:HcWin.Ph
    $label = T ('fix.' + $p.Ask) $p.Facts.Name
    New-HcQuestion (T 'win.confirm' $label) 'phToolYes' 'phToolNo'
}

# The chosen device: its card with the tools, four figures, the checks.
function Add-HcPhoneDevice {
    param($Panel)
    $w = $script:HcWin
    $p = $w.Ph
    $f = $p.Facts
    $busy = Test-HcBusy
    $add = { param($element) [void]$Panel.Children.Add($element) }
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    $dot = '  ' + [char]0x00B7 + '  '

    # "S24 Ultra van shamil (Samsung SM-S928B)": the name big, the model under it.
    $title = $f.Name
    $sub = @()
    if ("$($f.Name)" -match '^(.+) \(([^()]+)\)$') { $title = $Matches[1]; $sub += $Matches[2] }
    $name = New-HcText $title 24 'Text' -Bold -Margin @(0, 0, 0, 2)
    $name.FontFamily = New-Object Windows.Media.FontFamily('Georgia')
    $sub += "Android $($f.Android)"
    if ($f.Patch) { $sub += T 'ph.patch' $f.Patch.ToString('MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture)) }
    if ($null -ne $f.Apps) { $sub += T 'and.apps' $f.Apps }
    $tools = New-Object Windows.Controls.WrapPanel
    $tools.Margin = New-HcThickness @(0, 8, 0, 0)
    foreach ($id in $script:HcPhoneTools) {
        $b = New-HcButton (T "ph.$id") @{ Do = 'phTool'; FixId = $id } $(if ($id -eq 'phoneMirror') { 'HcPrimary' } else { 'HcButton' })
        $b.Margin = New-HcThickness @(0, 0, 8, 6)
        $b.IsEnabled = -not $busy
        [void]$tools.Children.Add($b)
    }
    $off = New-HcButton (T 'ph.phoneDebugOff') @{ Do = 'phTool'; FixId = 'phoneDebugOff' }
    $off.Margin = New-HcThickness @(0, 0, 8, 6)
    $off.IsEnabled = -not $busy
    $off.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Bad')
    [void]$tools.Children.Add($off)
    $card = @($name, (New-HcText ($sub -join $dot) 13.5 'Soft' -Margin @(0, 0, 0, 0)), $tools)
    if ($p.Ask) { $card += New-HcPhoneAsk }
    & $add (New-HcPhoneCard $card)

    # Four figures, coloured by the same limits as the checks.
    $figures = New-Object Windows.Controls.Primitives.UniformGrid
    $figures.Columns = 4
    $figures.Margin = New-HcThickness @(0, 0, 0, 6)
    foreach ($fig in @(Get-HcPhoneFigures $f)) {
        $lines = @((New-HcText $fig.Title.ToUpperInvariant() 11.5 $(if ($fig.Level -eq 'ok') { 'Soft' } else { 'Warn' }) -Bold -Margin @(0, 0, 0, 4)),
                   (New-HcText $fig.Value 15.5 'Text' -Bold -Margin @(0, 0, 0, 2)))
        if ($null -ne $fig.Bar) { $lines += New-HcBar $fig.Bar $(if ($fig.Level -eq 'ok') { 'Ok' } else { 'Warn' }) }
        if ($fig.Note) { $lines += New-HcText $fig.Note 12.5 $(if ($fig.Level -eq 'ok') { 'Soft' } else { 'Warn' }) -Margin @(0, 0, 0, 0) }
        $c = New-HcPhoneCard $lines $(if ($fig.Level -eq 'ok') { 'Panel' } else { 'HiSoft' })
        $c.Margin = New-HcThickness @(0, 0, 8, 8)
        $c.Padding = New-HcThickness @(12, 10, 12, 8)
        [void]$figures.Children.Add($c)
    }
    & $add $figures

    # The checks as tiles: what each found, at a glance.
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = New-HcThickness @(0, 4, 0, 8)
    $all = New-HcButton (T 'ph.checkAll') @{ Do = 'phCheckAll' }
    $all.IsEnabled = -not $busy
    [Windows.Controls.DockPanel]::SetDock($all, 'Right')
    [void]$head.Children.Add($all)
    [void]$head.Children.Add((New-HcText (T 'ph.checks') 18 'Text' -Bold -Margin @(0, 4, 0, 0)))
    & $add $head
    $tiles = New-Object Windows.Controls.Primitives.UniformGrid
    $tiles.Columns = 2
    foreach ($code in $script:HcPhoneTiles) {
        $report = $w.Reports[$code]
        $content = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.StackPanel
        $top.Orientation = 'Horizontal'
        [void]$top.Children.Add((New-HcText $code 12 'Hi' -Bold -Margin @(0, 2, 8, 0)))
        [void]$top.Children.Add((New-HcText (T "ph.tile.$code") 15 '' -Bold -Margin @(0, 0, 0, 0)))
        [void]$content.Children.Add($top)
        $line = if ($p.Pending.ContainsKey($code)) { @((T 'ph.tile.busy'), 'Soft') }
                elseif (-not $report) { @((T 'ph.tile.todo'), 'Soft') }
                else {
                    $level = Get-HcReportLevel $report
                    $first = @($report.Results | Where-Object { $_.Status -eq $level }) | Select-Object -First 1
                    switch ($level) {
                        'ok'    { @(([string][char]0x2713 + ' ' + (T 'ph.tile.ok')), 'Ok') }
                        default { @(([string][char]0x25B2 + ' ' + $(if ($first) { $first.Text } else { T 'ph.tile.look' })), $(if ($level -eq 'problem') { 'Bad' } else { 'Warn' })) }
                    }
                }
        $status = New-HcText $line[0] 12.5 $line[1] -Bold -Margin @(0, 4, 0, 0)
        $status.TextTrimming = 'CharacterEllipsis'
        $status.TextWrapping = 'NoWrap'
        [void]$content.Children.Add($status)
        $b = New-HcButton $content @{ Do = 'phTile'; Code = $code }
        $b.HorizontalContentAlignment = 'Left'
        $b.Margin = New-HcThickness @(0, 0, 8, 8)
        $b.IsEnabled = -not $busy
        if ($w.Code -eq $code) {
            $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'HiSoft')
            $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Hi')
        }
        [void]$tiles.Children.Add($b)
    }
    & $add $tiles
}

<#
    Pure: the four figures on the device card, with the same limits as the
    M checks (storage, memory, battery, last restart). Level ok or warn.
#>
function Get-HcPhoneFigures {
    param([pscustomobject]$Facts)
    $f = $Facts
    $out = @()
    if ($f.DataTotalKB) {
        $pct = 100 * $f.DataFreeKB / $f.DataTotalKB
        $low = $pct -lt $script:PhoneStorageLowPercent -or ($f.DataFreeKB * 1024 / 1e9) -lt $script:PhoneStorageFullGB
        $out += [pscustomobject]@{ Title = (T 'ph.fig.storage'); Value = (T 'ph.free' (Format-HcPhoneSize $f.DataFreeKB)); Bar = (100 - $pct); Note = (T 'ph.of' (Format-HcPhoneSize $f.DataTotalKB)); Level = $(if ($low) { 'warn' } else { 'ok' }) }
    }
    if ($f.RamKB) {
        $freePct = if ($f.RamFreeKB) { 100 * $f.RamFreeKB / $f.RamKB } else { 100 }
        $low = $freePct -lt $script:PhoneMemoryFullPercent -or ($f.RamKB * 1024 / 1e9) -lt $script:PhoneLowRamGB
        $out += [pscustomobject]@{ Title = (T 'ph.fig.memory'); Value = (T 'ph.free' (Format-HcPhoneSize $f.RamFreeKB)); Bar = (100 - $freePct); Note = (T 'ph.of' (Format-HcPhoneSize $f.RamKB)); Level = $(if ($low) { 'warn' } else { 'ok' }) }
    }
    $b = $f.Battery
    if ($b -and $null -ne $b.Level) {
        $state = switch ($b.Status) { 2 { 'charging' } 5 { 'full' } 4 { 'notCharging' } default { if ($b.Plugged) { 'plugged' } else { 'onBattery' } } }
        $bad = ($b.Health -in 3..6) -or ($null -ne $b.TempC -and $b.TempC -ge $script:PhoneHotCelsius) -or ($b.Plugged -and $state -eq 'notCharging' -and $b.Level -lt 95)
        $note = @()
        if ($null -ne $b.Health) { $note += T $(if ($b.Health -in 2..7) { "and.health.$($b.Health)" } else { 'and.health.1' }) }
        if ($null -ne $b.TempC) { $note += T 'ph.degrees' ("$($b.TempC)" -replace '\.', $(if ($script:Lang -eq 'nl') { ',' } else { '.' })) }
        $out += [pscustomobject]@{ Title = (T 'ph.fig.battery'); Value = ("$($b.Level)%, " + (T "and.bat.$state")); Bar = $b.Level; Note = ($note -join ', '); Level = $(if ($bad) { 'warn' } else { 'ok' }) }
    }
    if ($null -ne $f.UptimeSec) {
        $days = [int][Math]::Floor($f.UptimeSec / 86400)
        $long = $days -ge $script:PhoneUptimeDays
        $out += [pscustomobject]@{ Title = (T 'ph.fig.restart'); Value = (T 'ph.daysAgo' $days); Bar = $null; Note = $(if ($long) { T 'ph.restartAdvice' } else { '' }); Level = $(if ($long) { 'warn' } else { 'ok' }) }
    }
    $out
}

# ---------------------------------------------------------------- doing --

function Invoke-HcPhoneClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    $p = $w.Ph
    switch ($Tag.Do) {
        'phSelect'  { if (-not (Test-HcBusy)) { Clear-HcPhoneMessages; $p.Connect = $false; $p.Serial = $Tag.Serial; Start-HcPhoneLoad; Update-HcPhone } }
        'phRefresh' { if (-not (Test-HcBusy)) { Clear-HcPhoneMessages; Start-HcPhoneLoad; Update-HcPhone } }
        'phConnect' { Clear-HcPhoneMessages; $p.Connect = $true; Update-HcPhone }
        'phBack'    { Clear-HcPhoneMessages; $p.Connect = $false; Update-HcPhone }
        'phSteps'   { $p.ShowSteps = -not $p.ShowSteps; Update-HcPhone }
        'phAddress' {
            # Typing the address: the same input view as A3, on the right.
            $w.Code = 'M8'; $w.Input = $w.Inputs['M8']; $w.View = 'input'; Clear-HcMessages; Update-HcResult
        }
        'phTool'    { $p.Ask = $Tag.FixId; $p.Banner = $null; $p.Notice = $null; Update-HcPhone }
        'phToolNo'  { $p.Ask = $null; $p.Notice = T 'fix.cancelled'; Update-HcPhone }
        'phToolYes' { Invoke-HcPhoneTool }
        'phTile'    {
            if (Test-HcBusy) { return $true }
            $report = $w.Reports[$Tag.Code]
            if ($report) {
                # Checked already: show it; "check again" is one click on the right.
                $w.Code = $Tag.Code; $w.Report = $report; $w.View = 'report'; $w.FromAll = $false
                Clear-HcMessages
                $script:HcCurrentCode = $Tag.Code
                Update-HcResult
                Update-HcPhone
            } else {
                Open-HcProblem $Tag.Code
            }
        }
        'phCheckAll' { Start-HcPhoneCheckAll }
        default     { return $false }
    }
    $true
}

function Clear-HcPhoneMessages {
    $p = $script:HcWin.Ph
    $p.Ask = $null
    $p.Banner = $null
    $p.Notice = $null
    $p.ShowSteps = $false
}

# A tool, confirmed: run its fix on the worker like any other.
function Invoke-HcPhoneTool {
    $w = $script:HcWin
    $p = $w.Ph
    $id = $p.Ask
    $p.Ask = $null
    if (-not $id -or (Test-HcBusy)) { return }
    if ($script:DryRun) { $p.Notice = T 'fix.dryRun'; Update-HcPhone; return }
    $name = if ($p.Facts.Name) { $p.Facts.Name } else { $p.Facts.Serial }
    $p.Banner = (T ('fix.' + $id) $name) + '...'
    Add-HcJob @{ Kind = 'fix'; FixId = $id; Target = @{ Serial = $p.Facts.Serial; Label = $name }; Done = 'Complete-HcPhoneTool' }
    Update-HcPhone
    Update-HcSide
}

function Complete-HcPhoneTool {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $p = $w.Ph
    if ($ErrorText) {
        $p.Banner = $null
        $p.Notice = T 'fix.failed' $ErrorText
        Update-HcPhone
        return
    }
    $done = T ('fix.' + $Job.FixId + '.done') $Job.Target.Label
    if (-not $script:Fixes[$Job.FixId].NoLog) {
        [void](Add-HcChange $Job.FixId $Job.Target $done)
    }
    $p.Banner = [string][char]0x2713 + ' ' + $done
    # These change what is connected: read the devices again.
    if ($Job.FixId -in @('phoneRestart', 'phoneDebugOff', 'getAdb')) { Start-HcPhoneLoad }
    Update-HcPhone
    Update-HcSide
}

# "Alles controleren" for the device: M2-M7, each straight onto its tile.
function Start-HcPhoneCheckAll {
    $w = $script:HcWin
    $p = $w.Ph
    if ((Test-HcBusy) -or -not $p.Serial) { return }
    foreach ($code in $script:HcPhoneTiles) {
        $p.Pending[$code] = $true
        Add-HcJob @{ Kind = 'check'; Code = $code; Text = $p.Serial; Done = 'Complete-HcPhoneCheckItem' }
    }
    Update-HcPhone
}

function Complete-HcPhoneCheckItem {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $p = $w.Ph
    $p.Pending.Remove($Job.Code)
    $report = Get-HcJobReport $Output
    if ($report -and -not $ErrorText) {
        $w.Reports[$Job.Code] = $report
        $w.Inputs[$Job.Code] = $Job.Text
        if ((Get-HcReportLevel $report) -ne 'ok') { Save-HcVisit $Job.Code $report }
    }
    Update-HcPhone
}

# The 6-digit pairing code, from the code boxes: M8 with only the code.
function Submit-HcPairCode {
    param([string]$Code)
    $w = $script:HcWin
    $w.Code = 'M8'
    $w.Ph.PreferWifi = $true
    Clear-HcMessages
    Start-HcWindowCheck 'M8' $Code
}
