<#
    The invoice as a drawn A4 page (layout "B", Shamil's choice): seller and
    number on top, the client next to what it was about, then one table
    with the work done and the costs, the total and how it was paid.

    Get-HcInvoiceLayout measures everything once and returns the pages as
    drawing steps; Write-HcInvoicePage draws a page from them. The window
    and the printer use the same steps, so paper looks like the screen.
    Units are pixels of an A4 page at 96 dpi (794 x 1123).
#>

$script:HcPage = @{ Width = 794; Height = 1123; Left = 64; Right = 730; Top = 60; Bottom = 1040 }

function Get-HcInvoiceStyle {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $world = [Drawing.GraphicsUnit]::World
    $f = { param($size, $style = 'Regular') New-Object Drawing.Font('Segoe UI', [single]$size, [Drawing.FontStyle]$style, $world) }
    @{
        Fonts  = @{
            title = & $f 30 'Bold'; body = & $f 14; bodyBold = & $f 14 'Bold'; small = & $f 12.5
            cap = & $f 11 'Bold'; total = & $f 17 'Bold'; item = & $f 13.5
        }
        Colors = @{
            ink   = [Drawing.Color]::FromArgb(27, 31, 36)
            muted = [Drawing.Color]::FromArgb(107, 116, 128)
            rule  = [Drawing.Color]::FromArgb(215, 221, 227)
            ok    = [Drawing.Color]::FromArgb(46, 125, 79)
            open  = [Drawing.Color]::FromArgb(164, 84, 27)
        }
    }
}

# What the visit was about: the question typed in the invoice window, or
# else the problems that were checked.
function Get-HcInvoiceSubject {
    if ("$script:HcAsked".Trim()) { return "$script:HcAsked".Trim() }
    (@($script:HcVisit) | ForEach-Object { T "problem.$($_.Code)" }) -join ', '
}

# The work under "Computerhulp aan huis": Housecall's own fixes and the
# hand-made list, each with Done.
function Get-HcInvoiceWork {
    foreach ($c in @($script:HcChanges)) { [pscustomobject]@{ Text = $c.Label; Done = $true } }
    foreach ($w in @($script:HcWork)) {
        if ($w.Done) { [pscustomobject]@{ Text = $w.Text; Done = $true } }
        else { [pscustomobject]@{ Text = (T 'doc.notFixed' $w.Text); Done = $false } }
    }
}

# -Note: the same page as a plain note, for a visit without an invoice: no
# number and no amounts, but what was found, and how to reach Shamil.
function Get-HcInvoiceLayout {
    param($Invoice, [switch]$Note)
    $style = Get-HcInvoiceStyle
    $F = $style.Fonts
    $P = $script:HcPage
    $bmp = New-Object Drawing.Bitmap(1, 1)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.PageUnit = [Drawing.GraphicsUnit]::Pixel
    $measure = { param($text, $font, $width) $g.MeasureString([string]$text, $F[$font], [int]$width).Height }

    $pages = New-Object System.Collections.ArrayList
    $page = New-Object System.Collections.ArrayList
    [void]$pages.Add($page)
    $y = [single]$P.Top
    $text = { param($t, $font, $x, $yy, $w, $color = 'ink', $align = 'left')
        [void]$page.Add([pscustomobject]@{ Kind = 'text'; Text = [string]$t; Font = $font; X = [single]$x; Y = [single]$yy; W = [single]$w; Color = $color; Align = $align }) }
    $line = { param($yy, $color = 'rule', $width = 1)
        [void]$page.Add([pscustomobject]@{ Kind = 'line'; Y = [single]$yy; X = [single]$P.Left; X2 = [single]$P.Right; Color = $color; Width = [single]$width }) }
    # A new page when the next piece does not fit.
    $room = { param($h)
        if ($y + $h -gt $P.Bottom) {
            $next = New-Object System.Collections.ArrayList
            [void]$pages.Add($next)
            Set-Variable -Name page -Value $next -Scope 1
            Set-Variable -Name y -Value ([single]$P.Top) -Scope 1
        } }

    $s = $Invoice.seller
    $issued = [datetime]::Parse([string]$Invoice.issued_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
    $full = $P.Right - $P.Left
    $half = ($full - 32) / 2
    $amountW = 120
    $descW = $full - $amountW - 16

    # Top: "Factuur", number and date on the left; the seller on the right.
    # GDI+ pads text by a sixth of its size; at 30 px that shows, so pull it back in line.
    & $text $(if ($Note) { T 'doc.noteWord' } else { T 'doc.invoiceWord' }) 'title' ($P.Left - 4) $y $half
    $leftY = $y + (& $measure 'F' 'title' $half)
    $dateLine = if ($Note) { Format-HcLongDate $issued } else { T 'doc.numberDate' $Invoice.number (Format-HcLongDate $issued) }
    & $text $dateLine 'small' $P.Left $leftY $half 'muted'
    $leftY += (& $measure 'x' 'small' $half)
    $rightY = $y + 6
    $sellerX = $P.Left + $half + 32
    & $text $s.business_name 'bodyBold' $sellerX $rightY $half 'ink' 'right'
    $rightY += (& $measure 'x' 'bodyBold' $half)
    $ids = @()
    if ($s.kvk) { $ids += T 'doc.kvk' $s.kvk }
    if ($s.btw_number) { $ids += T 'doc.btwNumber' $s.btw_number }
    if ($s.iban) { $ids += T 'doc.iban' $s.iban }
    foreach ($l in @(@($s.owner_name, $s.address, $s.postcode_city, $s.email, $s.phone) + $ids | Where-Object { $_ })) {
        & $text $l 'small' $sellerX $rightY $half 'muted' 'right'
        $rightY += (& $measure $l 'small' $half)
    }
    $y = [Math]::Max($leftY, $rightY) + 34

    # The client, next to what it was about.
    & $text $(if ($Note) { T 'doc.forCap' } else { T 'doc.toCap' }) 'cap' $P.Left $y $half 'muted'
    & $text (T 'doc.subjectCap') 'cap' $sellerX $y $half 'muted'
    $y += 18
    $clientY = $y
    foreach ($l in @($Invoice.client_name, $Invoice.client_address, $Invoice.client_postcode_city, $Invoice.client_email) | Where-Object { $_ }) {
        & $text $l 'body' $P.Left $clientY $half
        $clientY += (& $measure $l 'body' $half)
    }
    $subject = Get-HcInvoiceSubject
    $subjectY = $y
    if ($subject) {
        & $text $subject 'body' $sellerX $y $half
        $subjectY += (& $measure $subject 'body' $half)
    }
    $y = [Math]::Max($clientY, $subjectY) + 34

    # The table.
    & $text (T 'doc.descriptionCap') 'cap' $P.Left $y $descW 'muted'
    if (-not $Note) { & $text (T 'doc.amountCap') 'cap' ($P.Right - $amountW) $y $amountW 'muted' 'right' }
    $y += 20
    & $line $y 'ink' 1.5
    $y += 8

    $work = @(Get-HcInvoiceWork)
    if ($work.Count) {
        & $room 30
        & $text (T 'doc.workTitle') 'bodyBold' $P.Left $y $descW
        $y += (& $measure 'x' 'bodyBold' $descW) + 2
        foreach ($w in $work) {
            $h = & $measure $w.Text 'item' ($descW - 24)
            & $room $h
            [void]$page.Add([pscustomobject]@{ Kind = $(if ($w.Done) { 'check' } else { 'dash' }); X = [single]($P.Left + 4); Y = [single]($y + 5); Color = $(if ($w.Done) { 'ok' } else { 'open' }) })
            & $text $w.Text 'item' ($P.Left + 24) $y ($descW - 24) $(if ($w.Done) { 'ink' } else { 'muted' })
            $y += $h + 1
        }
        $y += 6
        & $line $y
        $y += 8
    }
    # Advice from the Pc-overzicht, under the work: what would help next.
    $advice = @($script:HcAdvice)
    if ($advice.Count) {
        & $room 30
        & $text (T 'doc.adviceTitle') 'bodyBold' $P.Left $y $descW
        $y += (& $measure 'x' 'bodyBold' $descW) + 2
        foreach ($a in $advice) {
            $h = & $measure $a 'item' ($descW - 24)
            & $room $h
            & $text ([string][char]0x2192) 'item' ($P.Left + 2) $y 20 'open'
            & $text $a 'item' ($P.Left + 24) $y ($descW - 24)
            $y += $h + 1
        }
        $y += 6
        & $line $y
        $y += 8
    }
    if ($Note) {
        if ($work.Count -eq 0) {
            & $text (T 'note.nothingChanged') 'item' $P.Left $y $descW 'muted'
            $y += (& $measure 'x' 'item' $descW) + 14
        }
        # What was found, so the client can read back what was going on.
        $found = @($script:HcVisit | Where-Object { $_.FindingId })
        if ($found.Count) {
            & $room 40
            & $text (T 'note.found') 'bodyBold' $P.Left $y $full
            $y += (& $measure 'x' 'bodyBold' $full) + 2
            foreach ($v in $found) {
                $all = @('finding.' + $v.FindingId) + @($v.FindingArgs)
                $t = T @all
                $h = & $measure $t 'item' $full
                & $room $h
                & $text $t 'item' $P.Left $y $full
                $y += $h + 4
            }
            $y += 14
        }
        foreach ($para in @(@(T 'doc.noteKeep') + @($script:Contact))) {
            $h = & $measure $para 'small' $full
            & $room $h
            & $text $para 'small' $P.Left $y $full 'muted'
            $y += $h + 4
        }
    }
    $money = if ($Note) { @() } else { @($Invoice.lines) }
    foreach ($l in $money) {
        $h = & $measure $l.description 'body' $descW
        & $room ($h + 10)
        & $text $l.description 'body' $P.Left $y $descW
        & $text (Format-HcMoney ([decimal]$l.amount)) 'body' ($P.Right - $amountW) $y $amountW 'ink' 'right'
        $y += $h + 6
        & $line $y
        $y += 8
    }
    # The money: only on the invoice.
    if (-not $Note) {
        if ($Invoice.btw_mode -eq '21') {
            foreach ($pair in @(@((T 'doc.subtotal'), $Invoice.subtotal), @((T 'doc.btw'), $Invoice.btw_amount))) {
                & $room 26
                & $text $pair[0] 'small' $P.Left $y $descW 'muted'
                & $text (Format-HcMoney ([decimal]$pair[1])) 'small' ($P.Right - $amountW) $y $amountW 'muted' 'right'
                $y += 22
            }
        }
        & $room 44
        $y += 2
        & $line $y 'ink' 2
        $y += 8
        & $text (T 'doc.totalWord') 'total' $P.Left $y $descW
        & $text (Format-HcMoney ([decimal]$Invoice.total)) 'total' ($P.Right - $amountW - 40) $y ($amountW + 40) 'ink' 'right'
        $y += (& $measure 'x' 'total' $descW) + 26

        # How it was paid, and the BTW note.
        $paidOn = Format-HcLongDate $issued
        $pay = switch ($Invoice.payment) {
            'pin'      { T 'doc.paidPin' $paidOn }
            'cash'     { T 'doc.paidCash' $paidOn }
            'tikkie'   { T 'doc.paidTikkie' $paidOn }
            'transfer' {
                $due = Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture))
                T 'doc.transfer' (Format-HcMoney ([decimal]$Invoice.total)) $due $s.iban $Invoice.number
            }
        }
        foreach ($para in @($pay, $(if ($Invoice.btw_mode -eq 'kor') { T 'doc.kor' })) | Where-Object { $_ }) {
            $font = if ($para -eq $pay) { 'body' } else { 'small' }
            $h = & $measure $para $font $full
            & $room $h
            & $text $para $font $P.Left $y $full $(if ($font -eq 'small') { 'muted' } else { 'ink' })
            $y += $h + 10
        }
    }

    # The foot of every page.
    $n = $pages.Count
    for ($i = 0; $i -lt $n; $i++) {
        $page = $pages[$i]
        & $line ($P.Bottom + 22)
        & $text (T 'doc.thanks') 'small' $P.Left ($P.Bottom + 30) $half 'muted'
        & $text (T 'doc.pageOf' ($i + 1) $n) 'small' $sellerX ($P.Bottom + 30) $half 'muted' 'right'
    }
    $g.Dispose(); $bmp.Dispose()
    # One array of steps per page (a plain list, so @() gives the pages).
    foreach ($pg in $pages) { , $pg.ToArray() }
}

