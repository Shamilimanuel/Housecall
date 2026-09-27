<#
    Housecall as a window (phase 6): tabs across the top, the problem areas
    as groups, and the result with its fixes on the right. Only the front is
    new: every check, fix and undo is the code the text menu uses.

    The checks run in a second runspace (the worker) that loads Housecall's
    own source, so the window keeps responding while D1 takes ten seconds.
    What the visit remembers (the changes, the note) stays here; the worker
    only reads the PC and applies the one fix it is handed. Jobs run one at
    a time, from a queue that a timer on the window works through.

    Show-HcWindow returns what comes next: 'quit' (the note or invoice, as
    with Q), 'console' (carry on in the text menu), 'handedoff' (a new
    administrator window took over) or 'failed' (no window possible here).
#>

$script:HcWin = $null

# Light is the brand; dark looks like WinUtil. Each key is one of the
# window's brushes, so switching repaints everything at once.
$script:HcThemes = @{
    light = @{ Bg = '#FFF8F0'; Panel = '#FFFFFF'; Side = '#F3EBE0'; Line = '#E6DCCF'; Text = '#16323F'; Soft = '#5D6F78'
               Hi = '#E8862E'; HiSoft = '#FDE9D4'; Ok = '#2E7D4F'; Bad = '#B3401F'; Warn = '#A86A12'
               TabBar = '#16323F'; TabText = '#D9E4EA'; PrimaryBg = '#C96A1E'; PrimaryText = '#FFFFFF' }
    dark  = @{ Bg = '#14232B'; Panel = '#1B2E38'; Side = '#11202A'; Line = '#27404D'; Text = '#E9F0F3'; Soft = '#9FB4BF'
               Hi = '#F0953F'; HiSoft = '#3A2A1C'; Ok = '#6FD59A'; Bad = '#FF8A73'; Warn = '#F2C066'
               TabBar = '#0C181F'; TabText = '#BCD0DA'; PrimaryBg = '#F0953F'; PrimaryText = '#14232B' }
}

$script:HcTabs = @('problems', 'safety', 'visit', 'pc', 'ai')

# ------------------------------------------------------------ pure parts --

# The worst line of a report: problem, warn or ok. Colours a row in
# "Alles controleren".
function Get-HcReportLevel {
    param([pscustomobject]$Report)
    $statuses = @($Report.Results | ForEach-Object { $_.Status })
    if ($statuses -contains 'problem') { 'problem' } elseif ($statuses -contains 'warn') { 'warn' } else { 'ok' }
}

# What "Alles controleren" runs: every problem, except the two that need a
# typed address (A3, A4), and F1/F2, which F3 already covers.
function Get-HcCheckAllCodes {
    @($script:Areas.Values | ForEach-Object { $_ } | Where-Object { $_ -notin @('A3', 'A4', 'F1', 'F2') })
}

# The theme Windows itself uses for apps, so the window matches the PC.
function Get-HcDefaultTheme {
    $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme
    if ($light -eq 0) { 'dark' } else { 'light' }
}

# A window needs a desktop, WPF, the STA thread WPF runs on (powershell.exe
# 5.1 has one), and Housecall's source for the worker. A scripted run never
# gets one.
function Test-HcWindowPossible {
    if ($null -ne $script:HcInputQueue -or $script:NoConsole) { return $false }
    if (-not [Environment]::UserInteractive -or -not $script:HcSource) { return $false }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { return $false }
    try {
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
        $true
    } catch { $false }
}

# ------------------------------------------------------------ the worker --

# Runs in the worker runspace. 'load' puts Housecall's source there once;
# every other kind sets the language and rights first, since the worker
# has its own copy of those.
$script:HcWorkerScript = {
    param($Kind, $Lang, $IsAdmin, $DryRun, $Code, $Text, $FixId, $Target, $Source)
    $ErrorActionPreference = 'Stop'
    if ($Kind -eq 'load') { . ([scriptblock]::Create($Source)); return }
    $script:Lang = $Lang
    $script:IsAdmin = $IsAdmin
    $script:DryRun = $DryRun
    switch ($Kind) {
        'check' {
            $check = switch ($Code) {
                'A3'    { New-HcSiteCheck (ConvertTo-HcHostName $Text) }
                'A4'    { New-HcMailCheck (ConvertTo-HcMailDomain $Text) }
                default { & $script:ProblemHandlers[$Code] }
            }
            & $check
        }
        'fix' {
            $fix = $script:Fixes[$FixId]
            if ($fix.Admin) { New-HcRestorePoint }
            & $fix.Apply $Target
        }
        'undo'   { & $script:Fixes[$FixId].Undo $Target }
        'online' { Test-HcOnline }
    }
}.ToString()

# Queues a job. $Done names the function that gets the job, its output,
# an error message (or $null) and any lines the worker wrote.
function Add-HcJob {
    param([hashtable]$Job)
    [void]$script:HcWin.Queue.Add($Job)
}

function Start-HcJob {
    param([hashtable]$Job)
    $w = $script:HcWin
    $ps = [powershell]::Create()
    $ps.Runspace = $w.Runspace
    [void]$ps.AddScript($script:HcWorkerScript)
    $parameters = @{
        Kind = $Job.Kind; Lang = $script:Lang; IsAdmin = [bool]$script:IsAdmin; DryRun = [bool]$script:DryRun
        Code = $Job.Code; Text = $Job.Text; FixId = $Job.FixId; Target = $Job.Target; Source = $Job.Source
    }
    foreach ($name in $parameters.Keys) { [void]$ps.AddParameter($name, $parameters[$name]) }
    $Job.PS = $ps
    $Job.Async = $ps.BeginInvoke()
    $w.Job = $Job
}

