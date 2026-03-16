#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 Downloads Organizer – Tame your Downloads folder with smart sorting.
.DESCRIPTION
    A WPF-based GUI tool that scans your Downloads folder (or any folder) and organises
    files by Type, Date (Year/Month), or a hybrid of both.

    Features
    --------
    • Windows 11 Fluent dark-mode UI
    • Three sort modes: By Type, By Date (Year\Month), By Type+Date
    • Duplicate file detection (MD5 hash comparison) with interactive resolution
    • Archive Old Files – moves items older than N days to an 'Archive' sub-folder
    • Preview / Dry-Run mode before any files are touched
    • Real-time progress bar with cancel support
    • Undo last run (moves files back)
    • Persistent log file in %APPDATA%\CopilotOrganizer\Logs
    • Handles collisions, locked files, and access-denied gracefully

.NOTES
    Author  : CopilotCreates
    Version : 1.0.0
    Requires: Windows 10/11, PowerShell 5.1+
#>

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─── Assembly Imports ────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# ─── Constants ───────────────────────────────────────────────────────────────
$Script:AppName  = 'Downloads Organizer'
$Script:Version  = '1.0.0'
$Script:LogDir   = Join-Path $env:APPDATA 'CopilotOrganizer\Logs'
$Script:UndoFile = Join-Path $env:APPDATA 'CopilotOrganizer\downloads_organizer_undo.json'
$Script:LogFile  = Join-Path $Script:LogDir ("DownloadsOrganizer_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# ─── Category Map ─────────────────────────────────────────────────────────────
$Script:Categories = [ordered]@{
    'Images'     = @('jpg','jpeg','png','gif','bmp','tiff','tif','svg','webp','ico','raw','cr2','nef','heic','heif','avif','jfif','psd','ai','eps')
    'Documents'  = @('pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','odt','ods','odp','csv','md','markdown','epub','mobi','pages','numbers','key')
    'Videos'     = @('mp4','mkv','avi','mov','wmv','flv','webm','m4v','mpg','mpeg','3gp','ts','vob','rm','rmvb','divx')
    'Music'      = @('mp3','flac','wav','aac','ogg','wma','m4a','opus','aiff','ape','mid','midi')
    'Archives'   = @('zip','rar','7z','tar','gz','bz2','xz','iso','dmg','cab','deb','rpm','pkg','jar','war','tar.gz')
    'Programs'   = @('exe','msi','appx','msix','appxbundle','msixbundle','apk','ipa')
    'Code'       = @('py','js','ts','html','htm','css','java','c','cpp','cs','php','rb','go','rs','sh','ps1','sql','json','xml','yaml','yml')
    'Fonts'      = @('ttf','otf','woff','woff2','eot')
    'Other'      = @()
}

# ─── Logging ─────────────────────────────────────────────────────────────────
function Initialize-Log {
    if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }
}
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level = 'INFO')
    Add-Content -Path $Script:LogFile -Value "[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$Level] $Message" -Encoding UTF8
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Get-FileCategory {
    param([string]$Extension)
    $ext = $Extension.TrimStart('.').ToLower()
    foreach ($cat in $Script:Categories.Keys) {
        if ($cat -eq 'Other') { continue }
        if ($Script:Categories[$cat] -contains $ext) { return $cat }
    }
    return 'Other'
}

function Format-FileSize {
    param([long]$Bytes)
    switch ($Bytes) {
        { $_ -ge 1GB } { return '{0:N2} GB' -f ($_ / 1GB) }
        { $_ -ge 1MB } { return '{0:N2} MB' -f ($_ / 1MB) }
        { $_ -ge 1KB } { return '{0:N2} KB' -f ($_ / 1KB) }
        default        { return "$Bytes B" }
    }
}

