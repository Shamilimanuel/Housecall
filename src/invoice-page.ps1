<#
    The invoice as a drawn A4 page. Since 17 Oct the "Kader" look, made for
    Shamil's black-and-white laser printer: a heavy line on top, the logo
    with Housecall as on his business card, three boxes with the date, the
    payment and the total, what was done, the costs, a VOLDAAN stamp when
    it is paid, and a box with how to reach him. Only black, white and dark
    grey, and no large filled areas (toner, and blotchy halftones).

    Get-HcInvoiceLayout measures everything once and returns the pages as
    drawing steps; Write-HcInvoicePage draws a page from them. The window
    and the printer use the same steps, so paper looks like the screen.
    Units are pixels of an A4 page at 96 dpi (794 x 1123).
#>

$script:HcPage = @{ Width = 794; Height = 1123; Left = 64; Right = 730; Top = 60; Bottom = 1040 }

function Get-HcInvoiceStyle {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $world = [Drawing.GraphicsUnit]::World
    # Verdana (25 Oct): wide, clearly different letters (I l 1, 0 O) at small
    # sizes, and on every Windows PC. Its sizes are a little under Segoe UI's,
    # since Verdana runs wider.
    $f = { param($size, $style = 'Regular') New-Object Drawing.Font('Verdana', [single]($size * 0.92), [Drawing.FontStyle]$style, $world) }
    @{
        Fonts  = @{
            title = & $f 30 'Bold'; body = & $f 14; bodyBold = & $f 14 'Bold'; small = & $f 12.5
            cap = & $f 11 'Bold'; total = & $f 17 'Bold'; item = & $f 13.5; itemItalic = & $f 13.5 'Italic'
            head = & $f 15 'Bold'; brand = & $f 19 'Bold'; tile = & $f 22 'Bold'; stamp = & $f 24 'Bold'; stampSub = & $f 12 'Bold'
            bigTitle = & $f 34 'Bold'; big = & $f 25
        }
        # Pure black prints as solid toner; anything lighter is dithered.
        Colors = @{
            ink   = [Drawing.Color]::FromArgb(0, 0, 0)
            muted = [Drawing.Color]::FromArgb(68, 68, 68)
            rule  = [Drawing.Color]::FromArgb(0, 0, 0)
            ok    = [Drawing.Color]::FromArgb(0, 0, 0)
            open  = [Drawing.Color]::FromArgb(0, 0, 0)
        }
    }
}

# What the visit was about: the question typed in the invoice window, or
# else the problems that were checked.
function Get-HcInvoiceSubject {
    if ("$script:HcAsked".Trim()) { return "$script:HcAsked".Trim() }
    (@($script:HcVisit) | ForEach-Object { T "problem.$($_.Code)" }) -join ', '
}

# The work under "Wat er is gedaan": Housecall's own fixes and the
# hand-made list, each with Done. -Items: the list an invoice kept (text,
# done), for an invoice drawn again later, such as a corrected one.
function Get-HcInvoiceWork {
    param([object[]]$Items, [switch]$Record)
    if ($Record) {
        foreach ($i in @($Items | Where-Object { $_ })) {
            $t = "$(if ($null -ne $i.text) { $i.text } else { $i.Text })"
            $done = [bool]$(if ($null -ne $i.done) { $i.done } else { $i.Done })
            if ($done) { [pscustomobject]@{ Text = $t; Done = $true } }
            else { [pscustomobject]@{ Text = (T 'doc.notFixed' $t); Done = $false } }
        }
        return
    }
    foreach ($c in @($script:HcChanges)) { [pscustomobject]@{ Text = $c.Label; Done = $true } }
    foreach ($w in @($script:HcWork)) {
        if ($w.Done) { [pscustomobject]@{ Text = $w.Text; Done = $true } }
        else { [pscustomobject]@{ Text = (T 'doc.notFixed' $w.Text); Done = $false } }
    }
}

# "Bel of app 06-..., of mail ... Noem nummer B-2026-0001, ...": the text in
# the box under the costs; empty when the settings have no phone or email.
function Get-HcAskText {
    param($Seller, [string]$Number)
    $phone = "$($Seller.phone)".Trim()
    $mail = "$($Seller.email)".Trim()
    $reach = if ($phone -and $mail) { T 'doc.askPhoneMail' $phone $mail } elseif ($phone) { T 'doc.askPhone' $phone } elseif ($mail) { T 'doc.askMail' $mail } else { return '' }
    # Only a real number: a draft invoice says "concept".
    if ($Number -match '\d{4}-\d{4}') { $reach += ' ' + (T 'doc.askNumber' $Number) }
    $reach
}

