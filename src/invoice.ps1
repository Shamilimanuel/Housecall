<#
    The invoice: at the end of a visit (Q), a short form, then a proper
    invoice instead of the plain client note.

    Shamil's business details, hourly rate, call-out fee and BTW setting
    live in his Supabase (tools\setup-invoice.ps1 fills them in), never in
    this public script. The relay gives out the consecutive invoice number,
    works out the totals and BTW, and keeps the invoice (7 years: fiscale
    bewaarplicht) apart from the visit history.

    Without an unlock, without settings, or with 0 in the form, the client
    still gets the plain note, so a visit never ends without a document.
#>

$script:HcStartedAt = Get-Date

# 30,00 as "EUR 30,00" with the euro sign, in Dutch notation. The sign is
# built from its char code, since source files stay plain ASCII.
function Format-HcMoney {
    param([decimal]$Amount)
    $nl = [Globalization.CultureInfo]::GetCultureInfo('nl-NL')
    [string][char]0x20AC + ' ' + $Amount.ToString('N2', $nl)
}

# "19,95", "19.95", "EUR 19,95" -> 19.95; $null when it is not an amount.
function ConvertTo-HcAmount {
    param([string]$Text)
    $t = ("$Text" -replace [string][char]0x20AC, '' -replace '(?i)eur', '').Trim()
    if ($t -notmatch '^\d{1,6}([.,]\d{1,2})?$') { return $null }
    [decimal]::Parse(($t -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
}

# "Draadloze muis 19,95" -> description and amount; $null when there is no amount at the end.
function ConvertTo-HcExtraLine {
    param([string]$Text)
    $t = ("$Text" -replace [string][char]0x20AC, ' ').Trim()
    if ($t -notmatch '^(.+?)\s+(?:EUR\s*)?(\d{1,6}(?:[.,]\d{1,2})?)$') { return $null }
    $amount = ConvertTo-HcAmount $Matches[2]
    if ($null -eq $amount) { return $null }
    [pscustomobject]@{ Description = $Matches[1].Trim(); Amount = $amount }
}

# Minutes since Housecall started, rounded up to a quarter of an hour.
function Get-HcSuggestedMinutes {
    param([datetime]$Now = (Get-Date))
    $minutes = [Math]::Ceiling(($Now - $script:HcStartedAt).TotalMinutes / 15) * 15
    [int][Math]::Max(15, $minutes)
}

<#
    The labour lines for the time worked. With a starting price (settings
    start_fee and start_minutes) the first minutes cost that fixed amount
    and only the time after them goes by the hour; without one, all of it
    goes by the hour. 0 minutes gives no labour: a job at a fixed price is
    then an extra line.
#>
function Get-HcLabourLines {
    param([int]$Minutes, $Settings)
    if ($Minutes -le 0) { return }
    $rate = [decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 })
    $start = [decimal]$(if ($Settings.start_fee) { $Settings.start_fee } else { 0 })
    $included = [int]$(if ($Settings.start_minutes) { $Settings.start_minutes } else { 0 })
    if ($start -gt 0 -and $included -gt 0) {
        [pscustomobject]@{ Description = (T 'inv.startLine' $included); Amount = $start }
        $extra = $Minutes - $included
        if ($extra -gt 0 -and $rate -gt 0) {
            [pscustomobject]@{ Description = (T 'inv.extraTime' $extra (Format-HcMoney $rate)); Amount = [Math]::Round($rate * $extra / 60, 2) }
        }
        return
    }
    if ($rate -gt 0) {
        [pscustomobject]@{ Description = (T 'inv.labour' $Minutes (Format-HcMoney $rate)); Amount = [Math]::Round($rate * $Minutes / 60, 2) }
    }
}

# The price next to the minutes in the window.
function Get-HcRateText {
    param($Settings)
    $rate = Format-HcMoney ([decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 }))
    # The relay sends amounts as text ("0.00"), so compare them as numbers.
    $start = [decimal]$(if ($Settings.start_fee) { $Settings.start_fee } else { 0 })
    if ($start -gt 0 -and [int]$Settings.start_minutes -gt 0) {
        return (T 'inv.win.rateStart' (Format-HcMoney ([decimal]$Settings.start_fee)) $Settings.start_minutes $rate)
    }
    T 'inv.win.rate' $rate
}