# The window's timer: collects a finished job and starts the next one.
function Invoke-HcTick {
    $w = $script:HcWin
    try {
        if ($w.Job) {
            if (-not $w.Job.Async.IsCompleted) { return }
            $job = $w.Job
            $w.Job = $null
            $out = @()
            $err = $null
            try {
                $out = @($job.PS.EndInvoke($job.Async))
            } catch {
                $e = $_.Exception
                while ($e.InnerException) { $e = $e.InnerException }
                $err = $e.Message
            }
            $info = @($job.PS.Streams.Information | ForEach-Object { "$($_.MessageData)".Trim() } | Where-Object { $_ })
            $job.PS.Dispose()
            & $job.Done $job $out $err $info
        }
        if (-not $w.Job -and $w.Queue.Count -gt 0) {
            $next = $w.Queue[0]
            $w.Queue.RemoveAt(0)
            Start-HcJob $next
            Update-HcSide
        } elseif (-not $w.Job -and $w.WasBusy) {
            Update-HcSide
            Update-HcGroups
        }
        $w.WasBusy = [bool]($w.Job -or $w.Queue.Count)
    } catch {
        $w.Notice = T 'win.error' $_.Exception.Message
        Update-HcResult
    }
}

function Test-HcBusy { [bool]($script:HcWin.Job -or $script:HcWin.Queue.Count) }

# ------------------------------------------------------------ the window --

function New-HcWindowXaml {
    @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Housecall" Width="1180" Height="780" MinWidth="860" MinHeight="520"
        WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" FontSize="15"
        Background="{DynamicResource Bg}" UseLayoutRounding="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg" Color="#FFF8F0"/>
    <SolidColorBrush x:Key="Panel" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Side" Color="#F3EBE0"/>
    <SolidColorBrush x:Key="Line" Color="#E6DCCF"/>
    <SolidColorBrush x:Key="Text" Color="#16323F"/>
    <SolidColorBrush x:Key="Soft" Color="#5D6F78"/>
    <SolidColorBrush x:Key="Hi" Color="#E8862E"/>
    <SolidColorBrush x:Key="HiSoft" Color="#FDE9D4"/>
    <SolidColorBrush x:Key="Ok" Color="#2E7D4F"/>
    <SolidColorBrush x:Key="Bad" Color="#B3401F"/>
    <SolidColorBrush x:Key="Warn" Color="#A86A12"/>
    <SolidColorBrush x:Key="TabBar" Color="#16323F"/>
    <SolidColorBrush x:Key="TabText" Color="#D9E4EA"/>
    <SolidColorBrush x:Key="PrimaryBg" Color="#C96A1E"/>
    <SolidColorBrush x:Key="PrimaryText" Color="#FFFFFF"/>

    <Style x:Key="HcButton" TargetType="{x:Type Button}">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Background" Value="{DynamicResource Panel}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="Box" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Hi}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Hi}"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HcPrimary" TargetType="{x:Type Button}" BasedOn="{StaticResource HcButton}">
      <Setter Property="Background" Value="{DynamicResource PrimaryBg}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource PrimaryBg}"/>
      <Setter Property="Foreground" Value="{DynamicResource PrimaryText}"/>
      <Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style x:Key="HcGroup" TargetType="{x:Type Button}" BasedOn="{StaticResource HcButton}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="FontSize" Value="17"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Padding" Value="4,10"/>
      <Setter Property="Margin" Value="0"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    </Style>
    <Style x:Key="HcTab" TargetType="{x:Type Button}">
      <Setter Property="Foreground" Value="{DynamicResource TabText}"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="Box" Background="{TemplateBinding Background}" CornerRadius="8,8,0,0" Padding="16,9,16,10">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HcTabOn" TargetType="{x:Type Button}" BasedOn="{StaticResource HcTab}">
      <Setter Property="Background" Value="{DynamicResource Bg}"/>
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    </Style>
    <Style x:Key="HcPill" TargetType="{x:Type Button}">
      <Setter Property="Foreground" Value="{DynamicResource TabText}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="8,0,0,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="{x:Type Button}">
            <Border x:Name="Box" Background="Transparent" BorderBrush="#55FFFFFF" BorderThickness="1" CornerRadius="13" Padding="10,3">
              <ContentPresenter VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Hi}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Background="{DynamicResource Bg}">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border Background="{DynamicResource TabBar}" Padding="14,8,14,0">
      <DockPanel LastChildFill="False">
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" Margin="0,0,18,8" VerticalAlignment="Center">
          <Viewbox Width="30" Height="30">
            <Canvas Width="64" Height="64">
              <Path Data="M6,33 L28,14 L50,33" Stroke="#FFFFFF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              <Path Data="M13,31 V54 A3,3 0 0 0 16,57 H40 A3,3 0 0 0 43,54 V31" Stroke="#FFFFFF" StrokeThickness="6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              <Rectangle Canvas.Left="23" Canvas.Top="41" Width="10" Height="16" RadiusX="2" RadiusY="2" Fill="#FFFFFF"/>
              <Path Data="M46,16 A8,8 0 0 1 52,22" Stroke="#E8862E" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
              <Path Data="M47,7.5 A16,16 0 0 1 60.5,21" Stroke="#E8862E" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
            </Canvas>
          </Viewbox>
          <TextBlock Text="Housecall" FontFamily="Georgia" FontSize="22" FontWeight="Bold" Foreground="#FFFFFF" Margin="10,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel x:Name="Tabs" DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Bottom"/>
        <StackPanel x:Name="Status" DockPanel.Dock="Right" Orientation="Horizontal" Margin="0,0,0,8" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>

    <Grid Grid.Row="1" x:Name="ProblemsTab">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="236"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="380"/>
      </Grid.ColumnDefinitions>
      <Border Background="{DynamicResource Side}" BorderBrush="{DynamicResource Line}" BorderThickness="0,0,1,0">
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="SidePanel" Margin="16,14,16,14"/></ScrollViewer>
      </Border>
      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="GroupsPanel" Margin="18,10,18,18"/></ScrollViewer>
      <Border Grid.Column="2" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource Line}" BorderThickness="1,0,0,0">
        <ScrollViewer x:Name="ResultScroll" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ResultPanel" Margin="18,16,18,18"/></ScrollViewer>
      </Border>
    </Grid>

    <ScrollViewer Grid.Row="1" x:Name="OtherTab" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="OtherPanel" Margin="26,22,26,22" MaxWidth="900" HorizontalAlignment="Left"/>
    </ScrollViewer>
  </Grid>
</Window>
"@
}

# ------------------------------------------------------ building blocks --

function New-HcThickness {
    param([double[]]$Values)
    New-Object Windows.Thickness($Values[0], $Values[1], $Values[2], $Values[3])
}

