<#
    The window's Start tab (6 Oct, layout A of
    https://claude.ai/artifact/SmkY8P7PSzrzcRfHr1k6TH, chosen by Shamil):
    the first thing he sees at a client's.

      left    what Housecall already sees on this PC (the Pc-overzicht's own
              facts and advice, the ones needing attention first) and the
              last visit to this PC (after the Authenticator code)
      right   "what is the client troubled by?": the problem search and six
              quick buttons, then Alles controleren, Telefoon verbinden and
              Briefje / factuur

    Read-only like the Pc-overzicht: it shares that tab's facts ($HcWin.Pc)
    and the visit history ($HcWin.Hist), loading them when they are not there.
#>

# The quick buttons: what older clients call about most.
$script:HcStartQuick = @('A1', 'D1', 'C1', 'B1', 'F2', 'E1')

function Update-HcStartPanel {
    param($Panel)
    $w = $script:HcWin
    $add = { param($element) [void]$Panel.Children.Add($element) }
    if ($w.Pc.Stage -eq 'new') { Start-HcPcLoad }
    if ((Test-HcUnlocked) -and $w.Hist.Stage -eq 'new') { Start-HcHistoryLoad }

    # Goedemiddag, het bezoek is gestart om 14:05.
    $hour = (Get-Date).Hour
    $part = if ($hour -lt 12) { 'morning' } elseif ($hour -lt 18) { 'afternoon' } else { 'evening' }
    $title = New-HcText (T "start.hello.$part" $script:HcStartedAt.ToString('HH:mm')) 26 'Text' -Bold -Margin @(0, 0, 0, 2)
    $title.FontFamily = New-Object Windows.Media.FontFamily('Georgia')
    & $add $title
    $changed = $script:HcChangeLog.Count
    & $add (New-HcText $(if ($changed) { T 'start.changed' $changed } else { T 'start.nothingYet' }) 14.5 'Soft' -Margin @(0, 0, 0, 16))

    $grid = New-Object Windows.Controls.Grid
    foreach ($share in @(1.25, 1)) {
        $col = New-Object Windows.Controls.ColumnDefinition
        $col.Width = New-Object Windows.GridLength($share, 'Star')
        [void]$grid.ColumnDefinitions.Add($col)
    }
    $left = New-Object Windows.Controls.StackPanel
    $left.Margin = New-HcThickness @(0, 0, 10, 0)
    $right = New-Object Windows.Controls.StackPanel
    $right.Margin = New-HcThickness @(10, 0, 0, 0)
    [Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$grid.Children.Add($left)
    [void]$grid.Children.Add($right)

    [void]$left.Children.Add((New-HcStartPcCard))
    [void]$left.Children.Add((New-HcStartHistoryCard))
    [void]$right.Children.Add((New-HcStartAskCard))
    foreach ($b in @(New-HcStartActions)) { [void]$right.Children.Add($b) }
    & $add $grid
}

# A card with a heading and, on the right, a link-like button to its tab.
function New-HcStartCard {
    param([string]$Title, [hashtable]$LinkTag, [string]$LinkText, [object[]]$Children)
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = New-HcThickness @(0, 0, 0, 8)
    if ($LinkTag) {
        $link = New-HcButton $LinkText $LinkTag
        $link.Padding = New-HcThickness @(10, 3, 10, 3)
        [Windows.Controls.DockPanel]::SetDock($link, 'Right')
        [void]$head.Children.Add($link)
    }
    [void]$head.Children.Add((New-HcText $Title 18 'Text' -Bold -Margin @(0, 2, 0, 0)))
    $card = New-HcPhoneCard (@($head) + @($Children))
    $card.Padding = New-HcThickness @(18, 14, 18, 12)
    $card
}

# What Housecall already sees on this PC: what it is, and what needs attention.
function New-HcStartPcCard {
    $w = $script:HcWin
    $p = $w.Pc
    $lines = @()
    switch ($p.Stage) {
        { $_ -in @('new', 'loading') } { $lines += New-HcText (T 'pc.loading') 14.5 'Soft' }
        'error' { $lines += New-HcText (T 'pc.error' $p.Error) 14.5 'Warn' }
        default {
            $f = $p.Facts
            $lines += New-HcText $f.Name 16 'Text' -Bold -Margin @(0, 0, 0, 2)
            $lines += New-HcText (Get-HcStartPcLine $f) 13.5 'Soft' -Margin @(0, 0, 0, 10)
            $important = @($p.Advice | Where-Object { $_.Level -in @('problem', 'warn', 'upgrade') } | Select-Object -First 3)
            foreach ($a in $important) {
                $status = @{ problem = 'problem'; warn = 'warn'; upgrade = 'tip' }[$a.Level]
                $lines += New-HcLine $status (Get-HcAdviceText $a '.title')
            }
            $lines += New-HcLine 'ok' $(if ($w.Environment.Online) { T 'start.online' } else { T 'start.offline' })
            if (-not $important.Count) { $lines += New-HcLine 'ok' (T 'start.pcFine') }
        }
    }
    New-HcStartCard (T 'start.thisPc') @{ Do = 'tab'; Tab = 'pc' } (T 'win.tab.pc') $lines
}

# Pure: "AMD Ryzen 7 5800X (2020), 32 GB, 2 TB SSD, Windows 11 Home 25H2",
# joined by middle dots.
function Get-HcStartPcLine {
    param([pscustomobject]$Facts)
    $f = $Facts
    $parts = @()
    if ($f.Cpu) {
        $year = Get-HcCpuYear $f.Cpu
        $parts += $(if ($year) { "$($f.Cpu) ($year)" } else { $f.Cpu })
    }
    if ($f.RamGB) { $parts += "$([Math]::Round($f.RamGB)) GB" }
    $system = @($f.Disks | Where-Object { $_.Number -eq $f.SystemDisk }) | Select-Object -First 1
    if ($system) { $parts += ((Format-HcSize $system.SizeGB) + ' ' + (T "pc.kind.$($system.Kind)")) }
    $windows = ("$($f.Os) $($f.DisplayVersion)").Trim()
    if ($windows) { $parts += $windows }
    $parts -join ('  ' + [char]0x00B7 + '  ')
}

# The last visit to this PC, from the history behind the Authenticator code.
function New-HcStartHistoryCard {
    $w = $script:HcWin
    $h = $w.Hist
    $lines = @()
    if (-not (Test-HcUnlocked)) {
        $lines += New-HcText (T 'start.historyLocked') 14 'Soft' -Margin @(0, 0, 0, 8)
        $open = New-HcButton (T 'start.historyOpen') @{ Do = 'visitView'; View = 'history' }
        $open.HorizontalAlignment = 'Left'
        $lines += $open
    } elseif ($h.Stage -in @('new', 'loading')) {
        $lines += New-HcText (T 'start.historyLoading') 14 'Soft'
    } elseif (-not @($h.Visits).Count) {
        $lines += New-HcText (T 'start.historyNone') 14 'Soft'
    } else {
        $v = @($h.Visits)[0]
        $when = Format-HcDate ([datetime]::Parse([string]$v.visited_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime())
        $who = @($when)
        if ($v.label) { $who += [string]$v.label }
        if ($v.invoice_number) { $who += T 'mem.invoice' $v.invoice_number }
        $lines += New-HcText ($who -join ('  ' + [char]0x00B7 + '  ')) 14.5 'Text' -Bold -Margin @(0, 0, 0, 4)
        foreach ($p in @($v.problems | Select-Object -First 3)) { $lines += New-HcText ("$($p.code)  " + (T "problem.$($p.code)")) 13.5 'Soft' -Margin @(0, 0, 0, 2) }
        foreach ($c in @($v.changes | Select-Object -First 2)) { $lines += New-HcText ([string][char]0x2713 + ' ' + $c) 13.5 'Soft' -Margin @(0, 0, 0, 2) }
    }
    New-HcStartCard (T 'start.history') @{ Do = 'visitView'; View = 'history' } (T 'start.historyAll') $lines
}

# "Waar heeft de klant last van?": the problem search and six quick buttons.
function New-HcStartAskCard {
    $w = $script:HcWin
    $lines = @()
    $lines += New-HcText (T 'start.searchLabel') 13 'Soft' -Margin @(0, 0, 0, 4)
    $box = New-Object Windows.Controls.TextBox
    $box.FontSize = 15
    $box.Padding = New-HcThickness @(8, 6, 8, 6)
    $box.Margin = New-HcThickness @(0, 0, 0, 10)
    $box.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Bg')
    $box.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $box.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line')
    $box.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Hi')
    [Windows.Automation.AutomationProperties]::SetName($box, (T 'start.searchLabel'))
    # Enter: the same search in Problemen, with what was typed.
    $box.Add_KeyDown({ if ($_.Key -eq 'Return') { $_.Handled = $true; Submit-HcStartSearch $this.Text } })
    $lines += $box
    $quick = New-Object Windows.Controls.Primitives.UniformGrid
    $quick.Columns = 2
    foreach ($code in $script:HcStartQuick) {
        $content = New-Object Windows.Controls.StackPanel
        $content.Orientation = 'Horizontal'
        [void]$content.Children.Add((New-HcText $code 12 'Hi' -Bold -Margin @(0, 2, 8, 0)))
        [void]$content.Children.Add((New-HcText (T "start.quick.$code") 14.5 '' -Margin @(0, 0, 0, 0)))
        $b = New-HcButton $content @{ Do = 'problem'; Code = $code }
        $b.HorizontalContentAlignment = 'Left'
        $b.Margin = New-HcThickness @(0, 0, 8, 8)
        [void]$quick.Children.Add($b)
    }
    $lines += $quick
    New-HcStartCard (T 'start.ask') $null '' $lines
}

# The three big buttons: check everything, a phone, the note or invoice.
function New-HcStartActions {
    $busy = Test-HcBusy
    $all = New-Object Windows.Controls.StackPanel
    [void]$all.Children.Add((New-HcText (T 'win.checkAll') 16.5 '' -Bold -Margin @(0, 0, 0, 2)))
    $sub = New-HcText (T 'start.checkAllSub' @(Get-HcCheckAllCodes).Count) 13 '' -Margin @(0, 0, 0, 0)
    $sub.Opacity = 0.85
    [void]$all.Children.Add($sub)
    $big = New-HcButton $all @{ Do = 'checkAll' } 'HcPrimary'
    $big.HorizontalContentAlignment = 'Left'
    $big.Margin = New-HcThickness @(0, 4, 0, 10)
    $big.IsEnabled = -not $busy
    $big

    $row = New-Object Windows.Controls.Primitives.UniformGrid
    $row.Columns = 2
    $phone = New-HcButton (T 'start.phone') @{ Do = 'tab'; Tab = 'phone' }
    $phone.Margin = New-HcThickness @(0, 0, 8, 0)
    $note = New-HcButton (T 'win.noteInvoice') @{ Do = 'visitView'; View = 'finish' }
    $note.Margin = New-HcThickness @(0, 0, 0, 0)
    foreach ($b in @($phone, $note)) { $b.IsEnabled = -not $busy; [void]$row.Children.Add($b) }
    $row
}

# Enter in the start search: Problemen, with the same words in its search.
function Submit-HcStartSearch {
    param([string]$Text)
    $w = $script:HcWin
    $w.Tab = 'problems'
    Update-HcTabs
    Update-HcResult
    $box = $w.Window.FindName('ProblemSearch')
    $box.Text = "$Text".Trim()
    [void]$box.Focus()
    $box.CaretIndex = $box.Text.Length
}