# -Note: the same page as a plain note, for a visit without an invoice: no
# number and no amounts, but what was found, and how to reach Shamil.
function Get-HcInvoiceLayout {
    # -Receipt: a betaalbewijs, the amounts and "voldaan" with its own
    # number (B-2026-0001), for visits before the KvK registration.
    # -Record: an invoice drawn from what it kept (subject, work) instead of
    # from this visit, such as a corrected one. An invoice with credit_for is
    # a credit invoice (25 Oct): minus amounts, no work, no stamp, and the
    # sentence about the money (settle_with: the invoice that replaces it).
    param($Invoice, [switch]$Note, [switch]$Receipt, [switch]$Record)
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
    $rect = { param($x, $yy, $w, $h, $width = 1)
        [void]$page.Add([pscustomobject]@{ Kind = 'rect'; X = [single]$x; Y = [single]$yy; W = [single]$w; H = [single]$h; Width = [single]$width; Color = 'ink' }) }
    # A new page when the next piece does not fit.
    $room = { param($h)
        if ($y + $h -gt $P.Bottom) {
            $next = New-Object System.Collections.ArrayList
            [void]$pages.Add($next)
            Set-Variable -Name page -Value $next -Scope 1
            Set-Variable -Name y -Value ([single]$P.Top) -Scope 1
        } }
    $upper = { param($t) $t = [string]$t; if ($t) { $t.Substring(0, 1).ToUpperInvariant() + $t.Substring(1) } else { $t } }

    $s = $Invoice.seller
    $issued = [datetime]::Parse([string]$Invoice.issued_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
    $full = $P.Right - $P.Left
    $half = ($full - 32) / 2
    $colX = $P.Left + $half + 32
    $amountW = 120
    $descW = $full - $amountW - 16
    $credit = -not $Note -and -not $Receipt -and [bool]"$($Invoice.credit_for)"
    # Paid on the spot: a receipt, or an invoice paid by card or in cash. Those get the stamp.
    $paid = -not $Note -and -not $credit -and ($Receipt -or "$($Invoice.payment)" -in @('pin', 'cash'))
    $number = if ($Note) { '' } elseif ($Receipt) { "$($Invoice.receipt_number)" } else { "$($Invoice.number)" }

    # Top: a heavy line; the document's name and number on the left; on the
    # right the logo with Housecall and Shamil's details, as on his card.
    & $line ($y + 3) 'ink' 7
    $y += 24
    & $text $(if ($Note) { T 'doc.noteWord' } elseif ($Receipt) { T 'doc.receiptWord' } elseif ($credit) { T 'doc.creditWord' } else { T 'doc.invoiceWord' }) 'title' ($P.Left - 4) $y $half
    # GDI+ pads text by a sixth of its size; at 30 px that shows, so the title sits 4 px left.
    $leftY = $y + (& $measure 'F' 'title' $half)
    $under = if ($Note) { Format-HcLongDate $issued } else { $number }
    if ($under) {
        & $text $under 'small' $P.Left $leftY $half
        $leftY += (& $measure 'x' 'small' $half)
    }
    $logo = 52
    [void]$page.Add([pscustomobject]@{ Kind = 'logo'; X = [single]($P.Right - $logo); Y = [single]($y + 2); Size = [single]$logo; Color = 'ink' })
    $sellerX = $P.Right - $logo - 14 - $half
    $rightY = $y + 2
    & $text (T 'doc.brand') 'brand' $sellerX $rightY $half 'ink' 'right'
    $rightY += (& $measure 'x' 'brand' $half)
    $who = @(@($s.business_name, (T 'doc.workTitle')) | Where-Object { $_ }) -join ('  ' + [char]0x00B7 + '  ')
    $reach = @(@($s.phone, $s.email) | Where-Object { $_ }) -join ('  ' + [char]0x00B7 + '  ')
    $ids = @()
    if ($s.kvk) { $ids += T 'doc.kvk' $s.kvk }
    if ($s.btw_number) { $ids += T 'doc.btwNumber' $s.btw_number }
    if ($s.iban) { $ids += T 'doc.iban' $s.iban }
    $owner = if ($s.owner_name -and "$($s.owner_name)" -ne "$($s.business_name)") { $s.owner_name } else { $null }
    $first = $true
    foreach ($l in @(@($who, $owner, $s.address, $s.postcode_city, $reach) + $ids | Where-Object { $_ })) {
        & $text $l 'small' $sellerX $rightY $half $(if ($first) { 'ink' } else { 'muted' }) 'right'
        $rightY += (& $measure $l 'small' $half)
        $first = $false
    }
    $y = [Math]::Max([Math]::Max($leftY, $rightY), $y + $logo) + 26

    # Three boxes: the date, how it is paid, the total (the heavy one).
    if (-not $Note) {
        $gap = 12
        $unit = ($full - 2 * $gap) / 3.2
        $payValue = if ("$($Invoice.payment)" -eq 'transfer' -and -not $Receipt) {
            T 'doc.payBefore' (Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture)))
        } elseif ($Invoice.payment) { & $upper (T ('inv.pay.' + $Invoice.payment)) } else { '' }
        $tiles = @(
            @{ Cap = (T 'doc.dateCap'); Value = (Format-HcLongDate $issued); W = $unit; Font = 'bodyBold'; Pen = 1 }
            @{ Cap = $(if ($paid) { T 'doc.paidViaCap' } else { T 'doc.paymentCap' }); Value = $payValue; W = $unit; Font = 'bodyBold'; Pen = 1 }
            @{ Cap = $(if ($paid) { T 'doc.totalPaidCap' } else { T 'doc.totalDueCap' }); Value = (Format-HcMoney ([decimal]$Invoice.total)); W = ($full - 2 * $unit - 2 * $gap); Font = 'tile'; Pen = 3 })
        if ($credit) {
            # The middle box names the invoice it cancels, with that invoice's date.
            $was = "$($Invoice.credit_for)"
            if ($Invoice.credit_for_date) {
                $was = T 'doc.creditOf' $was (Format-HcLongDate ([datetime]::Parse([string]$Invoice.credit_for_date, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()))
            }
            $tiles[1] = @{ Cap = (T 'doc.creditForCap'); Value = $was; W = $unit; Font = 'bodyBold'; Pen = 1 }
            $tiles[2].Cap = T 'doc.creditTotalCap'
        }
        $tileH = 70
        foreach ($t in $tiles) { $tileH = [Math]::Max($tileH, 30 + (& $measure $t.Value $t.Font ($t.W - 32)) + 12) }
        $x = $P.Left
        foreach ($t in $tiles) {
            & $rect $x $y $t.W $tileH $t.Pen
            & $text $t.Cap 'cap' ($x + 16) ($y + 12) ($t.W - 32)
            & $text $t.Value $t.Font ($x + 16) ($y + 28) ($t.W - 32)
            $x += $t.W + $gap
        }
        $y += $tileH + 26
    }

    # The client, next to what it was about.
    & $text $(if ($Note -or $Receipt) { T 'doc.forCap' } else { T 'doc.toCap' }) 'cap' $P.Left $y $half
    & $text (T 'doc.subjectCap') 'cap' $colX $y $half
    $y += 18
    $clientY = $y
    foreach ($l in @($Invoice.client_name, $Invoice.client_address, $Invoice.client_postcode_city, $Invoice.client_email) | Where-Object { $_ }) {
        & $text $l 'body' $P.Left $clientY $half
        $clientY += (& $measure $l 'body' $half)
    }
    $subject = if ($credit) { T 'doc.creditSubject' $Invoice.credit_for } elseif ($Record) { "$($Invoice.subject)".Trim() } else { Get-HcInvoiceSubject }
    $subjectY = $y
    if ($subject) {
        & $text $subject 'body' $colX $y $half
        $subjectY += (& $measure $subject 'body' $half)
    }
    if ($Invoice.replaces -and -not $credit) {
        $replaces = T 'doc.replaces' $Invoice.replaces
        & $text $replaces 'small' $colX $subjectY $half 'muted'
        $subjectY += (& $measure $replaces 'small' $half)
    }
    $y = [Math]::Max($clientY, $subjectY) + 26

    # What was done, with ticks; not fixed in italics with a dash.
    $work = @(if ($credit) { } elseif ($Record) { Get-HcInvoiceWork $Invoice.work -Record } else { Get-HcInvoiceWork })
    if ($work.Count) {
        & $room 30
        & $text (T 'doc.doneTitle') 'head' $P.Left $y $full
        $y += (& $measure 'x' 'head' $full) + 2
        foreach ($w in $work) {
            $font = if ($w.Done) { 'item' } else { 'itemItalic' }
            $h = & $measure $w.Text $font ($full - 24)
            & $room $h
            [void]$page.Add([pscustomobject]@{ Kind = $(if ($w.Done) { 'check' } else { 'dash' }); X = [single]($P.Left + 4); Y = [single]($y + 5); Color = 'ink' })
            & $text $w.Text $font ($P.Left + 24) $y ($full - 24) $(if ($w.Done) { 'ink' } else { 'muted' })
            $y += $h + 1
        }
        $y += 12
    }
    # Advice from the Pc-overzicht, under the work: what would help next.
    # On an invoice or receipt the AI's summaries (Op het briefje) join the advice.
    $advice = @(if (-not $Record -and -not $credit) { $script:HcAdvice; if (-not $Note) { $script:HcAiNotes } })
    if ($advice.Count) {
        & $room 30
        & $text (T 'doc.adviceTitle') 'head' $P.Left $y $full
        $y += (& $measure 'x' 'head' $full) + 2
        foreach ($a in $advice) {
            $h = & $measure $a 'item' ($full - 24)
            & $room $h
            & $text ([string][char]0x2192) 'item' ($P.Left + 2) $y 20
            & $text $a 'item' ($P.Left + 24) $y ($full - 24)
            $y += $h + 1
        }
        $y += 12
    }
    if ($Note) {
        if ($work.Count -eq 0) {
            & $text (T 'note.nothingChanged') 'item' $P.Left $y $full 'muted'
            $y += (& $measure 'x' 'item' $full) + 14
        }
        # What was found, so the client can read back what was going on.
        $found = @($script:HcVisit | Where-Object { $_.FindingId })
        # The AI's summaries (Op het briefje) read as findings too.
        $foundTexts = @(foreach ($v in $found) { $all = @('finding.' + $v.FindingId) + @($v.FindingArgs); T @all }) + @($script:HcAiNotes)
        if ($foundTexts.Count) {
            & $room 40
            & $text (T 'note.found') 'head' $P.Left $y $full
            $y += (& $measure 'x' 'head' $full) + 2
            foreach ($t in $foundTexts) {
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

    # The money: not on the note.
    if (-not $Note) {
        $y += 4
        & $room 60
        & $text (T 'doc.descriptionCap') 'cap' $P.Left $y $descW
        & $text (T 'doc.amountCap') 'cap' ($P.Right - $amountW) $y $amountW 'ink' 'right'
        $y += 18
        & $line $y 'ink' 2
        $y += 7
        foreach ($l in @($Invoice.lines)) {
            $h = & $measure $l.description 'body' $descW
            & $room ($h + 10)
            & $text $l.description 'body' $P.Left $y $descW
            & $text (Format-HcMoney ([decimal]$l.amount)) 'body' ($P.Right - $amountW) $y $amountW 'ink' 'right'
            $y += $h + 6
            & $line $y
            $y += 7
        }
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
        & $line $y 'ink' 2.5
        $y += 8
        & $text (T 'doc.totalWord') 'total' $P.Left $y $descW
        & $text (Format-HcMoney ([decimal]$Invoice.total)) 'total' ($P.Right - $amountW - 40) $y ($amountW + 40) 'ink' 'right'
        $y += (& $measure 'x' 'total' $descW) + 8

        # Paid: the stamp under the total. Not yet paid: how to pay.
        if ($paid) {
            & $room 96
            $sub = $issued.ToString('dd-MM-yyyy') + '  ' + [char]0x00B7 + '  ' + (T ('inv.pay.' + $Invoice.payment))
            [void]$page.Add([pscustomobject]@{ Kind = 'stamp'; X = [single]($P.Right - 112); Y = [single]($y + 42); W = [single]200; H = [single]62; Text = (T 'doc.stamp'); Sub = $sub; Color = 'ink' })
            $y += 96
        } else {
            $y += 10
        }
        $paidOn = Format-HcLongDate $issued
        $pay = if ($credit) { if ($Invoice.settle_with) { T 'doc.creditSettle' $Invoice.settle_with } else { T 'doc.creditRefund' } }
               elseif ($paid) { $null } else { switch ($Invoice.payment) {
            'tikkie'   { T 'doc.paidTikkie' $paidOn }
            'transfer' {
                $due = Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture))
                T 'doc.transfer' (Format-HcMoney ([decimal]$Invoice.total)) $due $s.iban $Invoice.number
            }
        } }
        foreach ($para in @($pay, $(if ($Invoice.btw_mode -eq 'kor' -and -not $Receipt) { T 'doc.kor' })) | Where-Object { $_ }) {
            $font = if ($para -eq $pay) { 'body' } else { 'small' }
            $h = & $measure $para $font $full
            & $room $h
            & $text $para $font $P.Left $y $full $(if ($font -eq 'small') { 'muted' } else { 'ink' })
            $y += $h + 10
        }

        # How to reach Shamil again, with the number to mention.
        $ask = Get-HcAskText $s $number
        if ($ask) {
            $innerW = $full - 36
            $titleH = & $measure (T 'doc.askTitle') 'bodyBold' $innerW
            $askH = & $measure $ask 'small' $innerW
            $boxH = 14 + $titleH + $askH + 14
            $y += 6
            & $room ($boxH + 4)
            & $rect $P.Left $y $full $boxH 1
            & $text (T 'doc.askTitle') 'bodyBold' ($P.Left + 18) ($y + 14) $innerW
            & $text $ask 'small' ($P.Left + 18) ($y + 14 + $titleH) $innerW 'muted'
            $y += $boxH + 10
        }
    }

    # The foot of every page.
    $n = $pages.Count
    for ($i = 0; $i -lt $n; $i++) {
        $page = $pages[$i]
        & $line ($P.Bottom + 22)
        & $text (T 'doc.thanks') 'small' $P.Left ($P.Bottom + 30) $half 'muted'
        & $text (T 'doc.pageOf' ($i + 1) $n) 'small' $colX ($P.Bottom + 30) $half 'muted' 'right'
    }
    $g.Dispose(); $bmp.Dispose()
    # One array of steps per page (a plain list, so @() gives the pages).
    foreach ($pg in $pages) { , $pg.ToArray() }
}

# A big-print sheet for the client (25 Oct, AI-hulp /stappen): a title,
# the explanation and numbered steps in large letters, black on white, with
# the same header and foot as the other documents. One page; what does not
# fit is left off.
function Get-HcBigSheetLayout {
    param([string]$Title, [string]$Text, [string[]]$Steps)
    $style = Get-HcInvoiceStyle
    $F = $style.Fonts
    $P = $script:HcPage
    $bmp = New-Object Drawing.Bitmap(1, 1)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.PageUnit = [Drawing.GraphicsUnit]::Pixel
    $measure = { param($t, $font, $width) $g.MeasureString([string]$t, $F[$font], [int]$width).Height }
    $page = New-Object System.Collections.ArrayList
    $full = $P.Right - $P.Left
    $add = { param($t, $font, $x, $yy, $w, $color = 'ink')
        [void]$page.Add([pscustomobject]@{ Kind = 'text'; Text = [string]$t; Font = $font; X = [single]$x; Y = [single]$yy; W = [single]$w; Color = $color; Align = 'left' }) }
    $y = [single]$P.Top
    [void]$page.Add([pscustomobject]@{ Kind = 'line'; Y = [single]($y + 3); X = [single]$P.Left; X2 = [single]$P.Right; Color = 'ink'; Width = [single]7 })
    [void]$page.Add([pscustomobject]@{ Kind = 'logo'; X = [single]($P.Right - 52); Y = [single]($y + 26); Size = [single]52; Color = 'ink' })
    $y += 26
    & $add $Title 'bigTitle' ($P.Left - 4) $y ($full - 70)
    $y += (& $measure $Title 'bigTitle' ($full - 70)) + 30
    foreach ($para in @($Text | Where-Object { "$_".Trim() })) {
        $h = & $measure $para 'big' $full
        if ($y + $h -gt $P.Bottom) { break }
        & $add $para 'big' $P.Left $y $full
        $y += $h + 24
    }
    $n = 0
    foreach ($s in @($Steps | Where-Object { "$_".Trim() })) {
        $n++
        $h = & $measure $s 'big' ($full - 56)
        if ($y + $h -gt $P.Bottom) { break }
        & $add "$n." 'big' $P.Left $y 56
        & $add $s 'big' ($P.Left + 56) $y ($full - 56)
        $y += $h + 14
    }
    [void]$page.Add([pscustomobject]@{ Kind = 'line'; Y = [single]($P.Bottom + 22); X = [single]$P.Left; X2 = [single]$P.Right; Color = 'rule'; Width = [single]1 })
    & $add (T 'doc.thanks') 'small' $P.Left ($P.Bottom + 30) $full 'muted'
    $g.Dispose(); $bmp.Dispose()
    , $page.ToArray()
}

# A rectangle with round corners, as a path GDI+ can stroke or fill.
function New-HcRoundPath {
    param([single]$X, [single]$Y, [single]$W, [single]$H, [single]$R)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $path
}

# The Housecall logo (brand\housecall-icon-blue.svg) in one colour, drawn
# from its own 64 x 64 shapes so it stays sharp on paper.
function Write-HcLogo {
    param([Drawing.Graphics]$Graphics, [single]$X, [single]$Y, [single]$Size, [Drawing.Color]$Color)
    $state = $Graphics.Save()
    try {
        $Graphics.TranslateTransform($X, $Y)
        $Graphics.ScaleTransform($Size / 64, $Size / 64)
        $pen = { param($width)
            $p = New-Object Drawing.Pen($Color, [single]$width)
            $p.StartCap = 'Round'; $p.EndCap = 'Round'; $p.LineJoin = 'Round'
            $p }
        $thick = & $pen 6
        $Graphics.DrawLines($thick, [Drawing.PointF[]]@((New-Object Drawing.PointF(6, 33)), (New-Object Drawing.PointF(28, 14)), (New-Object Drawing.PointF(50, 33))))
        $walls = New-Object Drawing.Drawing2D.GraphicsPath
        $walls.AddLine(13, 31, 13, 54)
        $walls.AddArc(13, 51, 6, 6, 180, -90)
        $walls.AddLine(16, 57, 40, 57)
        $walls.AddArc(37, 51, 6, 6, 90, -90)
        $walls.AddLine(43, 54, 43, 31)
        $Graphics.DrawPath($thick, $walls)
        $door = New-HcRoundPath 23 41 10 16 2
        $brush = New-Object Drawing.SolidBrush($Color)
        $Graphics.FillPath($brush, $door)
        # The two waves: the SVG's arcs, with their centres worked out.
        $thin = & $pen 4.5
        $Graphics.DrawArc($thin, [single]36.2, [single]15.8, [single]16, [single]16, [single]-77, [single]64)
        $Graphics.DrawArc($thin, [single]28.67, [single]7.33, [single]32, [single]32, [single]-81.6, [single]73.2)
        $thick.Dispose(); $thin.Dispose(); $walls.Dispose(); $door.Dispose(); $brush.Dispose()
    } finally {
        $Graphics.Restore($state)
    }
}

function Write-HcInvoicePage {
    param([Drawing.Graphics]$Graphics, [object[]]$Steps)
    $style = Get-HcInvoiceStyle
    $Graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    # Plain AntiAlias, not GridFit: snapping Verdana's letters to whole
    # pixels gave uneven gaps in small wrapped text (25 Oct).
    $Graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
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
            'rect' {
                $pen = New-Object Drawing.Pen($color, $s.Width)
                $path = New-HcRoundPath $s.X $s.Y $s.W $s.H 8
                $Graphics.DrawPath($pen, $path)
                $path.Dispose(); $pen.Dispose()
            }
            'logo' { Write-HcLogo $Graphics $s.X $s.Y $s.Size $color }
            # VOLDAAN: a double outline turned a little, like a rubber stamp.
            'stamp' {
                $state = $Graphics.Save()
                try {
                    $Graphics.TranslateTransform($s.X, $s.Y)
                    $Graphics.RotateTransform(-5)
                    $w = $s.W; $h = $s.H
                    $inner = New-HcRoundPath (-$w / 2) (-$h / 2) $w $h 10
                    $outer = New-HcRoundPath (-$w / 2 - 5) (-$h / 2 - 5) ($w + 10) ($h + 10) 13
                    $pen = New-Object Drawing.Pen($color, [single]3)
                    $thin = New-Object Drawing.Pen($color, [single]1.2)
                    $Graphics.DrawPath($pen, $inner)
                    $Graphics.DrawPath($thin, $outer)
                    $format = New-Object Drawing.StringFormat
                    $format.Alignment = [Drawing.StringAlignment]::Center
                    $brush = New-Object Drawing.SolidBrush($color)
                    $Graphics.DrawString($s.Text, $style.Fonts['stamp'], $brush, (New-Object Drawing.RectangleF((-$w / 2), (-$h / 2 + 3), $w, [single]36)), $format)
                    $Graphics.DrawString($s.Sub, $style.Fonts['stampSub'], $brush, (New-Object Drawing.RectangleF((-$w / 2), (-$h / 2 + 37), $w, [single]20)), $format)
                    $inner.Dispose(); $outer.Dispose(); $pen.Dispose(); $thin.Dispose(); $brush.Dispose(); $format.Dispose()
                } finally {
                    $Graphics.Restore($state)
                }
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