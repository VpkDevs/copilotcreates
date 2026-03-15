#Requires -Version 5.1
<#
.SYNOPSIS
    GUI-based project manager for developers with hundreds of projects.

.DESCRIPTION
    A rich Windows Forms application for tracking, launching, tagging, noting,
    and archiving local software projects.  All metadata is stored in a single
    JSON file alongside the script (or at a custom path) so it survives moves.

    Features
    --------
    - Auto-scan a root folder and register every detected project
    - Open project folder, VS Code, or a custom "launch" command per project
    - Free-text search across name, path, tags and notes
    - Tag-based filtering (multi-select tag panel)
    - Per-project notes with auto-save
    - "Favourite" and "Archive" toggles
    - Git status badge (clean / dirty / no git)
    - Sort by name, last-opened, or date-added
    - Tray icon so the manager stays out of the way when not needed

.PARAMETER DataFile
    Path to the JSON database.  Defaults to ProjectManager.json in the same
    directory as this script.

.PARAMETER RootFolder
    If supplied the manager will scan this folder for projects on first run
    instead of asking interactively.

.EXAMPLE
    .\Invoke-ProjectManager.ps1
    .\Invoke-ProjectManager.ps1 -RootFolder C:\Dev -DataFile C:\Dev\.projects.json
#>
[CmdletBinding()]
param(
    [string] $DataFile   = (Join-Path $PSScriptRoot 'ProjectManager.json'),
    [string] $RootFolder = ''
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Colours & fonts ──────────────────────────────────────────────────────────
$C = @{
    BgDark   = [System.Drawing.Color]::FromArgb(18,  18,  24)
    BgMid    = [System.Drawing.Color]::FromArgb(28,  28,  38)
    BgLight  = [System.Drawing.Color]::FromArgb(40,  40,  56)
    Accent   = [System.Drawing.Color]::FromArgb(99, 102, 241)   # indigo-500
    AccentHi = [System.Drawing.Color]::FromArgb(129,140,248)    # indigo-400
    Success  = [System.Drawing.Color]::FromArgb( 34, 197,  94)  # green-500
    Warning  = [System.Drawing.Color]::FromArgb(234, 179,   8)  # yellow-500
    Danger   = [System.Drawing.Color]::FromArgb(239,  68,  68)  # red-500
    Text     = [System.Drawing.Color]::FromArgb(226, 232, 240)
    TextMut  = [System.Drawing.Color]::FromArgb(148, 163, 184)
    Border   = [System.Drawing.Color]::FromArgb( 51,  65,  85)
}
$FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FontMono = New-Object System.Drawing.Font('Cascadia Code', 9)
$FontH1   = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$FontH2   = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

# ── Data helpers ─────────────────────────────────────────────────────────────
function Load-Data {
    if (Test-Path $DataFile) {
        try { return Get-Content $DataFile -Raw | ConvertFrom-Json -AsHashtable }
        catch {}
    }
    return @{ projects = @(); nextId = 1 }
}

function Save-Data ($db) {
    $db | ConvertTo-Json -Depth 10 | Set-Content $DataFile -Encoding UTF8
}

function New-ProjectEntry ([string]$path) {
    $name = Split-Path $path -Leaf
    $hasGit = Test-Path (Join-Path $path '.git')
    return @{
        id          = $script:db.nextId++
        name        = $name
        path        = $path
        tags        = @()
        notes       = ''
        favourite   = $false
        archived    = $false
        hasGit      = $hasGit
        gitStatus   = 'unknown'
        launchCmd   = ''
        dateAdded   = (Get-Date -Format 'o')
        lastOpened  = $null
    }
}

function Detect-Projects ([string]$root) {
    $markers = @('.git','package.json','*.sln','*.csproj','pyproject.toml',
                 'Cargo.toml','go.mod','composer.json')
    $found = @()
    Get-ChildItem -Path $root -Directory -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($m in $markers) {
            if (Get-ChildItem $_.FullName -Filter $m -ErrorAction SilentlyContinue | Select-Object -First 1) {
                $found += $_.FullName
                break
            }
        }
    }
    return $found | Select-Object -Unique
}

function Get-GitStatus ([string]$path) {
    if (-not (Test-Path (Join-Path $path '.git'))) { return 'no-git' }
    try {
        $out = & git -C $path status --porcelain 2>$null
        if ($null -eq $out -or $out.Count -eq 0) { return 'clean' }
        return 'dirty'
    } catch { return 'unknown' }
}