function Write-HcInvoicePage {
    param([Drawing.Graphics]$Graphics, [object[]]$Steps)
    $style = Get-HcInvoiceStyle
    $Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    foreach ($s in $Steps) {
        $color = $style.Colors[$s.Color]
        switch ($s.Kind) {
            'text' {
                $format = New-Object Drawing.StringFormat
                if ($s.Align -eq 'right') { $format.Alignment = [Drawing.StringAlignment]::Far }
                $brush = New-Object Drawing.SolidBrush($color)
                $rect = New-Object Drawing.RectangleF($s.X, $s.Y, $s.W, [single]400)
                $Graphics.DrawString($s.Text, $style.Fonts[$s.Font], $brush, $rect, $format)
                $brush.Dispose(); $format.Dispose()
            }
            'line' {
                $pen = New-Object Drawing.Pen($color, $s.Width)
                $Graphics.DrawLine($pen, $s.X, $s.Y, $s.X2, $s.Y)
                $pen.Dispose()
            }
            # Drawn, not typed: GDI+ does not fall back to a font that has a tick.
            'check' {
                $pen = New-Object Drawing.Pen($color, [single]2)
                $Graphics.DrawLines($pen, [Drawing.PointF[]]@(
                    (New-Object Drawing.PointF(($s.X), ($s.Y + 5))),
                    (New-Object Drawing.PointF(($s.X + 4), ($s.Y + 9))),
                    (New-Object Drawing.PointF(($s.X + 11), ($s.Y + 1)))))
                $pen.Dispose()
            }
            'dash' {
                $pen = New-Object Drawing.Pen($color, [single]2)
                $Graphics.DrawLine($pen, $s.X, ($s.Y + 5), ($s.X + 10), ($s.Y + 5))
                $pen.Dispose()
            }
        }
    }
}