function Get-UniqueDestPath {
    param([string]$Dest)
    if (-not (Test-Path $Dest)) { return $Dest }
    $dir   = [System.IO.Path]::GetDirectoryName($Dest)
    $name  = [System.IO.Path]::GetFileNameWithoutExtension($Dest)
    $ext   = [System.IO.Path]::GetExtension($Dest)
    $i = 2
    do { $candidate = Join-Path $dir "${name} ($i)${ext}"; $i++ } while (Test-Path $candidate)
    return $candidate
}

function Get-FileMD5 {
    param([string]$Path)
    try {
        $md5    = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($Path)
        $hash   = [BitConverter]::ToString($md5.ComputeHash($stream)).Replace('-','')
        $stream.Close()
        $md5.Dispose()
        return $hash
    } catch { return $null }
}

function Compute-DestPath {
    param([System.IO.FileInfo]$File, [string]$BaseFolder, [string]$Mode)
    $cat = Get-FileCategory -Extension $File.Extension
    switch ($Mode) {
        'ByType'     { return Join-Path (Join-Path $BaseFolder $cat) $File.Name }
        'ByDate'     { return Join-Path (Join-Path $BaseFolder ("{0}\{1:00}" -f $File.LastWriteTime.Year, $File.LastWriteTime.Month)) $File.Name }
        'ByTypeDate' { return Join-Path (Join-Path $BaseFolder ("{0}\{1:00}" -f $File.LastWriteTime.Year, $File.LastWriteTime.Month) | Join-Path -ChildPath $cat) $File.Name }
    }
}