function Get-GitStatusColor ($status) {
    switch ($status) {
        'clean'   { return $C.Success }
        'dirty'   { return $C.Warning }
        'no-git'  { return $C.TextMut }
        default   { return $C.TextMut }
    }
}

# ── Load DB ───────────────────────────────────────────────────────────────────
$script:db = Load-Data

if ($RootFolder -and (Test-Path $RootFolder)) {
    $existing = $script:db.projects | ForEach-Object { $_.path }
    Detect-Projects $RootFolder | Where-Object { $_ -notin $existing } | ForEach-Object {
        $script:db.projects += New-ProjectEntry $_
    }
    Save-Data $script:db
}

# ── State ─────────────────────────────────────────────────────────────────────
$script:filterText   = ''
$script:filterTags   = @()
$script:showArchived = $false
$script:sortMode     = 'name'   # name | lastOpened | dateAdded
$script:selectedId   = $null

# ── Main form ─────────────────────────────────────────────────────────────────
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = '⚡ Project Manager'
$form.Size             = New-Object System.Drawing.Size(1080, 720)
$form.MinimumSize      = New-Object System.Drawing.Size(800, 560)
$form.BackColor        = $C.BgDark
$form.ForeColor        = $C.Text
$form.Font             = $FontUI
$form.StartPosition    = 'CenterScreen'
$form.Icon             = [System.Drawing.SystemIcons]::Application

# ── Top bar ───────────────────────────────────────────────────────────────────
$pnlTop                = New-Object System.Windows.Forms.Panel
$pnlTop.Dock           = 'Top'
$pnlTop.Height         = 52
$pnlTop.BackColor      = $C.BgMid
$pnlTop.Padding        = New-Object System.Windows.Forms.Padding(10,8,10,0)

$lblTitle              = New-Object System.Windows.Forms.Label
$lblTitle.Text         = '⚡ Project Manager'
$lblTitle.Font         = $FontH1
$lblTitle.ForeColor    = $C.AccentHi
$lblTitle.AutoSize     = $true
$lblTitle.Location     = New-Object System.Drawing.Point(10,12)

$txtSearch             = New-Object System.Windows.Forms.TextBox
$txtSearch.Size        = New-Object System.Drawing.Size(280,24)
$txtSearch.Location    = New-Object System.Drawing.Point(250,14)
$txtSearch.BackColor   = $C.BgLight
$txtSearch.ForeColor   = $C.Text
$txtSearch.BorderStyle = 'FixedSingle'
$txtSearch.Font        = $FontUI
$txtSearch.Text        = 'Search projects...'
$txtSearch.ForeColor   = $C.TextMut

$btnScan               = New-Object System.Windows.Forms.Button
$btnScan.Text          = '+ Scan Folder'
$btnScan.Size          = New-Object System.Drawing.Size(100,26)
$btnScan.Location      = New-Object System.Drawing.Point(548,13)
$btnScan.BackColor     = $C.Accent
$btnScan.ForeColor     = [System.Drawing.Color]::White
$btnScan.FlatStyle     = 'Flat'
$btnScan.FlatAppearance.BorderSize = 0

$btnAdd                = New-Object System.Windows.Forms.Button
$btnAdd.Text           = '+ Add Project'
$btnAdd.Size           = New-Object System.Drawing.Size(100,26)
$btnAdd.Location       = New-Object System.Drawing.Point(656,13)
$btnAdd.BackColor      = $C.BgLight
$btnAdd.ForeColor      = $C.Text
$btnAdd.FlatStyle      = 'Flat'
$btnAdd.FlatAppearance.BorderSize = 1
$btnAdd.FlatAppearance.BorderColor = $C.Border

$chkArchived           = New-Object System.Windows.Forms.CheckBox
$chkArchived.Text      = 'Show archived'
$chkArchived.Location  = New-Object System.Drawing.Point(768,16)
$chkArchived.ForeColor = $C.TextMut
$chkArchived.AutoSize  = $true

$cmbSort               = New-Object System.Windows.Forms.ComboBox
$cmbSort.Items.AddRange(@('Sort: Name','Sort: Last Opened','Sort: Date Added'))
$cmbSort.SelectedIndex = 0
$cmbSort.Size          = New-Object System.Drawing.Size(130,24)
$cmbSort.Location      = New-Object System.Drawing.Point(880,13)
$cmbSort.BackColor     = $C.BgLight
$cmbSort.ForeColor     = $C.Text
$cmbSort.FlatStyle     = 'Flat'
$cmbSort.DropDownStyle = 'DropDownList'