function Get-HcSettings {
    $r = Invoke-HcRelay @{ action = 'settings_get'; token = $script:HcToken }
    if (-not $r.Ok) { return [pscustomobject]@{ Ok = $false; Settings = $null; Error = $r.Error } }
    [pscustomobject]@{ Ok = $true; Settings = $r.Data.settings; Error = $null }
}

# Asks a question with a suggestion; Enter takes the suggestion, 0 cancels.
function Read-HcField {
    param([string]$Prompt, [string]$Default = '')
    $answer = "$(Read-HcLine $Prompt)".Trim()
    if ($answer -eq '0') { return $null }
    if (-not $answer) { return $Default }
    $answer
}

<#
    The form. Returns the client, the lines and the payment, or $null when
    Shamil cancels (0) -- then the plain note is shown instead.
#>
function Read-HcInvoiceForm {
    param($Settings)
    Write-Host ''
    Write-Host ('  ' + (T 'inv.title')) -ForegroundColor Yellow
    Write-Dim (T 'inv.intro')
    Write-Host ''

    $suggestName = if ($script:HcKnownLabel) { $script:HcKnownLabel } else { '' }
    $name = Read-HcField (T 'inv.clientName' $suggestName) $suggestName
    if ($null -eq $name) { return $null }
    while (-not $name) {
        $name = Read-HcField (T 'inv.clientName' '') ''
        if ($null -eq $name) { return $null }
    }
    $address = Read-HcField (T 'inv.address'); if ($null -eq $address) { return $null }
    $postcode = Read-HcField (T 'inv.postcode'); if ($null -eq $postcode) { return $null }
    $email = Read-HcField (T 'inv.email'); if ($null -eq $email) { return $null }

    $lines = New-Object System.Collections.ArrayList
    $suggested = Get-HcSuggestedMinutes
    $minutes = $null
    while ($null -eq $minutes) {
        $typed = Read-HcField (T 'inv.minutes' $suggested) "$suggested"
        if ($null -eq $typed) { return $null }
        if ($typed -match '^\d{1,4}$') { $minutes = [int]$typed } else { Write-Warn2 (T 'inv.minutesBad') }
    }
    foreach ($l in @(Get-HcLabourLines $minutes $Settings)) { [void]$lines.Add($l) }

    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($fee -gt 0) {
        $yes = Read-HcField (T 'inv.callout' (Format-HcMoney $fee)) 'j'
        if ($null -eq $yes) { return $null }
        if (Test-HcYes $yes) { [void]$lines.Add([pscustomobject]@{ Description = (T 'inv.calloutLine'); Amount = $fee }) }
    }

    while ($true) {
        $typed = "$(Read-HcLine (T 'inv.extra'))".Trim()
        if (-not $typed -or $typed -eq 'Q') { break }
        $extra = ConvertTo-HcExtraLine $typed
        if ($extra) { [void]$lines.Add($extra) } else { Write-Warn2 (T 'inv.extraBad') }
    }
    if ($lines.Count -eq 0) {
        Write-Warn2 (T 'inv.noLines')
        return $null
    }

    # Bank transfer only once an IBAN is set: the invoice has to say where to.
    $methods = [ordered]@{ '1' = 'pin'; '2' = 'cash' }
    if ($Settings.iban) { $methods['3'] = 'transfer' }
    # 'tikkie' stands for any payment request: Tikkie, or the bank's own (ASN betaalverzoek).
    $methods['4'] = 'tikkie'
    $choices = @($methods.Keys | ForEach-Object { "[$_] " + (T ('inv.pay.' + $methods[$_])) }) -join '  '
    $payment = $null
    while (-not $payment) {
        $typed = "$(Read-HcLine (T 'inv.payment' $choices))".Trim()
        if ($typed -in @('0', 'Q')) { return $null }
        if ($methods.Contains($typed)) { $payment = $methods[$typed] }
    }

    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    if (-not (Test-HcYes (Read-HcLine (T 'inv.confirm' (Format-HcMoney $total))))) { return $null }

    [pscustomobject]@{
        Client  = @{ name = $name; address = $address; postcode_city = $postcode; email = $email }
        Lines   = @($lines)
        Payment = $payment
    }
}