# A wrapping line of text. -Brush '' leaves the colour to the parent (a
# button's own foreground).
function New-HcText {
    param([string]$Text, [double]$Size = 15, [string]$Brush = 'Text', [switch]$Bold, [double[]]$Margin = @(0, 0, 0, 6))
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.TextWrapping = 'Wrap'
    $t.Margin = New-HcThickness $Margin
    if ($Bold) { $t.FontWeight = [Windows.FontWeights]::Bold }
    if ($Brush) { $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Brush) }
    $t
}

# Every button calls Invoke-HcClick; its Tag says what it is for.
function New-HcButton {
    param([object]$Content, [hashtable]$Tag, [string]$Style = 'HcButton')
    $b = New-Object Windows.Controls.Button
    $b.Style = $script:HcWin.Window.FindResource($Style)
    if ($Content -is [string]) { $Content = New-HcText $Content -Brush '' -Margin @(0, 0, 0, 0) }
    $b.Content = $Content
    $b.Tag = $Tag
    $b.Add_Click({ Invoke-HcClick $this })
    $b
}

function New-HcHeading {
    param([string]$Text)
    New-HcText $Text.ToUpperInvariant() 12 'Soft' -Bold -Margin @(0, 14, 0, 6)
}

# [ OK ], [ !! ], [ ! ] and [ -- ] as small framed tags, like the text menu.
function New-HcTag {
    param([string]$Status)
    $map = @{ ok = @('OK', 'Ok'); problem = @('!!', 'Bad'); warn = @('!', 'Warn'); skipped = @('--', 'Soft') }
    $style = $map[$Status]
    if (-not $style) { $style = $map['skipped'] }
    $border = New-Object Windows.Controls.Border
    $border.BorderThickness = New-HcThickness @(1, 1, 1, 1)
    $border.CornerRadius = New-Object Windows.CornerRadius(4)
    $border.Padding = New-HcThickness @(4, 0, 4, 0)
    $border.Margin = New-HcThickness @(0, 2, 8, 0)
    $border.MinWidth = 28
    $border.VerticalAlignment = 'Top'
    $border.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $style[1])
    $t = New-HcText $style[0] 11 $style[1] -Bold -Margin @(0, 0, 0, 0)
    $t.FontFamily = New-Object Windows.Media.FontFamily('Consolas')
    $t.HorizontalAlignment = 'Center'
    $border.Child = $t
    $border
}

# One report line: the tag, then the text wrapping beside it.
function New-HcLine {
    param([string]$Status, [string]$Text, [string]$Brush = 'Text')
    $row = New-Object Windows.Controls.DockPanel
    $row.Margin = New-HcThickness @(0, 0, 0, 6)
    $tag = New-HcTag $Status
    [Windows.Controls.DockPanel]::SetDock($tag, 'Left')
    [void]$row.Children.Add($tag)
    [void]$row.Children.Add((New-HcText $Text 14.5 $Brush -Margin @(0, 0, 0, 0)))
    $row
}

# A soft box with a small title: Gevonden, Wat te doen, a question.
function New-HcBox {
    param([string]$Title, [object[]]$Children, [string]$Background = 'HiSoft')
    $box = New-Object Windows.Controls.Border
    $box.CornerRadius = New-Object Windows.CornerRadius(8)
    $box.Padding = New-HcThickness @(12, 10, 12, 8)
    $box.Margin = New-HcThickness @(0, 6, 0, 10)
    $box.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $Background)
    $stack = New-Object Windows.Controls.StackPanel
    if ($Title) { [void]$stack.Children.Add((New-HcText $Title.TrimEnd(':').ToUpperInvariant() 12 'Hi' -Bold -Margin @(0, 0, 0, 4))) }
    foreach ($c in $Children) { [void]$stack.Children.Add($c) }
    $box.Child = $stack
    $box
}

# ------------------------------------------------------------- painting --

function Set-HcTheme {
    param([string]$Name)
    $w = $script:HcWin
    $w.Theme = $Name
    $converter = New-Object Windows.Media.BrushConverter
    foreach ($key in $script:HcThemes[$Name].Keys) {
        $w.Window.Resources[$key] = $converter.ConvertFromString($script:HcThemes[$Name][$key])
    }
}

function Update-HcAll {
    Update-HcTabs
    Update-HcStatus
    Update-HcSide
    Update-HcGroups
    Update-HcResult
    Update-HcOther
}

function Update-HcTabs {
    $w = $script:HcWin
    $panel = $w.Window.FindName('Tabs')
    $panel.Children.Clear()
    foreach ($tab in $script:HcTabs) {
        $style = if ($w.Tab -eq $tab) { 'HcTabOn' } else { 'HcTab' }
        [void]$panel.Children.Add((New-HcButton (T "win.tab.$tab") @{ Do = 'tab'; Tab = $tab } $style))
    }
    $problems = $w.Tab -eq 'problems'
    $w.Window.FindName('ProblemsTab').Visibility = if ($problems) { 'Visible' } else { 'Collapsed' }
    $w.Window.FindName('OtherTab').Visibility = if ($problems) { 'Collapsed' } else { 'Visible' }
}

function Update-HcStatus {
    $w = $script:HcWin
    $panel = $w.Window.FindName('Status')
    $panel.Children.Clear()
    [void]$panel.Children.Add((New-HcButton (T 'menu.language') @{ Do = 'language' } 'HcPill'))
    $icon = if ($w.Theme -eq 'dark') { [string][char]0x2600 } else { [string][char]0x263E }
    $theme = New-HcButton $icon @{ Do = 'theme' } 'HcPill'
    $theme.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI Symbol')
    $theme.ToolTip = T 'win.theme'
    [void]$panel.Children.Add($theme)
}

function Update-HcClock {
    $w = $script:HcWin
    if (-not $w.Clock) { return }
    $clock = Get-HcClockLine
    $w.Clock.Text = $clock.Text
    $w.Clock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($clock.Over) { 'Warn' } else { 'Text' }))
}

