<#
    Corrigeren (25 Oct): fixing a wrong invoice from the history. An invoice
    is never changed or deleted (it has to stay as it was, for the tax
    rules). Instead the relay makes a credit invoice that cancels it (its own
    number, the same lines with a minus) and a new invoice with the right
    details, both in one go. "Alleen crediteren" makes only the credit
    invoice, for an invoice that should not exist at all.

    It uses the Bezoek tab's own layout: the form on the left (FinishPanel),
    the buttons under it (FinishBar), and the two A4 pages on the right.
    The documents are in the old invoice's language.
#>

# ------------------------------------------------------------ pure parts --

function New-HcCorrState {
    param([string]$Number, $VisitId)
    @{
        Stage = 'loading'; Number = $Number; VisitId = $VisitId; Orig = $null; Settings = $null; Notice = $null
        Title = 'none'; Name = ''; Address = ''; Postcode = ''; Email = ''
        Minutes = $null; OrigMinutes = $null; Labour = @(); Lines = (New-Object System.Collections.ArrayList)
        Payment = 'pin'; CreditOnly = $false; Credit = $null; Invoice = $null; Pages = $null
        Kept = $null; MailAsk = $null; MailBusy = $false; MailResult = $null
    }
}

# Runs a script block with Housecall's language set to the invoice's, so
# its lines, pages and mail come out in the language the client got.
function Invoke-HcInLang {
    param([string]$Lang, [scriptblock]$Script)
    $old = $script:Lang
    if ($Lang -in @('nl', 'en')) { $script:Lang = $Lang }
    try { & $Script } finally { $script:Lang = $old }
}

# A string-table text as a pattern: "Extra tijd, {0} minuten ({1} x {2})"
# matches the line and gives back the minutes.
function Get-HcLinePattern {
    param([string]$Key, [string]$Lang)
    $format = $script:Strings[$Lang][$Key]
    if (-not $format) { return $null }
    $p = [regex]::Escape($format) -replace '\\\{0}', '(\d+)' -replace '\\\{[12]}', '.+?'
    '^' + $p + '$'
}

# The time lines of an invoice (starting price, extra time, or hourly
# labour), the minutes they add up to, and every other line. Minutes is
# $null when the invoice has no time line Housecall recognises (the oldest
# invoices): then all its lines are ordinary lines.
function Split-HcLabourLines {
    param([object[]]$Lines, [string]$Lang)
    $langs = @(@($Lang) + @('nl', 'en') | Where-Object { $_ -in @('nl', 'en') } | Select-Object -Unique)
    $minutes = 0
    $found = $false
    $labour = @()
    $rest = @()
    foreach ($l in @($Lines | Where-Object { $_ })) {
        $d = "$($l.description)".Trim()
        $hit = $null
        foreach ($lg in $langs) {
            foreach ($key in @('inv.startLine', 'inv.extraTime', 'inv.labour')) {
                $p = Get-HcLinePattern $key $lg
                if ($p -and $d -match $p) { $hit = [int]$Matches[1]; break }
            }
            if ($null -ne $hit) { break }
        }
        if ($null -ne $hit) {
            $minutes += $hit
            $found = $true
            $labour += [pscustomobject]@{ Description = $d; Amount = [decimal]$l.amount }
        } else {
            $rest += [pscustomobject]@{ Description = $d; Amount = [decimal]$l.amount }
        }
    }
    [pscustomobject]@{ Minutes = $(if ($found) { $minutes } else { $null }); Labour = $labour; Rest = $rest }
}

# "15,00" for a text box: the amount as the technician would type it.
function Format-HcAmountText {
    param([decimal]$Amount)
    $Amount.ToString('0.00', [Globalization.CultureInfo]::GetCultureInfo('nl-NL'))
}

# The lines of the corrected invoice: the time lines (the old ones while
# the minutes are unchanged, else made again at today's prices), then the
# other lines from the form. Lines without a description or a valid
# amount are left out here; Test-HcCorrForm names them.
function Get-HcCorrLines {
    param([hashtable]$Corr)
    $o = $Corr.Orig
    if ($null -ne $Corr.Minutes) {
        if ($Corr.Minutes -eq $Corr.OrigMinutes) { foreach ($l in @($Corr.Labour)) { $l } }
        else { Invoke-HcInLang $o.lang { foreach ($l in @(Get-HcLabourLines ([int]$Corr.Minutes) $Corr.Settings)) { $l } } }
    }
    foreach ($l in @($Corr.Lines)) {
        $d = "$($l.Description)".Trim()
        $a = ConvertTo-HcAmount $l.Amount
        if ($d -and $null -ne $a) { [pscustomobject]@{ Description = $d; Amount = $a } }
    }
}