# A page as a picture, for the window.
function New-HcInvoiceBitmap {
    param([object[]]$Steps)
    $bmp = New-Object Drawing.Bitmap($script:HcPage.Width, $script:HcPage.Height)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.PageUnit = [Drawing.GraphicsUnit]::Pixel
    $g.Clear([Drawing.Color]::White)
    Write-HcInvoicePage $g $Steps
    $g.Dispose()
    $bmp
}

# The window: the pages under each other on a grey ground, Print and Close.
function Show-HcInvoicePages {
    param($Invoice)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:HcInvoicePages = @(Get-HcInvoiceLayout $Invoice)
    $family = 'Segoe UI'

    $form = New-Object Windows.Forms.Form
    $form.Text = T 'doc.windowTitle' $Invoice.number
    $form.StartPosition = 'CenterScreen'
    $height = [Math]::Min(1000, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 20)
    $form.Size = New-Object Drawing.Size(880, $height)
    $form.MinimumSize = New-Object Drawing.Size(500, 400)
    $form.BackColor = [Drawing.Color]::FromArgb(233, 237, 241)
    $form.TopMost = $true
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })

    $scroll = New-Object Windows.Forms.FlowLayoutPanel
    $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true; $scroll.FlowDirection = 'TopDown'; $scroll.WrapContents = $false
    $scroll.Padding = New-Object Windows.Forms.Padding(28, 20, 20, 20)
    $scroll.BackColor = $form.BackColor
    foreach ($steps in $script:HcInvoicePages) {
        $pic = New-Object Windows.Forms.PictureBox
        $pic.Image = New-HcInvoiceBitmap $steps
        $pic.SizeMode = 'AutoSize'
        $pic.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 20)
        $scroll.Controls.Add($pic)
    }

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.FlowDirection = 'RightToLeft'; $buttons.Height = 72
    $buttons.Padding = New-Object Windows.Forms.Padding(24, 12, 24, 12)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $close = New-Object Windows.Forms.Button
    $close.Text = T 'note.close'; $close.Size = New-Object Drawing.Size(150, 44); $close.Font = New-Object Drawing.Font($family, 12)
    $close.BackColor = [Drawing.Color]::White; $close.ForeColor = [Drawing.Color]::Black
    $close.Add_Click({ $this.FindForm().Close() })
    $form.CancelButton = $close
    $print = New-Object Windows.Forms.Button
    $print.Text = T 'note.print'; $print.Size = New-Object Drawing.Size(150, 44); $print.Font = New-Object Drawing.Font($family, 12)
    $print.BackColor = [Drawing.Color]::White; $print.ForeColor = [Drawing.Color]::Black
    $print.Add_Click({ Invoke-HcInvoicePrint })
    $buttons.Controls.Add($close); $buttons.Controls.Add($print)

    $form.Controls.Add($scroll)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $close
    [void]$form.ShowDialog()
    foreach ($c in $scroll.Controls) { if ($c.Image) { $c.Image.Dispose() } }
    $form.Dispose()
}