function Update-HcSide {
    $w = $script:HcWin
    $panel = $w.Window.FindName('SidePanel')
    $panel.Children.Clear()
    $busy = Test-HcBusy

    [void]$panel.Children.Add((New-HcHeading (T 'win.visit')))
    $w.Clock = New-HcText '' 15 'Text' -Bold
    [void]$panel.Children.Add($w.Clock)
    Update-HcClock
    # What this PC is and what Housecall may do on it, as under the banner.
    $e = $w.Environment
    [void]$panel.Children.Add((New-HcText $e.Os 13 'Soft' -Margin @(0, 0, 0, 0)))
    [void]$panel.Children.Add((New-HcText $(if ($e.IsAdmin) { T 'status.admin' } else { T 'status.notAdmin' }) 13 'Soft' -Margin @(0, 0, 0, 0)))
    if ($e.Online) { [void]$panel.Children.Add((New-HcText (T 'status.online') 13 'Soft' -Margin @(0, 0, 0, 0))) }
    else { [void]$panel.Children.Add((New-HcText (T 'status.offline') 13 'Warn' -Bold -Margin @(0, 0, 0, 0))) }
    if ($script:DryRun) { [void]$panel.Children.Add((New-HcText (T 'status.dryRun') 13 'Hi' -Bold -Margin @(0, 4, 0, 0))) }

    [void]$panel.Children.Add((New-HcHeading (T 'win.actions')))
    $all = New-HcButton (T 'win.checkAll') @{ Do = 'checkAll' } 'HcPrimary'
    $all.IsEnabled = -not $busy
    [void]$panel.Children.Add($all)
    $undo = New-HcButton (T 'menu.undo') @{ Do = 'undo' }
    $undo.IsEnabled = (-not $busy) -and @($script:HcChanges | Where-Object { $script:Fixes[$_.FixId].Undo }).Count -gt 0
    [void]$panel.Children.Add($undo)

    [void]$panel.Children.Add((New-HcHeading (T 'win.finish')))
    $finish = New-HcButton (T 'win.noteInvoice') @{ Do = 'close'; Outcome = 'quit' }
    $finish.IsEnabled = -not $busy
    [void]$panel.Children.Add($finish)
    $console = New-HcButton (T 'win.console') @{ Do = 'close'; Outcome = 'console' }
    $console.IsEnabled = -not $busy
    [void]$panel.Children.Add($console)
    [void]$panel.Children.Add((New-HcText (T 'win.consoleHint') 13 'Soft'))
    [void]$panel.Children.Add((New-HcText (T 'promise') 13 'Soft' -Margin @(0, 14, 0, 0)))
}

function Update-HcGroups {
    $w = $script:HcWin
    $panel = $w.Window.FindName('GroupsPanel')
    $panel.Children.Clear()
    $panel.IsEnabled = -not (Test-HcBusy)
    foreach ($letter in $script:Areas.Keys) {
        $open = $w.Open[$letter]
        $head = New-Object Windows.Controls.DockPanel
        $sign = New-HcText $(if ($open) { [string][char]0x2212 } else { '+' }) 18 'Hi' -Bold -Margin @(0, 0, 10, 0)
        $sign.Width = 16
        [Windows.Controls.DockPanel]::SetDock($sign, 'Left')
        $code = New-HcText $letter 13 'Soft' -Bold -Margin @(10, 0, 4, 0)
        $code.VerticalAlignment = 'Center'
        [Windows.Controls.DockPanel]::SetDock($code, 'Right')
        [void]$head.Children.Add($sign)
        [void]$head.Children.Add($code)
        [void]$head.Children.Add((New-HcText (T "area.$letter") 17 '' -Bold -Margin @(0, 0, 0, 0)))
        [void]$panel.Children.Add((New-HcButton $head @{ Do = 'area'; Letter = $letter } 'HcGroup'))

        if ($open) {
            $wrap = New-Object Windows.Controls.WrapPanel
            $wrap.Margin = New-HcThickness @(20, 0, 0, 10)
            foreach ($problem in $script:Areas[$letter]) {
                $content = New-Object Windows.Controls.DockPanel
                $label = New-HcText $problem 12 'Hi' -Bold -Margin @(0, 2, 10, 0)
                [Windows.Controls.DockPanel]::SetDock($label, 'Left')
                [void]$content.Children.Add($label)
                [void]$content.Children.Add((New-HcText (T "problem.$problem") 15 '' -Margin @(0, 0, 0, 0)))
                $b = New-HcButton $content @{ Do = 'problem'; Code = $problem }
                $b.Width = 226
                $b.MinHeight = 52
                $b.Margin = New-HcThickness @(0, 0, 8, 8)
                if ($w.Code -eq $problem -and $w.View -ne 'checkall') {
                    $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'HiSoft')
                    $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Hi')
                }
                [void]$wrap.Children.Add($b)
            }
            [void]$panel.Children.Add($wrap)
        }
        $rule = New-Object Windows.Controls.Border
        $rule.Height = 1
        $rule.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Line')
        [void]$panel.Children.Add($rule)
    }
}

# The right-hand column: whatever $HcWin.View says is on it.
function Update-HcResult {
    $w = $script:HcWin
    $panel = $w.Window.FindName('ResultPanel')
    $panel.Children.Clear()
    $add = { param($element) [void]$panel.Children.Add($element) }

    if ($w.Code -and $w.View -in @('input', 'busy', 'report')) {
        & $add (New-HcText ($w.Code + '  ' + (T "problem.$($w.Code)")) 19 'Text' -Bold -Margin @(0, 0, 0, 10))
    } elseif ($w.View -eq 'checkall') {
        & $add (New-HcText (T 'win.checkAll') 19 'Text' -Bold -Margin @(0, 0, 0, 10))
    } else {
        & $add (New-HcText (T 'win.result') 19 'Text' -Bold -Margin @(0, 0, 0, 10))
    }
    if ($w.Banner) { & $add (New-HcText $w.Banner 14.5 'Ok' -Bold) }
    if ($w.Notice) { & $add (New-HcText $w.Notice 14.5 'Warn' -Bold) }
    if ($w.UndoAsk) { & $add (New-HcQuestion (T 'win.undoConfirm' $w.UndoAsk) 'undoYes' 'undoNo') }

    switch ($w.View) {
        'empty' {
            & $add (New-HcText (T 'win.pick') 15 'Soft')
        }
        'input' {
            $ask = if ($w.Code -eq 'A3') { T 'site.ask' } else { T 'mail.ask' }
            & $add (New-HcText $ask 15 'Text')
            $box = New-Object Windows.Controls.TextBox
            $box.FontSize = 16
            $box.Padding = New-HcThickness @(6, 5, 6, 5)
            $box.Margin = New-HcThickness @(0, 4, 0, 10)
            $box.Text = "$($w.Input)"
            $box.Tag = @{ Do = 'input' }
            $box.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'Bg')
            $box.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Text')
            $box.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'Hi')
            $box.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Text')
            $box.Add_KeyDown({ if ($_.Key -eq 'Return') { Invoke-HcClick $this } })
            & $add $box
            & $add (New-HcButton (T 'win.check') @{ Do = 'input' } 'HcPrimary')
            $w.InputBox = $box
            [void]$box.Focus()
        }
        'busy' {
            & $add (New-HcText $w.BusyText 15 'Soft')
            $bar = New-Object Windows.Controls.ProgressBar
            $bar.IsIndeterminate = $true
            $bar.Height = 6
            $bar.Margin = New-HcThickness @(0, 6, 0, 0)
            $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
            & $add $bar
        }
        'report' { Add-HcReportView $panel }
        'checkall' { Add-HcCheckAllView $panel }
    }
}

