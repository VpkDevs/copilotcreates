#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 Startup Manager – Take control of what runs at login.
.DESCRIPTION
    A WPF-based GUI tool that shows every startup entry across all registry hives
    and startup folders, letting you enable, disable, or remove them safely.

    Sources Covered
    ---------------
    • HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
    • HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
    • HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
    • HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run
    • HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce
    • User Startup Folder   (%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup)
    • Common Startup Folder (%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs\Startup)

    Features
    --------
    • Self-elevating to Administrator for full HKLM access
    • Colour-coded enable/disable status badges
    • Inline enable / disable toggle without removing the entry
    • Safe Remove with confirmation and backup to registry/JSON
    • Publisher resolution via file signing certificates
    • Search / filter the list in real time
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
        $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        try {
            Start-Process $psExe -ArgumentList $argLine -Verb RunAs -ErrorAction Stop
            exit 0
        } catch {
            # User declined UAC – continue with limited access
        }
    }
}
Invoke-SelfElevation

# ─── Assemblies ──────────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ─── Constants ───────────────────────────────────────────────────────────────
$Script:AppName     = 'Startup Manager'
$Script:Version     = '1.0.0'
$Script:LogDir      = Join-Path $env:APPDATA 'CopilotOrganizer\Logs'
$Script:LogFile     = Join-Path $Script:LogDir ("StartupManager_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Script:BackupFile  = Join-Path $env:APPDATA 'CopilotOrganizer\startup_backup.json'
$Script:IsAdmin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Disabled entries are stored under these parallel keys
$Script:DisabledRunKey  = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
$Script:DisabledRun32   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'
$Script:DisabledRunOnce = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\RunOnce'

# ─── Logging ─────────────────────────────────────────────────────────────────
function Initialize-Log {
    if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
}
function Write-Log {
    param([string]$Msg, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level = 'INFO')
    Add-Content -Path $Script:LogFile -Value "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Msg" -Encoding UTF8
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Get-FilePublisher {
    param([string]$FilePath)
    if (-not $FilePath) { return 'Unknown' }
    # Strip arguments from path (e.g. "C:\foo\bar.exe" /arg)
    $exe = $FilePath.Trim('"').Split(' ')[0].Trim()
    if (-not (Test-Path $exe -PathType Leaf)) { return 'File not found' }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $exe -ErrorAction SilentlyContinue
        if ($sig -and $sig.SignerCertificate) { return $sig.SignerCertificate.Subject -replace '^CN=','' -replace ',.*$','' }
        $vi  = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        if ($vi.CompanyName) { return $vi.CompanyName }
    } catch {}
    return 'Unknown'
}

function Get-IsEntryEnabled {
    param([string]$RegPath, [string]$Name)
    # Check StartupApproved keys – a value starting with 03 means DISABLED
    foreach ($approvedKey in @($Script:DisabledRunKey, $Script:DisabledRun32, $Script:DisabledRunOnce)) {
        if (Test-Path $approvedKey) {
            try {
                $val = Get-ItemProperty -Path $approvedKey -Name $Name -ErrorAction Stop
                if ($val.$Name -and $val.$Name[0] -eq 3) { return $false }
            } catch {}
        }
    }
    return $true
}

function Get-AllStartupEntries {
    $entries = [System.Collections.Generic.List[PSObject]]::new()

    $sources = [ordered]@{
        'HKCU Run'        = @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                       Type = 'Registry' }
        'HKCU RunOnce'    = @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';                  Type = 'Registry' }
        'HKLM Run'        = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';                      Type = 'Registry' }
        'HKLM Run32'      = @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';          Type = 'Registry' }
        'HKLM RunOnce'    = @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce';                  Type = 'Registry' }
    }

    foreach ($srcName in $sources.Keys) {
        $src = $sources[$srcName]
        if (-not (Test-Path $src.Path)) { continue }
        try {
            $props = Get-ItemProperty -Path $src.Path -ErrorAction Stop
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -in @('PSPath','PSParentPath','PSChildName','PSProvider','PSDrive')) { continue }
                $cmd       = $prop.Value
                $exePath   = ($cmd -replace '"','').Split(' ')[0]
                $enabled   = Get-IsEntryEnabled -RegPath $src.Path -Name $prop.Name
                $publisher = Get-FilePublisher -FilePath $cmd
                $entries.Add([PSCustomObject]@{
                    Name        = $prop.Name
                    Command     = $cmd
                    Publisher   = $publisher
                    Source      = $srcName
                    SourcePath  = $src.Path
                    Type        = 'Registry'
                    Enabled     = $enabled
                    StatusText  = if ($enabled) { 'Enabled' } else { 'Disabled' }
                    FilePath    = $exePath
                })
            }
        } catch { Write-Log "Error reading '$($src.Path)': $_" -Level WARN }
    }

    # Startup Folders
    $folders = @{
        'User Startup'   = [System.Environment]::GetFolderPath('Startup')
        'Common Startup' = [System.Environment]::GetFolderPath('CommonStartup')
    }
    foreach ($fName in $folders.Keys) {
        $fPath = $folders[$fName]
        if (-not (Test-Path $fPath)) { continue }
        Get-ChildItem -LiteralPath $fPath -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
            $entries.Add([PSCustomObject]@{
                Name       = $_.BaseName
                Command    = $_.FullName
                Publisher  = Get-FilePublisher -FilePath $_.FullName
                Source     = $fName
                SourcePath = $fPath
                Type       = 'Folder'
                Enabled    = $true
                StatusText = 'Enabled'
                FilePath   = $_.FullName
            })
        }
    }

    return $entries
}