# ─── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="📥  Downloads Organizer  v1.0"
    Height="820" Width="1050" MinHeight="620" MinWidth="820"
    WindowStartupLocation="CenterScreen"
    Background="#1C1C1C" Foreground="#FFFFFF"
    FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <SolidColorBrush x:Key="AccentBrush"      Color="#0078D4"/>
    <SolidColorBrush x:Key="SurfaceBrush"     Color="#2D2D2D"/>
    <SolidColorBrush x:Key="Surface2Brush"    Color="#383838"/>

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

    <Style x:Key="WarningBtn" TargetType="Button" BasedOn="{StaticResource SecondaryBtn}">
      <Setter Property="Foreground"  Value="#E8A820"/>
      <Setter Property="BorderBrush" Value="#A07010"/>
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
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#CCC"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Margin" Value="0,0,16,0"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background"    Value="#383838"/>
      <Setter Property="Foreground"    Value="#FFF"/>
      <Setter Property="BorderBrush"   Value="#555"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"       Value="8,6"/>
      <Setter Property="CaretBrush"    Value="White"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background"    Value="#383838"/>
      <Setter Property="Foreground"    Value="#FFF"/>
      <Setter Property="BorderBrush"   Value="#555"/>
      <Setter Property="Padding"       Value="8,6"/>
      <Setter Property="Height"        Value="32"/>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Background"      Value="#383838"/>
      <Setter Property="Foreground"      Value="#0078D4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height"          Value="6"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>
      <RowDefinition Height="Auto"/>
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
          <TextBlock Text="📥" FontSize="28" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Downloads Organizer" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Sort, de-duplicate, and archive your Downloads folder" Foreground="#888" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <TextBlock Text="v1.0.0" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="#555" FontSize="11"/>
      </Grid>
    </Border>

    <!-- Folder Selection -->
    <Border Grid.Row="1" Background="#252525" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="Folder:" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="#AAA"/>
        <TextBox   Grid.Column="1" x:Name="txtFolder" VerticalAlignment="Center"/>
        <Button    Grid.Column="2" x:Name="btnBrowse" Content="Browse…" Style="{StaticResource SecondaryBtn}" Margin="8,0,0,0" VerticalAlignment="Center"/>
        <Button    Grid.Column="3" x:Name="btnScan"   Content="🔍  Scan"  Style="{StaticResource PrimaryBtn}"   Margin="8,0,0,0" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- Options -->
    <Border Grid.Row="2" Background="#1C1C1C" Padding="20,10" BorderThickness="0,0,0,1" BorderBrush="#333">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Column="0" Text="Sort Mode:" VerticalAlignment="Center" Foreground="#AAA" Margin="0,0,10,0"/>
        <ComboBox  Grid.Column="1" x:Name="cmbMode" Width="200" VerticalAlignment="Center">
          <ComboBoxItem Content="By Type"           Tag="ByType"     IsSelected="True"/>
          <ComboBoxItem Content="By Date (Year/Month)" Tag="ByDate"/>
          <ComboBoxItem Content="By Type + Date"    Tag="ByTypeDate"/>
        </ComboBox>

        <CheckBox x:Name="chkDryRun"      Grid.Column="2" Content="🔎 Preview Only"     IsChecked="True" Margin="16,0,0,0"/>
        <CheckBox x:Name="chkDuplicates"  Grid.Column="3" Content="🔁 Detect Duplicates" IsChecked="True"/>
        <CheckBox x:Name="chkArchiveOld"  Grid.Column="4" Content="📦 Archive older than"/>
        <StackPanel Grid.Column="5" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBox x:Name="txtArchiveDays" Width="45" Text="90" Margin="6,0,4,0"/>
          <TextBlock Text="days" VerticalAlignment="Center" Foreground="#AAA"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Tabs: Files / Duplicates -->
    <TabControl Grid.Row="3" Background="#1C1C1C" BorderThickness="0" Margin="20,12,20,0">
      <TabControl.Resources>
        <Style TargetType="TabItem">
          <Setter Property="Background"  Value="#2D2D2D"/>
          <Setter Property="Foreground"  Value="#AAA"/>
          <Setter Property="Padding"     Value="14,8"/>
          <Setter Property="BorderThickness" Value="0"/>
          <Style.Triggers>
            <Trigger Property="IsSelected" Value="True">
              <Setter Property="Background" Value="#0078D4"/>
              <Setter Property="Foreground" Value="White"/>
            </Trigger>
          </Style.Triggers>
        </Style>
      </TabControl.Resources>

      <!-- Files Tab -->
      <TabItem Header="📂 All Files">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#2D2D2D" Padding="12,8" Margin="0,0,0,1">
            <Grid>
              <StackPanel Orientation="Horizontal">
                <TextBlock x:Name="txtTotalFiles" Text="0 files" FontWeight="SemiBold"/>
                <TextBlock Text=" · " Foreground="#666"/>
                <TextBlock x:Name="txtTotalSize"  Text="0 B" Foreground="#AAA"/>
              </StackPanel>
              <TextBlock x:Name="txtBreakdown" HorizontalAlignment="Right" Foreground="#888" FontSize="11"/>
            </Grid>
          </Border>
          <DataGrid Grid.Row="1" x:Name="dgFiles">
            <DataGrid.Columns>
              <DataGridTextColumn Header="File Name"   Binding="{Binding Name}"    Width="2*"/>
              <DataGridTextColumn Header="Category"    Binding="{Binding Category}" Width="110"/>
              <DataGridTextColumn Header="Size"        Binding="{Binding SizeFmt}" Width="90"/>
              <DataGridTextColumn Header="Modified"    Binding="{Binding Modified, StringFormat='{}{0:yyyy-MM-dd}'}" Width="100"/>
              <DataGridTextColumn Header="Destination" Binding="{Binding DestPath}" Width="2*"/>
              <DataGridTextColumn Header="Status"      Binding="{Binding Status}"  Width="100"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>

      <!-- Duplicates Tab -->
      <TabItem Header="🔁 Duplicates">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Grid.Row="0" Background="#2D2D2D" Padding="12,8" Margin="0,0,0,1">
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="txtDupCount" Text="No duplicates found" FontWeight="SemiBold"/>
              <TextBlock Text=" · " Foreground="#666"/>
              <TextBlock x:Name="txtDupSize"  Text="" Foreground="#AAA"/>
            </StackPanel>
          </Border>
          <DataGrid Grid.Row="1" x:Name="dgDuplicates">
            <DataGrid.Columns>
              <DataGridTextColumn Header="File Name"  Binding="{Binding Name}"     Width="2*"/>
              <DataGridTextColumn Header="Hash (MD5)" Binding="{Binding Hash}"     Width="240"/>
              <DataGridTextColumn Header="Size"       Binding="{Binding SizeFmt}"  Width="90"/>
              <DataGridTextColumn Header="Modified"   Binding="{Binding Modified, StringFormat='{}{0:yyyy-MM-dd}'}" Width="100"/>
              <DataGridTextColumn Header="Full Path"  Binding="{Binding FullPath}" Width="3*"/>
            </DataGrid.Columns>
          </DataGrid>
        </Grid>
      </TabItem>
    </TabControl>

    <!-- Progress -->
    <Border Grid.Row="4" Margin="20,10,20,0">
      <StackPanel>
        <Grid Margin="0,0,0,4">
          <TextBlock x:Name="txtProgress" Text="Ready" Foreground="#AAA" FontSize="11"/>
          <TextBlock x:Name="txtPct" HorizontalAlignment="Right" Foreground="#AAA" FontSize="11"/>
        </Grid>
        <ProgressBar x:Name="pbMain" Value="0" Maximum="100"/>
      </StackPanel>
    </Border>

    <!-- Log -->
    <Border Grid.Row="5" Margin="20,10,20,0" Background="#252525" CornerRadius="6" Height="100">
      <ScrollViewer x:Name="svLog" VerticalScrollBarVisibility="Auto">
        <TextBlock x:Name="txtLog" Foreground="#AAA" FontFamily="Consolas" FontSize="11" TextWrapping="Wrap" Padding="8"/>
      </ScrollViewer>
    </Border>

    <!-- Actions -->
    <Border Grid.Row="6" Padding="20,12,20,16">
      <Grid>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="btnExecute"      Content="▶  Execute"            Style="{StaticResource PrimaryBtn}"   IsEnabled="False"/>
          <Button x:Name="btnDeleteDups"   Content="🗑  Delete Duplicates"  Style="{StaticResource WarningBtn}"   Margin="8,0,0,0" IsEnabled="False"/>
          <Button x:Name="btnUndo"         Content="↩  Undo Last Run"       Style="{StaticResource SecondaryBtn}" Margin="8,0,0,0" IsEnabled="False"/>
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