function New-HcQuestion {
    param([string]$Text, [string]$Yes, [string]$No, [hashtable]$Extra = @{})
    $buttons = New-Object Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $yesTag = @{ Do = $Yes } + $Extra
    $yesButton = New-HcButton (T 'win.yes') $yesTag 'HcPrimary'
    $yesButton.MinWidth = 90
    $yesButton.Margin = New-HcThickness @(0, 4, 8, 0)
    $noButton = New-HcButton (T 'win.no') @{ Do = $No }
    $noButton.MinWidth = 90
    $noButton.Margin = New-HcThickness @(0, 4, 0, 0)
    [void]$buttons.Children.Add($yesButton)
    [void]$buttons.Children.Add($noButton)
    New-HcBox '' @((New-HcText $Text 15 'Text' -Bold -Margin @(0, 0, 0, 2)), $buttons) 'Side'
}

function Add-HcReportView {
    param($Panel)
    $w = $script:HcWin
    $r = $w.Report
    $add = { param($element) [void]$Panel.Children.Add($element) }
    if ($w.FromAll) { & $add (New-HcButton (T 'win.backToAll') @{ Do = 'backToAll' }) }

    foreach ($line in @($r.Results)) {
        $brush = if ($line.Status -eq 'skipped') { 'Soft' } else { 'Text' }
        & $add (New-HcLine $line.Status $line.Text $brush)
    }
    if ($r.FindingId) {
        $findingArgs = @('finding.' + $r.FindingId) + @($r.FindingArgs)
        & $add (New-HcBox (T 'run.found') @(New-HcText (T @findingArgs) 15 'Text' -Margin @(0, 0, 0, 2)))
        $advice = T ('advice.' + $r.FindingId)
        if ($advice -notmatch '^\[') {
            & $add (New-HcText (T 'run.advice') 13 'Soft' -Bold -Margin @(0, 2, 0, 2))
            & $add (New-HcText $advice 15 'Text' -Margin @(0, 0, 0, 10))
        }
    }

    $actions = @($r.Actions)
    $steps = @(Get-HcSteps $r)
    if ($actions.Count -or $steps.Count) { & $add (New-HcHeading (T 'fix.heading').TrimEnd('?')) }
    for ($i = 0; $i -lt $actions.Count; $i++) {
        $a = $actions[$i]
        $fix = $script:Fixes[$a.FixId]
        $content = New-Object Windows.Controls.StackPanel
        [void]$content.Children.Add((New-HcText (T ('fix.' + $a.FixId) $a.Target.Label) 15 '' -Bold -Margin @(0, 0, 0, 0)))
        $note = T ('fix.note.' + $fix.Note)
        if ($fix.Admin -and -not $script:IsAdmin) { $note += ' ' + (T 'fix.needsAdmin') }
        $noteText = New-HcText $note 13 '' -Margin @(0, 1, 0, 0)
        $noteText.Opacity = 0.8
        [void]$content.Children.Add($noteText)
        $style = if ($i -eq 0) { 'HcPrimary' } else { 'HcButton' }
        $b = New-HcButton $content @{ Do = 'fix'; Index = $i } $style
        $b.IsEnabled = -not (Test-HcBusy)
        & $add $b
        if ($w.Confirm -eq $i) {
            $label = T ('fix.' + $a.FixId) $a.Target.Label
            $question = if ($fix.Admin -and -not $script:IsAdmin -and -not $script:DryRun) { T 'win.elevateAsk' } else { T 'win.confirm' $label }
            & $add (New-HcQuestion $question 'fixYes' 'fixNo' @{ Index = $i })
        }
    }
    if ($steps.Count) {
        & $add (New-HcButton (T 'fix.steps') @{ Do = 'steps' })
        if ($w.ShowSteps) {
            for ($i = 0; $i -lt $steps.Count; $i++) {
                & $add (New-HcText ((T 'fix.stepOf' ($i + 1) $steps.Count) + ' ' + $steps[$i]) 15 'Text' -Margin @(4, 2, 0, 8))
            }
        }
    }
}

