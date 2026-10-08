<#
    Overzicht: every PDF a visit ended with (invoice, receipt, note), kept by
    the relay since 7 Oct 2026, per month with the totals. For Shamil's own
    PC only: it shows every client, so never on a client's PC.

        housecall -Overzicht
        powershell -ExecutionPolicy Bypass -File tools\overview.ps1

    The window asks for the Google Authenticator code, lists the documents,
    opens one as a PDF (a copy in %TEMP%\Housecall-overzicht, emptied each
    start) and saves the list as a CSV for the administration.

    The pure parts (months, totals, CSV rows) are tested from
    tests\Housecall.Tests.ps1, which dot-sources this file; the window only
    opens when the file is run.
#>
param([switch]$NoWindow)

$script:OverviewRelay = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'
$script:OverviewNl = [Globalization.CultureInfo]::GetCultureInfo('nl-NL')
$script:Euro = [string][char]0x20AC
$script:OverviewKinds = @{ invoice = 'Factuur'; receipt = 'Betaalbewijs'; note = 'Briefje' }
$script:OverviewPay = @{ pin = 'pin'; cash = 'contant'; transfer = 'overmaken'; tikkie = 'betaalverzoek' }

# ------------------------------------------------------------ pure parts --

function Format-HcOverviewMoney {
    param([decimal]$Amount)
    $script:Euro + ' ' + $Amount.ToString('N2', $script:OverviewNl)
}

# "Factuur 2026-0003", "Betaalbewijs", "Briefje".
function Get-HcOverviewKind {
    param($Doc)
    $name = $script:OverviewKinds["$($Doc.kind)"]
    if (-not $name) { $name = "$($Doc.kind)" }
    if ($Doc.kind -eq 'invoice' -and $Doc.invoice_number) { $name += " $($Doc.invoice_number)" }
    $name
}

# The documents (newest first, as doc_list gives them) per month, each
# month with its total: invoices and receipts count, a note has no amount.
function ConvertTo-HcOverviewMonths {
    param([object[]]$Documents)
    $months = [ordered]@{}
    foreach ($d in @($Documents | Where-Object { $_ })) {
        $when = [datetime]::Parse([string]$d.created_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal).ToLocalTime()
        $key = $when.ToString('yyyy-MM')
        if (-not $months.Contains($key)) {
            $title = $when.ToString('MMMM yyyy', $script:OverviewNl)
            $months[$key] = [pscustomobject]@{ Key = $key; Title = ($title.Substring(0, 1).ToUpper() + $title.Substring(1)); Total = [decimal]0; Rows = New-Object System.Collections.ArrayList }
        }
        $m = $months[$key]
        $amount = $null
        if ($d.kind -in @('invoice', 'receipt') -and $null -ne $d.total -and "$($d.total)" -ne '') {
            $amount = [decimal]::Parse("$($d.total)", [Globalization.CultureInfo]::InvariantCulture)
            $m.Total += $amount
        }
        [void]$m.Rows.Add([pscustomobject]@{
            Id = [string]$d.id; When = $when; Kind = (Get-HcOverviewKind $d); Client = [string]$d.client_name
            Amount = $amount; Payment = $(if ($d.payment) { $script:OverviewPay["$($d.payment)"] } else { '' })
        })
    }
    @($months.Values)
}

# One CSV row per document, in Dutch notation for Excel (semicolons).
function ConvertTo-HcOverviewCsv {
    param([object[]]$Months)
    $lines = @('Datum;Soort;Klant;Bedrag;Betaling')
    foreach ($m in @($Months)) {
        foreach ($r in @($m.Rows)) {
            $amount = if ($null -ne $r.Amount) { ([decimal]$r.Amount).ToString('0.00', $script:OverviewNl) } else { '' }
            $cells = @($r.When.ToString('yyyy-MM-dd'), $r.Kind, $r.Client, $amount, $r.Payment) | ForEach-Object {
                $c = "$_"
                if ($c -match '[;"\r\n]') { '"' + $c.Replace('"', '""') + '"' } else { $c }
            }
            $lines += ($cells -join ';')
        }
    }
    $lines
}

