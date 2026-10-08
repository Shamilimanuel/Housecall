<#
    The window's Bezoek tab (phase 6, step 2): finishing the visit with an
    invoice or a plain note, and this PC's earlier visits.

    Both start with the Authenticator code, in six slots: the prices, the
    invoice number and the history all live behind the relay. With the code
    in, the form fills a live A4 preview (the same page that is printed),
    and "Factuur maken" needs nothing more. A note needs no code at all.

    The form writes straight into the visit's own state ($script:HcAsked,
    $script:HcWork), so the invoice, the note and the history get exactly
    what the text menu would give them. Relay calls run in the worker.
#>

# ------------------------------------------------------------ pure parts --

# The lines of the invoice being filled in: time, call-out, and the extra
# parts that were added with a valid amount.
function Get-HcDraftLines {
    param([hashtable]$Fin, $Settings)
    foreach ($l in @(Get-HcLabourLines ([int]$Fin.Minutes) $Settings)) { $l }
    $fee = [decimal]$(if ($Settings.callout_fee) { $Settings.callout_fee } else { 0 })
    if ($Fin.Callout -and $fee -gt 0) { [pscustomobject]@{ Description = (T 'inv.calloutLine'); Amount = $fee } }
    foreach ($e in @($Fin.Extras)) { [pscustomobject]@{ Description = $e.Description; Amount = [decimal]$e.Amount } }
}

# The invoice as it will look before the relay numbers it: the same shape
# invoice_create returns, so one page layout draws both.
function New-HcDraftInvoice {
    param([hashtable]$Fin, $Settings, [datetime]$Now = (Get-Date))
    $lines = @(Get-HcDraftLines $Fin $Settings)
    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    $subtotal = $total
    $btw = [decimal]0
    if ("$($Settings.btw_mode)" -eq '21') {
        $subtotal = [Math]::Round($total / [decimal]1.21, 2)
        $btw = $total - $subtotal
    }
    $days = if ($Settings.payment_days) { [int]$Settings.payment_days } else { 14 }
    [pscustomobject]@{
        number               = (T 'win.fin.draft')
        issued_at            = $Now.ToUniversalTime().ToString('o')
        seller               = $(if ($Settings) { $Settings } else { [pscustomobject]@{ business_name = 'Housecall' } })
        client_name          = Format-HcClientName $Fin.Title $Fin.Name
        client_address       = "$($Fin.Address)".Trim()
        client_postcode_city = "$($Fin.Postcode)".Trim()
        client_email         = "$($Fin.Email)".Trim()
        lines                = @($lines | ForEach-Object { [pscustomobject]@{ description = $_.Description; amount = [decimal]$_.Amount } })
        btw_mode             = "$($Settings.btw_mode)"
        subtotal             = $subtotal
        btw_amount           = $btw
        total                = $total
        payment              = $Fin.Payment
        due_date             = $Now.AddDays($days).ToString('yyyy-MM-dd')
    }
}

# The salutations a client can get, in the order they are offered. Dutch
# has one word for a woman, married or not (Mevr.); English tells Mrs.
# (married) from Ms. (not married, or not known), so Ms. is English only.
$script:HcTitles = @('none', 'mr', 'mrs', 'ms', 'couple', 'family')

function Get-HcTitleChoices {
    param([string]$Lang = $script:Lang)
    @($script:HcTitles | Where-Object { $Lang -ne 'nl' -or $_ -ne 'ms' })
}

# "Mevr. Anna de Vries", "Mr. and Mrs. Smith", "The Smith family": the name as
# it goes on the note, the invoice and in the history.
function Format-HcClientName {
    param([string]$Title, [string]$Name, [string]$Lang = $script:Lang)
    $n = "$Name".Trim()
    if (-not $n -or -not $Title -or $Title -eq 'none') { return $n }
    $format = $script:Strings[$Lang]["name.$Title"]
    if (-not $format) { return $n }
    $format -f $n
}

# The other way round, for a name from the history: "Mevr. de Vries" gives
# mrs and "de Vries", in either language; anything else stays as it is.
function Split-HcClientName {
    param([string]$Label)
    $text = "$Label".Trim()
    foreach ($lang in @('nl', 'en')) {
        foreach ($title in @('couple', 'family', 'mr', 'mrs', 'ms')) {
            $format = $script:Strings[$lang]["name.$title"]
            if (-not $format) { continue }
            $pattern = '^' + ([regex]::Escape($format) -replace '\\\{0\}', '(.+)') + '$'
            if ($text -match $pattern) { return [pscustomobject]@{ Title = $title; Name = $Matches[1].Trim() } }
        }
    }
    [pscustomobject]@{ Title = 'none'; Name = $text }
}

# The mail that goes with the PDF, in the visit's language: the greeting by
# salutation, one sentence on what is attached, and Shamil's name (and
# phone, once it is in his settings) under it. Kind is invoice, receipt or note.
function New-HcMailText {
    param([string]$Kind, [string]$Title, [string]$Name, [datetime]$Date, [string]$Number, $Settings)
    $n = "$Name".Trim()
    $greet = if (-not $n) { T 'mail.greet.anon' } else { T "mail.greet.$(if ($Title) { $Title } else { 'none' })" $n }
    $subject = if ($Kind -eq 'invoice') { T 'mail.subject.invoice' $Number } else { T "mail.subject.$Kind" }
    $sign = @((T 'mail.regards'), $(if ($Settings.business_name) { [string]$Settings.business_name } else { 'Housecall' }), (T 'mail.brand'))
    if ($Settings.phone) { $sign += [string]$Settings.phone }
    $text = @($greet, '', (T "mail.body.$Kind" (Format-HcLongDate $Date)), '', (T 'mail.questions'), '', ($sign -join "`n")) -join "`n"
    [pscustomobject]@{ Subject = $subject; Text = $text }
}

# How the client can pay: a transfer only once an IBAN is set, since the
# invoice has to say where to.
function Get-HcPayMethods {
    # -Receipt: a betaalbewijs says "voldaan", so paying later is not one of them.
    param($Settings, [switch]$Receipt)
    $methods = @('pin', 'cash', 'tikkie')
    if ($Settings.iban -and -not $Receipt) { $methods += 'transfer' }
    $methods
}

# The start of a visit's state in the window.
function New-HcFinishState {
    @{
        Stage = 'new'; Mode = 'invoice'; Settings = $null; Notice = $null; Invoice = $null; Saved = $false; Pages = $null
        Title = (Split-HcClientName $script:HcKnownLabel).Title; Name = (Split-HcClientName $script:HcKnownLabel).Name; Address = ''; Postcode = ''; Email = ''; Minutes = 0; Callout = $true
        Extras = New-Object System.Collections.ArrayList; Payment = 'pin'; Offline = $false; CalcBlock = $null; AllPresets = $false
        MailAsk = $null; MailBusy = $false; MailResult = $null
        # The kept PDF: one id per visit, so a second save replaces the first.
        DocId = [guid]::NewGuid().ToString(); VisitId = $null; DocSaved = $false; DocFailed = $false
    }
}

# ------------------------------------------------------------- opening --

function Open-HcVisitTab {
    param([string]$View = 'finish')
    $w = $script:HcWin
    $w.Tab = 'visit'
    $w.VisitView = $View
    if ($View -eq 'finish') { Start-HcFinish } else { Start-HcHistory }
    Update-HcTabs
    Update-HcVisit
}

function Start-HcFinish {
    $w = $script:HcWin
    $f = $w.Fin
    if ($f.Stage -ne 'new') { return }
    if (-not $f.Minutes) { $f.Minutes = Get-HcSuggestedMinutes }
    # Without the relay there is no invoice; the note is always possible.
    if (-not $w.Environment.Online -or $script:DryRun) {
        $f.Mode = 'note'
        $f.Stage = 'form'
        $f.Offline = $true
        return
    }
    if (Test-HcUnlocked) { Start-HcSettingsLoad } else { $f.Stage = 'code' }
}

function Start-HcSettingsLoad {
    $f = $script:HcWin.Fin
    $f.Stage = 'loading'
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'settings_get'; token = $script:HcToken }; Done = 'Complete-HcSettings' }
}

