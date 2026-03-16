#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 PC Organizer Hub – Central launcher for all CopilotCreates organization tools.
.DESCRIPTION
    A beautiful WPF dashboard that gives you at-a-glance system stats and one-click
    access to all four PC-organization scripts:

    • Desktop Organizer   – Sort Desktop files into type folders
    • Downloads Organizer – Tame your Downloads folder
    • System Cleanup Pro  – Reclaim disk space safely
    • Startup Manager     – Control what runs at login

    Features
    --------
    • Live disk-usage gauges (per drive)
    • RAM and CPU snapshot
    • Recent log viewer (last 10 activity lines across all tools)
    • Self-locating – finds sibling scripts automatically
    • Windows 11 Fluent dark-mode design

.NOTES
    Author  : CopilotCreates
    Version : 1.0.0
    Requires: Windows 10/11, PowerShell 5.1+
    Place this script in the same folder as the other scripts.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ─── Constants ───────────────────────────────────────────────────────────────
$Script:AppName  = 'PC Organizer Hub'
$Script:Version  = '1.0.0'
$Script:ScriptDir = $PSScriptRoot
if (-not $Script:ScriptDir) { $Script:ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent }
$Script:LogDir   = Join-Path $env:APPDATA 'CopilotOrganizer\Logs'

# Sibling script paths
$Script:Tools = [ordered]@{
    'Desktop Organizer'   = @{ Script = 'Desktop-Organizer.ps1';   Emoji = '🗂'; Desc = 'Sort Desktop files into tidy category sub-folders'   }
    'Downloads Organizer' = @{ Script = 'Downloads-Organizer.ps1'; Emoji = '📥'; Desc = 'Organise Downloads by type, date, and remove duplicates' }
    'System Cleanup'      = @{ Script = 'System-Cleanup.ps1';      Emoji = '🧹'; Desc = 'Scan and safely delete junk files to reclaim disk space'  }
    'Startup Manager'     = @{ Script = 'Startup-Manager.ps1';     Emoji = '🚀'; Desc = 'Enable, disable, or remove startup programs'             }
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Format-FileSize {
    param([long]$Bytes)
    switch ($Bytes) {
        { $_ -ge 1TB } { return '{0:N1} TB' -f ($_ / 1TB) }
        { $_ -ge 1GB } { return '{0:N2} GB' -f ($_ / 1GB) }
        { $_ -ge 1MB } { return '{0:N2} MB' -f ($_ / 1MB) }
        default        { return '{0:N2} KB' -f ($_ / 1KB) }
    }
}

function Get-SystemStats {
    $stats = @{}

    # Drives
    $drives = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($null -eq $drive.Used -or ($drive.Used + $drive.Free) -eq 0) { continue }
        $total = $drive.Used + $drive.Free
        $drives.Add([PSCustomObject]@{
            Name    = "$($drive.Name):"
            Total   = $total
            Used    = $drive.Used
            Free    = $drive.Free
            PctUsed = [int](($drive.Used / $total) * 100)
        })
    }
    $stats['Drives'] = $drives

    # RAM
    try {
        $os         = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $stats['TotalRAM']     = [long]$os.TotalVisibleMemorySize * 1KB
        $stats['FreeRAM']      = [long]$os.FreePhysicalMemory    * 1KB
        $stats['UsedRAMPct']   = [int]((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100)
    } catch {
        $stats['TotalRAM'] = 0; $stats['FreeRAM'] = 0; $stats['UsedRAMPct'] = 0
    }

    # CPU
    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Measure-Object -Property LoadPercentage -Average).Average
        $stats['CPUPct'] = [int]$cpu
    } catch { $stats['CPUPct'] = 0 }

    # OS info
    try {
        $sys = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $stats['OSName']    = $sys.Caption
        $stats['OSBuild']   = $sys.BuildNumber
        $stats['LastBoot']  = $sys.LastBootUpTime
    } catch { $stats['OSName'] = 'Windows'; $stats['OSBuild'] = ''; $stats['LastBoot'] = $null }

    return $stats
}

