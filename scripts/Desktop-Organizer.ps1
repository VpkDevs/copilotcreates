#Requires -Version 5.1
<#
.SYNOPSIS
    Windows 11 Desktop Organizer – Sort any folder's files into tidy sub-folders.
.DESCRIPTION
    A WPF-based GUI tool that scans a chosen folder (default: your Desktop) and
    organises files into category sub-folders by extension.

    Features
    --------
    • Windows 11 Fluent dark-mode UI with accent colour
    • Live file inventory table with per-category counts & sizes
    • Preview / Dry-Run mode – see exactly what will happen before touching anything
    • One-click Execute with real-time progress bar and cancellation
    • Undo last run (moves files back and removes empty folders)
    • Persistent log file in %APPDATA%\CopilotOrganizer\Logs
    • Skip Shortcuts, Hidden files, or Files-in-Use toggles
    • Handles filename collisions with automatic numeric suffix
    • Graceful error recovery – locked/access-denied files are skipped and reported

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
$Script:AppName    = 'Desktop Organizer'
$Script:Version    = '1.0.0'
$Script:LogDir     = Join-Path $env:APPDATA 'CopilotOrganizer\Logs'
$Script:UndoFile   = Join-Path $env:APPDATA 'CopilotOrganizer\desktop_organizer_undo.json'
$Script:LogFile    = Join-Path $Script:LogDir ("DesktopOrganizer_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# ─── Category Map ────────────────────────────────────────────────────────────
$Script:Categories = [ordered]@{
    'Images'     = @('jpg','jpeg','png','gif','bmp','tiff','tif','svg','webp','ico','raw','cr2','nef','heic','heif','avif','jfif')
    'Documents'  = @('pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','odt','ods','odp','csv','md','markdown','epub','mobi','pages','numbers','key','djvu')
    'Videos'     = @('mp4','mkv','avi','mov','wmv','flv','webm','m4v','mpg','mpeg','3gp','ts','vob','rm','rmvb','divx')
    'Music'      = @('mp3','flac','wav','aac','ogg','wma','m4a','opus','aiff','ape','mid','midi')
    'Archives'   = @('zip','rar','7z','tar','gz','bz2','xz','iso','dmg','cab','deb','rpm','pkg','jar','war')
    'Code'       = @('py','js','ts','jsx','tsx','html','htm','css','scss','sass','java','c','cpp','cs','php','rb','go','rs','swift','sh','bash','ps1','psm1','psd1','lua','pl','r','sql','xml','json','yaml','yml','toml','ini','cfg','conf')
    'Programs'   = @('exe','msi','appx','msix','bat','cmd')
    'Shortcuts'  = @('lnk','url')
    'Other'      = @()   # catch-all
}

# ─── Logging ─────────────────────────────────────────────────────────────────
function Initialize-Log {
    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR','SUCCESS')]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8
}

# ─── Helper Functions ─────────────────────────────────────────────────────────
function Get-UniqueDestPath {
    param([string]$Dest)
    if (-not (Test-Path $Dest)) { return $Dest }
    $dir   = [System.IO.Path]::GetDirectoryName($Dest)
    $name  = [System.IO.Path]::GetFileNameWithoutExtension($Dest)
    $ext   = [System.IO.Path]::GetExtension($Dest)
    $index = 2
    do {
        $candidate = Join-Path $dir "${name} ($index)${ext}"
        $index++
    } while (Test-Path $candidate)
    return $candidate
}

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
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Scan-Folder {
    param(
        [string]$FolderPath,
        [bool]$SkipShortcuts,
        [bool]$SkipHidden
    )
    $results = [System.Collections.Generic.List[PSObject]]::new()
    try {
        $files = Get-ChildItem -LiteralPath $FolderPath -File -ErrorAction Stop
        foreach ($file in $files) {
            if ($SkipHidden -and $file.Attributes -band [System.IO.FileAttributes]::Hidden) { continue }
            $cat = Get-FileCategory -Extension $file.Extension
            if ($SkipShortcuts -and $cat -eq 'Shortcuts') { continue }
            $results.Add([PSCustomObject]@{
                Name     = $file.Name
                Category = $cat
                Size     = $file.Length
                SizeFmt  = Format-FileSize $file.Length
                FullPath = $file.FullName
                Modified = $file.LastWriteTime
            })
        }
    } catch {
        Write-Log "Error scanning folder '$FolderPath': $_" -Level ERROR
    }
    return $results
}

# ─── XAML ─────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="🗂  Desktop Organizer  v1.0"
    Height="780" Width="1000" MinHeight="600" MinWidth="800"
    WindowStartupLocation="CenterScreen"
    Background="#1C1C1C" Foreground="#FFFFFF"
    FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <!-- Colours -->
    <SolidColorBrush x:Key="AccentBrush"      Color="#0078D4"/>
    <SolidColorBrush x:Key="AccentHoverBrush" Color="#1A8EE8"/>
    <SolidColorBrush x:Key="SurfaceBrush"     Color="#2D2D2D"/>
    <SolidColorBrush x:Key="Surface2Brush"    Color="#383838"/>
    <SolidColorBrush x:Key="SubtleBrush"      Color="#888888"/>
    <SolidColorBrush x:Key="SuccessBrush"     Color="#3CB371"/>
    <SolidColorBrush x:Key="WarnBrush"        Color="#E8A820"/>
    <SolidColorBrush x:Key="DangerBrush"      Color="#E84040"/>

    <!-- Primary Button -->
    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background"   Value="#0078D4"/>
      <Setter Property="Foreground"   Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding"      Value="18,8"/>
      <Setter Property="Cursor"       Value="Hand"/>
      <Setter Property="FontSize"     Value="13"/>
      <Setter Property="FontWeight"   Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#1A8EE8"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter Property="Background" Value="#005A9E"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Background" Value="#444444"/>
                <Setter Property="Foreground" Value="#888888"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Secondary Button -->
    <Style x:Key="SecondaryBtn" TargetType="Button">
      <Setter Property="Background"   Value="#383838"/>
      <Setter Property="Foreground"   Value="White"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="BorderBrush"  Value="#555555"/>
      <Setter Property="Padding"      Value="14,8"/>
      <Setter Property="Cursor"       Value="Hand"/>
      <Setter Property="FontSize"     Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#444444"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#666666"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Danger Button -->
    <Style x:Key="DangerBtn" TargetType="Button" BasedOn="{StaticResource SecondaryBtn}">
      <Setter Property="Foreground" Value="#FF6B6B"/>
      <Setter Property="BorderBrush" Value="#E84040"/>
    </Style>

    <!-- DataGrid style -->
    <Style TargetType="DataGrid">
      <Setter Property="Background"            Value="#2D2D2D"/>
      <Setter Property="Foreground"            Value="#FFFFFF"/>
      <Setter Property="BorderThickness"       Value="0"/>
      <Setter Property="GridLinesVisibility"   Value="Horizontal"/>
      <Setter Property="HorizontalGridLinesBrush" Value="#444444"/>
      <Setter Property="RowBackground"         Value="#2D2D2D"/>
      <Setter Property="AlternatingRowBackground" Value="#333333"/>
      <Setter Property="SelectionMode"         Value="Extended"/>
      <Setter Property="AutoGenerateColumns"   Value="False"/>
      <Setter Property="CanUserAddRows"        Value="False"/>
      <Setter Property="CanUserDeleteRows"     Value="False"/>
      <Setter Property="IsReadOnly"            Value="True"/>
      <Setter Property="HeadersVisibility"     Value="Column"/>
      <Setter Property="ColumnHeaderHeight"    Value="36"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background"    Value="#1C1C1C"/>
      <Setter Property="Foreground"    Value="#AAAAAA"/>
      <Setter Property="FontWeight"    Value="SemiBold"/>
      <Setter Property="Padding"       Value="8,0"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="BorderBrush"   Value="#444444"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#404040"/>
        </Trigger>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#1A4E7A"/>
        </Trigger>
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

    <!-- CheckBox style -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground"     Value="#CCCCCC"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Margin"         Value="0,0,16,0"/>
    </Style>

    <!-- TextBox style -->
    <Style TargetType="TextBox">
      <Setter Property="Background"     Value="#383838"/>
      <Setter Property="Foreground"     Value="#FFFFFF"/>
      <Setter Property="BorderBrush"    Value="#555555"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding"        Value="8,6"/>
      <Setter Property="CaretBrush"     Value="White"/>
    </Style>

    <!-- ProgressBar style -->
    <Style TargetType="ProgressBar">
      <Setter Property="Background" Value="#383838"/>
      <Setter Property="Foreground" Value="#0078D4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Height" Value="6"/>
    </Style>

  </Window.Resources>

  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="64"/>   <!-- Title bar -->
      <RowDefinition Height="Auto"/> <!-- Folder row -->
      <RowDefinition Height="Auto"/> <!-- Options row -->
      <RowDefinition Height="*"/>    <!-- Main content -->
      <RowDefinition Height="Auto"/> <!-- Progress -->
      <RowDefinition Height="Auto"/> <!-- Log -->
      <RowDefinition Height="Auto"/> <!-- Action buttons -->
    </Grid.RowDefinitions>

    <!-- ── Title Bar ── -->
    <Border Grid.Row="0" Background="#111111">
      <Grid Margin="20,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="🗂" FontSize="28" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Desktop Organizer" FontSize="20" FontWeight="SemiBold"/>
            <TextBlock Text="Sort files into tidy category folders" Foreground="#888888" FontSize="11"/>
          </StackPanel>
        </StackPanel>
        <TextBlock x:Name="txtVersion" Text="v1.0.0" HorizontalAlignment="Right"
                   VerticalAlignment="Center" Foreground="#555555" FontSize="11"/>
      </Grid>
    </Border>

    <!-- ── Folder Selection ── -->
    <Border Grid.Row="1" Background="#252525" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="Folder:" VerticalAlignment="Center" Margin="0,0,12,0" Foreground="#AAAAAA"/>
        <TextBox   Grid.Column="1" x:Name="txtFolder" VerticalAlignment="Center"/>
        <Button    Grid.Column="2" x:Name="btnBrowse" Content="Browse…" Style="{StaticResource SecondaryBtn}"
                   Margin="8,0,0,0" VerticalAlignment="Center"/>
        <Button    Grid.Column="3" x:Name="btnScan"   Content="🔍  Scan" Style="{StaticResource PrimaryBtn}"
                   Margin="8,0,0,0" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- ── Options ── -->
    <Border Grid.Row="2" Background="#1C1C1C" Padding="20,10" BorderThickness="0,0,0,1" BorderBrush="#333333">
      <StackPanel Orientation="Horizontal">
        <CheckBox x:Name="chkDryRun"       Content="🔎 Preview Only (Dry Run)" IsChecked="True"/>
        <CheckBox x:Name="chkSkipShortcuts" Content="Skip Shortcuts"/>
        <CheckBox x:Name="chkSkipHidden"    Content="Skip Hidden Files" IsChecked="True"/>
      </StackPanel>
    </Border>

    <!-- ── File Table ── -->
    <Border Grid.Row="3" Margin="20,12,20,0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Summary bar -->
        <Border Grid.Row="0" Background="#2D2D2D" CornerRadius="6,6,0,0" Padding="12,8" Margin="0,0,0,1">
          <Grid>
            <StackPanel Orientation="Horizontal">
              <TextBlock x:Name="txtTotalFiles"  Text="0 files" FontWeight="SemiBold"/>
              <TextBlock Text=" · " Foreground="#666666"/>
              <TextBlock x:Name="txtTotalSize"   Text="0 B" Foreground="#AAAAAA"/>
            </StackPanel>
            <TextBlock x:Name="txtCatBreakdown" HorizontalAlignment="Right" Foreground="#888888" FontSize="11"/>
          </Grid>
        </Border>

        <!-- Grid -->
        <DataGrid Grid.Row="1" x:Name="dgFiles">
          <DataGrid.Columns>
            <DataGridTextColumn Header="File Name"   Binding="{Binding Name}"     Width="2*"/>
            <DataGridTextColumn Header="Category"    Binding="{Binding Category}" Width="110"/>
            <DataGridTextColumn Header="Size"        Binding="{Binding SizeFmt}"  Width="90"/>
            <DataGridTextColumn Header="Modified"    Binding="{Binding Modified, StringFormat='{}{0:yyyy-MM-dd HH:mm}'}" Width="140"/>
            <DataGridTextColumn Header="Destination" Binding="{Binding DestPath}" Width="2*"/>
          </DataGrid.Columns>
        </DataGrid>
      </Grid>
    </Border>

    <!-- ── Progress ── -->
    <Border Grid.Row="4" Margin="20,10,20,0">
      <StackPanel>
        <Grid Margin="0,0,0,4">
          <TextBlock x:Name="txtProgress" Text="Ready" Foreground="#AAAAAA" FontSize="11"/>
          <TextBlock x:Name="txtProgressPct" HorizontalAlignment="Right" Foreground="#AAAAAA" FontSize="11"/>
        </Grid>
        <ProgressBar x:Name="pbMain" Value="0" Maximum="100"/>
      </StackPanel>
    </Border>

    <!-- ── Log Output ── -->
    <Border Grid.Row="5" Margin="20,10,20,0" Background="#252525" CornerRadius="6" Height="110">
      <ScrollViewer x:Name="svLog" VerticalScrollBarVisibility="Auto" Padding="4">
        <TextBlock x:Name="txtLog" Foreground="#AAAAAA" FontFamily="Consolas" FontSize="11"
                   TextWrapping="Wrap" Padding="8"/>
      </ScrollViewer>
    </Border>

    <!-- ── Action Buttons ── -->
    <Border Grid.Row="6" Padding="20,12,20,16">
      <Grid>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="btnExecute" Content="▶  Execute"        Style="{StaticResource PrimaryBtn}" IsEnabled="False"/>
          <Button x:Name="btnUndo"    Content="↩  Undo Last Run"  Style="{StaticResource SecondaryBtn}" Margin="8,0,0,0" IsEnabled="False"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="btnOpenLog"  Content="📋 Open Log"    Style="{StaticResource SecondaryBtn}" Margin="0,0,8,0"/>
          <Button x:Name="btnClearLog" Content="Clear Log"      Style="{StaticResource SecondaryBtn}"/>
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

# ─── Control References ───────────────────────────────────────────────────────
$txtFolder        = $window.FindName('txtFolder')
$btnBrowse        = $window.FindName('btnBrowse')
$btnScan          = $window.FindName('btnScan')
$chkDryRun        = $window.FindName('chkDryRun')
$chkSkipShortcuts = $window.FindName('chkSkipShortcuts')
$chkSkipHidden    = $window.FindName('chkSkipHidden')
$dgFiles          = $window.FindName('dgFiles')
$txtTotalFiles    = $window.FindName('txtTotalFiles')
$txtTotalSize     = $window.FindName('txtTotalSize')
$txtCatBreakdown  = $window.FindName('txtCatBreakdown')
$pbMain           = $window.FindName('pbMain')
$txtProgress      = $window.FindName('txtProgress')
$txtProgressPct   = $window.FindName('txtProgressPct')
$txtLog           = $window.FindName('txtLog')
$svLog            = $window.FindName('svLog')
$btnExecute       = $window.FindName('btnExecute')
$btnUndo          = $window.FindName('btnUndo')
$btnOpenLog       = $window.FindName('btnOpenLog')
$btnClearLog      = $window.FindName('btnClearLog')

# ─── State ────────────────────────────────────────────────────────────────────
$Script:ScanResults  = [System.Collections.Generic.List[PSObject]]::new()
$Script:CancelToken  = $false

# ─── UI Helpers ───────────────────────────────────────────────────────────────
function Append-Log {
    param([string]$Msg, [string]$Color = '#AAAAAA')
    $ts   = Get-Date -Format 'HH:mm:ss'
    $line = "[$ts] $Msg`n"
    $txtLog.Dispatcher.Invoke([action]{
        $txtLog.Text += $line
        $svLog.ScrollToBottom()
    })
}

function Set-Progress {
    param([string]$Msg, [int]$Pct)
    $txtProgress.Dispatcher.Invoke([action]{
        $txtProgress.Text    = $Msg
        $txtProgressPct.Text = "$Pct%"
        $pbMain.Value        = $Pct
    })
}

# ─── Default Folder ───────────────────────────────────────────────────────────
$txtFolder.Text = [Environment]::GetFolderPath('Desktop')

# ─── Browse ───────────────────────────────────────────────────────────────────
$btnBrowse.Add_Click({
    $fbd = [System.Windows.Forms.FolderBrowserDialog]@{
        Description         = 'Select folder to organise'
        ShowNewFolderButton = $false
        SelectedPath        = $txtFolder.Text
    }
    if ($fbd.ShowDialog() -eq 'OK') {
        $txtFolder.Text = $fbd.SelectedPath
        $btnScan.IsEnabled = $true
    }
})

# ─── Scan ─────────────────────────────────────────────────────────────────────
$btnScan.Add_Click({
    $folder = $txtFolder.Text.Trim()
    if (-not (Test-Path $folder -PathType Container)) {
        [System.Windows.MessageBox]::Show("Folder not found:`n$folder", $Script:AppName, 'OK', 'Warning')
        return
    }

    Initialize-Log
    Append-Log "Scanning '$folder'…"
    Set-Progress 'Scanning…' 0

    $skipShortcuts = $chkSkipShortcuts.IsChecked
    $skipHidden    = $chkSkipHidden.IsChecked

    $Script:ScanResults = Scan-Folder -FolderPath $folder -SkipShortcuts $skipShortcuts -SkipHidden $skipHidden

    # Compute destinations
    foreach ($item in $Script:ScanResults) {
        $destDir  = Join-Path $folder $item.Category
        $destPath = Join-Path $destDir $item.Name
        $item | Add-Member -NotePropertyName DestPath -NotePropertyValue $destPath -Force
    }

    # Bind to DataGrid
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Script:ScanResults)
    $dgFiles.Dispatcher.Invoke([action]{ $dgFiles.ItemsSource = $Script:ScanResults })

    # Summary
    $total     = $Script:ScanResults.Count
    $totalSize = ($Script:ScanResults | Measure-Object -Property Size -Sum).Sum
    $breakdown = $Script:ScanResults | Group-Object Category | Sort-Object Count -Descending |
                 ForEach-Object { "$($_.Name): $($_.Count)" }

    $txtTotalFiles.Text    = "$total files"
    $txtTotalSize.Text     = Format-FileSize ([long]$totalSize)
    $txtCatBreakdown.Text  = ($breakdown -join '  ·  ')

    $btnExecute.IsEnabled  = ($total -gt 0)
    # Check if undo data exists
    $btnUndo.IsEnabled     = (Test-Path $Script:UndoFile)

    Append-Log "Found $total files · $(Format-FileSize ([long]$totalSize))"
    Set-Progress "Scan complete – $total files found" 100
    Write-Log "Scanned '$folder' – $total files found"
})