function Get-HcRelayResult {
    param([object[]]$Output)
    @($Output | Where-Object { $_ -and $_.PSObject.Properties['Ok'] }) | Select-Object -Last 1
}

function Complete-HcSettings {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $f = $script:HcWin.Fin
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $code = if ($r) { $r.Error } else { 'unreachable' }
        if ($code -eq 'locked_out') { $script:HcToken = $null; $f.Stage = 'code'; $f.Notice = T 'relay.expired' }
        else { $f.Stage = 'form'; $f.Mode = 'note'; $f.Notice = T 'inv.failed' (Get-HcRelayMessage $code) }
        Update-HcVisit
        return
    }
    $s = $r.Data.settings
    if ($s) { Set-HcContact $s }
    if (-not $s -or -not $s.business_name) {
        $f.Stage = 'form'; $f.Mode = 'note'; $f.Notice = T 'inv.noSettings'
        Update-HcVisit
        return
    }
    $f.Settings = $s
    $script:HcStartMinutes = if ([decimal]$(if ($s.start_fee) { $s.start_fee } else { 0 }) -gt 0) { [int]$s.start_minutes } else { 0 }
    if ((Get-HcPayMethods $s) -notcontains $f.Payment) { $f.Payment = 'pin' }
    $f.Stage = 'form'
    Update-HcVisit
    Update-HcClock
}

# ----------------------------------------------------------- code slots --

# Six boxes for the Authenticator code. Typing moves on by itself, pasting
# fills them all, Backspace goes back, and Enter (or the sixth digit) sends.
# -For 'pair' is the Wi-Fi pairing code of the phone tab: the same boxes,
# with its own label, hint and button.
function New-HcCodeBox {
    param([string]$For, [string]$Intro, [string]$Label = (T 'win.code.label'), [string]$Hint = (T 'win.code.hint'), [string]$GoText = (T 'win.code.go'))
    $w = $script:HcWin
    $w.Totp = @{ For = $For; Slots = @(); Hint = $null; Filling = $false }
    $stack = New-Object Windows.Controls.StackPanel
    if ($Intro) { [void]$stack.Children.Add((New-HcText $Intro 15 'Text' -Margin @(0, 0, 0, 10))) }
    [void]$stack.Children.Add((New-HcText $Label.ToUpperInvariant() 12 'Soft' -Bold -Margin @(0, 0, 0, 6)))
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $slots = @()
    for ($i = 0; $i -lt 6; $i++) {
        $box = New-Object Windows.Controls.TextBox
        $box.Width = 50
        $box.Height = 60
        $box.FontSize = 28
        $box.FontWeight = [Windows.FontWeights]::Bold
        $box.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
        $box.TextAlignment = 'Center'
        $box.VerticalContentAlignment = 'Center'
        $box.MaxLength = 6
        $box.BorderThickness = New-HcThickness @(2, 2, 2, 2)
        $box.Margin = New-HcThickness @(0, 0, $(if ($i -eq 2) { 18 } else { 8 }), 0)
        $box.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Panel')
        $box.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
        $box.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line')
        $box.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Hi')
        $box.Tag = @{ Slot = $i }
        [Windows.Automation.AutomationProperties]::SetName($box, (T 'win.code.digit' ($i + 1)))
        $box.Add_PreviewTextInput({ if ($_.Text -notmatch '^\d+$') { $_.Handled = $true } })
        $box.Add_TextChanged({ Invoke-HcSlotChanged $this })
        $box.Add_PreviewKeyDown({ Invoke-HcSlotKey $this $_ })
        $box.Add_GotKeyboardFocus({
            $this.SelectAll()
            $this.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Hi')
        })
        $box.Add_LostKeyboardFocus({ $this.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line') })
        if ($i -eq 0) { $box.Add_Loaded({ [void]$this.Focus() }) }
        $slots += $box
        [void]$row.Children.Add($box)
    }
    $w.Totp.Slots = $slots
    [void]$stack.Children.Add($row)
    $go = New-HcButton $GoText @{ Do = 'codeSubmit' } 'HcPrimary'
    $go.HorizontalAlignment = 'Left'
    $go.Margin = New-HcThickness @(0, 12, 0, 6)
    [void]$stack.Children.Add($go)
    $w.Totp.Hint = New-HcText $Hint 13.5 'Soft' -Margin @(0, 0, 0, 0)
    [void]$stack.Children.Add($w.Totp.Hint)
    New-HcBox '' @($stack) 'Side'
}

function Invoke-HcSlotChanged {
    param($Sender)
    $c = $script:HcWin.Totp
    if (-not $c -or $c.Filling) { return }
    try {
        $c.Filling = $true
        $i = $Sender.Tag.Slot
        $digits = $Sender.Text -replace '\D', ''
        if (-not $digits) { $Sender.Text = ''; return }
        # One digit, or a pasted code: spread it over this box and the next.
        for ($k = 0; $k -lt $digits.Length -and ($i + $k) -lt 6; $k++) { $c.Slots[$i + $k].Text = [string]$digits[$k] }
        [void]$c.Slots[[Math]::Min($i + $digits.Length, 5)].Focus()
    } finally {
        $c.Filling = $false
    }
    if ((($c.Slots | ForEach-Object { $_.Text }) -join '') -match '^\d{6}$') { Submit-HcCode }
}

function Invoke-HcSlotKey {
    param($Sender, $KeyArgs)
    $c = $script:HcWin.Totp
    $i = $Sender.Tag.Slot
    switch ([string]$KeyArgs.Key) {
        'Back' {
            if (-not $Sender.Text -and $i -gt 0) {
                $c.Slots[$i - 1].Text = ''
                [void]$c.Slots[$i - 1].Focus()
                $KeyArgs.Handled = $true
            }
        }
        'Left'   { if ($i -gt 0) { [void]$c.Slots[$i - 1].Focus(); $KeyArgs.Handled = $true } }
        'Right'  { if ($i -lt 5) { [void]$c.Slots[$i + 1].Focus(); $KeyArgs.Handled = $true } }
        'Return' { $KeyArgs.Handled = $true; Submit-HcCode }
    }
}

function Submit-HcCode {
    $w = $script:HcWin
    $c = $w.Totp
    if (-not $c -or (Test-HcBusy)) { return }
    $code = ($c.Slots | ForEach-Object { $_.Text }) -join ''
    if ($code -notmatch '^\d{6}$') {
        $c.Hint.Text = T 'win.code.incomplete'
        $first = @($c.Slots | Where-Object { -not $_.Text }) | Select-Object -First 1
        if ($first) { [void]$first.Focus() }
        return
    }
    foreach ($s in $c.Slots) { $s.IsEnabled = $false }
    if ($c.For -eq 'pair') { $c.Hint.Text = T 'ph.pairing'; Submit-HcPairCode $code; return }
    $c.Hint.Text = T 'win.code.checking'
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'unlock'; code = $code }; For = $c.For; Done = 'Complete-HcUnlock' }
}

function Complete-HcUnlock {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $code = if ($r) { $r.Error } else { 'unreachable' }
        $c = $w.Totp
        if ($c) {
            $c.Hint.Text = Get-HcRelayMessage $code
            $c.Hint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Warn')
            $c.Filling = $true
            foreach ($s in $c.Slots) { $s.Text = ''; $s.IsEnabled = $true }
            $c.Filling = $false
            [void]$c.Slots[0].Focus()
        }
        return
    }
    $script:HcToken = $r.Data.token
    $script:HcTokenExpires = [datetime]::Parse($r.Data.expires, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
    $w.Totp = $null
    Update-HcSide
    if ($Job.For -eq 'history') {
        Start-HcHistoryLoad
    } elseif ($Job.For -eq 'ai') {
        $w.Ai.Stage = 'ask'
        Update-HcOther
    } else {
        # Who this PC belongs to, from its earlier visits: the name for the invoice.
        Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'visit_get'; token = $script:HcToken; pc = (Get-HcWindowPcId) }; Done = 'Complete-HcKnown' }
        Start-HcSettingsLoad
    }
    Update-HcVisit
}

function Get-HcWindowPcId {
    $w = $script:HcWin
    if (-not $w.PcId) { $w.PcId = Get-HcPcId }
    $w.PcId
}

