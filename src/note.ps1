<#
    The client note: what they asked for help with, what was found, what was
    done, and how to reach you. It opens by itself when Housecall is closed
    (Q), in the client's language, in its own window with large text.

    Nothing is written to disk. Closing the window is the end of it; the
    Print button is how a client keeps a copy (Microsoft Print to PDF makes
    a PDF, for email).
#>

# Your contact details for the bottom of the note, one line each. Left
# empty, the "Questions?" part is simply not shown. This file is public on
# GitHub, so only details that may be public go here: decided 26 Sep, the
# email yes, the phone number no.
$script:Contact = @(
    'Shamil: shamilimanuel@outlook.com'
)

# The problems opened in this session, each with its latest finding (the
# one after any fixes). Filled by Invoke-HcProblem.
$script:HcVisit = New-Object System.Collections.ArrayList

# What Shamil did by hand, from the invoice window: Text, and Done ($true
# for fixed, $false for not fixed).
$script:HcWork = New-Object System.Collections.ArrayList

# The ready-made options for that list; any other text can be typed.
function Get-HcWorkPresets {
    @((T 'work.presets') -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Adds one item; $false when it is empty or already on the list.
function Add-HcWorkItem {
    param([string]$Text, [bool]$Done)
    $t = ("$Text" -replace '\s+', ' ').Trim()
    if (-not $t) { return $false }
    if ($t.Length -gt 150) { $t = $t.Substring(0, 150) }
    if (@($script:HcWork | Where-Object { $_.Text -eq $t }).Count) { return $false }
    [void]$script:HcWork.Add([pscustomobject]@{ Text = $t; Done = $Done })
    $true
}

# Everything done this visit for the history and the invoice: Housecall's
# fixes, then the hand-made list, with "Not fixed:" in front where needed.
function Get-HcVisitChanges {
    $all = @($script:HcChanges | ForEach-Object { $_.Label })
    $all += @($script:HcWork | ForEach-Object { if ($_.Done) { $_.Text } else { T 'note.notFixedItem' $_.Text } })
    @($all | Select-Object -First 30)
}

function Save-HcVisit {
    param([string]$Code, [pscustomobject]$Report)
    $entry = $script:HcVisit | Where-Object { $_.Code -eq $Code } | Select-Object -First 1
    if (-not $entry) {
        $entry = [pscustomobject]@{ Code = $Code; FindingId = $null; FindingArgs = @() }
        [void]$script:HcVisit.Add($entry)
    }
    $entry.FindingId = $Report.FindingId
    $entry.FindingArgs = @($Report.FindingArgs)
}

<#
    The note as a list of blocks, each with a Style (title, heading, text,
    small) and its Text. Pure, so it can be tested; the window and the
    printout both draw from it. Empty when no problem was opened.
#>
function Get-HcNoteBlocks {
    param([datetime]$Date = (Get-Date))
    if (@($script:HcVisit).Count -eq 0) { return @() }
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }

    & $block 'title' (T 'note.title' $Date.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture)))
    foreach ($b in @(Get-HcVisitBlocks)) { $b }

    if ($script:Contact) {
        & $block 'heading' (T 'note.contact')
        foreach ($line in @($script:Contact)) { & $block 'text' $line }
    }
    & $block 'small' (T 'note.footer')
}

# What the client asked, what was found and what was done: the middle of
# both the note and the invoice.
function Get-HcVisitBlocks {
    $visits = @($script:HcVisit)
    $block = { param($style, $text) [pscustomobject]@{ Style = $style; Text = $text } }
    & $block 'heading' (T 'note.asked')
    foreach ($v in $visits) { & $block 'text' (T "problem.$($v.Code)") }

    & $block 'heading' (T 'note.found')
    foreach ($v in $visits | Where-Object { $_.FindingId }) {
        $all = @('finding.' + $v.FindingId) + @($v.FindingArgs)
        & $block 'text' (T @all)
    }

    & $block 'heading' (T 'note.done')
    $changes = @($script:HcChanges)
    $fixed = @($script:HcWork | Where-Object { $_.Done })
    $open = @($script:HcWork | Where-Object { -not $_.Done })
    if ($changes.Count -eq 0 -and $fixed.Count -eq 0) {
        & $block 'text' (T 'note.nothingChanged')
    } else {
        foreach ($c in $changes) { & $block 'text' $c.Label }
        foreach ($w in $fixed) { & $block 'text' $w.Text }
    }
    if ($open.Count) {
        & $block 'heading' (T 'note.notFixed')
        foreach ($w in $open) { & $block 'text' $w.Text }
    }
}

function Show-HcNote {
    $blocks = @(Get-HcNoteBlocks)
    if ($blocks.Count -eq 0) { return }
    Show-HcDocument $blocks (T 'note.windowTitle')
}

# The note or the invoice: in its own window, or printed to the console when
# there is no one to look at a window.
function Show-HcDocument {
    param([object[]]$Blocks, [string]$Title)
    # A scripted run (the tests) prints the document instead of opening a window.
    if ($null -ne $script:HcInputQueue) {
        Write-Host ''
        foreach ($b in $Blocks) { Write-Host ('  [note] ' + $b.Text) }
        return
    }
    try {
        if ($script:NoConsole) { throw 'nobody to close a window' }
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
        Show-HcNoteWindow $Blocks $Title
    } catch {
        # No desktop to show a window on: show the document in the console.
        Write-Host ''
        foreach ($b in $Blocks) { Write-Host ('  ' + $b.Text) }
    }
}