<#
    The invoice form as a window (Shamil's request: click, fix, then make
    it). Its fields go through ConvertTo-HcInvoiceForm, which checks them
    and builds the same result as the console form, so it can be tested
    without a window. Without a desktop, the console form is used.
#>
function ConvertTo-HcInvoiceForm {
    param([hashtable]$Values, $Settings)
    $name = "$($Values.Name)".Trim()
    if (-not $name) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.needName') } }

    $lines = New-Object System.Collections.ArrayList
    foreach ($l in @(Get-HcLabourLines ([int]$Values.Minutes) $Settings)) { [void]$lines.Add($l) }
    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($Values.Callout -and $fee -gt 0) {
        [void]$lines.Add([pscustomobject]@{ Description = (T 'inv.calloutLine'); Amount = $fee })
    }
    $row = 0
    foreach ($extra in @($Values.Extras)) {
        $row++
        $description = "$($extra.Description)".Trim()
        $amountText = "$($extra.Amount)".Trim()
        if (-not $description -and -not $amountText) { continue }
        $amount = ConvertTo-HcAmount $amountText
        if (-not $description -or $null -eq $amount) {
            return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.badLine' $row) }
        }
        [void]$lines.Add([pscustomobject]@{ Description = $description; Amount = $amount })
    }
    if ($lines.Count -eq 0) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.nothing') } }
    if ($Values.Payment -notin @('pin', 'cash', 'transfer', 'tikkie')) { return [pscustomobject]@{ Form = $null; Error = (T 'inv.win.needPayment') } }

    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    [pscustomobject]@{
        Error = $null
        Total = $total
        Form  = [pscustomobject]@{
            Client  = @{ name = $name; address = "$($Values.Address)".Trim(); postcode_city = "$($Values.Postcode)".Trim(); email = "$($Values.Email)".Trim() }
            Lines   = @($lines)
            Payment = $Values.Payment
        }
    }
}