# ─── Load Window ──────────────────────────────────────────────────────────────
try {
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.MessageBox]::Show("Failed to load UI: $_", $Script:AppName, 'OK', 'Error')
    exit 1
}

# ─── Controls ────────────────────────────────────────────────────────────────
$txtFolder      = $window.FindName('txtFolder')
$btnBrowse      = $window.FindName('btnBrowse')
$btnScan        = $window.FindName('btnScan')
$cmbMode        = $window.FindName('cmbMode')
$chkDryRun      = $window.FindName('chkDryRun')
$chkDuplicates  = $window.FindName('chkDuplicates')
$chkArchiveOld  = $window.FindName('chkArchiveOld')
$txtArchiveDays = $window.FindName('txtArchiveDays')
$dgFiles        = $window.FindName('dgFiles')
$txtTotalFiles  = $window.FindName('txtTotalFiles')
$txtTotalSize   = $window.FindName('txtTotalSize')
$txtBreakdown   = $window.FindName('txtBreakdown')
$dgDuplicates   = $window.FindName('dgDuplicates')
$txtDupCount    = $window.FindName('txtDupCount')
$txtDupSize     = $window.FindName('txtDupSize')
$pbMain         = $window.FindName('pbMain')
$txtProgress    = $window.FindName('txtProgress')
$txtPct         = $window.FindName('txtPct')
$txtLog         = $window.FindName('txtLog')
$svLog          = $window.FindName('svLog')
$btnExecute     = $window.FindName('btnExecute')
$btnDeleteDups  = $window.FindName('btnDeleteDups')
$btnUndo        = $window.FindName('btnUndo')
$btnOpenLog     = $window.FindName('btnOpenLog')
$btnClearLog    = $window.FindName('btnClearLog')