function Get-RecentLogLines {
    $lines = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path $Script:LogDir)) { return $lines }
    $logFiles = Get-ChildItem -LiteralPath $Script:LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 5
    foreach ($lf in $logFiles) {
        try {
            $content = Get-Content -LiteralPath $lf.FullName -Tail 4 -ErrorAction SilentlyContinue
            foreach ($line in $content) { $lines.Add($line) }
        } catch {}
    }
    return $lines | Select-Object -Last 10
}

# ─── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="🖥  PC Organizer Hub  v1.0"
    Height="720" Width="940" MinHeight="580" MinWidth="740"
    WindowStartupLocation="CenterScreen"
    Background="#1C1C1C" Foreground="#FFFFFF"
    FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <Style x:Key="ToolCard" TargetType="Border">
      <Setter Property="Background"   Value="#2D2D2D"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding"      Value="20,16"/>
      <Setter Property="Margin"       Value="0,0,0,10"/>
      <Setter Property="Cursor"       Value="Hand"/>
    </Style>

    <Style x:Key="LaunchBtn" TargetType="Button">
      <Setter Property="Background"      Value="#0078D4"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="20,9"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="FontWeight"      Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#1A8EE8"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter Property="Background" Value="#005A9E"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False"><Setter Property="Background" Value="#444"/><Setter Property="Foreground" Value="#888"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecondaryBtn" TargetType="Button">
      <Setter Property="Background"      Value="#383838"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush"     Value="#555"/>
      <Setter Property="Padding"         Value="12,8"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#444"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ProgressBar">
      <Setter Property="Background"      Value="#383838"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height"          Value="8"/>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>  <!-- Title bar -->
      <RowDefinition Height="*"/>   <!-- Main split: tools + stats -->
      <RowDefinition Height="Auto"/> <!-- Recent activity -->
      <RowDefinition Height="Auto"/> <!-- Footer -->
    </Grid.RowDefinitions>

    <!-- ── Title Bar ── -->
    <Border Grid.Row="0" Background="#111111">
      <Grid Margin="20,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="🖥" FontSize="28" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="PC Organizer Hub" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Your central dashboard for Windows 11 organisation tools" Foreground="#888" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Button x:Name="btnRefreshStats" Content="🔄" Style="{StaticResource SecondaryBtn}" Padding="8,6" Margin="0,0,8,0" ToolTip="Refresh system stats"/>
          <TextBlock Text="v1.0.0" Foreground="#555" FontSize="11" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ── Main Split ── -->
    <Grid Grid.Row="1" Margin="20,16,20,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>       <!-- Tool cards -->
        <ColumnDefinition Width="12"/>
        <ColumnDefinition Width="260"/>     <!-- System stats -->
      </Grid.ColumnDefinitions>

      <!-- Tool Cards -->
      <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="spTools"/>
      </ScrollViewer>

      <!-- System Stats Panel -->
      <Border Grid.Column="2" Background="#252525" CornerRadius="10" Padding="16">
        <StackPanel>
          <TextBlock Text="System Overview" FontWeight="SemiBold" Margin="0,0,0,12" FontSize="14"/>

          <!-- OS Info -->
          <TextBlock x:Name="txtOS"       Foreground="#AAA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,2"/>
          <TextBlock x:Name="txtBoot"     Foreground="#777" FontSize="10" Margin="0,0,0,14"/>

          <!-- CPU -->
          <Grid Margin="0,0,0,4">
            <TextBlock Text="🖧 CPU" FontWeight="SemiBold"/>
            <TextBlock x:Name="txtCPU" HorizontalAlignment="Right" Foreground="#AAA" FontSize="11"/>
          </Grid>
          <ProgressBar x:Name="pbCPU" Foreground="#0078D4" Margin="0,0,0,14"/>

          <!-- RAM -->
          <Grid Margin="0,0,0,4">
            <TextBlock Text="💾 Memory" FontWeight="SemiBold"/>
            <TextBlock x:Name="txtRAM" HorizontalAlignment="Right" Foreground="#AAA" FontSize="11"/>
          </Grid>
          <ProgressBar x:Name="pbRAM" Foreground="#7B5EA7" Margin="0,0,0,14"/>

          <!-- Drives -->
          <TextBlock Text="💿 Drives" FontWeight="SemiBold" Margin="0,0,0,8"/>
          <StackPanel x:Name="spDrives"/>
        </StackPanel>
      </Border>
    </Grid>

    <!-- ── Recent Activity ── -->
    <Border Grid.Row="2" Margin="20,12,20,0" Background="#252525" CornerRadius="8" Padding="14,10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,6">
          <TextBlock Text="📋 Recent Activity" FontWeight="SemiBold"/>
          <Button x:Name="btnOpenLogDir" Content="Open Logs Folder" Style="{StaticResource SecondaryBtn}"
                  HorizontalAlignment="Right" Padding="10,4"/>
        </Grid>
        <ScrollViewer Grid.Row="1" Height="72" VerticalScrollBarVisibility="Auto">
          <TextBlock x:Name="txtActivity" Foreground="#888" FontFamily="Consolas" FontSize="11"
                     TextWrapping="Wrap"/>
        </ScrollViewer>
      </Grid>
    </Border>

    <!-- ── Footer ── -->
    <Border Grid.Row="3" Padding="20,10,20,14">
      <Grid>
        <TextBlock Text="CopilotCreates · All tools run locally – no data leaves your PC" Foreground="#444" FontSize="10" VerticalAlignment="Center"/>
        <TextBlock x:Name="txtStatus" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#666" FontSize="11"/>
      </Grid>
    </Border>

  </Grid>
