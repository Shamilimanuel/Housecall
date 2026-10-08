<#
    The window's Pc-overzicht tab (phase 6, step 3): cards for this PC,
    Windows, memory, storage and the battery, and the advice under them.
    Read-only: the facts come from the worker (Get-HcOverviewFacts), the
    rules are the pure ones in src\checks\overview.ps1. A piece of advice
    can go on the note or invoice with one click ($script:HcAdvice).
#>

function Start-HcPcLoad {
    $p = $script:HcWin.Pc
    $p.Stage = 'loading'
    Add-HcJob @{ Kind = 'overview'; Done = 'Complete-HcPcLoad' }
}

function Complete-HcPcLoad {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $p = $script:HcWin.Pc
    $facts = @($Output | Where-Object { $_ -and $_.PSObject.Properties['Disks'] }) | Select-Object -Last 1
    if ($ErrorText -or -not $facts) {
        $p.Stage = 'error'
        $p.Error = $(if ($ErrorText) { $ErrorText } else { '-' })
    } else {
        $p.Facts = $facts
        $p.Advice = @(Get-HcOverviewAdvice $facts)
        $p.Stage = 'ready'
    }
    Update-HcOther
}

# A card: a title, then its lines.
function New-HcCard {
    param([string]$Title, [object[]]$Children)
    $stack = New-Object Windows.Controls.StackPanel
    [void]$stack.Children.Add((New-HcText $Title.ToUpperInvariant() 12 'Soft' -Bold -Margin @(0, 0, 0, 8)))
    foreach ($c in $Children) { if ($c) { [void]$stack.Children.Add($c) } }
    $card = New-Object Windows.Controls.Border
    $card.Width = 300
    $card.CornerRadius = New-Object Windows.CornerRadius(12)
    $card.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $card.Padding = New-HcThickness @(16, 14, 16, 10)
    $card.Margin = New-HcThickness @(0, 0, 14, 14)
    $card.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel')
    $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Line')
    $card.Child = $stack
    $card
}

function New-HcBar {
    param([double]$Percent, [string]$Brush = 'Hi')
    $bar = New-Object Windows.Controls.ProgressBar
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
    $bar.Height = 8
    $bar.BorderThickness = New-HcThickness @(0, 0, 0, 0)
    $bar.Margin = New-HcThickness @(0, 2, 0, 4)
    $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $Brush)
    $bar.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Line')
    $bar
}