# What the old invoice was about, for the new one: what it kept, or for an
# older invoice the problems that were checked and the changes made.
function Get-HcCorrRecord {
    param($Orig)
    $subject = "$($Orig.subject)".Trim()
    if (-not $subject) {
        $subject = Invoke-HcInLang $Orig.lang { (@($Orig.problems | Where-Object { $_.code }) | ForEach-Object { T "problem.$($_.code)" }) -join ', ' }
    }
    $work = @($Orig.work | Where-Object { $_ } | ForEach-Object { @{ text = "$($_.text)"; done = [bool]$_.done } })
    if (-not $work.Count) { $work = @($Orig.changes | Where-Object { "$_".Trim() } | ForEach-Object { @{ text = "$_"; done = $true } }) }
    [pscustomobject]@{ Subject = $subject; Work = $work }
}

# The new invoice as it will look before the relay numbers it.
function New-HcCorrDraft {
    param([hashtable]$Corr, [datetime]$Now = (Get-Date))
    $o = $Corr.Orig
    $s = $Corr.Settings
    $lines = @(Get-HcCorrLines $Corr)
    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    $subtotal = $total
    $btw = [decimal]0
    if ("$($s.btw_mode)" -eq '21') { $subtotal = [Math]::Round($total / [decimal]1.21, 2); $btw = $total - $subtotal }
    $days = if ($s.payment_days) { [int]$s.payment_days } else { 14 }
    $record = Get-HcCorrRecord $o
    [pscustomobject]@{
        number = (Invoke-HcInLang $o.lang { T 'win.fin.draft' }); issued_at = $Now.ToUniversalTime().ToString('o'); seller = $s
        client_name = (Format-HcClientName $Corr.Title $Corr.Name $o.lang); client_address = "$($Corr.Address)".Trim()
        client_postcode_city = "$($Corr.Postcode)".Trim(); client_email = "$($Corr.Email)".Trim()
        lines = @($lines | ForEach-Object { [pscustomobject]@{ description = $_.Description; amount = [decimal]$_.Amount } })
        btw_mode = "$($s.btw_mode)"; subtotal = $subtotal; btw_amount = $btw; total = $total
        payment = $Corr.Payment; due_date = $Now.AddDays($days).ToString('yyyy-MM-dd')
        subject = $record.Subject; work = $record.Work; replaces = [string]$o.number
    }
}

# The credit invoice as it will look: the old one with a minus.
function New-HcCreditDraft {
    param($Orig, $Settings, [string]$SettleWith, [datetime]$Now = (Get-Date))
    $minus = { param($n) -[Math]::Round([decimal]$n, 2) }
    [pscustomobject]@{
        number = (Invoke-HcInLang $Orig.lang { T 'win.fin.draft' }); issued_at = $Now.ToUniversalTime().ToString('o'); seller = $Settings
        client_name = $Orig.client_name; client_address = $Orig.client_address
        client_postcode_city = $Orig.client_postcode_city; client_email = $Orig.client_email
        lines = @($Orig.lines | ForEach-Object { [pscustomobject]@{ description = $_.description; amount = (& $minus $_.amount) } })
        btw_mode = $Orig.btw_mode; subtotal = (& $minus $Orig.subtotal); btw_amount = (& $minus $Orig.btw_amount); total = (& $minus $Orig.total)
        payment = $Orig.payment; due_date = $null
        credit_for = [string]$Orig.number; credit_for_date = $Orig.issued_at; settle_with = $SettleWith
    }
}

# Whether the form differs from the old invoice: only then is there
# something to correct (or it is only being credited).
function Test-HcCorrChanged {
    param([hashtable]$Corr)
    if ($Corr.CreditOnly) { return $true }
    $o = $Corr.Orig
    $same = { param($a, $b) "$a".Trim() -ceq "$b".Trim() }
    if (-not (& $same (Format-HcClientName $Corr.Title $Corr.Name $o.lang) $o.client_name)) { return $true }
    foreach ($pair in @(@($Corr.Address, $o.client_address), @($Corr.Postcode, $o.client_postcode_city), @($Corr.Email, $o.client_email))) {
        if (-not (& $same $pair[0] $pair[1])) { return $true }
    }
    if ($Corr.Payment -ne $o.payment) { return $true }
    $key = { param($ls) (@($ls) | ForEach-Object { "$($_.Description)".Trim() + '|' + ([decimal]$_.Amount).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture) }) -join "`n" }
    $old = @($o.lines | ForEach-Object { [pscustomobject]@{ Description = $_.description; Amount = $_.amount } })
    (& $key @(Get-HcCorrLines $Corr)) -ne (& $key $old)
}