function Complete-HcKnown {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) { return }
    $label = @($r.Data.visits | Where-Object { $_ -and $_.label } | Select-Object -First 1).label
    if (-not $label) { return }
    $script:HcKnownLabel = $label
    if (-not "$($w.Fin.Name)".Trim()) {
        $known = Split-HcClientName $label
        $w.Fin.Title = $known.Title
        $w.Fin.Name = $known.Name
        if ($w.Fin.Stage -eq 'form') { Update-HcVisit }
    }
}

# ------------------------------------------------------------- painting --

function Update-HcVisit {
    $w = $script:HcWin
    if ($w.Tab -ne 'visit') { return }
    if ($w.VisitView -eq 'history') { Update-HcOther; return }
    Update-HcFinishPanel
    Update-HcFinishBar
    Update-HcPreview
}

# Afronden | Eerdere bezoeken, at the top of both views.
function New-HcVisitToggle {
    $w = $script:HcWin
    $row = New-Object Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Margin = New-HcThickness @(0, 0, 0, 12)
    foreach ($view in @('finish', 'history')) {
        $style = if ($w.VisitView -eq $view) { 'HcPrimary' } else { 'HcButton' }
        $b = New-HcButton (T "win.visitView.$view") @{ Do = 'visitView'; View = $view } $style
        $b.Margin = New-HcThickness @(0, 0, 8, 0)
        $b.IsEnabled = -not (Test-HcBusy) -or $w.VisitView -eq $view
        [void]$row.Children.Add($b)
    }
    $row
}

function New-HcSection {
    param([string]$Title, [string]$Note)
    $head = New-Object Windows.Controls.WrapPanel
    $head.Margin = New-HcThickness @(0, 14, 0, 8)
    [void]$head.Children.Add((New-HcText $Title 17 'Text' -Bold -Margin @(0, 0, 10, 0)))
    if ($Note) {
        $n = New-HcText $Note 13 'Soft' -Margin @(0, 3, 0, 0)
        [void]$head.Children.Add($n)
    }
    $head
}

# A labelled text box that writes into $HcWin.Fin as it is typed in.
function New-HcField {
    param([string]$Label, [string]$Field, [string]$Value, [double]$Width = 0)
    $stack = New-Object Windows.Controls.StackPanel
    $stack.Margin = New-HcThickness @(0, 0, 12, 8)
    $stack.HorizontalAlignment = 'Left'
    if ($Width) { $stack.Width = $Width }
    [void]$stack.Children.Add((New-HcText $Label 13 'Soft' -Bold -Margin @(0, 0, 0, 3)))
    $box = New-HcTextBox $Value
    $box.Tag = @{ Field = $Field }
    $box.Add_TextChanged({ Invoke-HcFieldChanged $this })
    [void]$stack.Children.Add($box)
    $stack
}

function New-HcTextBox {
    param([string]$Value)
    $box = New-Object Windows.Controls.TextBox
    $box.Text = $Value
    $box.FontSize = 15
    $box.Padding = New-HcThickness @(8, 6, 8, 6)
    $box.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Panel')
    $box.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
    $box.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Line')
    $box.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Text')
    $box
}

function New-HcChip {
    param([string]$Text, [hashtable]$Tag, [switch]$On)
    $b = New-HcButton $Text $Tag $(if ($On) { 'HcPrimary' } else { 'HcButton' })
    $b.Padding = New-HcThickness @(11, 5, 11, 5)
    $b.Margin = New-HcThickness @(0, 0, 6, 6)
    $b
}