function Show-HcNoteWindow {
    param([object[]]$Blocks, [string]$Title)
    [Windows.Forms.Application]::EnableVisualStyles()
    $family = 'Segoe UI'
    $script:HcNoteFonts = @{
        title   = New-Object Drawing.Font($family, 20, [Drawing.FontStyle]::Bold)
        heading = New-Object Drawing.Font($family, 14, [Drawing.FontStyle]::Bold)
        text    = New-Object Drawing.Font($family, 13)
        # The payment line under the total: normal text, with space above it.
        payment = New-Object Drawing.Font($family, 13)
        small   = New-Object Drawing.Font($family, 10, [Drawing.FontStyle]::Italic)
        # Money rows: a fixed-width font keeps the amounts in one column.
        row     = New-Object Drawing.Font('Consolas', 11)
        rowBold = New-Object Drawing.Font('Consolas', 11, [Drawing.FontStyle]::Bold)
    }
    $script:HcNoteBlocks = $Blocks

    $form = New-Object Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object Drawing.Size(680, 760)
    $form.MinimumSize = New-Object Drawing.Size(480, 400)
    $form.BackColor = [Drawing.Color]::White
    $form.TopMost = $true          # in front of the console, once
    $form.Add_Shown({ $this.Activate(); $this.TopMost = $false })

    $box = New-Object Windows.Forms.RichTextBox
    $box.Dock = 'Fill'
    $box.ReadOnly = $true
    $box.BorderStyle = 'None'
    $box.BackColor = [Drawing.Color]::White
    $box.DetectUrls = $false
    $box.Cursor = [Windows.Forms.Cursors]::Default
    foreach ($b in $Blocks) {
        $box.SelectionStart = $box.TextLength
        $box.SelectionFont = $script:HcNoteFonts[$b.Style]
        $box.SelectionColor = if ($b.Style -eq 'small') { [Drawing.Color]::DimGray } else { [Drawing.Color]::Black }
        $gap = if ($b.Style -in @('heading', 'small', 'payment')) { "`n" } else { '' }
        $box.AppendText($gap + $b.Text + "`n")
    }

    $inner = New-Object Windows.Forms.Panel
    $inner.Dock = 'Fill'
    $inner.Padding = New-Object Windows.Forms.Padding(32, 24, 32, 8)
    $inner.Controls.Add($box)

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Bottom'
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.Height = 72
    $buttons.Padding = New-Object Windows.Forms.Padding(24, 12, 24, 12)
    $buttons.BackColor = [Drawing.Color]::FromArgb(243, 244, 246)

    $close = New-Object Windows.Forms.Button
    $close.Text = T 'note.close'
    $close.Size = New-Object Drawing.Size(150, 44)
    $close.Font = New-Object Drawing.Font($family, 12)
    $close.BackColor = [Drawing.Color]::White; $close.ForeColor = [Drawing.Color]::Black
    $close.Add_Click({ $this.FindForm().Close() })
    $form.CancelButton = $close

    $print = New-Object Windows.Forms.Button
    $print.Text = T 'note.print'
    $print.Size = New-Object Drawing.Size(150, 44)
    $print.Font = New-Object Drawing.Font($family, 12)
    $print.BackColor = [Drawing.Color]::White; $print.ForeColor = [Drawing.Color]::Black
    $print.Add_Click({ Invoke-HcNotePrint })

    $buttons.Controls.Add($close)
    $buttons.Controls.Add($print)
    $form.Controls.Add($inner)
    $form.Controls.Add($buttons)
    $form.ActiveControl = $close     # no blinking text cursor in the note
    [void]$form.ShowDialog()
    $form.Dispose()
}

# Prints the note's blocks, continuing on a new page when one is full.
function Invoke-HcNotePrint {
    $doc = New-Object Drawing.Printing.PrintDocument
    $doc.DocumentName = 'Housecall'
    $script:HcNotePrintAt = 0
    $doc.Add_PrintPage({
        param($sender, $e)
        $area = $e.MarginBounds
        $y = [single]$area.Top
        while ($script:HcNotePrintAt -lt $script:HcNoteBlocks.Count) {
            $b = $script:HcNoteBlocks[$script:HcNotePrintAt]
            $font = $script:HcNoteFonts[$b.Style]
            if ($b.Style -in @('heading', 'small', 'payment')) { $y += $font.GetHeight($e.Graphics) * 0.6 }
            $size = $e.Graphics.MeasureString($b.Text, $font, $area.Width)
            if ($y + $size.Height -gt $area.Bottom -and $y -gt $area.Top) { $e.HasMorePages = $true; return }
            $rect = New-Object Drawing.RectangleF([single]$area.Left, $y, [single]$area.Width, $size.Height)
            $e.Graphics.DrawString($b.Text, $font, [Drawing.Brushes]::Black, $rect)
            $y += $size.Height + 4
            $script:HcNotePrintAt++
        }
        $e.HasMorePages = $false
    })
    $dialog = New-Object Windows.Forms.PrintDialog
    $dialog.Document = $doc
    $dialog.UseEXDialog = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        try { $doc.Print() } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Housecall') }
    }
    $doc.Dispose()
}