function Add-HcCheckAllView {
    param($Panel)
    $w = $script:HcWin
    $all = $w.All
    $add = { param($element) [void]$Panel.Children.Add($element) }
    $total = $all.Codes.Count
    $done = $all.Done.Count
    if ((Test-HcBusy) -and -not $all.Stopped) {
        $next = if ($done -lt $total) { $all.Codes[$done] } else { '' }
        & $add (New-HcText (T 'win.checkAllOf' ([Math]::Min($done + 1, $total)) $total ($next + ' ' + (T "problem.$next"))) 15 'Soft')
        $bar = New-Object Windows.Controls.ProgressBar
        $bar.Minimum = 0
        $bar.Maximum = $total
        $bar.Value = $done
        $bar.Height = 6
        $bar.Margin = New-HcThickness @(0, 2, 0, 10)
        $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Hi')
        & $add $bar
        & $add (New-HcButton (T 'win.stop') @{ Do = 'stopAll' })
    } elseif ($all.Stopped) {
        & $add (New-HcText (T 'win.stopped' $done $total) 15 'Soft')
    } else {
        & $add (New-HcText (T 'win.checkAllDone') 15 'Soft')
    }
    # Problems first, then warnings, then the rest, each in menu order.
    $order = @{ problem = 0; warn = 1; ok = 2; error = 3 }
    $rows = @($all.Done | Sort-Object @{ Expression = { $order[$_.Level] } }, @{ Expression = { $_.Index } })
    foreach ($row in $rows) {
        $content = New-Object Windows.Controls.StackPanel
        $status = if ($row.Level -eq 'error') { 'skipped' } else { $row.Level }
        [void]$content.Children.Add((New-HcLine $status ($row.Code + '  ' + (T "problem.$($row.Code)"))))
        if ($row.Detail) {
            $detail = New-HcText $row.Detail 13 '' -Margin @(36, 0, 0, 0)
            $detail.Opacity = 0.8
            [void]$content.Children.Add($detail)
        }
        $b = New-HcButton $content @{ Do = 'allRow'; Code = $row.Code }
        $b.Padding = New-HcThickness @(10, 7, 10, 5)
        $b.Margin = New-HcThickness @(0, 0, 0, 6)
        $b.IsEnabled = [bool]$w.Reports[$row.Code]
        & $add $b
    }
}

function Update-HcOther {
    $w = $script:HcWin
    $panel = $w.Window.FindName('OtherPanel')
    $panel.Children.Clear()
    $add = { param($element) [void]$panel.Children.Add($element) }
    if ($w.Tab -eq 'problems') { return }
    & $add (New-HcText (T "win.tab.$($w.Tab)") 24 'Text' -Bold -Margin @(0, 0, 0, 12))
    switch ($w.Tab) {
        'safety' {
            & $add (New-HcText (T 'win.safetyIntro') 15 'Soft' -Margin @(0, 0, 0, 14))
            $wrap = New-Object Windows.Controls.WrapPanel
            foreach ($code in @('F2', 'F1', 'F3')) {
                $card = New-Object Windows.Controls.StackPanel
                $card.Width = 260
                [void]$card.Children.Add((New-HcText (T "problem.$code") 17 'Text' -Bold))
                [void]$card.Children.Add((New-HcText (T "win.safety.$code") 14 'Soft' -Margin @(0, 0, 0, 12)))
                $style = if ($code -eq 'F3') { 'HcPrimary' } else { 'HcButton' }
                [void]$card.Children.Add((New-HcButton ((T 'win.check') + " ($code)") @{ Do = 'problem'; Code = $code } $style))
                $box = New-HcBox '' @($card) 'Panel'
                $box.Margin = New-HcThickness @(0, 0, 14, 14)
                $box.Padding = New-HcThickness @(16, 14, 16, 8)
                [void]$wrap.Children.Add($box)
            }
            & $add $wrap
        }
        'visit' {
            $clock = Get-HcClockLine
            & $add (New-HcBox (T 'win.visit.time') @(New-HcText $clock.Text 15 $(if ($clock.Over) { 'Warn' } else { 'Text' }) -Margin @(0, 0, 0, 2)) 'Panel')
            $done = @($script:HcChanges | ForEach-Object { [string][char]0x2713 + ' ' + $_.Label })
            if ($done.Count -eq 0) { $done = @(T 'win.visit.nothing') }
            & $add (New-HcBox (T 'win.visit.done') @($done | ForEach-Object { New-HcText $_ 15 'Text' -Margin @(0, 0, 0, 2) }) 'Panel')
            & $add (New-HcButton (T 'win.noteInvoice') @{ Do = 'close'; Outcome = 'quit' } 'HcPrimary')
            & $add (New-HcText (T 'win.visit.later') 14 'Soft' -Margin @(0, 10, 0, 6))
            & $add (New-HcButton (T 'win.console') @{ Do = 'close'; Outcome = 'console' })
        }
        'pc' { & $add (New-HcText (T 'win.pc.soon') 15 'Soft') }
        'ai' {
            & $add (New-HcText (T 'win.ai.soon') 15 'Soft')
            & $add (New-HcButton (T 'win.console') @{ Do = 'close'; Outcome = 'console' })
        }
    }
}

# ---------------------------------------------------------------- doing --

function Invoke-HcClick {
    param($Sender)
    $w = $script:HcWin
    try {
        $tag = $Sender.Tag
        switch ($tag.Do) {
            'tab'      { $w.Tab = $tag.Tab; Update-HcTabs; Update-HcOther }
            'language' { $script:Lang = if ($script:Lang -eq 'nl') { 'en' } else { 'nl' }; Update-HcAll }
            'theme'    { Set-HcTheme $(if ($w.Theme -eq 'dark') { 'light' } else { 'dark' }); Update-HcStatus }
            'area'     { $w.Open[$tag.Letter] = -not $w.Open[$tag.Letter]; Update-HcGroups }
            'problem'  { Open-HcProblem $tag.Code }
            'input'    { Submit-HcInput }
            'checkAll' { Start-HcCheckAll }
            'stopAll'  { $w.Queue.Clear(); $w.All.Stopped = $true; Update-HcResult }
            'allRow'   {
                $w.Code = $tag.Code
                $w.Report = $w.Reports[$tag.Code]
                $w.Input = $w.Inputs[$tag.Code]
                $w.FromAll = $true
                Clear-HcMessages
                $w.View = 'report'
                $script:HcCurrentCode = $tag.Code
                Save-HcVisit $tag.Code $w.Report
                Update-HcResult
            }
            'backToAll' { $w.View = 'checkall'; $w.FromAll = $false; Clear-HcMessages; Update-HcResult; Update-HcGroups }
            'steps'    { $w.ShowSteps = -not $w.ShowSteps; Update-HcResult }
            'fix'      { $w.Confirm = $tag.Index; $w.Notice = $null; Update-HcResult }
            'fixNo'    { $w.Confirm = $null; $w.Notice = T 'fix.cancelled'; Update-HcResult }
            'fixYes'   { $w.Confirm = $null; Invoke-HcWindowFix $tag.Index }
            'undo'     {
                $w.UndoAsk = @($script:HcChanges | Where-Object { $script:Fixes[$_.FixId].Undo }).Count
                if (-not $w.UndoAsk) { $w.UndoAsk = $null; $w.Notice = T 'undo.nothing' }
                $w.Tab = 'problems'; Update-HcTabs; Update-HcResult
            }
            'undoNo'   { $w.UndoAsk = $null; $w.Notice = T 'fix.cancelled'; Update-HcResult }
            'undoYes'  { $w.UndoAsk = $null; Start-HcWindowUndo }
            'close'    {
                if (Test-HcBusy) { return }
                $w.Outcome = $tag.Outcome
                $w.Window.Close()
            }
        }
    } catch {
        $w.Notice = T 'win.error' $_.Exception.Message
        Update-HcResult
    }
}