# A file name for an opened PDF: "Betaalbewijs 2026-10-07 Mevr. de Vries.pdf".
function Get-HcOverviewFileName {
    param($Row)
    $name = "$($Row.Kind) $($Row.When.ToString('yyyy-MM-dd')) $($Row.Client)".Trim()
    ($name -replace '[\\/:*?"<>|]', '') + '.pdf'
}

# -------------------------------------------------------------- relay --

function Invoke-HcOverviewRelay {
    param([hashtable]$Body)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 10 -Compress))
    try {
        $r = Invoke-WebRequest -Uri $script:OverviewRelay -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 60
        $reader = New-Object IO.StreamReader($r.RawContentStream, [Text.Encoding]::UTF8)
        return ($reader.ReadToEnd() | ConvertFrom-Json)
    } catch {
        $response = $_.Exception.Response
        if ($response) {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
            return ($reader.ReadToEnd() | ConvertFrom-Json)
        }
        return [pscustomobject]@{ error = 'unreachable' }
    }
}

function Get-HcOverviewError {
    param([string]$Code)
    switch ($Code) {
        'wrong_code'  { 'Die code klopt niet. Wacht op de volgende en probeer opnieuw.' }
        'code_used'   { 'Die code is al gebruikt. Wacht op de volgende.' }
        'locked'      { 'Te vaak een verkeerde code. Probeer het over een kwartier opnieuw.' }
        'locked_out'  { 'De sessie is verlopen. Vul een nieuwe code in.' }
        'unreachable' { 'De relay is niet bereikbaar. Is er internet?' }
        'not_found'   { 'Dat document staat niet meer in de opslag.' }
        default       { "De relay gaf een fout: $Code" }
    }
}

# -------------------------------------------------------------- window --