function Update-HcFinishPanel {
    $w = $script:HcWin
    $f = $w.Fin
    $panel = $w.Window.FindName('FinishPanel')
    $panel.Children.Clear()
    $add = { param($element) [void]$panel.Children.Add($element) }
    & $add (New-HcVisitToggle)
    if ($f.Notice) { & $add (New-HcText $f.Notice 14.5 'Warn' -Bold) }

    switch ($f.Stage) {
        'code' {
            & $add (New-HcText (T 'win.visitView.finish') 22 'Text' -Bold -Margin @(0, 4, 0, 8))
            & $add (New-HcCodeBox 'finish' (T 'win.fin.codeIntro'))
            $note = New-HcButton (T 'win.fin.noteOnly') @{ Do = 'noteOnly' }
            $note.HorizontalAlignment = 'Left'
            $note.Margin = New-HcThickness @(0, 6, 0, 0)
            & $add $note
            return
        }
        'loading' {
            & $add (New-HcText (T 'win.fin.loading') 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
            return
        }
    }

    $done = $f.Stage -in @('working', 'done')
    $form = New-Object Windows.Controls.StackPanel
    $form.IsEnabled = -not $done
    $put = { param($element) [void]$form.Children.Add($element) }

    # What the visit was about: typed, or one of the problems opened.
    & $put (New-HcSection (T 'win.fin.asked') (T 'win.fin.askedNote'))
    if (-not "$script:HcAsked".Trim() -and $script:HcVisit.Count) { $script:HcAsked = T "problem.$($script:HcVisit[0].Code)" }
    $asked = New-HcTextBox "$script:HcAsked"
    $asked.Tag = @{ Field = 'Asked' }
    $asked.Add_TextChanged({ Invoke-HcFieldChanged $this })
    $asked.Margin = New-HcThickness @(0, 0, 0, 6)
    & $put $asked
    $chips = New-Object Windows.Controls.WrapPanel
    foreach ($v in @($script:HcVisit)) {
        [void]$chips.Children.Add((New-HcChip ($v.Code + '  ' + (T "problem.$($v.Code)")) @{ Do = 'finAsked'; Text = (T "problem.$($v.Code)") }))
    }
    & $put $chips

    # What was done: Housecall's own fixes, then Shamil's list.
    & $put (New-HcSection (T 'note.done') (T 'win.fin.doneNote'))
    foreach ($c in @($script:HcChanges)) {
        $row = New-Object Windows.Controls.DockPanel
        $tag = New-HcText 'Housecall' 11.5 'Soft' -Bold -Margin @(8, 2, 0, 0)
        [Windows.Controls.DockPanel]::SetDock($tag, 'Right')
        [void]$row.Children.Add($tag)
        [void]$row.Children.Add((New-HcLine 'ok' $c.Label))
        & $put (New-HcBox '' @($row) 'Panel')
    }
    for ($i = 0; $i -lt $script:HcWork.Count; $i++) {
        $item = $script:HcWork[$i]
        $row = New-Object Windows.Controls.DockPanel
        $buttons = New-Object Windows.Controls.StackPanel
        $buttons.Orientation = 'Horizontal'
        [Windows.Controls.DockPanel]::SetDock($buttons, 'Right')
        foreach ($state in @($true, $false)) {
            $label = if ($state) { T 'inv.win.fixed' } else { T 'inv.win.notFixed' }
            $b = New-HcChip $label @{ Do = 'workDone'; Index = $i; Done = $state } -On:($item.Done -eq $state)
            $b.Margin = New-HcThickness @(6, 0, 0, 0)
            [void]$buttons.Children.Add($b)
        }
        $x = New-HcChip ([string][char]0x00D7) @{ Do = 'workRemove'; Index = $i }
        $x.Margin = New-HcThickness @(6, 0, 0, 0)
        $x.ToolTip = T 'win.fin.remove'
        [void]$buttons.Children.Add($x)
        [void]$row.Children.Add($buttons)
        [void]$row.Children.Add((New-HcLine $(if ($item.Done) { 'ok' } else { 'problem' }) $item.Text))
        $box = New-HcBox '' @($row) 'Panel'
        $box.Padding = New-HcThickness @(10, 6, 6, 4)
        $box.Margin = New-HcThickness @(0, 0, 0, 6)
        & $put $box
    }
    $addRow = New-Object Windows.Controls.DockPanel
    $addRow.Margin = New-HcThickness @(0, 4, 0, 6)
    $addButton = New-HcButton (T 'win.fin.add') @{ Do = 'workAdd' }
    $addButton.Margin = New-HcThickness @(8, 0, 0, 0)
    [Windows.Controls.DockPanel]::SetDock($addButton, 'Right')
    [void]$addRow.Children.Add($addButton)
    $w.WorkBox = New-HcTextBox ''
    $w.WorkBox.Tag = @{ Do = 'workAdd' }
    $w.WorkBox.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-HcClick $this } })
    [void]$addRow.Children.Add($w.WorkBox)
    & $put $addRow
    # The most used first; the rest behind "more", so the form stays short.
    $presets = New-Object Windows.Controls.WrapPanel
    $left = @(Get-HcWorkPresets | Where-Object { $p = $_; -not @($script:HcWork | Where-Object { $_.Text -eq $p }).Count })
    $shown = if ($f.AllPresets) { $left } else { @($left | Select-Object -First 8) }
    foreach ($p in $shown) { [void]$presets.Children.Add((New-HcChip ('+ ' + $p) @{ Do = 'workPreset'; Text = $p })) }
    if ($left.Count -gt $shown.Count) { [void]$presets.Children.Add((New-HcChip (T 'win.fin.more' ($left.Count - $shown.Count)) @{ Do = 'morePresets' })) }
    & $put $presets

    # The client.
    & $put (New-HcSection (T 'win.fin.client') $(if ($f.Mode -eq 'note') { T 'win.fin.clientNote' } else { '' }))
    # The salutation, picked with one click: it goes before the name.
    [void]$form.Children.Add((New-HcText (T 'win.fin.title') 13 'Soft' -Bold -Margin @(0, 0, 0, 3)))
    $titles = New-Object Windows.Controls.WrapPanel
    foreach ($t in @(Get-HcTitleChoices)) {
        [void]$titles.Children.Add((New-HcChip (T "win.title.$t") @{ Do = 'clientTitle'; Title = $t } -On:($f.Title -eq $t -or ($t -eq 'mrs' -and $f.Title -eq 'ms' -and $script:Lang -eq 'nl'))))
    }
    & $put $titles
    & $put (New-HcText (T 'win.fin.titleNote') 13 'Soft' -Margin @(0, 0, 0, 8))
    $grid = New-Object Windows.Controls.WrapPanel
    [void]$grid.Children.Add((New-HcField (T 'win.fin.fullName') 'Name' $f.Name 250))
    [void]$grid.Children.Add((New-HcField (T 'win.fin.email') 'Email' $f.Email 250))
    [void]$grid.Children.Add((New-HcField (T 'inv.address') 'Address' $f.Address 250))
    [void]$grid.Children.Add((New-HcField (T 'inv.postcode') 'Postcode' $f.Postcode 250))
    & $put $grid

    if ($f.Mode -in @('invoice', 'receipt') -and $f.Settings) {
        # Time and costs.
        & $put (New-HcSection (T 'win.fin.time'))
        $clock = Get-HcClockLine
        & $put (New-HcText $clock.Text 15 $(if ($clock.Over) { 'Warn' } else { 'Text' }) -Bold)
        $minutes = New-HcField (T 'inv.win.minutes') 'Minutes' ([string]$f.Minutes) 140
        & $put $minutes
        & $put (New-HcText (Get-HcRateText $f.Settings) 13.5 'Soft')
        $fee = [decimal]$(if ($f.Settings.callout_fee) { $f.Settings.callout_fee } else { 0 })
        if ($fee -gt 0) {
            $check = New-Object Windows.Controls.CheckBox
            $check.Content = T 'inv.win.callout' (Format-HcMoney $fee)
            $check.IsChecked = [bool]$f.Callout
            $check.Tag = @{ Field = 'Callout' }
            $check.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
            $check.Margin = New-HcThickness @(0, 4, 0, 8)
            $check.Add_Click({ Invoke-HcFieldChanged $this })
            & $put $check
        }
        # Parts, each with its price.
        foreach ($e in @($f.Extras)) {
            $i = $f.Extras.IndexOf($e)
            $row = New-Object Windows.Controls.DockPanel
            $x = New-HcChip ([string][char]0x00D7) @{ Do = 'extraRemove'; Index = $i }
            [Windows.Controls.DockPanel]::SetDock($x, 'Right')
            [void]$row.Children.Add($x)
            [void]$row.Children.Add((New-HcText ($e.Description + '   ' + (Format-HcMoney $e.Amount)) 15 'Text' -Margin @(0, 4, 0, 0)))
            $box = New-HcBox '' @($row) 'Panel'
            $box.Padding = New-HcThickness @(12, 6, 6, 0)
            $box.Margin = New-HcThickness @(0, 0, 0, 6)
            & $put $box
        }
        $extra = New-Object Windows.Controls.WrapPanel
        $w.ExtraText = New-HcField (T 'win.fin.part') 'ExtraText' '' 250
        $w.ExtraPrice = New-HcField (T 'win.fin.price') 'ExtraPrice' '' 110
        [void]$extra.Children.Add($w.ExtraText)
        [void]$extra.Children.Add($w.ExtraPrice)
        $addPart = New-HcButton (T 'win.fin.add') @{ Do = 'extraAdd' }
        $addPart.VerticalAlignment = 'Bottom'
        [void]$extra.Children.Add($addPart)
        & $put $extra
        $f.CalcBlock = New-HcText '' 14 'Soft' -Margin @(0, 4, 0, 0)
        & $put $f.CalcBlock
        Update-HcCalc

        # How it is paid.
        & $put (New-HcSection (T 'inv.win.payment'))
        $pay = New-Object Windows.Controls.WrapPanel
        foreach ($m in @(Get-HcPayMethods $f.Settings -Receipt:($f.Mode -eq 'receipt'))) {
            $label = T ('inv.pay.' + $m)
            $label = $label.Substring(0, 1).ToUpperInvariant() + $label.Substring(1)
            if ($m -eq 'transfer') { $label += ' (' + (T 'win.fin.days' $(if ($f.Settings.payment_days) { $f.Settings.payment_days } else { 14 })) + ')' }
            [void]$pay.Children.Add((New-HcChip $label @{ Do = 'pay'; Method = $m } -On:($f.Payment -eq $m)))
        }
        & $put $pay
    }
    & $add $form
}

# "Arbeid 50 min: starttarief ... EUR 15,00 . + 2 x 15 min ... EUR 10,00 . Totaal EUR 25,00"
function Update-HcCalc {
    $f = $script:HcWin.Fin
    if (-not $f.CalcBlock -or -not $f.Settings) { return }
    $lines = @(Get-HcDraftLines $f $f.Settings)
    $total = [decimal]0
    foreach ($l in $lines) { $total += [decimal]$l.Amount }
    $dot = '  ' + [char]0x00B7 + '  '
    # A non-breaking space after the euro sign, so an amount never splits.
    $money = { param($a) (Format-HcMoney $a) -replace ([string][char]0x20AC + ' '), ([string][char]0x20AC + [char]0x00A0) }
    $parts = @($lines | ForEach-Object { $_.Description + ': ' + (& $money $_.Amount) })
    $f.CalcBlock.Text = (@($parts) + @((T 'doc.totalWord') + ' ' + (& $money $total))) -join $dot
}