</Window>
'@

# ─── Load Window ─────────────────────────────────────────────────────────────
try {
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.MessageBox]::Show("Failed to load UI: $_", $Script:AppName, 'OK', 'Error')
    exit 1
}

# ─── Controls ────────────────────────────────────────────────────────────────
$spTools         = $window.FindName('spTools')
$btnRefreshStats = $window.FindName('btnRefreshStats')
$txtOS           = $window.FindName('txtOS')
$txtBoot         = $window.FindName('txtBoot')
$pbCPU           = $window.FindName('pbCPU')
$txtCPU          = $window.FindName('txtCPU')
$pbRAM           = $window.FindName('pbRAM')
$txtRAM          = $window.FindName('txtRAM')
$spDrives        = $window.FindName('spDrives')
$txtActivity     = $window.FindName('txtActivity')
$btnOpenLogDir   = $window.FindName('btnOpenLogDir')
$txtStatus       = $window.FindName('txtStatus')

# ─── Build Tool Cards ─────────────────────────────────────────────────────────
foreach ($toolName in $Script:Tools.Keys) {
    $tool      = $Script:Tools[$toolName]
    $scriptPath = Join-Path $Script:ScriptDir $tool.Script
    $exists    = Test-Path $scriptPath

    # Outer card border
    $card = [System.Windows.Controls.Border]@{
        Background   = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(45,45,45))
        CornerRadius = [System.Windows.CornerRadius]10
        Padding      = [System.Windows.Thickness]20
        Margin       = [System.Windows.Thickness](0,0,0,10)
    }

    $grid = [System.Windows.Controls.Grid]::new()
    $c0   = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
    $c1   = [System.Windows.Controls.ColumnDefinition]::new()
    $c1.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
    $c2   = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
    $grid.ColumnDefinitions.Add($c0); $grid.ColumnDefinitions.Add($c1); $grid.ColumnDefinitions.Add($c2)

    # Emoji
    $emojiTB = [System.Windows.Controls.TextBlock]@{
        Text              = $tool.Emoji
        FontSize          = 36
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        Margin            = [System.Windows.Thickness](0,0,16,0)
    }
    [System.Windows.Controls.Grid]::SetColumn($emojiTB, 0)
    $grid.Children.Add($emojiTB) | Out-Null

    # Text stack
    $sp = [System.Windows.Controls.StackPanel]@{
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    }
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)

    $nameTB = [System.Windows.Controls.TextBlock]@{
        Text       = $toolName
        FontSize   = 16
        FontWeight = [System.Windows.FontWeights]::SemiBold
    }
    $descTB = [System.Windows.Controls.TextBlock]@{
        Text       = $tool.Desc
        Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(160,160,160))
        FontSize   = 12
        TextWrapping = [System.Windows.TextWrapping]::Wrap
        Margin     = [System.Windows.Thickness](0,2,0,0)
    }
    $sp.Children.Add($nameTB) | Out-Null
    $sp.Children.Add($descTB) | Out-Null

    if (-not $exists) {
        $warnTB = [System.Windows.Controls.TextBlock]@{
            Text       = "⚠ Script not found: $($tool.Script)"
            Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,150,40))
            FontSize   = 11
            Margin     = [System.Windows.Thickness](0,4,0,0)
        }
        $sp.Children.Add($warnTB) | Out-Null
    }
    $grid.Children.Add($sp) | Out-Null

    # Launch button
    $btn = [System.Windows.Controls.Button]@{
        Content           = "  Launch ▶"
        IsEnabled         = $exists
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        Padding           = [System.Windows.Thickness](16,9,16,9)
        FontWeight        = [System.Windows.FontWeights]::SemiBold
        Cursor            = [System.Windows.Input.Cursors]::Hand
        Foreground        = [System.Windows.Media.Brushes]::White
        BorderThickness   = [System.Windows.Thickness]0
        Background        = if ($exists) {
            [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(0,120,212))
        } else {
            [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(60,60,60))
        }
    }

    # Apply template for hover
    $templateXml = [xml]@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 TargetType="Button">
  <Border Background="{TemplateBinding Background}" CornerRadius="6"
          Padding="{TemplateBinding Padding}">
    <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
  </Border>