# $null when the form can be sent, else what is missing.
function Test-HcCorrForm {
    param([hashtable]$Corr)
    if ($Corr.CreditOnly) { return $null }
    if (-not "$($Corr.Name)".Trim()) { return (T 'inv.win.needName') }
    $row = 0
    foreach ($l in @($Corr.Lines)) {
        $row++
        $d = "$($l.Description)".Trim(); $a = "$($l.Amount)".Trim()
        if (-not $d -and -not $a) { continue }
        if (-not $d -or $null -eq (ConvertTo-HcAmount $a)) { return (T 'inv.win.badLine' $row) }
    }
    if (-not @(Get-HcCorrLines $Corr).Count) { return (T 'inv.win.nothing') }
    $null
}

# What invoice_correct gets.
function New-HcCorrBody {
    param([hashtable]$Corr)
    $o = $Corr.Orig
    $record = Get-HcCorrRecord $o
    $body = @{ action = 'invoice_correct'; token = $script:HcToken; number = [string]$o.number; credit_only = [bool]$Corr.CreditOnly }
    if (-not $Corr.CreditOnly) {
        $body += @{
            pc = $(if ($o.pc) { [string]$o.pc } else { $null }); lang = [string]$o.lang
            client = @{ name = (Format-HcClientName $Corr.Title $Corr.Name $o.lang); address = "$($Corr.Address)".Trim(); postcode_city = "$($Corr.Postcode)".Trim(); email = "$($Corr.Email)".Trim() }
            lines = @(Get-HcCorrLines $Corr | ForEach-Object { @{ description = $_.Description; amount = [double]$_.Amount } })
            payment = $Corr.Payment
            problems = @($o.problems | Where-Object { $_ })
            changes = @($o.changes | Where-Object { $_ })
            subject = $(if ($record.Subject) { $record.Subject } else { $null })
            work = @($record.Work)
        }
    }
    $body
}

# The pages: the credit invoice, then the new one (made, or the concept).
function Get-HcCorrPages {
    param([hashtable]$Corr)
    $o = $Corr.Orig
    Invoke-HcInLang $o.lang {
        if ($Corr.Credit) {
            $credit = $Corr.Credit
            @(Get-HcInvoiceLayout $credit)
            if ($Corr.Invoice) { @(Get-HcInvoiceLayout $Corr.Invoice -Record) }
        } else {
            $draft = New-HcCorrDraft $Corr
            @(Get-HcInvoiceLayout (New-HcCreditDraft $o $Corr.Settings $(if ($Corr.CreditOnly) { $null } else { $draft.number })))
            if (-not $Corr.CreditOnly) { @(Get-HcInvoiceLayout $draft -Record) }
        }
    }
}

# ------------------------------------------------------------- opening --

function Start-HcCorrect {
    param([string]$Number, $VisitId)
    $w = $script:HcWin
    $w.Corr = New-HcCorrState $Number $VisitId
    $w.VisitView = 'correct'
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'invoice_get'; token = $script:HcToken; number = $Number }; Done = 'Complete-HcCorrInvoice' }
    Update-HcTabs
    Update-HcVisit
}

function Complete-HcCorrInvoice {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $code = if ($r) { $r.Error } else { 'unreachable' }
        $c.Stage = 'error'; $c.Notice = Get-HcRelayMessage $code
        Update-HcVisit
        return
    }
    if ($r.Data.credited_by) { $c.Stage = 'error'; $c.Notice = T 'corr.already'; Update-HcVisit; return }
    if ($r.Data.invoice.credit_for) { $c.Stage = 'error'; $c.Notice = T 'corr.isCredit'; Update-HcVisit; return }
    $c.Orig = $r.Data.invoice
    $s = $script:HcWin.Fin.Settings
    if ($s) { Initialize-HcCorrForm $s; return }
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'settings_get'; token = $script:HcToken }; Done = 'Complete-HcCorrSettings' }
}

function Complete-HcCorrSettings {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok -or -not $r.Data.settings) {
        $c.Stage = 'error'; $c.Notice = Get-HcRelayMessage $(if ($r -and $r.Error) { $r.Error } else { 'unreachable' })
        Update-HcVisit
        return
    }
    Initialize-HcCorrForm $r.Data.settings
}

# The form, filled in from the old invoice.
function Initialize-HcCorrForm {
    param($Settings)
    $c = $script:HcWin.Corr
    $o = $c.Orig
    $c.Settings = $Settings
    $name = Split-HcClientName $o.client_name
    $c.Title = $name.Title; $c.Name = $name.Name
    $c.Address = "$($o.client_address)"; $c.Postcode = "$($o.client_postcode_city)"; $c.Email = "$($o.client_email)"
    $split = Split-HcLabourLines @($o.lines) $o.lang
    $c.Minutes = $split.Minutes; $c.OrigMinutes = $split.Minutes; $c.Labour = @($split.Labour)
    $c.Lines.Clear()
    foreach ($l in @($split.Rest)) { [void]$c.Lines.Add(@{ Description = $l.Description; Amount = (Format-HcAmountText $l.Amount) }) }
    $c.Payment = if ((Get-HcPayMethods $Settings) -contains $o.payment) { [string]$o.payment } else { 'pin' }
    $c.Stage = 'form'
    Update-HcVisit
}