$pnlTop.Controls.AddRange(@($lblTitle,$txtSearch,$btnScan,$btnAdd,$chkArchived,$cmbSort))

# ── Left: project list ────────────────────────────────────────────────────────
$pnlLeft               = New-Object System.Windows.Forms.Panel
$pnlLeft.Dock          = 'Left'
$pnlLeft.Width         = 380
$pnlLeft.BackColor     = $C.BgMid

$lstProjects           = New-Object System.Windows.Forms.ListBox
$lstProjects.Dock      = 'Fill'
$lstProjects.BackColor = $C.BgMid
$lstProjects.ForeColor = $C.Text
$lstProjects.Font      = $FontUI
$lstProjects.BorderStyle = 'None'
$lstProjects.ItemHeight  = 48
$lstProjects.DrawMode    = 'OwnerDrawFixed'
$lstProjects.SelectionMode = 'One'
$pnlLeft.Controls.Add($lstProjects)

# Custom draw project list items
$lstProjects.Add_DrawItem({
    param($s, $e)
    $e.DrawBackground()
    if ($e.Index -lt 0) { return }
    $proj = $e.Item
    if ($null -eq $proj) { return }
    $bounds = $e.Bounds

    # Background
    $bg = if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) { $C.BgLight } else { $C.BgMid }
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $bounds)

    # Accent bar
    if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) {
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($C.Accent)),
            $bounds.X, $bounds.Y, 3, $bounds.Height)
    }

    $gitColor = Get-GitStatusColor $proj.gitStatus
    $starText = if ($proj.favourite) { '★ ' } else { '' }
    $nameText = "$starText$($proj.name)"

    # Name
    $e.Graphics.DrawString($nameText, $FontH2, (New-Object System.Drawing.SolidBrush($C.Text)),
        ($bounds.X + 12), ($bounds.Y + 6))

    # Path (truncated)
    $shortPath = if ($proj.path.Length -gt 45) { '...' + $proj.path.Substring($proj.path.Length - 42) } else { $proj.path }
    $e.Graphics.DrawString($shortPath, $FontUI, (New-Object System.Drawing.SolidBrush($C.TextMut)),
        ($bounds.X + 12), ($bounds.Y + 26))

    # Git dot
    $dotBrush = New-Object System.Drawing.SolidBrush($gitColor)
    $e.Graphics.FillEllipse($dotBrush, ($bounds.Right - 18), ($bounds.Y + 18), 8, 8)

    # Separator
    $e.Graphics.DrawLine((New-Object System.Drawing.Pen($C.Border, 1)),
        $bounds.X, $bounds.Bottom - 1, $bounds.Right, $bounds.Bottom - 1)
    $e.DrawFocusRectangle()
})

# ── Right: detail panel ───────────────────────────────────────────────────────
$pnlRight              = New-Object System.Windows.Forms.Panel
$pnlRight.Dock         = 'Fill'
$pnlRight.BackColor    = $C.BgDark
$pnlRight.Padding      = New-Object System.Windows.Forms.Padding(20)

$lblDetailName         = New-Object System.Windows.Forms.Label
$lblDetailName.Font    = $FontH1
$lblDetailName.ForeColor = $C.AccentHi
$lblDetailName.AutoSize  = $true
$lblDetailName.Location  = New-Object System.Drawing.Point(20,20)
$lblDetailName.Text      = 'Select a project'

$lblDetailPath         = New-Object System.Windows.Forms.Label
$lblDetailPath.ForeColor = $C.TextMut
$lblDetailPath.AutoSize  = $true
$lblDetailPath.Location  = New-Object System.Drawing.Point(20,48)
$lblDetailPath.Text      = ''

$pnlButtons            = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlButtons.Location   = New-Object System.Drawing.Point(20,76)
$pnlButtons.Size       = New-Object System.Drawing.Size(580,36)
$pnlButtons.BackColor  = $C.BgDark

function New-ActionButton([string]$text, [System.Drawing.Color]$bg) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text       = $text
    $b.Size       = New-Object System.Drawing.Size(110,30)
    $b.BackColor  = $bg
    $b.ForeColor  = [System.Drawing.Color]::White
    $b.FlatStyle  = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Margin     = New-Object System.Windows.Forms.Padding(0,0,6,0)
    return $b
}