# The window. Returns the form result, or $null for "no invoice".
function Show-HcInvoiceWindow {
    param($Settings)
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    [Windows.Forms.Application]::EnableVisualStyles()
    $font = New-Object Drawing.Font('Segoe UI', 11)
    $bold = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)

    $form = New-Object Windows.Forms.Form
    $form.Text = 'Housecall - ' + (T 'inv.title')
    $form.StartPosition = 'CenterScreen'
    # Tall enough for everything, but never taller than the screen: the
    # fields scroll on a small laptop.
    $height = [Math]::Min(960, [Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 20)
    $form.Size = New-Object Drawing.Size(640, $height)
    $form.MinimumSize = New-Object Drawing.Size(560, 480)
    $form.Font = $font
    # Every colour set explicitly: Windows themes with custom system colours
    # (Shamil's PC has one) otherwise give white text on white, or dark fields.
    $form.BackColor = [Drawing.Color]::White
    $form.ForeColor = [Drawing.Color]::Black
    $form.TopMost = $true
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })
    $paint = { param($c) $c.BackColor = [Drawing.Color]::White; $c.ForeColor = [Drawing.Color]::Black }

    $layout = New-Object Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.Padding = New-Object Windows.Forms.Padding(20, 16, 20, 8)
    $layout.ColumnCount = 2
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute, 190)))
    [void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
    $layout.AutoScroll = $true

    $heading = { param($text)
        $l = New-Object Windows.Forms.Label
        $l.Text = $text; $l.Font = $bold; $l.AutoSize = $true; $l.Margin = New-Object Windows.Forms.Padding(0, 12, 0, 4)
        $layout.Controls.Add($l); $layout.SetColumnSpan($l, 2) }
    $field = { param($label, $value)
        $l = New-Object Windows.Forms.Label
        $l.Text = $label; $l.AutoSize = $true; $l.Anchor = 'Left'; $l.Margin = New-Object Windows.Forms.Padding(0, 6, 8, 0)
        $t = New-Object Windows.Forms.TextBox
        $t.Text = $value; $t.Dock = 'Fill'; $t.BorderStyle = 'FixedSingle'; & $paint $t
        $layout.Controls.Add($l); $layout.Controls.Add($t); $t }

    & $heading (T 'inv.win.client')
    $name = & $field (T 'inv.win.name') "$script:HcKnownLabel"
    $address = & $field (T 'inv.address') ''
    $postcode = & $field (T 'inv.postcode') ''
    $email = & $field (T 'inv.email') ''

    & $heading (T 'inv.win.work')
    $l = New-Object Windows.Forms.Label
    $l.Text = T 'inv.win.minutes'; $l.AutoSize = $true; $l.Anchor = 'Left'
    $minutesRow = New-Object Windows.Forms.FlowLayoutPanel
    $minutesRow.AutoSize = $true; $minutesRow.Dock = 'Fill'; $minutesRow.WrapContents = $false
    $minutes = New-Object Windows.Forms.NumericUpDown
    $minutes.Minimum = 0; $minutes.Maximum = 1440; $minutes.Increment = 15; $minutes.Width = 90; $minutes.BorderStyle = 'FixedSingle'; & $paint $minutes
    $minutes.Value = Get-HcSuggestedMinutes
    $rateLabel = New-Object Windows.Forms.Label
    $rateLabel.AutoSize = $true; $rateLabel.Margin = New-Object Windows.Forms.Padding(8, 6, 0, 0)
    $rateLabel.MaximumSize = New-Object Drawing.Size(290, 0)
    $rateLabel.Text = Get-HcRateText $Settings
    $minutesRow.Controls.Add($minutes); $minutesRow.Controls.Add($rateLabel)
    $layout.Controls.Add($l); $layout.Controls.Add($minutesRow)

    $callout = New-Object Windows.Forms.CheckBox
    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($fee -gt 0) {
        $callout.Text = T 'inv.win.callout' (Format-HcMoney $fee); $callout.AutoSize = $true; $callout.Checked = $true
        $layout.Controls.Add((New-Object Windows.Forms.Label)); $layout.Controls.Add($callout)
    }

    # What was done and what not: pick an option or type one, then Fixed or
    # Not fixed. It goes on the note or invoice, next to Housecall's own fixes.
    & $heading (T 'inv.win.done')
    $workRow = New-Object Windows.Forms.FlowLayoutPanel
    $workRow.AutoSize = $true; $workRow.Dock = 'Fill'; $workRow.WrapContents = $false
    $workPick = New-Object Windows.Forms.ComboBox
    $workPick.DropDownStyle = 'DropDown'; $workPick.Width = 300; $workPick.FlatStyle = 'Flat'; & $paint $workPick
    $workPick.MaxDropDownItems = 12
    foreach ($p in @(Get-HcWorkPresets)) { [void]$workPick.Items.Add($p) }
    $workPick.AutoCompleteMode = 'SuggestAppend'; $workPick.AutoCompleteSource = 'ListItems'
    $addFixed = New-Object Windows.Forms.Button
    $addFixed.Text = T 'inv.win.fixed'; $addFixed.AutoSize = $true; & $paint $addFixed
    $addOpen = New-Object Windows.Forms.Button
    $addOpen.Text = T 'inv.win.notFixed'; $addOpen.AutoSize = $true; & $paint $addOpen
    $workRow.Controls.Add($workPick); $workRow.Controls.Add($addFixed); $workRow.Controls.Add($addOpen)
    $layout.Controls.Add($workRow); $layout.SetColumnSpan($workRow, 2)
    $workList = New-Object Windows.Forms.ListBox
    $workList.Height = 96; $workList.Dock = 'Fill'; $workList.BorderStyle = 'FixedSingle'; & $paint $workList
    $layout.Controls.Add($workList); $layout.SetColumnSpan($workList, 2)
    $removeWork = New-Object Windows.Forms.Button
    $removeWork.Text = T 'inv.win.remove'; $removeWork.AutoSize = $true; $removeWork.Anchor = 'Left'; & $paint $removeWork
    $layout.Controls.Add($removeWork); $layout.SetColumnSpan($removeWork, 2)

    $showWork = {
        $workList.Items.Clear()
        foreach ($w in $script:HcWork) {
            $key = if ($w.Done) { 'inv.win.itemFixed' } else { 'inv.win.itemOpen' }
            [void]$workList.Items.Add((T $key $w.Text))
        }
    }
    $addWork = { param([bool]$done)
        if (Add-HcWorkItem $workPick.Text $done) { $workPick.Text = ''; & $showWork }
        $workPick.Focus() | Out-Null
    }
    $addFixed.Add_Click({ & $addWork $true })
    $addOpen.Add_Click({ & $addWork $false })
    # Enter in the box counts as Fixed, the most common answer.
    $workPick.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $_.SuppressKeyPress = $true; & $addWork $true } })
    $removeWork.Add_Click({
        $i = $workList.SelectedIndex
        if ($i -ge 0) { $script:HcWork.RemoveAt($i); & $showWork }
    })
    & $showWork

    & $heading (T 'inv.win.extras')
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Height = 130; $grid.Dock = 'Fill'
    $grid.AllowUserToAddRows = $true; $grid.RowHeadersVisible = $false
    $grid.AutoSizeColumnsMode = 'Fill'; $grid.BackgroundColor = [Drawing.Color]::White
    $grid.GridColor = [Drawing.Color]::Gainsboro
    $grid.EnableHeadersVisualStyles = $false
    $grid.DefaultCellStyle.BackColor = [Drawing.Color]::White
    $grid.DefaultCellStyle.ForeColor = [Drawing.Color]::Black
    $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(204, 228, 247)
    $grid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::Black
    $grid.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::Black
    [void]$grid.Columns.Add('description', (T 'inv.win.description'))
    [void]$grid.Columns.Add('amount', (T 'inv.win.amount'))
    $grid.Columns[0].FillWeight = 75; $grid.Columns[1].FillWeight = 25
    $layout.Controls.Add($grid); $layout.SetColumnSpan($grid, 2)

    & $heading (T 'inv.win.payment')
    $pay = New-Object Windows.Forms.FlowLayoutPanel
    $pay.AutoSize = $true; $pay.Dock = 'Fill'
    $radios = [ordered]@{}
    $methods = @('pin', 'cash')
    if ($Settings.iban) { $methods += 'transfer' }
    $methods += 'tikkie'
    foreach ($m in $methods) {
        $r = New-Object Windows.Forms.RadioButton
        $r.Text = T ('inv.pay.' + $m); $r.AutoSize = $true; $r.Tag = $m
        $pay.Controls.Add($r); $radios[$m] = $r
    }
    $layout.Controls.Add($pay); $layout.SetColumnSpan($pay, 2)

    $total = New-Object Windows.Forms.Label
    $total.Font = $bold; $total.AutoSize = $true; $total.Margin = New-Object Windows.Forms.Padding(0, 14, 0, 0)
    $layout.Controls.Add($total); $layout.SetColumnSpan($total, 2)
    $problem = New-Object Windows.Forms.Label
    $problem.ForeColor = [Drawing.Color]::Firebrick; $problem.AutoSize = $true; $problem.MaximumSize = New-Object Drawing.Size(540, 0)
    $layout.Controls.Add($problem); $layout.SetColumnSpan($problem, 2)

    # Reads every field into the values ConvertTo-HcInvoiceForm checks.
    $read = {
        $extras = @(foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }
            [pscustomobject]@{ Description = $row.Cells[0].Value; Amount = $row.Cells[1].Value }
        })
        $chosen = @($radios.Values | Where-Object { $_.Checked } | ForEach-Object { $_.Tag }) | Select-Object -First 1
        ConvertTo-HcInvoiceForm @{
            Name = $name.Text; Address = $address.Text; Postcode = $postcode.Text; Email = $email.Text
            Minutes = [int]$minutes.Value; Callout = $callout.Checked; Extras = $extras; Payment = $chosen
        } $Settings
    }
    $script:HcInvoiceResult = $null

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'; $buttons.FlowDirection = 'RightToLeft'; $buttons.Height = 64
    $buttons.Padding = New-Object Windows.Forms.Padding(16, 10, 16, 10)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)
    $make = New-Object Windows.Forms.Button
    $make.Text = T 'inv.win.make'; $make.AutoSize = $true; $make.Height = 40; $make.Font = $bold; & $paint $make
    $none = New-Object Windows.Forms.Button
    $none.Text = T 'inv.win.none'; $none.AutoSize = $true; $none.Height = 40; & $paint $none
    $make.Add_Click({
        $grid.EndEdit() | Out-Null
        $check = & $read
        if ($check.Error) { $problem.Text = $check.Error; return }
        $script:HcInvoiceResult = $check.Form
        $this.FindForm().Close()
    })
    $none.Add_Click({ $script:HcInvoiceResult = $null; $this.FindForm().Close() })
    $buttons.Controls.Add($make); $buttons.Controls.Add($none)

    # Live total: labour + call-out + valid extra lines, whatever the payment.
    $update = {
        $sum = [decimal]0
        foreach ($l in @(Get-HcLabourLines ([int]$minutes.Value) $Settings)) { $sum += [decimal]$l.Amount }
        if ($callout.Checked) { $sum += $fee }
        foreach ($row in $grid.Rows) {
            if ($row.IsNewRow) { continue }
            $a = ConvertTo-HcAmount "$($row.Cells[1].Value)"
            if ($null -ne $a) { $sum += $a }
        }
        $total.Text = T 'inv.win.total' (Format-HcMoney $sum)
        $problem.Text = ''
    }
    $minutes.Add_ValueChanged($update)
    $callout.Add_CheckedChanged($update)
    $grid.Add_CellValueChanged($update)
    $grid.Add_RowsRemoved($update)
    & $update

    $form.Controls.Add($layout)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $name
    [void]$form.ShowDialog()
    $form.Dispose()
    $script:HcInvoiceResult
}