function Update-HcFinishBar {
    $w = $script:HcWin
    $f = $w.Fin
    $bar = $w.Window.FindName('FinishBar')
    $bar.Children.Clear()
    $row = New-Object Windows.Controls.WrapPanel
    $add = { param($element) $element.Margin = New-HcThickness @(0, 0, 8, 6); [void]$row.Children.Add($element) }
    $hint = $null
    if ($w.CloseAsk) { [void]$bar.Children.Add((New-HcText (T 'win.fin.closeFirst') 14.5 'Warn' -Bold)) }
    if ($f.MailAsk) { [void]$bar.Children.Add((New-HcQuestion (T "win.mail.ask.$(Get-HcDocKind)" $f.MailAsk) 'mailYes' 'mailNo')) }
    if ($f.MailBusy) { [void]$bar.Children.Add((New-HcText (T 'win.mail.busy') 14.5 'Soft' -Bold)) }
    elseif ($f.MailResult) { [void]$bar.Children.Add((New-HcText $f.MailResult.Text 14.5 $(if ($f.MailResult.Ok) { 'Ok' } else { 'Warn' }) -Bold)) }
    $mail = { if (-not $f.Offline) { & $add (New-HcButton (T 'win.fin.mail') @{ Do = 'finMail' }) } }
    switch ($f.Stage) {
        'working' { $hint = T 'win.fin.working' }
        'done' {
            if ($f.Invoice) {
                [void]$bar.Children.Add((New-HcText ([string][char]0x2713 + ' ' + (T 'win.fin.made' $f.Invoice.number) + $(if ($f.Saved) { ' ' + (T 'win.fin.savedToo') } else { '' })) 15 'Ok' -Bold))
            }
            & $add (New-HcButton (T 'note.print') @{ Do = 'finPrint' } 'HcPrimary')
            & $add (New-HcButton (T 'win.fin.pdf') @{ Do = 'finPdf' })
            & $mail
            & $add (New-HcButton (T 'win.fin.close') @{ Do = 'finDone' })
        }
        'form' {
            if ($f.Mode -eq 'invoice' -and $f.Settings) {
                & $add (New-HcButton (T 'win.fin.make') @{ Do = 'finMake' } 'HcPrimary')
                $hint = T 'win.fin.makeHint'
            } elseif ($f.Mode -eq 'receipt' -and $f.Settings) {
                & $add (New-HcButton (T 'win.fin.receiptPrint') @{ Do = 'finPrint' } 'HcPrimary')
                & $add (New-HcButton (T 'win.fin.pdf') @{ Do = 'finPdf' })
                & $mail
                & $add (New-HcButton (T 'win.fin.close') @{ Do = 'finDone' })
                $hint = T 'win.fin.receiptHint'
            } else {
                & $add (New-HcButton (T 'win.fin.notePrint') @{ Do = 'finPrint' } 'HcPrimary')
                & $add (New-HcButton (T 'win.fin.pdf') @{ Do = 'finPdf' })
                & $mail
                & $add (New-HcButton (T 'win.fin.close') @{ Do = 'finDone' })
                $hint = if ($f.Offline) { T 'win.fin.noteOffline' } elseif (Test-HcUnlocked) { T 'win.fin.noteSaves' } else { T 'win.fin.noteNoCode' }
            }
        }
    }
    # Last, as the least wanted way out.
    if ($w.CloseAsk -and $f.Stage -ne 'done') { & $add (New-HcButton (T 'win.fin.closeAnyway') @{ Do = 'closeAnyway' }) }
    if ($row.Children.Count) { [void]$bar.Children.Add($row) }
    if ($hint) { [void]$bar.Children.Add((New-HcText $hint 13 'Soft' -Margin @(0, 0, 0, 0))) }
    $w.Window.FindName('FinishBarBorder').Visibility = if ($bar.Children.Count) { 'Visible' } else { 'Collapsed' }
}

# The A4 page on the right: the invoice being filled in, the finished one,
# or the note. Drawn by the same code as the printout.
function Update-HcPreview {
    $w = $script:HcWin
    $f = $w.Fin
    if ($w.Tab -ne 'visit' -or $w.VisitView -ne 'finish') { return }
    $top = $w.Window.FindName('PreviewTop')
    $top.Children.Clear()
    $panel = $w.Window.FindName('PreviewPanel')
    $panel.Children.Clear()

    $state = if ($f.Stage -eq 'done' -and $f.Invoice) { T 'win.fin.stateMade' $f.Invoice.number }
             elseif ($f.Mode -eq 'note') { T 'win.fin.stateNote' }
             elseif ($f.Mode -eq 'receipt') { T 'win.fin.stateReceipt' }
             else { T 'win.fin.stateDraft' }
    $label = New-HcText $state.ToUpperInvariant() 12 $(if ($f.Invoice) { 'Ok' } else { 'Soft' }) -Bold -Margin @(0, 8, 0, 0)
    [Windows.Controls.DockPanel]::SetDock($label, 'Left')
    [void]$top.Children.Add($label)
    if ($f.Stage -ne 'done') {
        $modes = New-Object Windows.Controls.StackPanel
        $modes.Orientation = 'Horizontal'
        [Windows.Controls.DockPanel]::SetDock($modes, 'Right')
        foreach ($m in @('invoice', 'receipt', 'note')) {
            $b = New-HcChip (T "win.fin.mode.$m") @{ Do = 'finMode'; Mode = $m } -On:($f.Mode -eq $m)
            $b.IsEnabled = -not ($m -ne 'note' -and $f.Offline) -and $f.Stage -ne 'working'
            [void]$modes.Children.Add($b)
        }
        [void]$top.Children.Add($modes)
    }

    if ($f.Mode -in @('invoice', 'receipt') -and -not $f.Settings -and -not $f.Invoice) {
        [void]$panel.Children.Add((New-HcText (T 'win.fin.previewAfterCode') 14.5 'Soft' -Margin @(0, 12, 0, 0)))
        $f.Pages = $null
        return
    }
    try {
        # One @() around the whole choice: each page is an array of steps,
        # and an if-statement would unroll the list of pages into its steps.
        $pages = @(if ($f.Invoice) { Get-HcInvoiceLayout $f.Invoice }
                   elseif ($f.Mode -eq 'note') { Get-HcInvoiceLayout (New-HcDraftInvoice $f $f.Settings) -Note }
                   elseif ($f.Mode -eq 'receipt') { Get-HcInvoiceLayout (New-HcDraftInvoice $f $f.Settings) -Receipt }
                   else { Get-HcInvoiceLayout (New-HcDraftInvoice $f $f.Settings) })
    } catch {
        [void]$panel.Children.Add((New-HcText (T 'win.error' $_.Exception.Message) 14 'Warn'))
        return
    }
    $f.Pages = $pages
    foreach ($steps in $pages) {
        $bmp = New-HcInvoiceBitmap $steps
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
        [void]$panel.Children.Add($paper)
    }
}

# A redraw a moment after the last keystroke, not on every one.
function Request-HcPreview {
    $script:HcWin.PreviewDue = (Get-Date).AddMilliseconds(300)
}

# ---------------------------------------------------------------- doing --

function Invoke-HcFieldChanged {
    param($Sender)
    $w = $script:HcWin
    $f = $w.Fin
    $field = $Sender.Tag.Field
    switch ($field) {
        'Asked'    { $script:HcAsked = "$($Sender.Text)".Trim() }
        'Minutes'  {
            $n = 0
            if ([int]::TryParse("$($Sender.Text)".Trim(), [ref]$n) -and $n -ge 0 -and $n -le 1440) { $f.Minutes = $n }
            Update-HcCalc
        }
        'Callout'  { $f.Callout = [bool]$Sender.IsChecked; Update-HcCalc }
        'ExtraText' { return }
        'ExtraPrice' { return }
        default    { $f[$field] = "$($Sender.Text)" }
    }
    $f.Notice = $null
    Request-HcPreview
}

