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
    $rate = [decimal]$(if ($Settings.hourly_rate) { $Settings.hourly_rate } else { 0 })
    $suggested = Get-HcSuggestedMinutes
    $minutes = $null
    while ($null -eq $minutes) {
        $typed = Read-HcField (T 'inv.minutes' $suggested) "$suggested"
        if ($null -eq $typed) { return $null }
        if ($typed -match '^\d{1,4}$') { $minutes = [int]$typed } else { Write-Warn2 (T 'inv.minutesBad') }
    }
    if ($minutes -gt 0 -and $rate -gt 0) {
        $amount = [Math]::Round($rate * $minutes / 60, 2)
        [void]$lines.Add([pscustomobject]@{ Description = (T 'inv.labour' $minutes (Format-HcMoney $rate)); Amount = $amount })
    }

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

    $form = Read-HcInvoiceForm $s.Settings
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
        changes  = @($script:HcChanges | ForEach-Object { $_.Label })
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