function Update-HcPcPanel {
    param($Panel)
    $w = $script:HcWin
    $p = $w.Pc
    $add = { param($element) [void]$Panel.Children.Add($element) }
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = New-HcThickness @(0, 0, 0, 14)
    $refresh = New-HcButton (T 'pc.refresh') @{ Do = 'pcRefresh' }
    $refresh.IsEnabled = $p.Stage -ne 'loading' -and -not (Test-HcBusy)
    [Windows.Controls.DockPanel]::SetDock($refresh, 'Right')
    [void]$head.Children.Add($refresh)
    [void]$head.Children.Add((New-HcText (T 'pc.readOnly') 15 'Soft' -Margin @(0, 8, 0, 0)))
    & $add $head

    if ($p.Stage -eq 'new') { Start-HcPcLoad }
    switch ($p.Stage) {
        'loading' {
            & $add (New-HcText (T 'pc.loading') 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.MaxWidth = 400
            $bar.HorizontalAlignment = 'Left'
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
            return
        }
        'error' { & $add (New-HcText (T 'pc.error' $p.Error) 15 'Warn' -Bold); return }
    }
    $f = $p.Facts
    $today = Get-Date
    $cards = New-Object Windows.Controls.WrapPanel

    # This PC.
    $lines = @((New-HcText $f.Name 17 'Text' -Bold -Margin @(0, 0, 0, 4)))
    $lines += New-HcText $(if ($f.Laptop) { T 'pc.laptop' } else { T 'pc.desktop' }) 14 'Soft'
    $lines += New-HcText $f.Cpu 14.5 'Text' -Margin @(0, 0, 0, 2)
    $year = Get-HcCpuYear $f.Cpu
    $lines += New-HcText $(if ($year) { T 'pc.cpuYear' $year $f.Cores } else { T 'pc.cpuCores' $f.Cores }) 13.5 'Soft'
    foreach ($g in @($f.Gpus)) { $lines += New-HcText (T 'pc.gpu' $g) 13.5 'Soft' -Margin @(0, 0, 0, 2) }
    [void]$cards.Children.Add((New-HcCard (T 'pc.card.pc') $lines))

    # Windows, and until when it gets updates.
    $support = Get-HcWindowsSupport $f.Build $f.DisplayVersion $f.Edition $today
    $lines = @((New-HcText (($f.Os + ' ' + $f.DisplayVersion).Trim()) 16 'Text' -Bold))
    if (-not $support) {
        $lines += New-HcLine 'skipped' (T 'pc.win.unknown')
    } elseif ($support.Major -eq 10) {
        $lines += New-HcLine 'problem' (T 'pc.win10' (Format-HcLongDate $support.End))
        $lines += New-HcLine $(if ($today -lt $support.Esu) { 'warn' } else { 'problem' }) (T 'pc.win10Esu' (Format-HcLongDate $support.Esu))
        $cpuOk = Test-HcCpuWin11 $f.Cpu
        $lines += New-HcLine $(if ($cpuOk -eq $true) { 'ok' } elseif ($cpuOk -eq $false) { 'problem' } else { 'skipped' }) (T "pc.win11Cpu.$(if ($null -eq $cpuOk) { 'unknown' } else { "$cpuOk".ToLower() })")
    } else {
        $status = @{ ok = 'ok'; soon = 'warn'; ended = 'problem' }[$support.Status]
        $lines += New-HcLine $status (T "pc.win.$($support.Status)" (Format-HcLongDate $support.End))
    }
    [void]$cards.Children.Add((New-HcCard 'Windows' $lines))

    # Memory.
    $lines = @((New-HcText ((T 'pc.ram' ([Math]::Round($f.RamGB)) "$($f.RamType)")).Trim() 16 'Text' -Bold))
    if ($f.SlotsTotal -gt 0) { $lines += New-HcText (T 'pc.slots' $f.SlotsUsed $f.SlotsTotal) 13.5 'Soft' }
    $lines += New-HcLine $(if ($f.RamGB -ge 7.5) { 'ok' } else { 'warn' }) $(if ($f.RamGB -ge 7.5) { T 'pc.ramOk' } else { T 'pc.ramLow' })
    [void]$cards.Children.Add((New-HcCard (T 'pc.card.ram') $lines))

    # Storage: every disk, and how full the one with Windows is.
    $lines = @()
    foreach ($d in @($f.Disks)) {
        $lines += New-HcText ((Format-HcSize $d.SizeGB) + ' ' + (T "pc.kind.$($d.Kind)") + $(if ($d.Bus -eq 'NVMe') { ' (NVMe)' } else { '' })) 15 'Text' -Bold -Margin @(0, 4, 0, 0)
        $lines += New-HcText $d.Name 12.5 'Soft' -Margin @(0, 0, 0, 2)
        if ($d.Number -eq $f.SystemDisk -and $f.SystemSizeGB -gt 0) {
            $used = 100 * (1 - $f.SystemFreeGB / $f.SystemSizeGB)
            $lines += New-HcText (T 'pc.systemDisk') 13.5 'Text'
            $lines += New-HcBar $used $(if ($used -ge 90) { 'Warn' } else { 'Hi' })
            $lines += New-HcText (T 'pc.free' ([Math]::Round($f.SystemFreeGB)) ([Math]::Round($f.SystemSizeGB))) 13 'Soft'
        }
        $lines += New-HcLine $(if ($d.Health -eq 'Healthy') { 'ok' } elseif ($d.Health) { 'problem' } else { 'skipped' }) $(if ($d.Health -eq 'Healthy') { T 'pc.healthOk' } else { T 'pc.healthBad' $d.Health })
    }
    if (-not $lines.Count) { $lines = @(New-HcLine 'skipped' (T 'pc.noDisks')) }
    [void]$cards.Children.Add((New-HcCard (T 'pc.card.disk') $lines))

    # The battery, on a laptop.
    if ($f.HasBattery) {
        $lines = if ($f.BatteryHealth) {
            @((New-HcText "$($f.BatteryHealth)%" 20 'Text' -Bold), (New-HcBar $f.BatteryHealth $(if ($f.BatteryHealth -lt 70) { 'Warn' } else { 'Ok' })), (New-HcText (T 'pc.battery' $f.BatteryHealth) 13.5 'Soft'))
        } else { @(New-HcLine 'skipped' (T 'pc.noBatteryInfo')) }
        [void]$cards.Children.Add((New-HcCard (T 'pc.card.battery') $lines))
    }
    & $add $cards

    # The advice.
    & $add (New-HcText (T 'pc.advice') 20 'Text' -Bold -Margin @(0, 6, 0, 10))
    foreach ($a in @($p.Advice)) {
        $short = Get-HcAdviceText $a '.short'
        $stack = New-Object Windows.Controls.StackPanel
        $status = @{ problem = 'problem'; warn = 'warn'; upgrade = 'tip'; info = 'info'; ok = 'ok' }[$a.Level]
        [void]$stack.Children.Add((New-HcLine $status (Get-HcAdviceText $a '.title') 'Text'))
        $body = New-HcText (Get-HcAdviceText $a) 14.5 'Text' -Margin @(36, 0, 0, 8)
        [void]$stack.Children.Add($body)
        $buttons = New-Object Windows.Controls.WrapPanel
        $buttons.Margin = New-HcThickness @(36, 0, 0, 0)
        if ($a.Level -ne 'ok') {
            $on = $script:HcAdvice -contains $short
            $label = if ($on) { [string][char]0x2713 + ' ' + (T 'pc.onNoteDone') } else { T 'pc.onNote' }
            [void]$buttons.Children.Add((New-HcChip $label @{ Do = 'adviceNote'; Text = $short } -On:$on))
        }
        if ($a.Code) { [void]$buttons.Children.Add((New-HcChip ((T 'win.open' $a.Code) + '  ' + (T "problem.$($a.Code)")) @{ Do = 'problem'; Code = $a.Code })) }
        if ($buttons.Children.Count) { [void]$stack.Children.Add($buttons) }
        $box = New-HcBox '' @($stack) $(if ($a.Level -in @('problem', 'upgrade')) { 'HiSoft' } else { 'Panel' })
        $box.Padding = New-HcThickness @(14, 12, 14, 6)
        $box.MaxWidth = 940
        $box.HorizontalAlignment = 'Left'
        & $add $box
    }
}

# One piece of advice in words: its sentence, or with a suffix its .title or .short.
function Get-HcAdviceText {
    param([pscustomobject]$Advice, [string]$Suffix = '')
    $all = @("adv.$($Advice.Id)$Suffix") + @($Advice.Args)
    T @all
}

function Invoke-HcPcClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    switch ($Tag.Do) {
        'pcRefresh' { if (-not (Test-HcBusy)) { $w.Pc.Stage = 'new'; Update-HcOther } }
        'adviceNote' {
            if ($script:HcAdvice -contains $Tag.Text) { $script:HcAdvice.Remove($Tag.Text) } else { [void]$script:HcAdvice.Add($Tag.Text) }
            Update-HcOther
        }
        default { return $false }
    }
    $true
}