<#
    The whole invoice step at Q. Returns the invoice from the relay (with its
    number, totals and the seller's details), or $null for the plain note.
#>
function Invoke-HcInvoice {
    param([pscustomobject]$Environment)
    if ($script:HcVisit.Count -eq 0 -or $script:DryRun -or -not $Environment.Online) { return $null }
    Write-Host ''
    if (-not (Unlock-HcRelay 'inv.askCode')) {
        # Enter at the code: no invoice, and no second question to save the visit.
        $script:HcQuitSkipped = $true
        return $null
    }
    $s = Get-HcSettings
    if (-not $s.Ok) { Write-Warn2 (T 'inv.failed' (Get-HcRelayMessage $s.Error)); return $null }
    if (-not $s.Settings -or -not $s.Settings.business_name) { Write-Warn2 (T 'inv.noSettings'); return $null }

    # The window when there is a desktop; the console form in tests and without one.
    $form = $null
    $useWindow = ($null -eq $script:HcInputQueue) -and -not $script:NoConsole
    if ($useWindow) {
        try { $form = Show-HcInvoiceWindow $s.Settings } catch { $useWindow = $false }
    }
    if (-not $useWindow) { $form = Read-HcInvoiceForm $s.Settings }
    if (-not $form) { Write-Dim (T 'inv.skipped'); return $null }

    $r = Invoke-HcRelay @{
        action   = 'invoice_create'
        token    = $script:HcToken
        pc       = (Get-HcPcId)
        lang     = $script:Lang
        client   = $form.Client
        lines    = @($form.Lines | ForEach-Object { @{ description = $_.Description; amount = [double]$_.Amount } })
        payment  = $form.Payment
        problems = @($script:HcVisit | Where-Object { $_.FindingId } | ForEach-Object { @{ code = $_.Code; finding = $_.FindingId } })
        changes  = @(Get-HcVisitChanges)
    }
    if (-not $r.Ok) { Write-Warn2 (T 'inv.failed' (Get-HcRelayMessage $r.Error)); return $null }
    Write-Ok (T 'inv.made' $r.Data.invoice.number)
    $r.Data.invoice
}

# ----------------------------------------------------------------- document --

function Format-HcLongDate {
    param([datetime]$Date)
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))
}