# ------------------------------------------------------------- painting --

function Update-HcCorrPanel {
    $w = $script:HcWin
    $c = $w.Corr
    $panel = $w.Window.FindName('FinishPanel')
    $panel.Children.Clear()
    $add = { param($element) [void]$panel.Children.Add($element) }
    & $add (New-HcVisitToggle)
    & $add (New-HcText (T 'win.corr.title' $c.Number) 22 'Text' -Bold -Margin @(0, 4, 0, 6))
    if ($c.Notice) { & $add (New-HcText $c.Notice 14.5 'Warn' -Bold) }
    switch ($c.Stage) {
        'loading' {
            & $add (New-HcText (T 'win.corr.loading' $c.Number) 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
            return
        }
        'error' { return }
    }
    & $add (New-HcBox '' @((New-HcText (T 'win.corr.intro') 14 'Text' -Margin @(0, 0, 0, 2))))

    $form = New-Object Windows.Controls.StackPanel
    $form.IsEnabled = $c.Stage -eq 'form'
    $put = { param($element) [void]$form.Children.Add($element) }

    # The client.
    & $put (New-HcSection (T 'win.corr.client'))
    [void]$form.Children.Add((New-HcText (T 'win.fin.title') 13 'Soft' -Bold -Margin @(0, 0, 0, 3)))
    $titles = New-Object Windows.Controls.WrapPanel
    foreach ($t in @(Get-HcTitleChoices $c.Orig.lang)) {
        [void]$titles.Children.Add((New-HcChip (Invoke-HcInLang $c.Orig.lang { T "win.title.$t" }) @{ Do = 'corrTitle'; Title = $t } -On:($c.Title -eq $t)))
    }
    & $put $titles
    $grid = New-Object Windows.Controls.WrapPanel
    [void]$grid.Children.Add((New-HcCorrField (T 'win.fin.fullName') 'Name' $c.Name 250 'name'))
    [void]$grid.Children.Add((New-HcCorrField (T 'win.fin.email') 'Email' $c.Email 250 ''))
    [void]$grid.Children.Add((New-HcCorrField (T 'inv.address') 'Address' $c.Address 250 'address'))
    [void]$grid.Children.Add((New-HcCorrField (T 'inv.postcode') 'Postcode' $c.Postcode 250 'place'))
    & $put $grid

    # The time: a quarter of an hour at a time, which makes the time lines again.
    & $put (New-HcSection (T 'win.corr.time') $(if ($null -ne $c.OrigMinutes) { T 'win.corr.was' $c.OrigMinutes } else { '' }))
    if ($null -ne $c.Minutes) {
        $row = New-Object Windows.Controls.WrapPanel
        [void]$row.Children.Add((New-HcChip ([string][char]0x2212 + ' 15 min') @{ Do = 'corrMinutes'; Step = -15 }))
        [void]$row.Children.Add((New-HcText "$($c.Minutes) min" 18 $(if ($c.Minutes -ne $c.OrigMinutes) { 'Hi' } else { 'Text' }) -Bold -Margin @(6, 2, 12, 0)))
        [void]$row.Children.Add((New-HcChip '+ 15 min' @{ Do = 'corrMinutes'; Step = 15 }))
        & $put $row
        foreach ($l in @(Get-HcCorrLines @{ Orig = $c.Orig; Minutes = $c.Minutes; OrigMinutes = $c.OrigMinutes; Labour = $c.Labour; Settings = $c.Settings; Lines = @() })) {
            & $put (New-HcText ($l.Description + '   ' + (Format-HcMoney $l.Amount)) 14 'Soft' -Margin @(0, 0, 0, 2))
        }
    } else {
        & $put (New-HcText (T 'win.corr.timeUnknown') 13.5 'Soft')
    }

    # The other lines, each with its amount.
    & $put (New-HcSection (T 'win.corr.lines'))
    for ($i = 0; $i -lt $c.Lines.Count; $i++) {
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = New-HcThickness @(0, 0, 0, 6)
        $x = New-HcChip ([string][char]0x00D7) @{ Do = 'corrLineRemove'; Index = $i }
        $x.ToolTip = T 'win.fin.remove'
        $x.Margin = New-HcThickness @(6, 0, 0, 0)
        [Windows.Controls.DockPanel]::SetDock($x, 'Right')
        [void]$row.Children.Add($x)
        $amount = New-HcTextBox $c.Lines[$i].Amount
        $amount.Width = 100
        $amount.Margin = New-HcThickness @(6, 0, 0, 0)
        $amount.Tag = @{ CorrLine = $i; Part = 'Amount' }
        $amount.Add_TextChanged({ Invoke-HcCorrTyped $this })
        [Windows.Controls.DockPanel]::SetDock($amount, 'Right')
        [void]$row.Children.Add($amount)
        $desc = New-HcTextBox $c.Lines[$i].Description
        $desc.Tag = @{ CorrLine = $i; Part = 'Description'; Case = 'sentence' }
        $desc.Add_TextChanged({ Invoke-HcCorrTyped $this })
        $desc.Add_LostFocus({ Set-HcBoxCase $this })
        [void]$row.Children.Add($desc)
        & $put $row
    }
    $addLine = New-HcChip (T 'win.corr.addLine') @{ Do = 'corrLineAdd' }
    $addLine.HorizontalAlignment = 'Left'
    & $put $addLine

    # How the new invoice is paid.
    & $put (New-HcSection (T 'win.corr.payment'))
    $pay = New-Object Windows.Controls.WrapPanel
    foreach ($m in @(Get-HcPayMethods $c.Settings)) {
        $label = T ('inv.pay.' + $m)
        $label = $label.Substring(0, 1).ToUpperInvariant() + $label.Substring(1)
        $chip = New-HcChip $label @{ Do = 'corrPay'; Method = $m } -On:($c.Payment -eq $m)
        $chip.IsEnabled = -not $c.CreditOnly
        [void]$pay.Children.Add($chip)
    }
    & $put $pay

    $check = New-Object Windows.Controls.CheckBox
    $check.Content = T 'win.corr.creditOnly'
    $check.IsChecked = [bool]$c.CreditOnly
    $check.Tag = @{ Do = 'corrCreditOnly' }
    $check.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $check.Margin = New-HcThickness @(0, 12, 0, 2)
    $check.Add_Click({ Invoke-HcClick $this })
    & $put $check
    & $put (New-HcText (T 'win.corr.creditOnlyNote') 13 'Soft' -Margin @(22, 0, 0, 8))
    & $add $form
}

# A labelled text box that writes into the correction as it is typed in;
# -Case puts capitals in when the box is left (see ConvertTo-HcCapitals).
function New-HcCorrField {
    param([string]$Label, [string]$Field, [string]$Value, [double]$Width, [string]$Case)
    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-HcThickness @(0, 0, 12, 8)
    $stack.HorizontalAlignment = 'Left'
    $stack.Width = $Width
    [void]$stack.Children.Add((New-HcText $Label 13 'Soft' -Bold -Margin @(0, 0, 0, 3)))
    $box = New-HcTextBox $Value
    $box.Tag = @{ CorrField = $Field; Case = $Case }
    $box.Add_TextChanged({ Invoke-HcCorrTyped $this })
    if ($Case) { $box.Add_LostFocus({ Set-HcBoxCase $this }) }
    [void]$stack.Children.Add($box)
    $stack
}

function Update-HcCorrBar {
    $w = $script:HcWin
    $c = $w.Corr
    $bar = $w.Window.FindName('FinishBar')
    $bar.Children.Clear()
    $row = New-Object Windows.Controls.WrapPanel
    $add = { param($element) $element.Margin = New-HcThickness @(0, 0, 8, 6); [void]$row.Children.Add($element) }
    $hint = $null
    if ($c.MailAsk) { [void]$bar.Children.Add((New-HcQuestion (T 'win.mail.ask.correction' $c.MailAsk) 'corrMailYes' 'corrMailNo')) }
    if ($c.MailBusy) { [void]$bar.Children.Add((New-HcText (T 'win.mail.busy') 14.5 'Soft' -Bold)) }
    elseif ($c.MailResult) { [void]$bar.Children.Add((New-HcText $c.MailResult.Text 14.5 $(if ($c.MailResult.Ok) { 'Ok' } else { 'Warn' }) -Bold)) }
    switch ($c.Stage) {
        'form' {
            $make = New-HcButton $(if ($c.CreditOnly) { T 'win.corr.makeCredit' } else { T 'win.corr.make' }) @{ Do = 'corrMake' } 'HcPrimary'
            $make.IsEnabled = Test-HcCorrChanged $c
            & $add $make
            & $add (New-HcButton (T 'win.corr.cancel') @{ Do = 'corrBack' })
            if (-not $make.IsEnabled) { $hint = T 'win.corr.unchanged' }
        }
        'working' { $hint = T 'win.corr.working' }
        'done' {
            $made = if ($c.Invoice) { T 'win.corr.made' $c.Credit.number $c.Invoice.number } else { T 'win.corr.madeCredit' $c.Credit.number }
            if ($c.Kept -eq $true) { $made += ' ' + (T 'win.corr.kept') }
            [void]$bar.Children.Add((New-HcText ([string][char]0x2713 + ' ' + $made) 15 'Ok' -Bold))
            if ($c.Kept -is [string]) { [void]$bar.Children.Add((New-HcText (T 'win.corr.notKept' $c.Kept) 14 'Warn' -Bold)) }
            & $add (New-HcButton (T 'note.print') @{ Do = 'corrPrint' } 'HcPrimary')
            & $add (New-HcButton (T 'win.fin.pdf') @{ Do = 'corrPdf' })
            & $add (New-HcButton (T 'win.fin.mail') @{ Do = 'corrMail' })
            & $add (New-HcButton (T 'win.corr.back') @{ Do = 'corrBack' })
        }
        'error' { & $add (New-HcButton (T 'win.corr.back') @{ Do = 'corrBack' }) }
    }
    if ($row.Children.Count) { [void]$bar.Children.Add($row) }
    if ($hint) { [void]$bar.Children.Add((New-HcText $hint 13 'Soft' -Margin @(0, 0, 0, 0))) }
    $w.Window.FindName('FinishBarBorder').Visibility = if ($bar.Children.Count) { 'Visible' } else { 'Collapsed' }
}

function Update-HcCorrPreview {
    $w = $script:HcWin
    $c = $w.Corr
    $top = $w.Window.FindName('PreviewTop')
    $top.Children.Clear()
    $panel = $w.Window.FindName('PreviewPanel')
    $panel.Children.Clear()
    if (-not $c.Orig -or -not $c.Settings) { return }
    $state = if ($c.Credit -and $c.Invoice) { T 'win.corr.stateMade' $c.Credit.number $c.Invoice.number }
             elseif ($c.Credit) { T 'win.corr.stateCredit' $c.Credit.number }
             else { T 'win.corr.stateDraft' }
    [void]$top.Children.Add((New-HcText $state.ToUpperInvariant() 12 $(if ($c.Credit) { 'Ok' } else { 'Soft' }) -Bold -Margin @(0, 8, 0, 0)))
    try {
        $pages = @(Get-HcCorrPages $c)
    } catch {
        [void]$panel.Children.Add((New-HcText (T 'win.error' $_.Exception.Message) 14 'Warn'))
        return
    }
    $c.Pages = $pages
    foreach ($steps in $pages) { [void]$panel.Children.Add((New-HcPaper $steps)) }
}

# One drawn page as a sheet of paper with a soft shadow.
function New-HcPaper {
    param([object[]]$Steps)
    $bmp = New-HcInvoiceBitmap $Steps
    $stream = New-Object IO.MemoryStream
    try {
        $bmp.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
        $stream.Position = 0
        $source = New-Object Windows.Media.Imaging.BitmapImage
        $source.BeginInit()
        $source.CacheOption = 'OnLoad'
        $source.StreamSource = $stream
        $source.EndInit()
        $source.Freeze()
    } finally {
        $stream.Dispose()
        $bmp.Dispose()
    }
    $image = New-Object Windows.Controls.Image
    $image.Source = $source
    $image.Stretch = 'Uniform'
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($image, 'HighQuality')
    $paper = New-Object Windows.Controls.Border
    $paper.Background = [Windows.Media.Brushes]::White
    $paper.Margin = New-HcThickness @(0, 0, 0, 14)
    $paper.Effect = New-Object Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 14; ShadowDepth = 2; Opacity = 0.25 }
    $paper.Child = $image
    $paper
}