function Clear-HcMessages {
    $w = $script:HcWin
    $w.Banner = $null
    $w.Notice = $null
    $w.Confirm = $null
    $w.ShowSteps = $false
    $w.UndoAsk = $null
}

function Open-HcProblem {
    param([string]$Code)
    $w = $script:HcWin
    if (Test-HcBusy) { return }
    $w.Tab = 'problems'
    $w.Code = $Code
    $w.FromAll = $false
    Clear-HcMessages
    Update-HcTabs
    if ($Code -in @('A3', 'A4')) {
        $w.Input = $w.Inputs[$Code]
        $w.View = 'input'
        Update-HcGroups
        Update-HcResult
        return
    }
    Start-HcWindowCheck $Code $null
}

# A3 and A4 need an address first; checked the same way the text menu does.
function Submit-HcInput {
    $w = $script:HcWin
    $typed = "$($w.InputBox.Text)".Trim()
    $w.Input = $typed
    if (-not $typed) { return }
    if ($w.Code -eq 'A3') {
        if (-not (ConvertTo-HcHostName $typed)) { $w.Notice = T 'site.invalid' $typed; Update-HcResult; return }
    } elseif (-not (ConvertTo-HcMailDomain $typed)) {
        $w.Notice = T 'mail.invalid' $typed; Update-HcResult; return
    }
    $w.Inputs[$w.Code] = $typed
    $w.Notice = $null
    Start-HcWindowCheck $w.Code $typed
}

function Start-HcWindowCheck {
    param([string]$Code, [string]$Text, [string]$Banner, [string]$BusyText = (T 'run.checking'))
    $w = $script:HcWin
    $w.View = 'busy'
    $w.BusyText = $BusyText
    Add-HcJob @{ Kind = 'check'; Code = $Code; Text = $Text; Banner = $Banner; Done = 'Complete-HcWindowCheck' }
    Update-HcGroups
    Update-HcResult
}

function Get-HcJobReport {
    param([object[]]$Output)
    @($Output | Where-Object { $_ -and $_.PSObject.Properties['FindingId'] -and $_.PSObject.Properties['Results'] }) | Select-Object -Last 1
}

function Complete-HcWindowCheck {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $report = Get-HcJobReport $Output
    if ($ErrorText -or -not $report) {
        $w.View = 'empty'
        $w.Notice = T 'win.error' $(if ($ErrorText) { $ErrorText } else { '-' })
        Update-HcResult
        return
    }
    $w.Report = $report
    $w.Reports[$Job.Code] = $report
    $w.Inputs[$Job.Code] = $Job.Text
    $w.Banner = $Job.Banner
    $w.View = 'report'
    $script:HcCurrentCode = $Job.Code
    Save-HcVisit $Job.Code $report
    Update-HcGroups
    Update-HcResult
    $w.Window.FindName('ResultScroll').ScrollToTop()
}

function Start-HcCheckAll {
    $w = $script:HcWin
    if (Test-HcBusy) { return }
    $codes = Get-HcCheckAllCodes
    $w.All = @{ Codes = $codes; Done = New-Object System.Collections.ArrayList; Stopped = $false }
    $w.Tab = 'problems'
    $w.Code = $null
    $w.FromAll = $false
    $w.View = 'checkall'
    Clear-HcMessages
    for ($i = 0; $i -lt $codes.Count; $i++) {
        Add-HcJob @{ Kind = 'check'; Code = $codes[$i]; Index = $i; Done = 'Complete-HcCheckAllItem' }
    }
    Update-HcTabs
    Update-HcGroups
    Update-HcResult
}

# One check of "Alles controleren" is back. Only what is not all right goes
# on the note; a clean result would only make it longer.
function Complete-HcCheckAllItem {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    $report = Get-HcJobReport $Output
    $row = [pscustomobject]@{ Code = $Job.Code; Index = $Job.Index; Level = 'error'; Detail = $ErrorText }
    if ($report -and -not $ErrorText) {
        $w.Reports[$Job.Code] = $report
        $row.Level = Get-HcReportLevel $report
        $row.Detail = @($report.Results | Where-Object { $_.Status -eq $row.Level } | ForEach-Object { $_.Text }) | Select-Object -First 1
        if ($row.Level -ne 'ok') { Save-HcVisit $Job.Code $report }
    }
    [void]$w.All.Done.Add($row)
    if ($w.View -eq 'checkall') { Update-HcResult }
}

# A fix, picked and confirmed: the same order of things as the text menu
# (Invoke-HcActionMenu), with the window's own question instead of J/N.
function Invoke-HcWindowFix {
    param([int]$Index)
    $w = $script:HcWin
    $action = @($w.Report.Actions)[$Index]
    $fix = $script:Fixes[$action.FixId]
    $label = T ('fix.' + $action.FixId) $action.Target.Label
    $w.Banner = $null

    if ($fix.Admin -and -not $script:IsAdmin -and -not $script:DryRun) {
        if (-not $script:HcSource) { $w.Notice = T 'fix.adminHow'; Update-HcResult; return }
        if (Start-HcElevated $script:HcCurrentCode) {
            $script:HandedOff = $true
            $w.Outcome = 'handedoff'
            $w.Window.Close()
            return
        }
        $w.Notice = T 'fix.cancelled'
        Update-HcResult
        return
    }
    if ($script:DryRun) { $w.Notice = T 'fix.dryRun'; Update-HcResult; return }

    $w.View = 'busy'
    $w.BusyText = $label + '...'
    Add-HcJob @{ Kind = 'fix'; FixId = $action.FixId; Target = $action.Target; Code = $w.Code; Text = $w.Inputs[$w.Code]; Done = 'Complete-HcWindowFix' }
    Update-HcSide
    Update-HcResult
}