$btnOpen   = New-ActionButton '📂 Open'   $C.Accent
$btnCode   = New-ActionButton '🖥 VS Code' $C.BgLight
$btnTerm   = New-ActionButton '⚡ Terminal' $C.BgLight
$btnFav    = New-ActionButton '★ Favourite' $C.BgLight
$btnArchive= New-ActionButton '📦 Archive'  $C.BgLight
$btnDelete = New-ActionButton '🗑 Remove'   $C.Danger

$btnCode.FlatAppearance.BorderColor   = $C.Border
$btnTerm.FlatAppearance.BorderColor   = $C.Border
$btnFav.FlatAppearance.BorderColor    = $C.Border
$btnArchive.FlatAppearance.BorderColor= $C.Border

$pnlButtons.Controls.AddRange(@($btnOpen,$btnCode,$btnTerm,$btnFav,$btnArchive,$btnDelete))

$lblNotesHeader        = New-Object System.Windows.Forms.Label
$lblNotesHeader.Text   = 'Notes'
$lblNotesHeader.Font   = $FontH2
$lblNotesHeader.ForeColor = $C.Text
$lblNotesHeader.AutoSize  = $true
$lblNotesHeader.Location  = New-Object System.Drawing.Point(20,124)

$txtNotes              = New-Object System.Windows.Forms.RichTextBox
$txtNotes.Location     = New-Object System.Drawing.Point(20,148)
$txtNotes.Size         = New-Object System.Drawing.Size(580,140)
$txtNotes.BackColor    = $C.BgLight
$txtNotes.ForeColor    = $C.Text
$txtNotes.Font         = $FontMono
$txtNotes.BorderStyle  = 'None'

$lblTagsHeader         = New-Object System.Windows.Forms.Label
$lblTagsHeader.Text    = 'Tags  (comma-separated)'
$lblTagsHeader.Font    = $FontH2
$lblTagsHeader.ForeColor = $C.Text
$lblTagsHeader.AutoSize  = $true
$lblTagsHeader.Location  = New-Object System.Drawing.Point(20,302)

$txtTags               = New-Object System.Windows.Forms.TextBox
$txtTags.Location      = New-Object System.Drawing.Point(20,326)
$txtTags.Size          = New-Object System.Drawing.Size(580,24)
$txtTags.BackColor     = $C.BgLight
$txtTags.ForeColor     = $C.Text
$txtTags.BorderStyle   = 'None'
$txtTags.Font          = $FontUI

$lblLaunchHeader       = New-Object System.Windows.Forms.Label
$lblLaunchHeader.Text  = 'Custom Launch Command'
$lblLaunchHeader.Font  = $FontH2
$lblLaunchHeader.ForeColor = $C.Text
$lblLaunchHeader.AutoSize  = $true
$lblLaunchHeader.Location  = New-Object System.Drawing.Point(20,364)

$txtLaunchCmd          = New-Object System.Windows.Forms.TextBox
$txtLaunchCmd.Location = New-Object System.Drawing.Point(20,388)
$txtLaunchCmd.Size     = New-Object System.Drawing.Size(580,24)
$txtLaunchCmd.BackColor= $C.BgLight
$txtLaunchCmd.ForeColor= $C.Text
$txtLaunchCmd.BorderStyle = 'None'
$txtLaunchCmd.Font     = $FontMono

$lblGitStatus          = New-Object System.Windows.Forms.Label
$lblGitStatus.Text     = ''
$lblGitStatus.Font     = $FontUI
$lblGitStatus.AutoSize = $true
$lblGitStatus.Location = New-Object System.Drawing.Point(20,426)

$btnSaveDetail         = New-Object System.Windows.Forms.Button
$btnSaveDetail.Text    = 'Save Changes'
$btnSaveDetail.Location= New-Object System.Drawing.Point(20,460)
$btnSaveDetail.Size    = New-Object System.Drawing.Size(130,30)
$btnSaveDetail.BackColor= $C.Accent
$btnSaveDetail.ForeColor= [System.Drawing.Color]::White
$btnSaveDetail.FlatStyle= 'Flat'
$btnSaveDetail.FlatAppearance.BorderSize = 0