# ---------------------------------------------------------------- doing --

# Typing: into the state, the button and (a moment later) the pages, but
# the form is not rebuilt, so the cursor stays where it is.
function Invoke-HcCorrTyped {
    param($Sender)
    $c = $script:HcWin.Corr
    if (-not $c) { return }
    $tag = $Sender.Tag
    if ($tag.CorrField) { $c[$tag.CorrField] = "$($Sender.Text)" }
    elseif ($null -ne $tag.CorrLine -and $tag.CorrLine -lt $c.Lines.Count) { $c.Lines[$tag.CorrLine][$tag.Part] = "$($Sender.Text)" }
    $c.Notice = $null
    Update-HcCorrBar
    Request-HcPreview
}

function Invoke-HcCorrClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    $c = $w.Corr
    switch ($Tag.Do) {
        'corrOpen'       { Start-HcCorrect $Tag.Number $Tag.VisitId; return $true }
        'corrBack'       { $w.Corr = $null; Open-HcVisitTab 'history'; return $true }
        'corrTitle'      { $c.Title = $Tag.Title }
        'corrMinutes'    { $c.Minutes = [Math]::Max(15, [Math]::Min(600, [int]$c.Minutes + [int]$Tag.Step)) }
        'corrLineAdd'    { [void]$c.Lines.Add(@{ Description = ''; Amount = '' }) }
        'corrLineRemove' { $c.Lines.RemoveAt($Tag.Index) }
        'corrPay'        { $c.Payment = $Tag.Method }
        'corrCreditOnly' { $c.CreditOnly = -not $c.CreditOnly }
        'corrMake'       { Start-HcCorrMake; return $true }
        'corrPrint'      { $script:HcInvoicePages = $c.Pages; Invoke-HcInvoicePrint; return $true }
        'corrPdf'        { Save-HcCorrPdf; return $true }
        'corrMail'       { Request-HcCorrMail; return $true }
        'corrMailYes'    { Send-HcCorrMail; return $true }
        'corrMailNo'     { $c.MailAsk = $null; Update-HcCorrBar; return $true }
        default          { return $false }
    }
    $c.Notice = $null
    Update-HcVisit
    $true
}