function Invoke-HcVisitClick {
    param([hashtable]$Tag)
    $w = $script:HcWin
    $f = $w.Fin
    switch ($Tag.Do) {
        'visitView'  { Open-HcVisitTab $Tag.View }
        'finAsked'   { $script:HcAsked = $Tag.Text; Update-HcVisit }
        'workPreset' { [void](Add-HcWorkItem $Tag.Text $true); Update-HcVisit }
        'morePresets' { $f.AllPresets = $true; Update-HcFinishPanel }
        'workAdd'    { if (Add-HcWorkItem $w.WorkBox.Text $true) { Update-HcVisit; [void]$w.WorkBox.Focus() } }
        'workDone'   { $script:HcWork[$Tag.Index].Done = $Tag.Done; Update-HcVisit }
        'workRemove' { $script:HcWork.RemoveAt($Tag.Index); Update-HcVisit }
        'extraAdd'   {
            $text = "$($w.ExtraText.Children[1].Text)".Trim()
            $amount = ConvertTo-HcAmount $w.ExtraPrice.Children[1].Text
            if (-not $text -or $null -eq $amount) { $f.Notice = T 'win.fin.badPart'; Update-HcFinishPanel; return }
            [void]$f.Extras.Add([pscustomobject]@{ Description = $text; Amount = $amount })
            $f.Notice = $null
            Update-HcVisit
        }
        'extraRemove' { $f.Extras.RemoveAt($Tag.Index); Update-HcVisit }
        'pay'        { $f.Payment = $Tag.Method; Update-HcVisit }
        'clientTitle' { $f.Title = $Tag.Title; Update-HcVisit }
        'finMode'    {
            # A receipt has no paying later.
            if ($Tag.Mode -eq 'receipt' -and $f.Payment -eq 'transfer') { $f.Payment = 'pin' }
            if ($Tag.Mode -in @('invoice', 'receipt') -and -not $f.Settings) {
                $f.Mode = $Tag.Mode
                if (Test-HcUnlocked) { Start-HcSettingsLoad } else { $f.Stage = 'code' }
            } else {
                $f.Mode = $Tag.Mode
                # The note needs no code: leave the code slots for the note's form.
                if ($f.Mode -eq 'note' -and $f.Stage -in @('code', 'new')) { $f.Stage = 'form'; $w.Totp = $null }
            }
            $f.Notice = $null
            Update-HcVisit
        }
        'noteOnly'   { $f.Mode = 'note'; $f.Stage = 'form'; $w.Totp = $null; Update-HcVisit }
        'codeSubmit' { Submit-HcCode }
        'finMake'    { Start-HcMakeInvoice }
        'finPrint'   {
            if (-not $f.Pages) { Update-HcPreview }
            $script:HcInvoicePages = $f.Pages
            Invoke-HcInvoicePrint
        }
        'finPdf'     { Save-HcWindowPdf }
        'finMail'    { Request-HcMail }
        'mailYes'    { Send-HcMail }
        'mailNo'     { $f.MailAsk = $null; Update-HcFinishBar }
        'finDone'    { Complete-HcVisitWindow }
        'closeAnyway' { $w.CloseAnyway = $true; $w.Outcome = 'done'; $w.Window.Close() }
        'histDelete' { $w.Hist.Confirm = $Tag.Id; $w.Hist.Notice = $null; Update-HcOther }
        'histNo'     { $w.Hist.Confirm = $null; Update-HcOther }
        'histDoc'    { Open-HcKeptDoc $Tag.Id }
        'histYes'    {
            $visit = @($w.Hist.Visits | Where-Object { [long]$_.id -eq [long]$w.Hist.Confirm }) | Select-Object -First 1
            $w.Hist.Confirm = $null
            $w.Hist.Stage = 'loading'
            Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'visit_delete'; token = $script:HcToken; pc = (Get-HcWindowPcId); id = [long]$visit.id }
                         Visit = $visit; Done = 'Complete-HcHistoryDelete' }
            Update-HcOther
        }
    }
}

# Checks the form the way the text menu's window did, then lets the relay
# number and keep it, and saves the visit with it.
function Start-HcMakeInvoice {
    $w = $script:HcWin
    $f = $w.Fin
    $check = ConvertTo-HcInvoiceForm @{
        Name = (Format-HcClientName $f.Title $f.Name); Address = $f.Address; Postcode = $f.Postcode; Email = $f.Email
        Minutes = $f.Minutes; Callout = $f.Callout; Payment = $f.Payment
        Extras = @($f.Extras | ForEach-Object { [pscustomobject]@{ Description = $_.Description; Amount = ([decimal]$_.Amount).ToString([Globalization.CultureInfo]::InvariantCulture) } })
    } $f.Settings
    if ($check.Error) { $f.Notice = $check.Error; Update-HcFinishPanel; return }
    $f.Notice = $null
    $f.Stage = 'working'
    Add-HcJob @{ Kind = 'relay'; Body = (New-HcInvoiceBody $check.Form (Get-HcWindowPcId)); Done = 'Complete-HcInvoiceMade' }
    Update-HcVisit
}

function Complete-HcInvoiceMade {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $f = $w.Fin
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $code = if ($r) { $r.Error } else { 'unreachable' }
        if ($code -eq 'locked_out') { $script:HcToken = $null; $f.Stage = 'code'; $f.Notice = T 'relay.expired' }
        else { $f.Stage = 'form'; $f.Notice = T 'inv.failed' (Get-HcRelayMessage $code) }
        Update-HcVisit
        return
    }
    $f.Invoice = $r.Data.invoice
    $f.Stage = 'done'
    $w.CloseAsk = $false
    Add-HcJob @{ Kind = 'relay'; Body = (New-HcVisitBody $w.Environment ([string]$f.Invoice.client_name) ([string]$f.Invoice.number) (Get-HcWindowPcId)); Done = 'Complete-HcVisitSaved' }
    Update-HcVisit
}