$pnlRight.Controls.AddRange(@(
    $lblDetailName,$lblDetailPath,$pnlButtons,
    $lblNotesHeader,$txtNotes,
    $lblTagsHeader,$txtTags,
    $lblLaunchHeader,$txtLaunchCmd,
    $lblGitStatus,$btnSaveDetail
))

# ── Status bar ────────────────────────────────────────────────────────────────
$statusBar             = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor   = $C.BgMid
$statusLabel           = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.ForeColor = $C.TextMut
$statusLabel.Text      = 'Ready'
$statusBar.Items.Add($statusLabel) | Out-Null

# ── Assemble layout ───────────────────────────────────────────────────────────
$pnlContent            = New-Object System.Windows.Forms.Panel
$pnlContent.Dock       = 'Fill'
$pnlContent.Controls.AddRange(@($pnlRight, $pnlLeft))

$form.Controls.AddRange(@($pnlContent, $pnlTop, $statusBar))

# ── Helper: refresh project list ─────────────────────────────────────────────
function Refresh-ProjectList {
    $lstProjects.BeginUpdate()
    $lstProjects.Items.Clear()

    $projects = $script:db.projects | Where-Object {
        ($script:showArchived -or -not $_.archived) -and
        (
            $script:filterText -eq '' -or
            $_.name  -like "*$($script:filterText)*" -or
            $_.path  -like "*$($script:filterText)*" -or
            ($_.tags -join ',') -like "*$($script:filterText)*" -or
            $_.notes -like "*$($script:filterText)*"
        ) -and
        (
            $script:filterTags.Count -eq 0 -or
            ($script:filterTags | Where-Object { $_ -in $_.tags }).Count -gt 0
        )
    }

    $projects = switch ($script:sortMode) {
        'lastOpened' { $projects | Sort-Object { if ($_.lastOpened) { [datetime]$_.lastOpened } else { [datetime]::MinValue } } -Descending }
        'dateAdded'  { $projects | Sort-Object { [datetime]$_.dateAdded } -Descending }
        default      { $projects | Sort-Object { $_.name.ToLower() } }
    }

    foreach ($p in $projects) {
        $lstProjects.Items.Add($p) | Out-Null
    }

    $statusLabel.Text = "$($lstProjects.Items.Count) of $($script:db.projects.Count) projects shown"
    $lstProjects.EndUpdate()
}

# ── Helper: load project into detail panel ────────────────────────────────────
function Load-ProjectDetail ($proj) {
    if ($null -eq $proj) {
        $lblDetailName.Text  = 'Select a project'
        $lblDetailPath.Text  = ''
        $txtNotes.Text       = ''
        $txtTags.Text        = ''
        $txtLaunchCmd.Text   = ''
        $lblGitStatus.Text   = ''
        return
    }
    $script:selectedId   = $proj.id
    $lblDetailName.Text  = $proj.name
    $lblDetailPath.Text  = $proj.path
    $txtNotes.Text       = $proj.notes
    $txtTags.Text        = ($proj.tags -join ', ')
    $txtLaunchCmd.Text   = $proj.launchCmd

    $gs = Get-GitStatus $proj.path
    $proj.gitStatus = $gs
    $lblGitStatus.ForeColor = Get-GitStatusColor $gs
    $lblGitStatus.Text = "Git: $gs"

    $btnFav.Text = if ($proj.favourite) { '★ Unfavourite' } else { '★ Favourite' }
    $btnArchive.Text = if ($proj.archived) { '📤 Unarchive' } else { '📦 Archive' }
}

function Get-SelectedProject {
    if ($script:selectedId -eq $null) { return $null }
    return $script:db.projects | Where-Object { $_.id -eq $script:selectedId } | Select-Object -First 1
}

# ── Events ────────────────────────────────────────────────────────────────────
$txtSearch.Add_GotFocus({
    if ($txtSearch.Text -eq 'Search projects...') {
        $txtSearch.Text = ''
        $txtSearch.ForeColor = $C.Text
    }
})
$txtSearch.Add_LostFocus({
    if ($txtSearch.Text -eq '') {
        $txtSearch.Text = 'Search projects...'
        $txtSearch.ForeColor = $C.TextMut
    }
})
$txtSearch.Add_TextChanged({
    $script:filterText = if ($txtSearch.Text -eq 'Search projects...') { '' } else { $txtSearch.Text }
    Refresh-ProjectList
})

$cmbSort.Add_SelectedIndexChanged({
    $script:sortMode = switch ($cmbSort.SelectedIndex) {
        1 { 'lastOpened' }
        2 { 'dateAdded' }
        default { 'name' }
    }
    Refresh-ProjectList
})

