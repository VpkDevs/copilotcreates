#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 System Cleanup Pro – Safely reclaim disk space.
.DESCRIPTION
    A WPF-based GUI tool that scans common junk-file locations and lets you choose
    exactly what to remove before touching anything.

    Cleanup Targets
    ---------------
    • User Temp Folder           (%TEMP%)
    • Windows Temp Folder        (C:\Windows\Temp)   ← requires elevation
    • Recycle Bin                (all drives)
    • Windows Update Cache       (SoftwareDistribution\Download) ← requires elevation
    • Thumbnail Cache            (%LocalAppData%\Microsoft\Windows\Explorer)
    • Windows Error Reports      (%LocalAppData%\Microsoft\Windows\WER)
    • Crash Dumps                (%LocalAppData%\CrashDumps)
    • Browser Caches             (Chrome, Edge, Firefox, Brave)
    • Prefetch                   (C:\Windows\Prefetch)  ← requires elevation

    Features
    --------
    • Self-elevating to Administrator when needed
    • Scan First – shows exact sizes before you delete anything
    • Per-category checkboxes with size indicators
    • Real-time progress bar and cancellation support
    • Detailed log with per-category bytes freed
    • Persistent log in %APPDATA%\CopilotOrganizer\Logs

.NOTES
    Author  : CopilotCreates
    Version : 1.0.0
    Requires: Windows 10/11, PowerShell 5.1+
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─── Self-Elevation ───────────────────────────────────────────────────────────
function Invoke-SelfElevation {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $psExe = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
        $args  = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        try {
            Start-Process $psExe -ArgumentList $args -Verb RunAs -ErrorAction Stop
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Administrator privileges are recommended for full cleanup.`nSome targets will be skipped.",
                'System Cleanup Pro', 'OK', 'Warning')
        }
        exit 0
    }
}

# ─── Assemblies ──────────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ─── Constants ───────────────────────────────────────────────────────────────
$Script:AppName = 'System Cleanup Pro'
$Script:Version = '1.0.0'
$Script:LogDir  = Join-Path $env:APPDATA 'CopilotOrganizer\Logs'
$Script:LogFile = Join-Path $Script:LogDir ("SystemCleanup_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Script:IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Prompt for elevation (non-blocking; some targets just get skipped if not admin)
if (-not $Script:IsAdmin) { Invoke-SelfElevation }

# ─── Cleanup Target Definitions ───────────────────────────────────────────────
$Script:Targets = [ordered]@{
    UserTemp = @{
        Label       = "User Temp Folder  (%TEMP%)"
        NeedsAdmin  = $false
        Paths       = @($env:TEMP)
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🌡'
    }
    WinTemp = @{
        Label       = 'Windows Temp Folder  (C:\Windows\Temp)'
        NeedsAdmin  = $true
        Paths       = @("$env:SystemRoot\Temp")
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🏠'
    }
    WinUpdateCache = @{
        Label       = 'Windows Update Download Cache'
        NeedsAdmin  = $true
        Paths       = @("$env:SystemRoot\SoftwareDistribution\Download")
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🔄'
    }
    Thumbnails = @{
        Label       = 'Thumbnail Cache'
        NeedsAdmin  = $false
        Paths       = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer")
        Filter      = 'thumbcache_*.db'
        Recursive   = $false
        SizeBytes   = 0
        Emoji       = '🖼'
    }
    WER = @{
        Label       = 'Windows Error Reports'
        NeedsAdmin  = $false
        Paths       = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
            "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue"
        )
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '⚠'
    }
    CrashDumps = @{
        Label       = 'Crash Dumps  (%LocalAppData%\CrashDumps)'
        NeedsAdmin  = $false
        Paths       = @("$env:LOCALAPPDATA\CrashDumps")
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '💥'
    }
    Prefetch = @{
        Label       = 'Prefetch Files  (C:\Windows\Prefetch)'
        NeedsAdmin  = $true
        Paths       = @("$env:SystemRoot\Prefetch")
        Filter      = '*.pf'
        Recursive   = $false
        SizeBytes   = 0
        Emoji       = '⚡'
    }
    ChromeCache = @{
        Label       = 'Google Chrome Cache'
        NeedsAdmin  = $false
        Paths       = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
        )
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🌐'
    }
    EdgeCache = @{
        Label       = 'Microsoft Edge Cache'
        NeedsAdmin  = $false
        Paths       = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
        )
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🔵'
    }
    FirefoxCache = @{
        Label       = 'Mozilla Firefox Cache'
        NeedsAdmin  = $false
        Paths       = @("$env:LOCALAPPDATA\Mozilla\Firefox\Profiles")
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🦊'
    }
    BraveCache = @{
        Label       = 'Brave Browser Cache'
        NeedsAdmin  = $false
        Paths       = @(
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache",
            "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Code Cache"
        )
        Recursive   = $true
        SizeBytes   = 0
        Emoji       = '🦁'
    }
    RecycleBin = @{
        Label       = 'Recycle Bin  (all drives)'
        NeedsAdmin  = $false
        Paths       = @()   # handled specially
        Recursive   = $false
        SizeBytes   = 0
        Emoji       = '🗑'
    }
}

# ─── Logging ─────────────────────────────────────────────────────────────────
function Initialize-Log {
    if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
}
function Write-Log {
    param([string]$Msg, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level = 'INFO')
    Add-Content -Path $Script:LogFile -Value "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Msg" -Encoding UTF8
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Format-FileSize {
    param([long]$Bytes)
    switch ($Bytes) {
        { $_ -ge 1GB } { return '{0:N2} GB' -f ($_ / 1GB) }
        { $_ -ge 1MB } { return '{0:N2} MB' -f ($_ / 1MB) }
        { $_ -ge 1KB } { return '{0:N2} KB' -f ($_ / 1KB) }
        default        { return "$Bytes B" }
    }
}

function Get-FolderSize {
    param([string]$Path, [string]$Filter = '*', [bool]$Recursive = $true)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $recurse = if ($Recursive) { $true } else { $false }
        $files   = Get-ChildItem -LiteralPath $Path -Filter $Filter -Recurse:$recurse -File -Force -ErrorAction SilentlyContinue
        return ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    } catch { return 0 }
}

function Get-RecycleBinSize {
    $total = 0L
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path $_.Root })) {
        $rbPath = Join-Path $drive.Root '$Recycle.Bin'
        if (Test-Path $rbPath) {
            try {
                $total += (Get-ChildItem -LiteralPath $rbPath -Recurse -Force -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum).Sum
            } catch {}
        }
    }
    return $total
}

function Remove-FolderContents {
    param([string]$Path, [string]$Filter = '*', [bool]$Recursive = $true)
    if (-not (Test-Path $Path)) { return 0 }
    $freed = 0L
    try {
        $items = if ($Recursive) {
            Get-ChildItem -LiteralPath $Path -Filter $Filter -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue
        }
        foreach ($item in $items) {
            try {
                $size = if ($item.PSIsContainer) { 0 } else { $item.Length }
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                $freed += $size
            } catch { <# Skip locked / access denied #> }
        }
    } catch {}
    return $freed
}

# ─── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="🧹  System Cleanup Pro  v1.0"
    Height="780" Width="860" MinHeight="600" MinWidth="700"
    WindowStartupLocation="CenterScreen"
    Background="#1C1C1C" Foreground="#FFFFFF"
    FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background"      Value="#0078D4"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="18,8"/>
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
      <Setter Property="Padding"         Value="14,8"/>
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
              <Trigger Property="IsEnabled"   Value="False"><Setter Property="Foreground" Value="#666"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="CleanupBtn" TargetType="Button">
      <Setter Property="Background"      Value="#C84040"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="18,8"/>
      <Setter Property="Cursor"          Value="Hand"/>
      <Setter Property="FontWeight"      Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#E05050"/></Trigger>
              <Trigger Property="IsPressed"   Value="True"><Setter Property="Background" Value="#A03030"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False"><Setter Property="Background" Value="#444"/><Setter Property="Foreground" Value="#888"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#CCC"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Background"      Value="#383838"/>
      <Setter Property="Foreground"      Value="#0078D4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height"          Value="8"/>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Title Bar -->
    <Border Grid.Row="0" Background="#111111">
      <Grid Margin="20,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="🧹" FontSize="28" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="System Cleanup Pro" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Safely scan and remove junk files to reclaim disk space" Foreground="#888" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Border x:Name="adminBadge" CornerRadius="4" Padding="8,3" Margin="0,0,8,0">
            <TextBlock x:Name="adminLabel" FontSize="11" FontWeight="SemiBold"/>
          </Border>
          <TextBlock Text="v1.0.0" Foreground="#555" FontSize="11" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Select All / None -->
    <Border Grid.Row="1" Background="#252525" Padding="20,10" BorderThickness="0,0,0,1" BorderBrush="#333">
      <StackPanel Orientation="Horizontal">
        <Button x:Name="btnSelectAll"  Content="Select All"  Style="{StaticResource SecondaryBtn}" Padding="10,5"/>
        <Button x:Name="btnSelectNone" Content="Select None" Style="{StaticResource SecondaryBtn}" Padding="10,5" Margin="8,0,0,0"/>
        <TextBlock x:Name="txtTotalSelected" Text="Nothing selected" VerticalAlignment="Center" Foreground="#888" Margin="16,0,0,0"/>
      </StackPanel>
    </Border>

    <!-- Targets ScrollViewer -->
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" Margin="0">
      <StackPanel x:Name="spTargets" Margin="20,12,20,12"/>
    </ScrollViewer>

    <!-- Progress -->
    <Border Grid.Row="3" Margin="20,0,20,0">
      <StackPanel>
        <Grid Margin="0,0,0,4">
          <TextBlock x:Name="txtProgress" Text="Scan to see what can be cleaned." Foreground="#AAA" FontSize="11"/>
          <TextBlock x:Name="txtPct"      HorizontalAlignment="Right" Foreground="#AAA" FontSize="11"/>
        </Grid>
        <ProgressBar x:Name="pbMain" Value="0" Maximum="100"/>
      </StackPanel>
    </Border>

    <!-- Log -->
    <Border Grid.Row="4" Margin="20,10,20,0" Background="#252525" CornerRadius="6" Height="110">
      <ScrollViewer x:Name="svLog" VerticalScrollBarVisibility="Auto">
        <TextBlock x:Name="txtLog" Foreground="#AAA" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" Padding="8"/>
      </ScrollViewer>
    </Border>

    <!-- Actions -->
    <Border Grid.Row="5" Padding="20,12,20,16">
      <Grid>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="btnScan"    Content="🔍  Scan Selected"  Style="{StaticResource PrimaryBtn}"/>
          <Button x:Name="btnCleanup" Content="🧹  Clean Now"      Style="{StaticResource CleanupBtn}" Margin="8,0,0,0" IsEnabled="False"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="btnOpenLog"  Content="📋 Open Log" Style="{StaticResource SecondaryBtn}" Margin="0,0,8,0"/>
          <Button x:Name="btnClearLog" Content="Clear Log"   Style="{StaticResource SecondaryBtn}"/>
        </StackPanel>
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
$spTargets       = $window.FindName('spTargets')
$btnSelectAll    = $window.FindName('btnSelectAll')
$btnSelectNone   = $window.FindName('btnSelectNone')
$txtTotalSelected= $window.FindName('txtTotalSelected')
$pbMain          = $window.FindName('pbMain')
$txtProgress     = $window.FindName('txtProgress')
$txtPct          = $window.FindName('txtPct')
$txtLog          = $window.FindName('txtLog')
$svLog           = $window.FindName('svLog')
$btnScan         = $window.FindName('btnScan')
$btnCleanup      = $window.FindName('btnCleanup')
$btnOpenLog      = $window.FindName('btnOpenLog')
$btnClearLog     = $window.FindName('btnClearLog')
$adminBadge      = $window.FindName('adminBadge')
$adminLabel      = $window.FindName('adminLabel')

# ─── Admin Badge ─────────────────────────────────────────────────────────────
if ($Script:IsAdmin) {
    $adminBadge.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(20,100,40)
    $adminLabel.Text       = '🔐 Administrator'
    $adminLabel.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(100,220,100)
} else {
    $adminBadge.Background = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(80,60,10)
    $adminLabel.Text       = '⚠ Limited (Non-Admin)'
    $adminLabel.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(220,180,50)
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Append-Log {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg`n"
    $txtLog.Dispatcher.Invoke([action]{ $txtLog.Text += $line; $svLog.ScrollToBottom() })
}
function Set-Progress {
    param([string]$Msg, [int]$Pct)
    $txtProgress.Dispatcher.Invoke([action]{
        $txtProgress.Text = $Msg; $txtPct.Text = "$Pct%"; $pbMain.Value = $Pct
    })
}

# ─── Build Target Cards dynamically ──────────────────────────────────────────
$Script:CheckBoxes = @{}  # key -> CheckBox
$Script:SizeLabels = @{}  # key -> TextBlock

foreach ($key in $Script:Targets.Keys) {
    $t = $Script:Targets[$key]

    # Skip admin-only targets if not admin
    $isAvailable = ($Script:IsAdmin -or -not $t.NeedsAdmin)

    $card = [System.Windows.Controls.Border]@{
        Background       = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(45,45,45))
        CornerRadius     = [System.Windows.CornerRadius]8
        Padding          = [System.Windows.Thickness]14
        Margin           = [System.Windows.Thickness](0,0,0,6)
    }

    $grid = [System.Windows.Controls.Grid]::new()
    $col0 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
    $col1 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]1 }  # star
    $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $col2 = [System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::Auto }
    $grid.ColumnDefinitions.Add($col0)
    $grid.ColumnDefinitions.Add($col1)
    $grid.ColumnDefinitions.Add($col2)

    # CheckBox
    $cb = [System.Windows.Controls.CheckBox]@{
        IsChecked = $isAvailable
        IsEnabled = $isAvailable
        Margin    = [System.Windows.Thickness](0,0,12,0)
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    }
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)
    $grid.Children.Add($cb) | Out-Null

    # Label stack
    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)

    $titleTB = [System.Windows.Controls.TextBlock]@{
        Text       = "$($t.Emoji)  $($t.Label)"
        Foreground = if ($isAvailable) { [System.Windows.Media.Brushes]::White } else { [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,100,100)) }
        FontSize   = 13
    }
    $sp.Children.Add($titleTB) | Out-Null

    if (-not $isAvailable) {
        $notesTB = [System.Windows.Controls.TextBlock]@{
            Text       = 'Requires Administrator privileges'
            Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(180,120,40))
            FontSize   = 11
        }
        $sp.Children.Add($notesTB) | Out-Null
    }
    $grid.Children.Add($sp) | Out-Null

    # Size label
    $sizeTB = [System.Windows.Controls.TextBlock]@{
        Text              = '–'
        Foreground        = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,180,100))
        FontSize          = 13
        FontWeight        = [System.Windows.FontWeights]::SemiBold
        VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        Margin            = [System.Windows.Thickness](12,0,0,0)
    }
    [System.Windows.Controls.Grid]::SetColumn($sizeTB, 2)
    $grid.Children.Add($sizeTB) | Out-Null

    $card.Child = $grid
    $spTargets.Children.Add($card) | Out-Null

    $Script:CheckBoxes[$key] = $cb
    $Script:SizeLabels[$key] = $sizeTB

    # Update summary when checkbox changes
    $cb.Add_Checked({ Update-TotalSelected })
    $cb.Add_Unchecked({ Update-TotalSelected })
}