function Start-HcCorrMake {
    $w = $script:HcWin
    $c = $w.Corr
    $problem = Test-HcCorrForm $c
    if ($problem) { $c.Notice = $problem; Update-HcVisit; return }
    if (-not (Test-HcUnlocked)) { $c.Notice = T 'relay.expired'; Update-HcVisit; return }
    $c.Stage = 'working'
    Add-HcJob @{ Kind = 'relay'; Body = (New-HcCorrBody $c); Done = 'Complete-HcCorrMade' }
    Update-HcVisit
}

function Complete-HcCorrMade {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $c = $w.Corr
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok -or -not $r.Data.credit) {
        $c.Stage = 'form'
        $c.Notice = T 'inv.failed' (Get-HcRelayMessage $(if ($r -and $r.Error) { $r.Error } else { 'unreachable' }))
        Update-HcVisit
        return
    }
    $credit = $r.Data.credit
    $credit | Add-Member -NotePropertyName credit_for_date -NotePropertyValue $c.Orig.issued_at -Force
    $credit | Add-Member -NotePropertyName settle_with -NotePropertyValue $(if ($r.Data.invoice) { [string]$r.Data.invoice.number } else { $null }) -Force
    $c.Credit = $credit
    $c.Invoice = $r.Data.invoice
    $c.Stage = 'done'
    # The lists in the history are out of date now.
    $w.Hist.Stage = 'new'; $w.Hist.AllStage = 'new'
    Update-HcVisit
    Start-HcCorrKeep
}