# ─── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="🚀  Startup Manager  v1.0"
    Height="700" Width="1050" MinHeight="500" MinWidth="800"
    WindowStartupLocation="CenterScreen"
    Background="#1C1C1C" Foreground="#FFFFFF"
    FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background"      Value="#0078D4"/>
      <Setter Property="Foreground"      Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"         Value="16,8"/>
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
              <Trigger Property="IsEnabled"   Value="False"><Setter Property="Foreground" Value="#666"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="ToggleEnableBtn" TargetType="Button" BasedOn="{StaticResource SecondaryBtn}">
      <Setter Property="Foreground" Value="#3CB371"/>
      <Setter Property="BorderBrush" Value="#1A6040"/>
    </Style>

    <Style x:Key="RemoveBtn" TargetType="Button" BasedOn="{StaticResource SecondaryBtn}">
      <Setter Property="Foreground" Value="#FF6B6B"/>
      <Setter Property="BorderBrush" Value="#882020"/>
    </Style>

    <Style TargetType="DataGrid">
      <Setter Property="Background"            Value="#2D2D2D"/>
      <Setter Property="Foreground"            Value="#FFF"/>
      <Setter Property="BorderThickness"       Value="0"/>
      <Setter Property="GridLinesVisibility"   Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#444"/>
      <Setter Property="RowBackground"         Value="#2D2D2D"/>
      <Setter Property="AlternatingRowBackground" Value="#333"/>
      <Setter Property="AutoGenerateColumns"   Value="False"/>
      <Setter Property="CanUserAddRows"        Value="False"/>
      <Setter Property="IsReadOnly"            Value="True"/>
      <Setter Property="SelectionMode"         Value="Single"/>
      <Setter Property="HeadersVisibility"     Value="Column"/>
      <Setter Property="ColumnHeaderHeight"    Value="36"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background"    Value="#1C1C1C"/>
      <Setter Property="Foreground"    Value="#AAA"/>
      <Setter Property="FontWeight"    Value="SemiBold"/>
      <Setter Property="Padding"       Value="8,0"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="BorderBrush"   Value="#444"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Foreground" Value="#FFF"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#404040"/></Trigger>
        <Trigger Property="IsSelected"  Value="True"><Setter Property="Background" Value="#1A4E7A"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="Padding"         Value="8,4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Padding="{TemplateBinding Padding}" Background="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background"    Value="#383838"/>
      <Setter Property="Foreground"    Value="#FFF"/>
      <Setter Property="BorderBrush"   Value="#555"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"       Value="8,6"/>
      <Setter Property="CaretBrush"    Value="White"/>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Title Bar -->
    <Border Grid.Row="0" Background="#111111">
      <Grid Margin="20,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="🚀" FontSize="28" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Startup Manager" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Control every program that runs when Windows starts" Foreground="#888" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Border x:Name="adminBadge" CornerRadius="4" Padding="8,3" Margin="0,0,8,0">
            <TextBlock x:Name="adminLabel" FontSize="11" FontWeight="SemiBold"/>
          </Border>
          <TextBlock x:Name="txtEntryCount" Text="" Foreground="#555" FontSize="11" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Toolbar: Refresh + Search + Action Buttons -->
    <Border Grid.Row="1" Background="#252525" Padding="20,10" BorderThickness="0,0,0,1" BorderBrush="#333">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <Button Grid.Column="0" x:Name="btnRefresh"  Content="🔄  Refresh"          Style="{StaticResource PrimaryBtn}"/>
        <TextBlock Grid.Column="1" Text="Search:" VerticalAlignment="Center" Margin="16,0,8,0" Foreground="#AAA"/>
        <TextBox   Grid.Column="2" x:Name="txtSearch" VerticalAlignment="Center" Height="32"/>

        <Button Grid.Column="3" x:Name="btnToggleEnable" Content="⏸  Disable Selected" Style="{StaticResource ToggleEnableBtn}" Margin="8,0,0,0" IsEnabled="False"/>
        <Button Grid.Column="4" x:Name="btnRemove"       Content="🗑  Remove Selected"  Style="{StaticResource RemoveBtn}"      Margin="8,0,0,0" IsEnabled="False"/>
        <Button Grid.Column="5" x:Name="btnOpenFile"     Content="📂 Open Location"    Style="{StaticResource SecondaryBtn}"   Margin="8,0,0,0" IsEnabled="False"/>
      </Grid>
    </Border>

    <!-- DataGrid -->
    <Border Grid.Row="2" Margin="20,12,20,0">
      <DataGrid x:Name="dgStartup">
        <DataGrid.Columns>
          <DataGridTextColumn Header="Name"       Binding="{Binding Name}"       Width="1.5*"/>
          <DataGridTextColumn Header="Status"     Binding="{Binding StatusText}" Width="85"/>
          <DataGridTextColumn Header="Publisher"  Binding="{Binding Publisher}"  Width="1.5*"/>
          <DataGridTextColumn Header="Source"     Binding="{Binding Source}"     Width="120"/>
          <DataGridTextColumn Header="Command"    Binding="{Binding Command}"    Width="3*"/>
        </DataGrid.Columns>
      </DataGrid>
    </Border>

    <!-- Log -->
    <Border Grid.Row="3" Margin="20,10,20,0" Background="#252525" CornerRadius="6" Height="90">
      <ScrollViewer x:Name="svLog" VerticalScrollBarVisibility="Auto">
        <TextBlock x:Name="txtLog" Foreground="#AAA" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" Padding="8"/>
      </ScrollViewer>
    </Border>

    <!-- Bottom bar -->
    <Border Grid.Row="4" Padding="20,12,20,16">
      <Grid>
        <TextBlock x:Name="txtDetail" Foreground="#888" FontSize="11" VerticalAlignment="Center"
                   TextTrimming="CharacterEllipsis"/>
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
$dgStartup       = $window.FindName('dgStartup')
$btnRefresh      = $window.FindName('btnRefresh')
$txtSearch       = $window.FindName('txtSearch')
$btnToggleEnable = $window.FindName('btnToggleEnable')
$btnRemove       = $window.FindName('btnRemove')
$btnOpenFile     = $window.FindName('btnOpenFile')
$txtLog          = $window.FindName('txtLog')
$svLog           = $window.FindName('svLog')
$txtDetail       = $window.FindName('txtDetail')
$btnOpenLog      = $window.FindName('btnOpenLog')
$btnClearLog     = $window.FindName('btnClearLog')
$adminBadge      = $window.FindName('adminBadge')
$adminLabel      = $window.FindName('adminLabel')
$txtEntryCount   = $window.FindName('txtEntryCount')