# ─── State ───────────────────────────────────────────────────────────────────
$Script:ScanResults = [System.Collections.Generic.List[PSObject]]::new()
$Script:DupGroups   = [System.Collections.Generic.List[PSObject]]::new()

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

# ─── Default Folder ──────────────────────────────────────────────────────────
$defaultDownloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
if (Test-Path $defaultDownloads) { $txtFolder.Text = $defaultDownloads }
else { $txtFolder.Text = [Environment]::GetFolderPath('Desktop') }

# ─── Browse ──────────────────────────────────────────────────────────────────
$btnBrowse.Add_Click({
    $fbd = [System.Windows.Forms.FolderBrowserDialog]@{
        Description  = 'Select folder to organise'; ShowNewFolderButton = $false; SelectedPath = $txtFolder.Text
    }
    if ($fbd.ShowDialog() -eq 'OK') { $txtFolder.Text = $fbd.SelectedPath }
})

# ─── Scan ────────────────────────────────────────────────────────────────────
$btnScan.Add_Click({
    $folder = $txtFolder.Text.Trim()
    if (-not (Test-Path $folder -PathType Container)) {
        [System.Windows.MessageBox]::Show("Folder not found:`n$folder", $Script:AppName, 'OK', 'Warning'); return
    }

    Initialize-Log
    Append-Log "Scanning '$folder'…"
    Set-Progress 'Scanning…' 0

    # Resolve sort mode from selected ComboBoxItem
    $modeTag = ($cmbMode.SelectedItem).Tag
    $archiveDays = 90
    if ($chkArchiveOld.IsChecked) {
        try { $archiveDays = [int]$txtArchiveDays.Text } catch { $archiveDays = 90 }
    }

    $Script:ScanResults = [System.Collections.Generic.List[PSObject]]::new()
    $files = Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue
    $total = @($files).Count
    $i = 0

    foreach ($file in $files) {
        $i++
        Set-Progress "Scanning $i / $total" ([int](($i / [Math]::Max($total,1)) * 60))

        $cat      = Get-FileCategory -Extension $file.Extension
        $destPath = Compute-DestPath -File $file -BaseFolder $folder -Mode $modeTag

        # Archive override
        if ($chkArchiveOld.IsChecked -and ((Get-Date) - $file.LastWriteTime).TotalDays -gt $archiveDays) {
            $destPath = Join-Path $folder "Archive\$($file.Name)"
            $cat      = "Archive"
        }

        $Script:ScanResults.Add([PSCustomObject]@{
            Name     = $file.Name
            Category = $cat
            Size     = $file.Length
            SizeFmt  = Format-FileSize $file.Length
            FullPath = $file.FullName
            Modified = $file.LastWriteTime
            DestPath = $destPath
            Hash     = $null
            Status   = 'Pending'
        })
    }

    # Duplicate detection
    $Script:DupGroups = [System.Collections.Generic.List[PSObject]]::new()
    if ($chkDuplicates.IsChecked) {
        Append-Log "Computing file hashes for duplicate detection…"
        $hashMap = @{}
        $j = 0
        foreach ($item in $Script:ScanResults) {
            $j++
            Set-Progress "Hashing $j / $total" (60 + [int](($j / [Math]::Max($total,1)) * 35))
            $hash = Get-FileMD5 -Path $item.FullPath
            $item.Hash = $hash
            if ($hash) {
                if (-not $hashMap.ContainsKey($hash)) { $hashMap[$hash] = [System.Collections.Generic.List[PSObject]]::new() }
                $hashMap[$hash].Add($item)
            }
        }
        foreach ($entry in $hashMap.GetEnumerator()) {
            if ($entry.Value.Count -gt 1) {
                foreach ($dup in $entry.Value) { $Script:DupGroups.Add($dup) }
            }
        }
        $dupFileCount = $Script:DupGroups.Count
        $dupSize      = ($Script:DupGroups | Measure-Object Size -Sum).Sum
        $txtDupCount.Text = if ($dupFileCount -gt 0) { "$dupFileCount duplicate files in $(($hashMap.Values | Where-Object { $_.Count -gt 1 }).Count) groups" } else { "No duplicates found ✔" }
        $txtDupSize.Text  = if ($dupSize)    { "Wasted: $(Format-FileSize ([long]$dupSize))" } else { '' }
        $dgDuplicates.ItemsSource = $Script:DupGroups
        $btnDeleteDups.IsEnabled  = ($dupFileCount -gt 0)
        Append-Log "Duplicate check: $dupFileCount files with duplicate content."
    }

    # Bind files grid
    $dgFiles.ItemsSource = $Script:ScanResults

    # Summary
    $fileCount = $Script:ScanResults.Count
    $totalSz   = ($Script:ScanResults | Measure-Object Size -Sum).Sum
    $txtTotalFiles.Text = "$fileCount files"
    $txtTotalSize.Text  = Format-FileSize ([long]$totalSz)
    $breakdown = $Script:ScanResults | Group-Object Category | Sort-Object Count -Descending |
                 ForEach-Object { "$($_.Name): $($_.Count)" }
    $txtBreakdown.Text = ($breakdown -join '  ·  ')

    $btnExecute.IsEnabled = ($fileCount -gt 0)
    $btnUndo.IsEnabled    = (Test-Path $Script:UndoFile)

    Set-Progress "Scan complete – $fileCount files" 100
    Append-Log "Scan complete: $fileCount files, $(Format-FileSize ([long]$totalSz))"
    Write-Log "Scanned '$folder' – $fileCount files"
})