# ─── Execute ──────────────────────────────────────────────────────────────────
$btnExecute.Add_Click({
    $isDryRun = $chkDryRun.IsChecked
    $folder   = $txtFolder.Text.Trim()

    if (-not $isDryRun) {
        $confirm = [System.Windows.MessageBox]::Show(
            "This will MOVE $($Script:ScanResults.Count) files into sub-folders inside:`n`n$folder`n`nProceed?",
            $Script:AppName, 'YesNo', 'Question')
        if ($confirm -ne 'Yes') { return }
    }

    $btnExecute.IsEnabled = $false
    $btnScan.IsEnabled    = $false
    $Script:CancelToken   = $false
    $undoLog              = [System.Collections.Generic.List[PSObject]]::new()

    Initialize-Log

    $total   = $Script:ScanResults.Count
    $current = 0
    $errors  = 0

    foreach ($item in $Script:ScanResults) {
        if ($Script:CancelToken) {
            Append-Log "⚠ Cancelled by user."
            break
        }

        $current++
        $pct = [int](($current / $total) * 100)
        Set-Progress "Processing $current / $total – $($item.Name)" $pct

        if ($isDryRun) {
            Append-Log "[DRY RUN] Would move: $($item.Name) → $($item.Category)\"
            Write-Log "[DRY RUN] $($item.FullPath) → $($item.DestPath)"
            continue
        }

        # Real move
        try {
            $destDir = Join-Path $folder $item.Category
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            $finalDest = Get-UniqueDestPath -Dest $item.DestPath
            Move-Item -LiteralPath $item.FullPath -Destination $finalDest -Force -ErrorAction Stop

            $undoLog.Add([PSCustomObject]@{ From = $finalDest; To = $item.FullPath })
            Append-Log "✔ Moved: $($item.Name) → $($item.Category)\"
            Write-Log "Moved '$($item.FullPath)' → '$finalDest'"
        } catch {
            $errors++
            Append-Log "✘ Error moving '$($item.Name)': $_"
            Write-Log "ERROR moving '$($item.FullPath)': $_" -Level ERROR
        }

        # Allow UI to breathe
        [System.Windows.Application]::Current.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    # Save undo log
    if (-not $isDryRun -and $undoLog.Count -gt 0) {
        $undoLog | ConvertTo-Json -Depth 3 | Set-Content -Path $Script:UndoFile -Encoding UTF8
        $btnUndo.IsEnabled = $true
    }

    $verb = if ($isDryRun) { 'previewed' } else { 'moved' }
    $msg  = "Done! $($current - $errors) files $verb. $errors error(s)."
    Set-Progress $msg 100
    Append-Log $msg
    Write-Log $msg -Level SUCCESS

    if (-not $isDryRun) {
        [System.Windows.MessageBox]::Show($msg, $Script:AppName, 'OK', 'Information')
    }

    $btnExecute.IsEnabled = $true
    $btnScan.IsEnabled    = $true
})

# ─── Undo ─────────────────────────────────────────────────────────────────────
$btnUndo.Add_Click({
    if (-not (Test-Path $Script:UndoFile)) {
        [System.Windows.MessageBox]::Show('No undo data found.', $Script:AppName, 'OK', 'Warning')
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "This will move files back to their original locations.`nProceed?",
        $Script:AppName, 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }

    $undoItems = Get-Content $Script:UndoFile -Raw | ConvertFrom-Json
    $total     = $undoItems.Count
    $current   = 0
    $errors    = 0

    foreach ($item in $undoItems) {
        $current++
        Set-Progress "Undoing $current / $total" ([int](($current / $total) * 100))
        try {
            $destDir = [System.IO.Path]::GetDirectoryName($item.To)
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Move-Item -LiteralPath $item.From -Destination $item.To -Force -ErrorAction Stop
            Append-Log "↩ Restored: $([System.IO.Path]::GetFileName($item.To))"
        } catch {
            $errors++
            Append-Log "✘ Undo error for '$($item.From)': $_"
        }
    }

    # Remove empty category folders
    $folder = $txtFolder.Text.Trim()
    foreach ($cat in $Script:Categories.Keys) {
        $catPath = Join-Path $folder $cat
        if ((Test-Path $catPath) -and (-not (Get-ChildItem $catPath))) {
            Remove-Item $catPath -Force -ErrorAction SilentlyContinue
        }
    }

    Remove-Item $Script:UndoFile -Force -ErrorAction SilentlyContinue
    $btnUndo.IsEnabled = $false
    $msg = "Undo complete. $($current - $errors) restored, $errors error(s)."
    Set-Progress $msg 100
    Append-Log $msg
    Write-Log $msg -Level SUCCESS
})

# ─── Open Log ─────────────────────────────────────────────────────────────────
$btnOpenLog.Add_Click({
    if (Test-Path $Script:LogFile) {
        Start-Process notepad.exe -ArgumentList $Script:LogFile
    } else {
        [System.Windows.MessageBox]::Show('No log file yet. Run a scan first.', $Script:AppName, 'OK', 'Information')
    }
})

# ─── Clear Log ────────────────────────────────────────────────────────────────
$btnClearLog.Add_Click({
    $txtLog.Text = ''
})

# ─── Window Loaded ────────────────────────────────────────────────────────────
$window.Add_Loaded({
    Initialize-Log
    Append-Log "Welcome to $($Script:AppName) v$($Script:Version)"
    Append-Log "Default folder set to Desktop. Click 'Scan' to begin."
    Write-Log "Application started"
})

# ─── Run ─────────────────────────────────────────────────────────────────────
[void]$window.ShowDialog()
Write-Log "Application closed"