function Complete-HcVisitSaved {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $f = $w.Fin
    $r = Get-HcRelayResult $Output
    if (-not $ErrorText -and $r -and $r.Ok) {
        $f.Saved = $true
        if ($r.Data.id) { $f.VisitId = [long]$r.Data.id }
        # A list read before this save lacks it: read it again when shown.
        if ($w.Hist.Stage -eq 'list') { $w.Hist.Stage = 'new' }
    }
    else { $f.Notice = T 'mem.notSaved' (Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' })) }
    if ($Job.ThenClose) {
        if (Test-HcDocWanted) { Start-HcDocSave; return }
        $w.Outcome = 'done'; $w.Finished = $true; $w.Window.Close(); return
    }
    Update-HcFinishBar
    Update-HcFinishPanel
}

# Klaar: with a note, the visit is still saved when the code was given.
function Complete-HcVisitWindow {
    $w = $script:HcWin
    $f = $w.Fin
    $worth = $script:HcVisit.Count -gt 0 -or $script:HcWork.Count -gt 0
    if (-not $f.Invoice -and -not $f.Saved -and $worth -and -not $script:DryRun -and $w.Environment.Online -and (Test-HcUnlocked)) {
        $f.Stage = 'working'
        $label = if ("$($f.Name)".Trim()) { Format-HcClientName $f.Title $f.Name } else { $script:HcKnownLabel }
        Add-HcJob @{ Kind = 'relay'; Body = (New-HcVisitBody $w.Environment $label $null (Get-HcWindowPcId)); ThenClose = $true; Done = 'Complete-HcVisitSaved' }
        Update-HcVisit
        return
    }
    if (Test-HcDocWanted) { Start-HcDocSave; return }
    $w.Outcome = 'done'
    $w.Finished = $true
    $w.Window.Close()
}

# "Factuur 2026-0005.pdf", "Betaalbewijs 2026-09-28.pdf" or "Briefje 2026-09-28.pdf".
function Get-HcPdfName {
    $f = $script:HcWin.Fin
    $today = Get-Date -Format 'yyyy-MM-dd'
    if ($f.Invoice) { return (T 'win.fin.pdfInvoice' $f.Invoice.number) }
    if ($f.Mode -eq 'receipt') { return (T 'win.fin.pdfReceipt' $today) }
    T 'win.fin.pdfNote' $today
}

# invoice, receipt or note: which document the visit ends with.
function Get-HcDocKind {
    $f = $script:HcWin.Fin
    if ($f.Invoice) { 'invoice' } elseif ($f.Mode -eq 'receipt') { 'receipt' } else { 'note' }
}

# The client's address for the mail: the one on the invoice, else the form's.
function Get-HcMailTo {
    $f = $script:HcWin.Fin
    $to = if ($f.Invoice -and $f.Invoice.client_email) { [string]$f.Invoice.client_email } else { "$($f.Email)".Trim() }
    if ($to -match '^[^\s@<>(),;:"\\]+@[^\s@<>(),;:"\\]+\.[a-zA-Z]{2,}$') { $to } else { $null }
}

# Mail naar klant: an address, the code (the relay sends it), then a Ja/Nee.
function Request-HcMail {
    $w = $script:HcWin
    $f = $w.Fin
    $f.MailResult = $null
    $to = Get-HcMailTo
    if (-not $to) { $f.MailResult = @{ Ok = $false; Text = (T 'win.mail.needAddress') }; Update-HcFinishBar; return }
    if (-not (Test-HcUnlocked)) {
        if ($f.Stage -eq 'form') { $f.Stage = 'code'; $f.Notice = T 'win.mail.needCode'; Update-HcVisit }
        else { $f.MailResult = @{ Ok = $false; Text = (T 'relay.expired') }; Update-HcFinishBar }
        return
    }
    $f.MailAsk = $to
    Update-HcFinishBar
}

# The page as a PDF (Windows' own PDF printer, into a temporary file that is
# gone straight after), then through the relay from Shamil's Outlook.
function Send-HcMail {
    $w = $script:HcWin
    $f = $w.Fin
    $to = $f.MailAsk
    $f.MailAsk = $null
    if (-not $f.Pages) { Update-HcPreview }
    # Printed by the worker, like the document at the end: the window stays
    # responsive while Windows' PDF printer works.
    Add-HcJob @{ Kind = 'pdf'; Body = @{ Pages = @($f.Pages) }; To = $to; Done = 'Complete-HcMailPdf' }
    $f.MailBusy = $true
    Update-HcFinishBar
}

function Complete-HcMailPdf {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $f = $script:HcWin.Fin
    $r = Get-HcPdfResult $Output
    if ($ErrorText -or -not $r -or -not $r.PdfBytes) {
        $why = if ($ErrorText) { $ErrorText } elseif ($r) { $r.PdfProblem } else { '' }
        $f.MailBusy = $false
        $f.MailResult = @{ Ok = $false; Text = (T 'win.fin.pdfFailed' "$why") }
        Update-HcFinishBar
        return
    }
    $to = $Job.To
    $kind = Get-HcDocKind
    $mail = New-HcMailText $kind $f.Title $f.Name (Get-Date) $(if ($f.Invoice) { [string]$f.Invoice.number } else { '' }) $f.Settings
    Add-HcJob @{ Kind = 'relay'; To = $to; Done = 'Complete-HcMailSent'; Body = @{
        action = 'mail_send'; token = $script:HcToken; to = $to; subject = $mail.Subject; text = $mail.Text
        pdf_base64 = [Convert]::ToBase64String($r.PdfBytes); filename = (Get-HcPdfName) } }
}

function Complete-HcMailSent {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $f = $script:HcWin.Fin
    $f.MailBusy = $false
    $r = Get-HcRelayResult $Output
    if (-not $ErrorText -and $r -and $r.Ok) { $f.MailResult = @{ Ok = $true; Text = (T 'win.mail.sent' $Job.To) } }
    else { $f.MailResult = @{ Ok = $false; Text = (Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' })) } }
    Update-HcFinishBar
}

# Opslaan als PDF: Windows' own PDF printer, to a file the client can get
# by email. Documents by default; the name says what it is.
function Save-HcWindowPdf {
    $w = $script:HcWin
    $f = $w.Fin
    if (-not $f.Pages) { Update-HcPreview }
    if (-not $f.Pages) { return }
    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Filter = 'PDF (*.pdf)|*.pdf'
    $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    $dialog.FileName = Get-HcPdfName
    if (-not $dialog.ShowDialog($w.Window)) { return }
    $script:HcInvoicePages = $f.Pages
    $problem = Save-HcPagesPdf $dialog.FileName
    $f.Notice = if ($problem) { T 'win.fin.pdfFailed' $problem } else { T 'win.fin.pdfSaved' $dialog.FileName }
    Update-HcFinishPanel
}

# --------------------------------------------------- the kept document --

# Klaar keeps the PDF the visit ended with in Shamil's own storage behind
# the relay (7 Oct): the invoice once it is made, else the receipt, else the
# note. It needs the code; a note without the code is not kept.
function Test-HcDocWanted {
    $w = $script:HcWin
    $f = $w.Fin
    if ($script:DryRun -or -not $w.Environment.Online -or -not (Test-HcUnlocked) -or $f.DocSaved -or $f.DocFailed) { return $false }
    switch (Get-HcDocKind) {
        'invoice' { return $true }
        'receipt' { return ([bool]$f.Settings -and (New-HcDraftInvoice $f $f.Settings).total -gt 0) }
        default   { return ($script:HcVisit.Count -gt 0 -or $script:HcWork.Count -gt 0) }
    }
}

# The pages of that document. An invoice that was never made is no
# document, so the visit then ends with the note.
function Get-HcDocPages {
    param([hashtable]$Fin, [string]$Kind)
    switch ($Kind) {
        'invoice' { @(Get-HcInvoiceLayout $Fin.Invoice) }
        'receipt' { @(Get-HcInvoiceLayout (New-HcDraftInvoice $Fin $Fin.Settings) -Receipt) }
        default   { @(Get-HcInvoiceLayout (New-HcDraftInvoice $Fin $Fin.Settings) -Note) }
    }
}

# What doc_save gets: the PDF and what it is about, for the overview.
function New-HcDocBody {
    param([hashtable]$Fin, [string]$Kind, [byte[]]$Pdf, [string]$PcId, [string]$Label)
    $total = $null; $payment = $null; $number = $null; $client = $Label
    if ($Kind -eq 'invoice') {
        $total = [double]$Fin.Invoice.total; $payment = [string]$Fin.Invoice.payment
        $number = [string]$Fin.Invoice.number; $client = [string]$Fin.Invoice.client_name
    } elseif ($Kind -eq 'receipt') {
        $total = [double](New-HcDraftInvoice $Fin $Fin.Settings).total; $payment = [string]$Fin.Payment
    }
    if ($client -and $client.Length -gt 100) { $client = $client.Substring(0, 100) }
    @{
        action = 'doc_save'; token = $script:HcToken; id = $Fin.DocId; pc = $PcId
        visit_id = $(if ($Fin.VisitId) { [long]$Fin.VisitId } else { $null })
        kind = $Kind; client_name = $(if ($client) { $client } else { $null }); invoice_number = $number
        total = $total; payment = $(if ($payment) { $payment } else { $null }); lang = $script:Lang
        pdf_base64 = [Convert]::ToBase64String($Pdf)
    }
}

function Start-HcDocSave {
    $w = $script:HcWin
    $f = $w.Fin
    $kind = Get-HcDocKind
    $f.StageBefore = $f.Stage
    try {
        $pages = @(Get-HcDocPages $f $kind)
    } catch {
        Complete-HcDocSaved @{} @() (T 'win.fin.pdfFailed' $_.Exception.Message) @()
        return
    }
    # The PDF is printed by the worker, so the window says it is busy rather
    # than freezing; Complete-HcDocPdf then sends it to the relay.
    $f.Stage = 'working'
    Add-HcJob @{ Kind = 'pdf'; Body = @{ Pages = $pages }; DocKind = $kind; Done = 'Complete-HcDocPdf' }
    Update-HcVisit
}

# The PDF a worker job printed, or why it could not.
function Get-HcPdfResult {
    param([object[]]$Output)
    @($Output | Where-Object { $_ -is [hashtable] -and ($_.ContainsKey('PdfBytes') -or $_.ContainsKey('PdfProblem')) }) | Select-Object -Last 1
}

function Complete-HcDocPdf {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $f = $script:HcWin.Fin
    $r = Get-HcPdfResult $Output
    if ($ErrorText -or -not $r -or -not $r.PdfBytes) {
        $why = if ($ErrorText) { $ErrorText } elseif ($r) { $r.PdfProblem } else { '' }
        Complete-HcDocSaved @{} @() (T 'win.fin.pdfFailed' "$why") @()
        return
    }
    $label = if ("$($f.Name)".Trim()) { Format-HcClientName $f.Title $f.Name } else { $script:HcKnownLabel }
    Add-HcJob @{ Kind = 'relay'; Body = (New-HcDocBody $f $Job.DocKind $r.PdfBytes (Get-HcWindowPcId) $label); Done = 'Complete-HcDocSaved' }
}

# Kept: the window closes. Not kept: it says so and stays open; Klaar again
# closes without trying again.
function Complete-HcDocSaved {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $f = $w.Fin
    $r = Get-HcRelayResult $Output
    if (-not $ErrorText -and $r -and $r.Ok) {
        $f.DocSaved = $true
        $w.Outcome = 'done'; $w.Finished = $true; $w.Window.Close()
        return
    }
    $f.DocFailed = $true
    $why = if ($ErrorText) { $ErrorText } else { Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' }) }
    $f.Notice = T 'doc.notKept' $why
    if ($f.StageBefore) { $f.Stage = $f.StageBefore }
    Update-HcVisit
}

# A kept PDF opened from the history: into the temporary folder, opened
# with the PDF viewer, and removed when Housecall closes (Remove-HcOpenedDocs).
function Open-HcKeptDoc {
    param([string]$Id)
    $h = $script:HcWin.Hist
    $h.Notice = T 'doc.opening'
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'doc_get'; token = $script:HcToken; id = $Id }; Done = 'Complete-HcKeptDoc' }
    Update-HcOther
}

function Complete-HcKeptDoc {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $h = $script:HcWin.Hist
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok -or -not $r.Data.pdf_base64) {
        $h.Notice = Get-HcRelayMessage $(if ($r -and $r.Error) { $r.Error } else { 'unreachable' })
        Update-HcOther
        return
    }
    $path = Join-Path $env:TEMP ('housecall-doc-' + [guid]::NewGuid().ToString('N') + '.pdf')
    try {
        [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String([string]$r.Data.pdf_base64))
        Start-Process -FilePath $path -ErrorAction Stop
        $h.Notice = $null
    } catch {
        $h.Notice = T 'doc.openFailed' $_.Exception.Message
    }
    Update-HcOther
}

function Remove-HcOpenedDocs {
    Get-ChildItem -Path $env:TEMP -Filter 'housecall-doc-*.pdf' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# "Betaalbewijs  EUR 32,50  pin": a kept document in one line.
function Format-HcDocLine {
    param($Doc)
    $parts = @(if ($Doc.kind -eq 'invoice' -and $Doc.invoice_number) { T 'mem.invoice' $Doc.invoice_number } else { T "doc.kind.$($Doc.kind)" })
    if ($null -ne $Doc.total -and "$($Doc.total)" -ne '') { $parts += Format-HcMoney ([decimal]$Doc.total) }
    if ($Doc.payment) { $parts += T "inv.pay.$($Doc.payment)" }
    $parts -join ('  ' + [char]0x00B7 + '  ')
}

# -------------------------------------------------------------- history --

function Start-HcHistory {
    $w = $script:HcWin
    $h = $w.Hist
    if (-not $w.Environment.Online) { $h.Stage = 'offline'; return }
    if ($h.Stage -in @('loading', 'list')) { return }
    if (Test-HcUnlocked) { Start-HcHistoryLoad } else { $h.Stage = 'code' }
}

function Start-HcHistoryLoad {
    $h = $script:HcWin.Hist
    $h.Stage = 'loading'
    Add-HcJob @{ Kind = 'relay'; Body = @{ action = 'visit_get'; token = $script:HcToken; pc = (Get-HcWindowPcId) }; Done = 'Complete-HcHistory' }
}

function Complete-HcHistory {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $h = $w.Hist
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $code = if ($r) { $r.Error } else { 'unreachable' }
        if ($code -eq 'locked_out') { $script:HcToken = $null; $h.Stage = 'code'; $h.Notice = T 'relay.expired' }
        else { $h.Stage = 'list'; $h.Visits = @(); $h.Notice = Get-HcRelayMessage $code }
    } else {
        $h.Visits = @($r.Data.visits | Where-Object { $_ })
        $h.Docs = @($r.Data.documents | Where-Object { $_ })
        $h.Stage = 'list'
        $label = @($h.Visits | Where-Object { $_.label } | Select-Object -First 1).label
        if ($label) {
            $script:HcKnownLabel = $label
            if (-not "$($w.Fin.Name)".Trim()) { $known = Split-HcClientName $label; $w.Fin.Title = $known.Title; $w.Fin.Name = $known.Name }
        }
    }
    Update-HcOther
}

function Complete-HcHistoryDelete {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $h = $script:HcWin.Hist
    $r = Get-HcRelayResult $Output
    if ($ErrorText -or -not $r -or -not $r.Ok) {
        $h.Notice = Get-HcRelayMessage $(if ($r) { $r.Error } else { 'unreachable' })
    } else {
        $h.Notice = T 'mem.deleted'
        if ($Job.Visit.invoice_number) { $h.Notice += ' ' + (T 'mem.invoiceKept' $Job.Visit.invoice_number) }
    }
    Start-HcHistoryLoad
    Update-HcOther
}

function Update-HcHistoryPanel {
    param($Panel)
    $w = $script:HcWin
    $h = $w.Hist
    $add = { param($element) [void]$Panel.Children.Add($element) }
    & $add (New-HcVisitToggle)
    & $add (New-HcText (T 'mem.title') 22 'Text' -Bold -Margin @(0, 4, 0, 10))
    if ($h.Notice) { & $add (New-HcText $h.Notice 14.5 'Ok' -Bold) }
    switch ($h.Stage) {
        'offline' { & $add (New-HcText (T 'win.hist.offline') 15 'Soft') }
        'code'    { & $add (New-HcCodeBox 'history' (T 'win.hist.codeIntro')) }
        'loading' {
            & $add (New-HcText (T 'win.fin.loading') 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.MaxWidth = 400
            $bar.HorizontalAlignment = 'Left'
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
        }
        'list' {
            if (@($h.Visits).Count -eq 0 -and @($h.Docs).Count -eq 0) { & $add (New-HcText (T 'mem.none') 15 'Soft'); return }
            foreach ($v in @($h.Visits)) {
                $card = New-Object Windows.Controls.StackPanel
                $head = New-Object Windows.Controls.DockPanel
                $delete = New-HcChip (T 'win.hist.delete') @{ Do = 'histDelete'; Id = [long]$v.id }
                [Windows.Controls.DockPanel]::SetDock($delete, 'Right')
                [void]$head.Children.Add($delete)
                $title = Format-HcVisitLine $v
                if ($v.label) { $title += '  ' + [char]0x00B7 + '  ' + $v.label }
                [void]$head.Children.Add((New-HcText $title 16 'Text' -Bold -Margin @(0, 4, 0, 4)))
                [void]$card.Children.Add($head)
                if ($v.invoice_number) { [void]$card.Children.Add((New-HcText (T 'mem.invoice' $v.invoice_number) 13.5 'Hi' -Bold -Margin @(0, 0, 0, 4))) }
                foreach ($p in @($v.problems)) { [void]$card.Children.Add((New-HcText ($p.code + '  ' + (T "problem.$($p.code)")) 14 'Soft' -Margin @(0, 0, 0, 2))) }
                foreach ($c in @($v.changes)) { [void]$card.Children.Add((New-HcLine 'ok' $c)) }
                foreach ($d in @($h.Docs | Where-Object { $_.visit_id -and [long]$_.visit_id -eq [long]$v.id })) { [void]$card.Children.Add((New-HcDocRow $d)) }
                if ($h.Confirm -eq [long]$v.id) {
                    [void]$card.Children.Add((New-HcQuestion (T 'win.hist.deleteAsk' (Format-HcVisitLine $v)) 'histYes' 'histNo'))
                }
                $box = New-HcBox '' @($card) 'Panel'
                $box.Padding = New-HcThickness @(16, 12, 12, 8)
                & $add $box
            }
            # Kept documents whose visit is not among these (an older one, or one never saved).
            $shown = @($h.Visits | ForEach-Object { [long]$_.id })
            $other = @($h.Docs | Where-Object { -not $_.visit_id -or [long]$_.visit_id -notin $shown })
            if ($other.Count) {
                $card = New-Object Windows.Controls.StackPanel
                [void]$card.Children.Add((New-HcText (T 'doc.other') 16 'Text' -Bold -Margin @(0, 4, 0, 4)))
                foreach ($d in $other) { [void]$card.Children.Add((New-HcDocRow $d -WithDate)) }
                $box = New-HcBox '' @($card) 'Panel'
                $box.Padding = New-HcThickness @(16, 12, 12, 8)
                & $add $box
            }
        }
    }
}

# One kept document in the history: what it is, and Openen.
function New-HcDocRow {
    param($Doc, [switch]$WithDate)
    $row = New-Object Windows.Controls.DockPanel
    $row.Margin = New-HcThickness @(0, 4, 0, 0)
    $open = New-HcChip (T 'doc.open') @{ Do = 'histDoc'; Id = [string]$Doc.id }
    [Windows.Controls.DockPanel]::SetDock($open, 'Right')
    [void]$row.Children.Add($open)
    $text = Format-HcDocLine $Doc
    if ($WithDate -and $Doc.created_at) {
        $when = Format-HcDate ([datetime]::Parse([string]$Doc.created_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime())
        $text = $when + '  ' + [char]0x00B7 + '  ' + $text
    }
    [void]$row.Children.Add((New-HcText $text 14 'Hi' -Bold -Margin @(0, 4, 0, 4)))
    $row
}