# ─── Execute ─────────────────────────────────────────────────────────────────
$btnExecute.Add_Click({
    $isDryRun = $chkDryRun.IsChecked
    $folder   = $txtFolder.Text.Trim()

    if (-not $isDryRun) {
        $conf = [System.Windows.MessageBox]::Show(
            "Move $($Script:ScanResults.Count) files into organised sub-folders in:`n$folder`n`nProceed?",
            $Script:AppName, 'YesNo', 'Question')
        if ($conf -ne 'Yes') { return }
    }

    $btnExecute.IsEnabled = $false
    $undoLog = [System.Collections.Generic.List[PSObject]]::new()
    $total = $Script:ScanResults.Count; $curr = 0; $errors = 0

    foreach ($item in $Script:ScanResults) {
        $curr++
        Set-Progress "Processing $curr / $total – $($item.Name)" ([int](($curr / $total) * 100))

        if ($isDryRun) {
            $item.Status = 'Preview'
            Append-Log "[DRY RUN] $($item.Name) → $($item.Category)\"
            continue
        }

        try {
            $destDir   = [System.IO.Path]::GetDirectoryName($item.DestPath)
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            $finalDest = Get-UniqueDestPath -Dest $item.DestPath
            Move-Item -LiteralPath $item.FullPath -Destination $finalDest -Force -ErrorAction Stop
            $undoLog.Add([PSCustomObject]@{ From = $finalDest; To = $item.FullPath })
            $item.Status = 'Moved'
            Write-Log "Moved '$($item.FullPath)' → '$finalDest'"
        } catch {
            $errors++
            $item.Status = 'Error'
            Append-Log "✘ $($item.Name): $_"
            Write-Log "ERROR '$($item.FullPath)': $_" -Level ERROR
        }
        [System.Windows.Application]::Current.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    $dgFiles.Items.Refresh()

    if (-not $isDryRun -and $undoLog.Count -gt 0) {
        $undoLog | ConvertTo-Json -Depth 3 | Set-Content $Script:UndoFile -Encoding UTF8
        $btnUndo.IsEnabled = $true
    }

    $msg = "Done! $($curr - $errors) files processed. $errors error(s)."
    Set-Progress $msg 100
    Append-Log $msg
    if (-not $isDryRun) { [System.Windows.MessageBox]::Show($msg, $Script:AppName, 'OK', 'Information') }
    $btnExecute.IsEnabled = $true
})

# ─── Delete Duplicates ────────────────────────────────────────────────────────
$btnDeleteDups.Add_Click({
    if ($Script:DupGroups.Count -eq 0) { return }

    $conf = [System.Windows.MessageBox]::Show(
        "This will delete DUPLICATE copies (keeping the first occurrence of each hash).`n" +
        "$($Script:DupGroups.Count) files will be evaluated.`n`nThis cannot be undone. Proceed?",
        $Script:AppName, 'YesNo', 'Warning')
    if ($conf -ne 'Yes') { return }

    # Keep first occurrence per hash; delete the rest
    $seen    = @{}
    $deleted = 0; $errors = 0
    foreach ($item in $Script:DupGroups) {
        if (-not $seen.ContainsKey($item.Hash)) { $seen[$item.Hash] = $item.FullPath; continue }
        try {
            Remove-Item -LiteralPath $item.FullPath -Force -ErrorAction Stop
            $deleted++
            Append-Log "🗑 Deleted duplicate: $($item.Name)"
            Write-Log "Deleted duplicate '$($item.FullPath)' (original: $($seen[$item.Hash]))"
        } catch {
            $errors++
            Append-Log "✘ Could not delete '$($item.Name)': $_"
        }
    }
    [System.Windows.MessageBox]::Show("Deleted $deleted duplicate(s). $errors error(s).", $Script:AppName, 'OK', 'Information')
    $btnDeleteDups.IsEnabled = $false
})

# ─── Undo ────────────────────────────────────────────────────────────────────
$btnUndo.Add_Click({
    if (-not (Test-Path $Script:UndoFile)) {
        [System.Windows.MessageBox]::Show('No undo data.', $Script:AppName, 'OK', 'Warning'); return
    }
    $conf = [System.Windows.MessageBox]::Show("Restore files to their original locations?", $Script:AppName, 'YesNo', 'Question')
    if ($conf -ne 'Yes') { return }

    $items = Get-Content $Script:UndoFile -Raw | ConvertFrom-Json
    $total = @($items).Count; $curr = 0; $errors = 0
    foreach ($item in $items) {
        $curr++
        Set-Progress "Undoing $curr / $total" ([int](($curr / $total) * 100))
        try {
            $dir = [System.IO.Path]::GetDirectoryName($item.To)
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Move-Item -LiteralPath $item.From -Destination $item.To -Force -ErrorAction Stop
            Append-Log "↩ Restored: $([System.IO.Path]::GetFileName($item.To))"
        } catch { $errors++; Append-Log "✘ Undo error: $_" }
    }
    Remove-Item $Script:UndoFile -Force -ErrorAction SilentlyContinue
    $btnUndo.IsEnabled = $false
    $msg = "Undo complete. $($curr - $errors) restored, $errors error(s)."
    Set-Progress $msg 100; Append-Log $msg
})

$btnOpenLog.Add_Click({
    if (Test-Path $Script:LogFile) { Start-Process notepad.exe $Script:LogFile }
    else { [System.Windows.MessageBox]::Show('No log yet.', $Script:AppName, 'OK', 'Information') }
})
$btnClearLog.Add_Click({ $txtLog.Text = '' })

$window.Add_Loaded({
    Initialize-Log
    Append-Log "Welcome to $($Script:AppName) v$($Script:Version)"
    Append-Log "Default folder: $($txtFolder.Text)"
    Write-Log "Application started"
})

[void]$window.ShowDialog()
Write-Log "Application closed"