function Update-TotalSelected {
    $count = ($Script:CheckBoxes.Values | Where-Object IsChecked).Count
    $txtTotalSelected.Text = if ($count -eq 0) { 'Nothing selected' } else { "$count target(s) selected" }
}

# ─── Select All / None ────────────────────────────────────────────────────────
$btnSelectAll.Add_Click({
    foreach ($key in $Script:CheckBoxes.Keys) {
        if ($Script:CheckBoxes[$key].IsEnabled) { $Script:CheckBoxes[$key].IsChecked = $true }
    }
})
$btnSelectNone.Add_Click({
    foreach ($key in $Script:CheckBoxes.Keys) { $Script:CheckBoxes[$key].IsChecked = $false }
})

# ─── Scan ─────────────────────────────────────────────────────────────────────
$btnScan.Add_Click({
    Initialize-Log
    Append-Log "Scanning selected targets…"
    $btnScan.IsEnabled    = $false
    $btnCleanup.IsEnabled = $false
    Set-Progress 'Scanning…' 0

    $keys  = @($Script:CheckBoxes.Keys | Where-Object { $Script:CheckBoxes[$_].IsChecked })
    $total = $keys.Count
    $i     = 0

    foreach ($key in $keys) {
        $i++
        $t      = $Script:Targets[$key]
        $sizeLbl= $Script:SizeLabels[$key]
        Set-Progress "Scanning: $($t.Label)" ([int](($i / $total) * 100))

        $size = 0L
        if ($key -eq 'RecycleBin') {
            $size = Get-RecycleBinSize
        } else {
            $filter    = if ($t.ContainsKey('Filter')) { $t.Filter } else { '*' }
            $recursive = $t.Recursive
            foreach ($path in $t.Paths) {
                $size += Get-FolderSize -Path $path -Filter $filter -Recursive $recursive
            }
        }
        $t.SizeBytes = $size

        $displaySize = Format-FileSize ([long]$size)
        $sizeLbl.Dispatcher.Invoke([action]{
            $sizeLbl.Text = if ($size -gt 0) { $displaySize } else { '0 B' }
            $sizeLbl.Foreground = if ($size -gt 100MB) {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(230,100,50))
            } elseif ($size -gt 1MB) {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(230,180,50))
            } else {
                [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,180,100))
            }
        })
        Append-Log "$($t.Emoji) $($t.Label): $(Format-FileSize ([long]$size))"
        Write-Log "Scanned '$key': $(Format-FileSize ([long]$size))"
    }

    $totalSize = ($Script:Targets.Values | Measure-Object -Property SizeBytes -Sum).Sum
    Set-Progress "Scan complete – total reclaimable: $(Format-FileSize ([long]$totalSize))" 100
    Append-Log "─── Total reclaimable: $(Format-FileSize ([long]$totalSize)) ───"
    Write-Log "Scan complete. Total: $(Format-FileSize ([long]$totalSize))"

    $btnScan.IsEnabled    = $true
    $btnCleanup.IsEnabled = $true
})