# The pages in $script:HcInvoicePages as a document for any printer.
function New-HcPagesDocument {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    $doc = New-Object Drawing.Printing.PrintDocument
    $doc.DocumentName = 'Housecall'
    $script:HcInvoicePrintAt = 0
    $doc.Add_PrintPage({
        param($sender, $e)
        $g = $e.Graphics
        # The printer draws in hundredths of an inch from its printable edge:
        # move back to the paper's corner, then scale 96 dpi pixels to it.
        $g.PageUnit = [Drawing.GraphicsUnit]::Display
        $g.TranslateTransform(-$e.PageSettings.HardMarginX, -$e.PageSettings.HardMarginY)
        $g.ScaleTransform([single](100 / 96), [single](100 / 96))
        Write-HcInvoicePage $g $script:HcInvoicePages[$script:HcInvoicePrintAt]
        $script:HcInvoicePrintAt++
        $e.HasMorePages = $script:HcInvoicePrintAt -lt $script:HcInvoicePages.Count
    })
    $doc
}

function Invoke-HcInvoicePrint {
    $doc = New-HcPagesDocument
    $dialog = New-Object Windows.Forms.PrintDialog
    $dialog.Document = $doc
    $dialog.UseEXDialog = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        try { $doc.Print() } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Housecall') }
    }
    $doc.Dispose()
}

<#
    Saves the pages as a PDF through Windows' own "Microsoft Print to PDF",
    without a print dialog: for a client who wants the invoice by email, or
    a copy on the USB stick. Returns $null when it worked, else the reason.
#>
function Save-HcPagesPdf {
    param([string]$Path)
    $doc = New-HcPagesDocument
    try {
        $doc.PrinterSettings.PrinterName = 'Microsoft Print to PDF'
        if (-not $doc.PrinterSettings.IsValid) { return (T 'doc.noPdfPrinter') }
        $doc.PrinterSettings.PrintToFile = $true
        $doc.PrinterSettings.PrintFileName = $Path
        $doc.PrintController = New-Object Drawing.Printing.StandardPrintController
        $doc.Print()
        $null
    } catch {
        $_.Exception.Message
    } finally {
        $doc.Dispose()
    }
}