</ControlTemplate>
'@
    $btn.Template = [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($templateXml))

    [System.Windows.Controls.Grid]::SetColumn($btn, 2)
    $grid.Children.Add($btn) | Out-Null

    $card.Child = $grid
    $spTools.Children.Add($card) | Out-Null

    # Capture for closure
    $capturedScript = $scriptPath
    $capturedName   = $toolName

    $btn.Add_Click({
        $ps = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        try {
            Start-Process $ps -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$capturedScript`"" -ErrorAction Stop
            $txtStatus.Text = "Launched: $capturedName"
        } catch {
            [System.Windows.MessageBox]::Show("Failed to launch '$capturedName':`n$_", $Script:AppName, 'OK', 'Error')
        }
    }.GetNewClosure())
}

# ─── Load System Stats ────────────────────────────────────────────────────────
function Load-SystemStats {
    $s = Get-SystemStats

    # OS
    $txtOS.Text   = "$($s['OSName'])"
    $txtBoot.Text = if ($s['LastBoot']) { "Last boot: $($s['LastBoot'].ToString('ddd MMM d, HH:mm'))" } else { '' }

    # CPU
    $pct = $s['CPUPct']
    $pbCPU.Value  = $pct
    $txtCPU.Text  = "$pct%"
    $pbCPU.Foreground = if ($pct -gt 85) {
        [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,60,60))
    } elseif ($pct -gt 60) {
        [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,160,40))
    } else {
        [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(0,120,212))
    }

    # RAM
    $ramPct = $s['UsedRAMPct']
    $pbRAM.Value  = $ramPct
    $usedGB   = if ($s['TotalRAM'] -gt 0) { Format-FileSize ($s['TotalRAM'] - $s['FreeRAM']) } else { '?' }
    $totalGB  = if ($s['TotalRAM'] -gt 0) { Format-FileSize $s['TotalRAM'] } else { '?' }
    $txtRAM.Text  = "$usedGB / $totalGB  ($ramPct%)"
    $pbRAM.Foreground = if ($ramPct -gt 85) {
        [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,60,60))
    } else {
        [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(123,94,167))
    }

    # Drives
    $spDrives.Children.Clear()
    foreach ($drv in $s['Drives']) {
        $dg = [System.Windows.Controls.Grid]::new()
        $dg.Margin = [System.Windows.Thickness](0,0,0,10)
        $dc0 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
        $dc1 = [System.Windows.Controls.ColumnDefinition]::new()
        $dc1.Width = [System.Windows.GridLength]::new(1,[System.Windows.GridUnitType]::Star)
        $dc2 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
        $dg.ColumnDefinitions.Add($dc0); $dg.ColumnDefinitions.Add($dc1); $dg.ColumnDefinitions.Add($dc2)
        $dg.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::Auto })
        $dg.RowDefinitions.Add([System.Windows.Controls.RowDefinition]@{ Height = [System.Windows.GridLength]::Auto })

        $nameTB = [System.Windows.Controls.TextBlock]@{
            Text      = $drv.Name
            FontWeight = [System.Windows.FontWeights]::SemiBold
            Margin    = [System.Windows.Thickness](0,0,8,2)
        }
        [System.Windows.Controls.Grid]::SetColumn($nameTB,0); [System.Windows.Controls.Grid]::SetRow($nameTB,0)
        $dg.Children.Add($nameTB) | Out-Null

        $usedTB = [System.Windows.Controls.TextBlock]@{
            Text      = "$(Format-FileSize $drv.Used) used"
            Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(170,170,170))
            FontSize  = 11
            Margin    = [System.Windows.Thickness](0,0,0,2)
        }
        [System.Windows.Controls.Grid]::SetColumn($usedTB,1); [System.Windows.Controls.Grid]::SetRow($usedTB,0)
        $dg.Children.Add($usedTB) | Out-Null

        $freeTB = [System.Windows.Controls.TextBlock]@{
            Text      = "$(Format-FileSize $drv.Free) free"
            Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,180,100))
            FontSize  = 11
            HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
            Margin    = [System.Windows.Thickness](0,0,0,2)
        }
        [System.Windows.Controls.Grid]::SetColumn($freeTB,2); [System.Windows.Controls.Grid]::SetRow($freeTB,0)
        $dg.Children.Add($freeTB) | Out-Null

        $pb = [System.Windows.Controls.ProgressBar]@{
            Minimum = 0; Maximum = 100; Value = $drv.PctUsed
            Height  = 8
            BorderThickness = [System.Windows.Thickness]0
            Foreground = if ($drv.PctUsed -gt 90) {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,60,60))
            } elseif ($drv.PctUsed -gt 75) {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,160,40))
            } else {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(0,160,90))
            }
            Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(56,56,56))
        }
        [System.Windows.Controls.Grid]::SetColumnSpan($pb,3); [System.Windows.Controls.Grid]::SetRow($pb,1)
        $dg.Children.Add($pb) | Out-Null

        $spDrives.Children.Add($dg) | Out-Null
    }
}

function Load-Activity {
    $lines = Get-RecentLogLines
    if ($lines.Count -eq 0) {
        $txtActivity.Text = 'No activity yet. Launch a tool to get started.'
    } else {
        $txtActivity.Text = ($lines -join "`n")
    }
}

$btnRefreshStats.Add_Click({
    Load-SystemStats
    Load-Activity
    $txtStatus.Text = "Refreshed at $(Get-Date -Format 'HH:mm:ss')"
})

$btnOpenLogDir.Add_Click({
    if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList $Script:LogDir
})

$window.Add_Loaded({
    Load-SystemStats
    Load-Activity
    $txtStatus.Text = "Ready"
})

[void]$window.ShowDialog()