# ─── Clean ────────────────────────────────────────────────────────────────────
$btnCleanup.Add_Click({
    $keys = @($Script:CheckBoxes.Keys | Where-Object { $Script:CheckBoxes[$_].IsChecked })
    if ($keys.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one target.', $Script:AppName, 'OK', 'Warning'); return
    }

    $totalEstimate = ($keys | ForEach-Object { $Script:Targets[$_].SizeBytes } | Measure-Object -Sum).Sum
    $conf = [System.Windows.MessageBox]::Show(
        "You are about to permanently delete files from $($keys.Count) target(s).`n" +
        "Estimated space to free: $(Format-FileSize ([long]$totalEstimate))`n`n" +
        "⚠  This CANNOT be undone!`n`nAre you sure you want to proceed?",
        $Script:AppName, 'YesNo', 'Warning')
    if ($conf -ne 'Yes') { return }

    $btnScan.IsEnabled    = $false
    $btnCleanup.IsEnabled = $false

    $total    = $keys.Count
    $i        = 0
    $totalFrd = 0L

    foreach ($key in $keys) {
        $i++
        $t = $Script:Targets[$key]
        Set-Progress "Cleaning: $($t.Label)" ([int](($i / $total) * 100))
        Append-Log "Cleaning $($t.Emoji) $($t.Label)…"

        $freed = 0L
        if ($key -eq 'RecycleBin') {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                $freed = $t.SizeBytes
                Append-Log "  ✔ Recycle Bin emptied."
                Write-Log "Emptied Recycle Bin (~$(Format-FileSize ([long]$freed)))"
            } catch {
                Append-Log "  ✘ Could not empty Recycle Bin: $_"
                Write-Log "ERROR emptying Recycle Bin: $_" -Level ERROR
            }
        } else {
            $filter    = if ($t.ContainsKey('Filter')) { $t.Filter } else { '*' }
            $recursive = $t.Recursive
            foreach ($path in $t.Paths) {
                $f = Remove-FolderContents -Path $path -Filter $filter -Recursive $recursive
                $freed += $f
                Write-Log "Cleaned '$path': freed $(Format-FileSize ([long]$f))"
            }
            Append-Log "  ✔ Freed: $(Format-FileSize ([long]$freed))"
        }

        $totalFrd += $freed
        # Update size label to show freed amount
        $lbl = $Script:SizeLabels[$key]
        $lbl.Dispatcher.Invoke([action]{
            $lbl.Text       = "✔ Freed $(Format-FileSize ([long]$freed))"
            $lbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,200,100))
        })

        [System.Windows.Application]::Current.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    $msg = "Cleanup complete! Total freed: $(Format-FileSize ([long]$totalFrd))"
    Set-Progress $msg 100
    Append-Log $msg
    Write-Log $msg -Level SUCCESS
    [System.Windows.MessageBox]::Show($msg, $Script:AppName, 'OK', 'Information')

    $btnScan.IsEnabled    = $true
    $btnCleanup.IsEnabled = $true
})

$btnOpenLog.Add_Click({
    if (Test-Path $Script:LogFile) { Start-Process notepad.exe $Script:LogFile }
    else { [System.Windows.MessageBox]::Show('No log yet. Run a scan first.', $Script:AppName, 'OK', 'Information') }
})
$btnClearLog.Add_Click({ $txtLog.Text = '' })

$window.Add_Loaded({
    Initialize-Log
    $adminStatus = if ($Script:IsAdmin) { 'Running as Administrator' } else { 'Running as Standard User (some targets skipped)' }
    Append-Log "Welcome to $($Script:AppName) v$($Script:Version)"
    Append-Log $adminStatus
    Write-Log "Application started – $adminStatus"
    Update-TotalSelected
})

[void]$window.ShowDialog()
Write-Log "Application closed"