# Keeps both PDFs in the history, one after the other, like a visit's own
# document: printed to PDF by the worker, then sent to the relay.
function Start-HcCorrKeep {
    $c = $script:HcWin.Corr
    $o = $c.Orig
    $c.KeepQueue = New-Object System.Collections.ArrayList
    [void]$c.KeepQueue.Add(@{ Kind = 'credit'; Invoice = $c.Credit; Pages = @(Invoke-HcInLang $o.lang { Get-HcInvoiceLayout $c.Credit }) })
    if ($c.Invoice) { [void]$c.KeepQueue.Add(@{ Kind = 'invoice'; Invoice = $c.Invoice; Pages = @(Invoke-HcInLang $o.lang { Get-HcInvoiceLayout $c.Invoice -Record }) }) }
    Start-HcCorrKeepNext
}

function Start-HcCorrKeepNext {
    $c = $script:HcWin.Corr
    if (-not $c -or -not $c.KeepQueue.Count) {
        if ($c -and $c.Kept -isnot [string]) { $c.Kept = $true; Update-HcCorrBar }
        return
    }
    $next = $c.KeepQueue[0]
    $c.KeepQueue.RemoveAt(0)
    Add-HcJob @{ Kind = 'pdf'; Body = @{ Pages = $next.Pages }; Keep = $next; Done = 'Complete-HcCorrKeepPdf' }
}

function Complete-HcCorrKeepPdf {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    if (-not $c) { return }
    $r = Get-HcPdfResult $Output
    if ($ErrorText -or -not $r -or -not $r.PdfBytes) {
        $c.Kept = if ($ErrorText) { $ErrorText } elseif ($r) { "$($r.PdfProblem)" } else { '' }
        Update-HcCorrBar
        return
    }
    $inv = $Job.Keep.Invoice
    $client = "$($inv.client_name)"
    if ($client.Length -gt 100) { $client = $client.Substring(0, 100) }
    $body = @{
        action = 'doc_save'; token = $script:HcToken; id = [guid]::NewGuid().ToString()
        pc = $(if ($c.Orig.pc) { [string]$c.Orig.pc } else { $null })
        visit_id = $(if ($c.VisitId) { [long]$c.VisitId } else { $null })
        kind = $Job.Keep.Kind; client_name = $(if ($client) { $client } else { $null }); invoice_number = [string]$inv.number; receipt_number = $null
        total = [double]$inv.total; payment = $(if ($inv.payment) { [string]$inv.payment } else { $null }); lang = [string]$c.Orig.lang
        pdf_base64 = [Convert]::ToBase64String($r.PdfBytes)
    }
    Add-HcJob @{ Kind = 'relay'; Body = $body; Done = 'Complete-HcCorrKept' }
}