function Complete-HcWindowFix {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    if ($ErrorText) {
        $w.View = 'report'
        $w.Notice = T 'fix.failed' $ErrorText
        Update-HcResult
        return
    }
    $fix = $script:Fixes[$Job.FixId]
    $done = T ('fix.' + $Job.FixId + '.done') $Job.Target.Label
    if (-not $fix.NoLog) {
        [void]$script:HcChanges.Add([pscustomobject]@{ FixId = $Job.FixId; Target = $Job.Target; Label = $done })
    }
    # A fix often brings the internet back: measure again, for the pill,
    # the invoice and the history.
    if (-not $w.Environment.Online) { Add-HcJob @{ Kind = 'online'; Done = 'Complete-HcOnline' } }
    $banner = T 'win.doneAgain' $done
    if ($Info.Count) { $banner = ($Info -join ' ') + ' ' + $banner }
    Start-HcWindowCheck $Job.Code $Job.Text $banner (T 'fix.checkingAgain')
    Update-HcSide
}

function Complete-HcOnline {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    if (-not $ErrorText -and @($Output) -contains $true) {
        $w.Environment.Online = $true
        Update-HcSide
    }
}

# U in the window: this visit's changes undone, newest first, then the
# problem on screen checked again so the result shows it.
function Start-HcWindowUndo {
    $w = $script:HcWin
    $undoable = @($script:HcChanges | Where-Object { $script:Fixes[$_.FixId].Undo })
    $w.UndoMessages = New-Object System.Collections.ArrayList
    for ($i = $undoable.Count - 1; $i -ge 0; $i--) {
        $change = $undoable[$i]
        Add-HcJob @{ Kind = 'undo'; FixId = $change.FixId; Target = $change.Target; Change = $change; Last = ($i -eq 0); Done = 'Complete-HcWindowUndo' }
    }
    $w.View = if ($w.Report) { 'busy' } else { 'empty' }
    $w.BusyText = T 'menu.undo'
    Update-HcSide
    Update-HcResult
}

function Complete-HcWindowUndo {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    if ($ErrorText) {
        [void]$w.UndoMessages.Add((T 'undo.failed' $Job.Change.Label))
    } else {
        $script:HcChanges.Remove($Job.Change)
        [void]$w.UndoMessages.Add((T 'undo.done' $Job.Change.Label))
    }
    if (-not $Job.Last) { return }
    $message = @($w.UndoMessages) -join ' / '
    if ($w.Code -and $w.Report) {
        Start-HcWindowCheck $w.Code $w.Inputs[$w.Code] $message (T 'fix.checkingAgain')
    } else {
        $w.View = 'empty'
        $w.Banner = $message
        Update-HcResult
    }
    Update-HcSide
}

# ------------------------------------------------------------------ main --

function Show-HcWindow {
    param([pscustomobject]$Environment, [string]$Start, [string]$Message)
    if (-not (Test-HcWindowPossible)) { return 'failed' }
    try {
        $window = [Windows.Markup.XamlReader]::Parse((New-HcWindowXaml))
    } catch {
        Write-Warn2 (T 'win.failed' $_.Exception.Message)
        return 'failed'
    }

    $open = @{}
    foreach ($letter in $script:Areas.Keys) { $open[$letter] = $true }
    $script:HcWin = @{
        Window = $window; Environment = $Environment; Tab = 'problems'; Theme = 'light'; Open = $open
        View = 'empty'; Code = $null; Report = $null; Reports = @{}; Inputs = @{}; Input = $null; InputBox = $null
        Banner = $null; Notice = $Message; Confirm = $null; ShowSteps = $false; UndoAsk = $null; UndoMessages = $null
        FromAll = $false; All = $null; BusyText = ''; Clock = $null
        Queue = New-Object System.Collections.ArrayList; Job = $null; WasBusy = $false
        Runspace = $null; Outcome = 'quit'
    }
    $w = $script:HcWin

    # The window must fit an old 1366x768 laptop as well as a big screen.
    $area = [Windows.SystemParameters]::WorkArea
    $window.Width = [Math]::Min(1180, $area.Width * 0.96)
    $window.Height = [Math]::Min(800, $area.Height * 0.94)

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $w.Runspace = $rs
    Add-HcJob @{ Kind = 'load'; Source = $script:HcSource; Start = $Start; Done = 'Complete-HcLoad' }

    Set-HcTheme (Get-HcDefaultTheme)
    Update-HcAll

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({ Invoke-HcTick })
    $clock = New-Object Windows.Threading.DispatcherTimer
    $clock.Interval = [TimeSpan]::FromSeconds(20)
    $clock.Add_Tick({ try { Update-HcClock } catch { } })

    # A fix or undo halfway must finish: closing waits for it.
    $window.Add_Closing({
        $job = $script:HcWin.Job
        if ($job -and $job.Kind -in @('fix', 'undo')) {
            $_.Cancel = $true
            $script:HcWin.Notice = T 'win.busyClose'
            Update-HcResult
        }
    })
    $window.Add_ContentRendered({ $this.Topmost = $true; $this.Activate(); $this.Topmost = $false })

    $timer.Start()
    $clock.Start()
    try {
        [void]$window.ShowDialog()
    } finally {
        $timer.Stop()
        $clock.Stop()
        if ($w.Job) { try { [void]$w.Job.PS.BeginStop($null, $null) } catch { } }
        try { $rs.CloseAsync() } catch { }
    }
    $w.Outcome
}

function Complete-HcLoad {
    param([hashtable]$Job, [object[]]$Output, [string]$ErrorText, [string[]]$Info)
    $w = $script:HcWin
    if ($ErrorText) {
        $w.Notice = T 'win.error' $ErrorText
        Update-HcResult
        return
    }
    if ($Job.Start -and ($script:Areas.Values | ForEach-Object { $_ }) -contains $Job.Start) { Open-HcProblem $Job.Start }
}