# ─── Admin Badge ─────────────────────────────────────────────────────────────
if ($Script:IsAdmin) {
    $adminBadge.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(20,100,40))
    $adminLabel.Text       = '🔐 Administrator'
    $adminLabel.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(100,220,100))
} else {
    $adminBadge.Background = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(80,60,10))
    $adminLabel.Text       = '⚠ Limited (Non-Admin)'
    $adminLabel.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.Color]::FromRgb(220,180,50))
}

# ─── State ───────────────────────────────────────────────────────────────────
$Script:AllEntries = [System.Collections.Generic.List[PSObject]]::new()

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Append-Log {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg`n"
    $txtLog.Dispatcher.Invoke([action]{ $txtLog.Text += $line; $svLog.ScrollToBottom() })
}

function Refresh-Grid {
    param([string]$Filter = '')
    if ($Filter) {
        $filtered = $Script:AllEntries | Where-Object {
            $_.Name -like "*$Filter*" -or $_.Publisher -like "*$Filter*" -or
            $_.Command -like "*$Filter*" -or $_.Source -like "*$Filter*"
        }
    } else { $filtered = $Script:AllEntries }
    $dgStartup.Dispatcher.Invoke([action]{
        $dgStartup.ItemsSource = $filtered
        $txtEntryCount.Text    = "$($Script:AllEntries.Count) entries"
    })
}

function Load-StartupEntries {
    Append-Log "Loading startup entries…"
    $Script:AllEntries = Get-AllStartupEntries
    Refresh-Grid
    Append-Log "Loaded $($Script:AllEntries.Count) startup entries."
    Write-Log "Loaded $($Script:AllEntries.Count) entries" -Level INFO
}

# ─── Events ──────────────────────────────────────────────────────────────────
$btnRefresh.Add_Click({ Load-StartupEntries })

$txtSearch.Add_TextChanged({ Refresh-Grid -Filter $txtSearch.Text })

$dgStartup.Add_SelectionChanged({
    $sel = $dgStartup.SelectedItem
    if (-not $sel) {
        $btnToggleEnable.IsEnabled = $false
        $btnRemove.IsEnabled       = $false
        $btnOpenFile.IsEnabled     = $false
        $txtDetail.Text            = ''
        return
    }
    $btnRemove.IsEnabled       = $true
    $btnOpenFile.IsEnabled     = $true
    $btnToggleEnable.IsEnabled = ($sel.Type -eq 'Registry')
    $btnToggleEnable.Content   = if ($sel.Enabled) { '⏸  Disable Selected' } else { '▶  Enable Selected' }
    $txtDetail.Text            = "Path: $($sel.Command)"
})

# ─── Toggle Enable ────────────────────────────────────────────────────────────
$btnToggleEnable.Add_Click({
    $sel = $dgStartup.SelectedItem
    if (-not $sel -or $sel.Type -ne 'Registry') { return }

    if ($sel.Enabled) {
        # Disable: write 03 00 00 00 00 00 00 00 00 00 00 00 to StartupApproved
        try {
            $approvedPath = $Script:DisabledRunKey
            if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
            # 12-byte binary: 03 = disabled flag
            $bytes = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
            Set-ItemProperty -Path $approvedPath -Name $sel.Name -Value $bytes -Type Binary -ErrorAction Stop
            $sel.Enabled    = $false
            $sel.StatusText = 'Disabled'
            Append-Log "⏸ Disabled: '$($sel.Name)'"
            Write-Log "Disabled startup entry '$($sel.Name)' ($($sel.Source))" -Level SUCCESS
        } catch {
            [System.Windows.MessageBox]::Show("Could not disable entry: $_", $Script:AppName, 'OK', 'Error')
            Write-Log "Error disabling '$($sel.Name)': $_" -Level ERROR
        }
    } else {
        # Enable: write 02 00 00 00 00 00 00 00 00 00 00 00 (or remove the key)
        try {
            $approvedPath = $Script:DisabledRunKey
            if (Test-Path $approvedPath) {
                $bytes = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0)
                Set-ItemProperty -Path $approvedPath -Name $sel.Name -Value $bytes -Type Binary -ErrorAction Stop
            }
            $sel.Enabled    = $true
            $sel.StatusText = 'Enabled'
            Append-Log "▶ Enabled: '$($sel.Name)'"
            Write-Log "Enabled startup entry '$($sel.Name)' ($($sel.Source))" -Level SUCCESS
        } catch {
            [System.Windows.MessageBox]::Show("Could not enable entry: $_", $Script:AppName, 'OK', 'Error')
            Write-Log "Error enabling '$($sel.Name)': $_" -Level ERROR
        }
    }

    $btnToggleEnable.Content = if ($sel.Enabled) { '⏸  Disable Selected' } else { '▶  Enable Selected' }
    $dgStartup.Items.Refresh()
})

# ─── Remove ──────────────────────────────────────────────────────────────────
$btnRemove.Add_Click({
    $sel = $dgStartup.SelectedItem
    if (-not $sel) { return }

    $conf = [System.Windows.MessageBox]::Show(
        "Remove '$($sel.Name)' from startup?`n`nSource: $($sel.Source)`nCommand: $($sel.Command)`n`n" +
        "⚠ This permanently removes the startup entry (the program itself is NOT deleted).",
        $Script:AppName, 'YesNo', 'Warning')
    if ($conf -ne 'Yes') { return }

    # Backup first
    try {
        if (-not (Test-Path $Script:BackupFile)) {
            '[]' | Set-Content $Script:BackupFile -Encoding UTF8
        }
        $backups = Get-Content $Script:BackupFile -Raw | ConvertFrom-Json
        if (-not $backups) { $backups = @() }
        $backups += [PSCustomObject]@{
            Name       = $sel.Name
            Command    = $sel.Command
            Source     = $sel.Source
            SourcePath = $sel.SourcePath
            Type       = $sel.Type
            RemovedAt  = (Get-Date -Format 'o')
        }
        $backups | ConvertTo-Json -Depth 4 | Set-Content $Script:BackupFile -Encoding UTF8
    } catch { Write-Log "Backup failed: $_" -Level WARN }

    try {
        if ($sel.Type -eq 'Registry') {
            Remove-ItemProperty -Path $sel.SourcePath -Name $sel.Name -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $sel.FilePath -Force -ErrorAction Stop
        }
        $Script:AllEntries.Remove($sel) | Out-Null
        Refresh-Grid -Filter $txtSearch.Text
        Append-Log "🗑 Removed: '$($sel.Name)' from $($sel.Source)"
        Write-Log "Removed startup entry '$($sel.Name)' ($($sel.Source))" -Level SUCCESS
        [System.Windows.MessageBox]::Show("'$($sel.Name)' has been removed from startup.`nA backup was saved to:`n$($Script:BackupFile)", $Script:AppName, 'OK', 'Information')
    } catch {
        [System.Windows.MessageBox]::Show("Could not remove entry: $_", $Script:AppName, 'OK', 'Error')
        Write-Log "Error removing '$($sel.Name)': $_" -Level ERROR
    }
})

# ─── Open File Location ───────────────────────────────────────────────────────
$btnOpenFile.Add_Click({
    $sel = $dgStartup.SelectedItem
    if (-not $sel) { return }
    $exePath = ($sel.Command -replace '"','').Split(' ')[0].Trim()
    if (Test-Path $exePath) {
        Start-Process explorer.exe -ArgumentList "/select,`"$exePath`""
    } else {
        [System.Windows.MessageBox]::Show("File not found:`n$exePath", $Script:AppName, 'OK', 'Warning')
    }
})

$btnOpenLog.Add_Click({
    if (Test-Path $Script:LogFile) { Start-Process notepad.exe $Script:LogFile }
    else { [System.Windows.MessageBox]::Show('No log yet.', $Script:AppName, 'OK', 'Information') }
})
$btnClearLog.Add_Click({ $txtLog.Text = '' })

$window.Add_Loaded({
    Initialize-Log
    Append-Log "Welcome to $($Script:AppName) v$($Script:Version)"
    Write-Log "Application started"
    Load-StartupEntries
})

[void]$window.ShowDialog()
Write-Log "Application closed"