function Complete-HcCorrKept {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    if (-not $c) { return }
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $c.Kept = if ($ErrorText) { $ErrorText } else { Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' }) }
        Update-HcCorrBar
        return
    }
    Start-HcCorrKeepNext
}

# "Creditfactuur 2026-0006 en factuur 2026-0007.pdf"
function Get-HcCorrPdfName {
    $c = $script:HcWin.Corr
    if ($c.Invoice) { T 'win.corr.pdfName' $c.Credit.number $c.Invoice.number } else { T 'win.corr.pdfCredit' $c.Credit.number }
}

function Save-HcCorrPdf {
    $w = $script:HcWin
    $c = $w.Corr
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'PDF (*.pdf)|*.pdf'
    $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    $dialog.FileName = Get-HcCorrPdfName
    if (-not $dialog.ShowDialog($w.Window)) { return }
    $script:HcInvoicePages = $c.Pages
    $problem = Save-HcPagesPdf $dialog.FileName
    $c.Notice = if ($problem) { T 'win.fin.pdfFailed' $problem } else { T 'win.fin.pdfSaved' $dialog.FileName }
    Update-HcVisit
}

# Both documents in one PDF, to the address on the new invoice (else the old one).
function Request-HcCorrMail {
    $c = $script:HcWin.Corr
    $c.MailResult = $null
    $to = if ($c.Invoice -and $c.Invoice.client_email) { [string]$c.Invoice.client_email } else { [string]$c.Orig.client_email }
    if ($to -notmatch '^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[a-zA-Z]{2,}$') { $c.MailResult = @{ Ok = $false; Text = (T 'win.mail.needAddress') }; Update-HcCorrBar; return }
    if (-not (Test-HcUnlocked)) { $c.MailResult = @{ Ok = $false; Text = (T 'relay.expired') }; Update-HcCorrBar; return }
    $c.MailAsk = $to
    Update-HcCorrBar
}

function Send-HcCorrMail {
    $c = $script:HcWin.Corr
    $to = $c.MailAsk
    $c.MailAsk = $null
    $c.MailBusy = $true
    Add-HcJob @{ Kind = 'pdf'; Body = @{ Pages = @($c.Pages) }; To = $to; Done = 'Complete-HcCorrMailPdf' }
    Update-HcCorrBar
}

function Complete-HcCorrMailPdf {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    if (-not $c) { return }
    $r = Get-HcPdfResult $Output
    if ($ErrorText -or -not $r -or -not $r.PdfBytes) {
        $c.MailBusy = $false
        $c.MailResult = @{ Ok = $false; Text = (T 'win.fin.pdfFailed' "$(if ($ErrorText) { $ErrorText } elseif ($r) { $r.PdfProblem })") }
        Update-HcCorrBar
        return
    }
    $inv = if ($c.Invoice) { $c.Invoice } else { $c.Orig }
    $name = Split-HcClientName $inv.client_name
    $mail = Invoke-HcInLang $c.Orig.lang {
        if ($c.Invoice) {
            New-HcMailText 'invoice' $name.Title $name.Name (Get-Date) '' $c.Settings -Subject (T 'mail.subject.correction' $c.Invoice.number) -Body (T 'mail.body.correction' $c.Credit.number $c.Invoice.number $c.Orig.number)
        } else {
            New-HcMailText 'invoice' $name.Title $name.Name (Get-Date) '' $c.Settings -Subject (T 'mail.subject.credit' $c.Credit.number) -Body (T 'mail.body.credit' $c.Credit.number $c.Orig.number)
        }
    }
    Add-HcJob @{ Kind = 'relay'; To = $Job.To; Done = 'Complete-HcCorrMailSent'; Body = @{
        action = 'mail_send'; token = $script:HcToken; to = $Job.To; subject = $mail.Subject; text = $mail.Text
        pdf_base64 = [Convert]::ToBase64String($r.PdfBytes); filename = (Get-HcCorrPdfName) } }
}

function Complete-HcCorrMailSent {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $c = $script:HcWin.Corr
    if (-not $c) { return }
    $c.MailBusy = $false
    $r = Get-HcRelayResult $Output
    if (-not $ErrorText -and $r -and $r.Ok) { $c.MailResult = @{ Ok = $true; Text = (T 'win.mail.sent' $Job.To) } }
    else { $c.MailResult = @{ Ok = $false; Text = (Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' })) } }
    Update-HcCorrBar
}