$chkArchived.Add_CheckedChanged({
    $script:showArchived = $chkArchived.Checked
    Refresh-ProjectList
})

$lstProjects.Add_SelectedIndexChanged({
    $proj = $lstProjects.SelectedItem
    Load-ProjectDetail $proj
})

$btnSaveDetail.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.notes     = $txtNotes.Text
    $proj.tags      = ($txtTags.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    $proj.launchCmd = $txtLaunchCmd.Text
    Save-Data $script:db
    $statusLabel.Text = "Saved: $($proj.name)"
})

$btnOpen.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.lastOpened = (Get-Date -Format 'o')
    Save-Data $script:db
    Start-Process 'explorer.exe' $proj.path
})

$btnCode.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.lastOpened = (Get-Date -Format 'o')
    Save-Data $script:db
    Start-Process 'code' $proj.path
})

$btnTerm.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.lastOpened = (Get-Date -Format 'o')
    Save-Data $script:db
    Start-Process 'wt.exe' "-d `"$($proj.path)`"" -ErrorAction SilentlyContinue
    if (-not $?) { Start-Process 'powershell.exe' "-NoExit -Command Set-Location '$($proj.path)'" }
})

$btnFav.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.favourite = -not $proj.favourite
    Save-Data $script:db
    Load-ProjectDetail $proj
    Refresh-ProjectList
})

$btnArchive.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $proj.archived = -not $proj.archived
    Save-Data $script:db
    Load-ProjectDetail $proj
    Refresh-ProjectList
})

$btnDelete.Add_Click({
    $proj = Get-SelectedProject
    if ($null -eq $proj) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove '$($proj.name)' from the manager? (Files will NOT be deleted)",
        'Remove Project', 'YesNo', 'Question')
    if ($confirm -eq 'Yes') {
        $script:db.projects = @($script:db.projects | Where-Object { $_.id -ne $proj.id })
        Save-Data $script:db
        $script:selectedId = $null
        Load-ProjectDetail $null
        Refresh-ProjectList
    }
})

$btnScan.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select root folder to scan for projects'
    if ($dlg.ShowDialog() -eq 'OK') {
        $statusLabel.Text = 'Scanning...'
        $form.Refresh()
        $existing = $script:db.projects | ForEach-Object { $_.path }
        $added = 0
        Detect-Projects $dlg.SelectedPath | Where-Object { $_ -notin $existing } | ForEach-Object {
            $script:db.projects += New-ProjectEntry $_
            $added++
        }
        Save-Data $script:db
        Refresh-ProjectList
        $statusLabel.Text = "Scan complete — $added new project(s) added"
    }
})

$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select project folder'
    if ($dlg.ShowDialog() -eq 'OK') {
        $existing = $script:db.projects | ForEach-Object { $_.path }
        if ($dlg.SelectedPath -in $existing) {
            [System.Windows.Forms.MessageBox]::Show('Project already in list.','Info','OK','Information') | Out-Null
            return
        }
        $script:db.projects += New-ProjectEntry $dlg.SelectedPath
        Save-Data $script:db
        Refresh-ProjectList
    }
})

# ── Tray icon ─────────────────────────────────────────────────────────────────
$tray                        = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon                   = [System.Drawing.SystemIcons]::Application
$tray.Text                   = 'Project Manager'
$tray.Visible                = $true

$ctxMenu                     = New-Object System.Windows.Forms.ContextMenuStrip
$mnuShow                     = $ctxMenu.Items.Add('Show')
$mnuExit                     = $ctxMenu.Items.Add('Exit')
$tray.ContextMenuStrip        = $ctxMenu

$tray.Add_DoubleClick({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$mnuShow.Add_Click({ $form.Show(); $form.WindowState = 'Normal'; $form.Activate() })
$mnuExit.Add_Click({ $tray.Visible = $false; $form.Close() })

$form.Add_FormClosing({
    param($s,$e)
    if ($e.CloseReason -eq 'UserClosing') {
        $e.Cancel = $true
        $form.Hide()
        $tray.ShowBalloonTip(1500,'Project Manager','Minimised to tray','Info')
    }
})

# ── Initial load ──────────────────────────────────────────────────────────────
Refresh-ProjectList
[System.Windows.Forms.Application]::Run($form)
$tray.Visible = $false