# A money row: description on the left, amount on the right, in a fixed-width
# font so the amounts line up on screen and on paper.
function New-HcMoneyRow {
    param([string]$Description, [decimal]$Amount, [string]$Style = 'row')
    $width = 44
    $d = if ($Description.Length -gt $width) { $Description.Substring(0, $width - 3) + '...' } else { $Description }
    [pscustomobject]@{ Style = $Style; Text = $d.PadRight($width) + (Format-HcMoney $Amount).PadLeft(14) }
}

<#
    The invoice as blocks for the same window and printout as the note:
    seller, number and date, client, what was wrong and done, the money,
    and how to pay.
#>
function Get-HcInvoiceBlocks {
    param($Invoice)
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    $s = $Invoice.seller
    $issued = [datetime]::Parse([string]$Invoice.issued_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()

    & $block 'title' (T 'doc.invoice' $Invoice.number)
    & $block 'small' (T 'doc.date' (Format-HcLongDate $issued))

    $seller = @($s.business_name, $s.owner_name, $s.address, $s.postcode_city) | Where-Object { $_ }
    & $block 'text' ($seller -join "`n")
    $ids = @()
    if ($s.kvk) { $ids += T 'doc.kvk' $s.kvk }
    if ($s.btw_number) { $ids += T 'doc.btwNumber' $s.btw_number }
    if ($s.iban) { $ids += T 'doc.iban' $s.iban }
    $contact = @($s.email, $s.phone) | Where-Object { $_ }
    if ($ids.Count) { & $block 'small' ($ids -join '   ') }
    if ($contact.Count) { & $block 'small' ($contact -join '   ') }

    & $block 'heading' (T 'doc.to')
    $client = @($Invoice.client_name, $Invoice.client_address, $Invoice.client_postcode_city, $Invoice.client_email) | Where-Object { $_ }
    & $block 'text' ($client -join "`n")

    foreach ($b in @(Get-HcVisitBlocks)) { $b }

    & $block 'heading' (T 'doc.costs')
    foreach ($l in @($Invoice.lines)) { New-HcMoneyRow $l.description ([decimal]$l.amount) }
    & $block 'row' ('-' * 58)
    if ($Invoice.btw_mode -eq '21') {
        New-HcMoneyRow (T 'doc.subtotal') ([decimal]$Invoice.subtotal)
        New-HcMoneyRow (T 'doc.btw') ([decimal]$Invoice.btw_amount)
    }
    New-HcMoneyRow (T 'doc.total') ([decimal]$Invoice.total) 'rowBold'

    $paidOn = Format-HcLongDate $issued
    switch ($Invoice.payment) {
        'pin'      { & $block 'payment' (T 'doc.paidPin' $paidOn) }
        'cash'     { & $block 'payment' (T 'doc.paidCash' $paidOn) }
        'tikkie'   { & $block 'payment' (T 'doc.paidTikkie' $paidOn) }
        'transfer' {
            $due = Format-HcLongDate ([datetime]::Parse([string]$Invoice.due_date, [Globalization.CultureInfo]::InvariantCulture))
            & $block 'payment' (T 'doc.transfer' (Format-HcMoney ([decimal]$Invoice.total)) $due $s.iban $Invoice.number)
        }
    }
    # No BTW line until BTW is set: Shamil is not a registered business yet.
    if ($Invoice.btw_mode -eq 'kor') { & $block 'small' (T 'doc.kor') }
    & $block 'small' (T 'doc.thanks')
}

function Show-HcInvoice {
    param($Invoice)
    Show-HcDocument @(Get-HcInvoiceBlocks $Invoice) (T 'doc.windowTitle' $Invoice.number)
}