function Show-HcOverview {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $tempDir = Join-Path $env:TEMP 'Housecall-overzicht'
    if (Test-Path -LiteralPath $tempDir) { Get-ChildItem -LiteralPath $tempDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    else { [void](New-Item -ItemType Directory -Path $tempDir) }

    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Housecall - Overzicht" Width="900" Height="720" MinWidth="560" MinHeight="420"
        WindowStartupLocation="CenterScreen" Background="#FFF8F0" FontFamily="Segoe UI" FontSize="14">
  <Window.Resources>
    <Style x:Key="Chip" TargetType="Button">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="Foreground" Value="#16323F"/>
      <Setter Property="BorderBrush" Value="#E7DCCD"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="BorderBrush" Value="#E8862E"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter Property="BorderBrush" Value="#E8862E"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel>
    <Border DockPanel.Dock="Top" Background="#1D4E63" Padding="20,12">
      <DockPanel>
        <Button x:Name="CsvButton" DockPanel.Dock="Right" Style="{StaticResource Chip}" Content="Opslaan als CSV" IsEnabled="False"/>
        <TextBlock Text="Bewaarde documenten" Foreground="#FFFFFF" FontFamily="Georgia" FontSize="22" FontWeight="Bold" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>
    <TextBlock x:Name="Status" DockPanel.Dock="Top" Margin="22,12,22,0" TextWrapping="Wrap" Foreground="#5C6B72" FontSize="14"/>
    <StackPanel x:Name="CodePanel" DockPanel.Dock="Top" Margin="22,16,22,0" Orientation="Horizontal">
      <TextBlock Text="Code uit Google Authenticator" VerticalAlignment="Center" Foreground="#16323F" FontWeight="SemiBold" Margin="0,0,12,0"/>
      <TextBox x:Name="CodeBox" Width="120" FontSize="20" MaxLength="6" Padding="6,3" FontFamily="Consolas" VerticalContentAlignment="Center"/>
      <Button x:Name="UnlockButton" Style="{StaticResource Chip}" Content="Ontgrendelen" Margin="10,0,0,0" IsDefault="True"/>
    </StackPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,12,0,0">
      <StackPanel x:Name="Months" Margin="22,0,22,22"/>
    </ScrollViewer>
  </DockPanel>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $ui = @{}
    foreach ($n in 'CsvButton', 'Status', 'CodePanel', 'CodeBox', 'UnlockButton', 'Months') { $ui[$n] = $window.FindName($n) }
    $state = @{ Token = $null; Months = @() }
    $brush = { param($hex) (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
    $thick = { param($l, $t, $r, $b) New-Object Windows.Thickness($l, $t, $r, $b) }
    # The status shows before a relay call blocks the window for a moment.
    $setStatus = { param([string]$Text) $ui.Status.Text = $Text; $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }

    $openDoc = {
        param($Row)
        $window.Cursor = [Windows.Input.Cursors]::Wait
        & $setStatus 'De PDF wordt opgehaald...'
        try {
            $r = Invoke-HcOverviewRelay @{ action = 'doc_get'; token = $state.Token; id = $Row.Id }
            if (-not $r.pdf_base64) { & $setStatus (Get-HcOverviewError $(if ($r.error) { $r.error } else { 'unreachable' })); return }
            $path = Join-Path $tempDir (Get-HcOverviewFileName $Row)
            [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String([string]$r.pdf_base64))
            Start-Process -FilePath $path
            & $setStatus "Geopend: $(Split-Path -Leaf $path)"
        } catch {
            & $setStatus "De PDF kon niet worden geopend: $($_.Exception.Message)"
        } finally { $window.Cursor = $null }
    }

    $render = {
        $ui.Months.Children.Clear()
        if (-not @($state.Months).Count) {
            $empty = New-Object Windows.Controls.TextBlock
            $empty.Text = 'Nog geen bewaarde documenten. Ze komen hier zodra een bezoek met Klaar wordt afgerond.'
            $empty.TextWrapping = 'Wrap'; $empty.Foreground = & $brush '#5C6B72'; $empty.Margin = & $thick 0 8 0 0
            [void]$ui.Months.Children.Add($empty)
            return
        }
        foreach ($m in $state.Months) {
            $card = New-Object Windows.Controls.Border
            $card.BorderBrush = & $brush '#E7DCCD'; $card.BorderThickness = & $thick 1 1 1 1; $card.CornerRadius = New-Object Windows.CornerRadius(10)
            $card.Background = & $brush '#FFFFFF'; $card.Margin = & $thick 0 0 0 14
            $stack = New-Object Windows.Controls.StackPanel
            $head = New-Object Windows.Controls.DockPanel
            $head.Background = & $brush '#F6EEE3'
            $total = New-Object Windows.Controls.TextBlock
            $total.Text = Format-HcOverviewMoney $m.Total; $total.Foreground = & $brush '#16323F'; $total.FontWeight = [Windows.FontWeights]::Bold; $total.FontSize = 15; $total.Margin = & $thick 0 10 16 10
            [Windows.Controls.DockPanel]::SetDock($total, 'Right')
            [void]$head.Children.Add($total)
            $title = New-Object Windows.Controls.TextBlock
            $title.Text = $m.Title; $title.FontFamily = New-Object Windows.Media.FontFamily('Georgia'); $title.FontSize = 17; $title.FontWeight = [Windows.FontWeights]::Bold; $title.Margin = & $thick 16 9 0 9
            $title.Foreground = & $brush '#16323F'
            [void]$head.Children.Add($title)
            [void]$stack.Children.Add($head)
            foreach ($row in $m.Rows) {
                $grid = New-Object Windows.Controls.Grid
                $grid.Margin = & $thick 16 0 12 0
                foreach ($w in @(70, 170, '*', 100, 120, 90)) {
                    $col = New-Object Windows.Controls.ColumnDefinition
                    $col.Width = if ($w -eq '*') { New-Object Windows.GridLength(1, 'Star') } else { New-Object Windows.GridLength($w) }
                    [void]$grid.ColumnDefinitions.Add($col)
                }
                $cells = @(
                    @{ Text = $row.When.ToString('d MMM', $script:OverviewNl); Color = '#5C6B72'; Bold = $false; Right = $false }
                    @{ Text = $row.Kind; Color = '#1D4E63'; Bold = $true; Right = $false }
                    @{ Text = $row.Client; Color = '#16323F'; Bold = $false; Right = $false }
                    @{ Text = $(if ($null -ne $row.Amount) { Format-HcOverviewMoney $row.Amount } else { '' }); Color = '#16323F'; Bold = $true; Right = $true }
                    @{ Text = $row.Payment; Color = '#5C6B72'; Bold = $false; Right = $false }
                )
                for ($i = 0; $i -lt $cells.Count; $i++) {
                    $t = New-Object Windows.Controls.TextBlock
                    $t.Text = $cells[$i].Text; $t.Foreground = & $brush $cells[$i].Color; $t.VerticalAlignment = 'Center'
                    $t.TextTrimming = 'CharacterEllipsis'; $t.Margin = $(if ($cells[$i].Right) { & $thick 0 0 14 0 } else { & $thick 0 0 8 0 })
                    if ($cells[$i].Bold) { $t.FontWeight = [Windows.FontWeights]::SemiBold }
                    if ($cells[$i].Right) { $t.HorizontalAlignment = 'Right' }
                    [Windows.Controls.Grid]::SetColumn($t, $i)
                    [void]$grid.Children.Add($t)
                }
                $open = New-Object Windows.Controls.Button
                $open.Content = 'Openen'; $open.Style = $window.FindResource('Chip'); $open.Margin = & $thick 0 7 0 7; $open.Tag = $row
                $open.Add_Click({ param($sender) & $openDoc $sender.Tag })
                [Windows.Controls.Grid]::SetColumn($open, 5)
                [void]$grid.Children.Add($open)
                $line = New-Object Windows.Controls.Border
                $line.BorderBrush = & $brush '#E7DCCD'; $line.BorderThickness = & $thick 0 1 0 0; $line.Child = $grid
                [void]$stack.Children.Add($line)
            }
            $card.Child = $stack
            [void]$ui.Months.Children.Add($card)
        }
    }

    $load = {
        & $setStatus 'De documenten worden opgehaald...'
        $r = Invoke-HcOverviewRelay @{ action = 'doc_list'; token = $state.Token }
        if ($r.error) {
            if ($r.error -eq 'locked_out') { $state.Token = $null; $ui.CodePanel.Visibility = 'Visible' }
            & $setStatus (Get-HcOverviewError $r.error)
            return
        }
        $state.Months = @(ConvertTo-HcOverviewMonths @($r.documents))
        $count = @($r.documents | Where-Object { $_ }).Count
        & $setStatus $(if ($count -eq 1) { '1 document.' } else { "$count documenten." })
        $ui.CsvButton.IsEnabled = $count -gt 0
        & $render
    }

    $ui.UnlockButton.Add_Click({
        $code = "$($ui.CodeBox.Text)".Trim()
        if ($code -notmatch '^\d{6}$') { & $setStatus 'Vul de 6 cijfers uit Google Authenticator in.'; return }
        $window.Cursor = [Windows.Input.Cursors]::Wait
        try {
            $r = Invoke-HcOverviewRelay @{ action = 'unlock'; code = $code }
            if (-not $r.token) { & $setStatus (Get-HcOverviewError $(if ($r.error) { $r.error } else { 'unreachable' })); return }
            $state.Token = $r.token
            $ui.CodeBox.Text = ''
            $ui.CodePanel.Visibility = 'Collapsed'
            & $load
        } finally { $window.Cursor = $null }
    })

    $ui.CsvButton.Add_Click({
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Filter = 'CSV (*.csv)|*.csv'
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
        $dialog.FileName = "Housecall overzicht $(Get-Date -Format 'yyyy-MM-dd').csv"
        if (-not $dialog.ShowDialog($window)) { return }
        try {
            # UTF-8 with a BOM, so Excel shows the euro sign and accents right.
            [IO.File]::WriteAllLines($dialog.FileName, [string[]](ConvertTo-HcOverviewCsv $state.Months), (New-Object Text.UTF8Encoding $true))
            & $setStatus "Opgeslagen: $($dialog.FileName)"
        } catch { & $setStatus "Opslaan lukte niet: $($_.Exception.Message)" }
    })

    & $setStatus 'Alleen op je eigen pc: dit overzicht toont alle klanten.'
    $window.Add_ContentRendered({ [void]$ui.CodeBox.Focus() })
    [void]$window.ShowDialog()
    Get-ChildItem -LiteralPath $tempDir -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

if (-not $NoWindow -and $MyInvocation.InvocationName -ne '.') { Show-HcOverview }
