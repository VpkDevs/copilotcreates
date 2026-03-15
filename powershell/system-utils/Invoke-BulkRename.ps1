#Requires -Version 5.1
<#
.SYNOPSIS
    Bulk-rename files with a live preview GUI before committing any changes.

.DESCRIPTION
    A Windows Forms wizard that lets you:
      - Pick a source folder (or supply it on the command line)
      - Apply transformations: find & replace, regex, number sequencing,
        date stamp, case change, prefix/suffix add/remove, extension change
      - See a colour-coded before/after preview in real time
      - Commit all renames with a single click
      - Undo the last batch rename

.PARAMETER Folder
    Folder containing the files to rename.  Prompts if omitted.

.PARAMETER Recurse
    Include files in sub-folders.

.EXAMPLE
    .\Invoke-BulkRename.ps1
    .\Invoke-BulkRename.ps1 -Folder C:\Photos\Unsorted -Recurse
#>
[CmdletBinding()]
param(
    [string] $Folder  = '',
    [switch] $Recurse
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Colours ───────────────────────────────────────────────────────────────────
$C = @{
    Bg      = [System.Drawing.Color]::FromArgb(18,18,24)
    BgMid   = [System.Drawing.Color]::FromArgb(28,28,38)
    BgLight = [System.Drawing.Color]::FromArgb(38,38,56)
    Accent  = [System.Drawing.Color]::FromArgb(20,184,166)
    Text    = [System.Drawing.Color]::FromArgb(226,232,240)
    TextMut = [System.Drawing.Color]::FromArgb(100,116,139)
    Green   = [System.Drawing.Color]::FromArgb(34,197,94)
    Red     = [System.Drawing.Color]::FromArgb(239,68,68)
    Yellow  = [System.Drawing.Color]::FromArgb(234,179,8)
    Border  = [System.Drawing.Color]::FromArgb(51,65,85)
}
$FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FontMono = New-Object System.Drawing.Font('Cascadia Code', 9)
$FontH1   = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$FontBold = New-Object System.Drawing.Font('Segoe UI', 9,  [System.Drawing.FontStyle]::Bold)

# ── State ─────────────────────────────────────────────────────────────────────
$script:sourceFiles = @()
$script:undoData    = $null
$script:folderPath  = $Folder

# ── Form ──────────────────────────────────────────────────────────────────────
$form               = New-Object System.Windows.Forms.Form
$form.Text          = '✏ Bulk Rename'
$form.Size          = New-Object System.Drawing.Size(1000,660)
$form.MinimumSize   = New-Object System.Drawing.Size(800,540)
$form.BackColor     = $C.Bg
$form.ForeColor     = $C.Text
$form.Font          = $FontUI
$form.StartPosition = 'CenterScreen'
$form.Icon          = [System.Drawing.SystemIcons]::Application

# ── Top: folder picker ────────────────────────────────────────────────────────
$pnlTop             = New-Object System.Windows.Forms.Panel
$pnlTop.Dock        = 'Top'
$pnlTop.Height      = 48
$pnlTop.BackColor   = $C.BgMid

$lblH               = New-Object System.Windows.Forms.Label
$lblH.Text          = '✏ Bulk Rename'
$lblH.Font          = $FontH1
$lblH.ForeColor     = $C.Accent
$lblH.AutoSize      = $true
$lblH.Location      = New-Object System.Drawing.Point(10,13)

$txtFolder          = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(160,13)
$txtFolder.Size     = New-Object System.Drawing.Size(480,22)
$txtFolder.BackColor= $C.BgLight
$txtFolder.ForeColor= $C.Text
$txtFolder.BorderStyle = 'FixedSingle'
$txtFolder.Text     = $script:folderPath

$btnBrowse          = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse'
$btnBrowse.Location = New-Object System.Drawing.Point(648,12)
$btnBrowse.Size     = New-Object System.Drawing.Size(70,24)
$btnBrowse.BackColor= $C.BgLight
$btnBrowse.ForeColor= $C.Text
$btnBrowse.FlatStyle= 'Flat'
$btnBrowse.FlatAppearance.BorderColor = $C.Border

$chkRecurse         = New-Object System.Windows.Forms.CheckBox
$chkRecurse.Text    = 'Include sub-folders'
$chkRecurse.Location= New-Object System.Drawing.Point(728,14)
$chkRecurse.ForeColor = $C.Text
$chkRecurse.AutoSize = $true
$chkRecurse.Checked = $Recurse

$btnLoad            = New-Object System.Windows.Forms.Button
$btnLoad.Text       = '↻ Load Files'
$btnLoad.Location   = New-Object System.Drawing.Point(880,12)
$btnLoad.Size       = New-Object System.Drawing.Size(96,24)
$btnLoad.BackColor  = $C.Accent
$btnLoad.ForeColor  = [System.Drawing.Color]::White
$btnLoad.FlatStyle  = 'Flat'
$btnLoad.FlatAppearance.BorderSize = 0

$pnlTop.Controls.AddRange(@($lblH,$txtFolder,$btnBrowse,$chkRecurse,$btnLoad))

# ── Left: transform options ───────────────────────────────────────────────────
$pnlOptions         = New-Object System.Windows.Forms.Panel
$pnlOptions.Dock    = 'Left'
$pnlOptions.Width   = 320
$pnlOptions.BackColor = $C.BgMid
$pnlOptions.Padding = New-Object System.Windows.Forms.Padding(10)

$y = 10

function Add-Label ([string]$text) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text; $lbl.Font = $FontBold; $lbl.ForeColor = $C.Text
    $lbl.Location = New-Object System.Drawing.Point(10,$script:y)
    $lbl.AutoSize = $true
    $pnlOptions.Controls.Add($lbl)
    $script:y += 24
}
function Add-TextRow ([string]$label) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label; $lbl.ForeColor = $C.TextMut; $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(10, $script:y)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(110, $script:y - 2)
    $txt.Size = New-Object System.Drawing.Size(190,22)
    $txt.BackColor = $C.BgLight; $txt.ForeColor = $C.Text; $txt.BorderStyle = 'None'
    $pnlOptions.Controls.AddRange(@($lbl,$txt))
    $script:y += 28
    return $txt
}
function Add-CheckRow ([string]$label) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $label; $chk.ForeColor = $C.Text; $chk.AutoSize = $true
    $chk.Location = New-Object System.Drawing.Point(10, $script:y)
    $pnlOptions.Controls.Add($chk)
    $script:y += 26
    return $chk
}
function Add-ComboRow ([string]$label, [string[]]$items) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label; $lbl.ForeColor = $C.TextMut; $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(10,$script:y)
    $cmb = New-Object System.Windows.Forms.ComboBox
    $cmb.Location = New-Object System.Drawing.Point(110,$script:y-2)
    $cmb.Size     = New-Object System.Drawing.Size(190,22)
    $cmb.BackColor = $C.BgLight; $cmb.ForeColor = $C.Text
    $cmb.FlatStyle = 'Flat'; $cmb.DropDownStyle = 'DropDownList'
    $items | ForEach-Object { $cmb.Items.Add($_) | Out-Null }
    $cmb.SelectedIndex = 0
    $pnlOptions.Controls.AddRange(@($lbl,$cmb))
    $script:y += 28
    return $cmb
}

Add-Label 'Find & Replace'
$txtFind    = Add-TextRow 'Find'
$txtReplace = Add-TextRow 'Replace with'
$chkRegex   = Add-CheckRow 'Use Regex'
$chkCase    = Add-CheckRow 'Case sensitive'

$script:y += 8; Add-Label 'Case Transform'
$cmbCase    = Add-ComboRow 'Mode' @('None','UPPERCASE','lowercase','Title Case','Sentence case','camelCase','snake_case')

$script:y += 8; Add-Label 'Prefix / Suffix'
$txtPrefix  = Add-TextRow 'Add Prefix'
$txtSuffix  = Add-TextRow 'Add Suffix'
$txtRemPfx  = Add-TextRow 'Remove Prefix'
$txtRemSfx  = Add-TextRow 'Remove Suffix'

$script:y += 8; Add-Label 'Extension'
$txtExt     = Add-TextRow 'Change Ext to'

$script:y += 8; Add-Label 'Numbering'
$chkNumber  = Add-CheckRow 'Add sequence number'
$txtNumStart= Add-TextRow 'Start at'
$txtNumPad  = Add-TextRow 'Pad to digits'
$txtNumSep  = Add-TextRow 'Separator'
$txtNumStart.Text = '1'; $txtNumPad.Text = '3'; $txtNumSep.Text = '_'

$script:y += 8
$btnPreview         = New-Object System.Windows.Forms.Button
$btnPreview.Text    = '👁 Preview'
$btnPreview.Location= New-Object System.Drawing.Point(10, $script:y)
$btnPreview.Size    = New-Object System.Drawing.Size(140,30)
$btnPreview.BackColor = $C.Accent
$btnPreview.ForeColor = [System.Drawing.Color]::White
$btnPreview.FlatStyle = 'Flat'
$btnPreview.FlatAppearance.BorderSize = 0
$pnlOptions.Controls.Add($btnPreview)

# ── Right: preview grid ───────────────────────────────────────────────────────
$pnlRight           = New-Object System.Windows.Forms.Panel
$pnlRight.Dock      = 'Fill'
$pnlRight.BackColor = $C.Bg

$grid               = New-Object System.Windows.Forms.DataGridView
$grid.Dock          = 'Fill'
$grid.BackgroundColor = $C.Bg
$grid.GridColor     = $C.Border
$grid.ForeColor     = $C.Text
$grid.Font          = $FontMono
$grid.BorderStyle   = 'None'
$grid.RowHeadersVisible = $false
$grid.AllowUserToAddRows    = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly      = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.DefaultCellStyle.BackColor        = $C.Bg
$grid.DefaultCellStyle.ForeColor        = $C.Text
$grid.DefaultCellStyle.SelectionBackColor = $C.BgLight
$grid.DefaultCellStyle.SelectionForeColor = $C.Text
$grid.ColumnHeadersDefaultCellStyle.BackColor = $C.BgMid
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $C.TextMut
$grid.ColumnHeadersBorderStyle = 'Single'
$grid.EnableHeadersVisualStyles = $false

$col1 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$col1.HeaderText = 'Original Name'; $col1.Width = 300; $col1.Name = 'Original'
$col2 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$col2.HeaderText = 'New Name';      $col2.Width = 300; $col2.Name = 'New'
$col3 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$col3.HeaderText = 'Status';        $col3.Width = 80;  $col3.Name = 'Status'
$grid.Columns.AddRange(@($col1,$col2,$col3))

$pnlRight.Controls.Add($grid)

# ── Bottom: action bar ────────────────────────────────────────────────────────
$pnlBottom          = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock     = 'Bottom'
$pnlBottom.Height   = 44
$pnlBottom.BackColor= $C.BgMid

$lblCount           = New-Object System.Windows.Forms.Label
$lblCount.ForeColor = $C.TextMut
$lblCount.AutoSize  = $true
$lblCount.Location  = New-Object System.Drawing.Point(10,13)
$lblCount.Text      = 'Load a folder to begin'

$btnRename          = New-Object System.Windows.Forms.Button
$btnRename.Text     = '✓ Rename All'
$btnRename.Location = New-Object System.Drawing.Point(730,7)
$btnRename.Size     = New-Object System.Drawing.Size(120,30)
$btnRename.BackColor= $C.Green
$btnRename.ForeColor= [System.Drawing.Color]::White
$btnRename.FlatStyle= 'Flat'
$btnRename.FlatAppearance.BorderSize = 0
$btnRename.Enabled  = $false

$btnUndo            = New-Object System.Windows.Forms.Button
$btnUndo.Text       = '↩ Undo'
$btnUndo.Location   = New-Object System.Drawing.Point(862,7)
$btnUndo.Size       = New-Object System.Drawing.Size(80,30)
$btnUndo.BackColor  = $C.BgLight
$btnUndo.ForeColor  = $C.Text
$btnUndo.FlatStyle  = 'Flat'
$btnUndo.FlatAppearance.BorderColor = $C.Border
$btnUndo.Enabled    = $false

$pnlBottom.Controls.AddRange(@($lblCount,$btnRename,$btnUndo))

$form.Controls.AddRange(@($pnlBottom,$pnlRight,$pnlOptions,$pnlTop))

# ── Helpers ───────────────────────────────────────────────────────────────────
function Load-Files {
    $path = $txtFolder.Text
    if (-not (Test-Path $path)) { return }
    $script:folderPath = $path
    $recurse = $chkRecurse.Checked
    $script:sourceFiles = @(Get-ChildItem $path -File -Recurse:$recurse -ErrorAction SilentlyContinue)
    $lblCount.Text = "$($script:sourceFiles.Count) files loaded"
    $grid.Rows.Clear()
    foreach ($f in $script:sourceFiles) {
        $grid.Rows.Add($f.Name, $f.Name, '—') | Out-Null
    }
}

function Apply-Transform ([string]$name) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext  = [System.IO.Path]::GetExtension($name)

    # Find & Replace
    $find    = $txtFind.Text
    $replace = $txtReplace.Text
    if ($find) {
        if ($chkRegex.Checked) {
            $opts = if ($chkCase.Checked) { 'None' } else { 'IgnoreCase' }
            $base = [System.Text.RegularExpressions.Regex]::Replace($base, $find, $replace, $opts)
        } else {
            $cmp = if ($chkCase.Checked) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }
            $base = $base.Replace($find, $replace, $cmp) # PS6+
        }
    }

    # Case
    $base = switch ($cmbCase.SelectedItem) {
        'UPPERCASE'     { $base.ToUpper() }
        'lowercase'     { $base.ToLower() }
        'Title Case'    { (Get-Culture).TextInfo.ToTitleCase($base.ToLower()) }
        'Sentence case' { $base.Substring(0,1).ToUpper() + $base.Substring(1).ToLower() }
        'camelCase' {
            $words = $base -split '[\s_\-]+'
            $words[0].ToLower() + ($words[1..($words.Length-1)] | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) } | Join-String)
        }
        'snake_case'    { ($base -replace '[\s\-]+','_').ToLower() }
        default         { $base }
    }

    # Prefix / Suffix
    if ($txtRemPfx.Text -and $base.StartsWith($txtRemPfx.Text)) { $base = $base.Substring($txtRemPfx.Text.Length) }
    if ($txtRemSfx.Text -and $base.EndsWith($txtRemSfx.Text))   { $base = $base.Substring(0, $base.Length - $txtRemSfx.Text.Length) }
    if ($txtPrefix.Text) { $base = $txtPrefix.Text + $base }
    if ($txtSuffix.Text) { $base = $base + $txtSuffix.Text }

    # Extension
    if ($txtExt.Text) { $ext = if ($txtExt.Text.StartsWith('.')) { $txtExt.Text } else { ".$($txtExt.Text)" } }

    return $base + $ext
}

function Run-Preview {
    if ($script:sourceFiles.Count -eq 0) { return }
    $grid.SuspendLayout()
    $grid.Rows.Clear()

    $counter  = [int]($txtNumStart.Text -replace '[^\d]','') ; if ($counter -eq 0) { $counter = 1 }
    $pad      = [int]($txtNumPad.Text   -replace '[^\d]','') ; if ($pad     -eq 0) { $pad     = 3 }
    $sep      = $txtNumSep.Text

    $changed = 0; $conflicts = 0
    $newNames = @{}

    foreach ($f in $script:sourceFiles) {
        $newName = Apply-Transform $f.Name
        if ($chkNumber.Checked) {
            $base2 = [System.IO.Path]::GetFileNameWithoutExtension($newName)
            $ext2  = [System.IO.Path]::GetExtension($newName)
            $num   = $counter.ToString().PadLeft($pad,'0')
            $newName = "$base2$sep$num$ext2"
            $counter++
        }

        $status = '—'
        $color  = $grid.DefaultCellStyle.BackColor
        if ($newName -ne $f.Name) {
            $changed++
            if ($newNames.ContainsKey($newName.ToLower())) {
                $status = '⚠ Conflict'
                $conflicts++
            } else {
                $status = '✓ Changed'
            }
        }
        $newNames[$newName.ToLower()] = $true

        $rowIdx = $grid.Rows.Add($f.Name, $newName, $status)
        if ($status -eq '✓ Changed')  { $grid.Rows[$rowIdx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(20,40,20) }
        if ($status -eq '⚠ Conflict') { $grid.Rows[$rowIdx].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(50,30,10) }
    }

    $grid.ResumeLayout()
    $lblCount.Text = "$($script:sourceFiles.Count) files  ·  $changed to rename  ·  $conflicts conflicts"
    $btnRename.Enabled = ($changed -gt 0 -and $conflicts -eq 0)
}

function Do-Rename {
    $undoList = @()
    $ok = 0; $fail = 0
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $orig  = $grid.Rows[$i].Cells['Original'].Value
        $new   = $grid.Rows[$i].Cells['New'].Value
        if ($orig -eq $new) { continue }
        $file  = $script:sourceFiles[$i]
        $dest  = Join-Path $file.DirectoryName $new
        try {
            Rename-Item -Path $file.FullName -NewName $new -ErrorAction Stop
            $undoList += @{ from = $dest; to = $file.FullName }
            $ok++
        } catch {
            $grid.Rows[$i].Cells['Status'].Value = "✗ $_"
            $fail++
        }
    }
    $script:undoData = $undoList
    $btnUndo.Enabled = ($undoList.Count -gt 0)
    $lblCount.Text   = "✓ Renamed $ok files" + (if ($fail) { "  ✗ $fail failed" } else { '' })
    Load-Files
    Run-Preview
}

# ── Events ────────────────────────────────────────────────────────────────────
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtFolder.Text
    if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath; Load-Files }
})

$btnLoad.Add_Click({ Load-Files; Run-Preview })
$btnPreview.Add_Click({ Run-Preview })
$btnRename.Add_Click({ Do-Rename })

$btnUndo.Add_Click({
    if (-not $script:undoData) { return }
    foreach ($op in $script:undoData) {
        try { Rename-Item -Path $op.from -NewName (Split-Path $op.to -Leaf) -ErrorAction Stop } catch {}
    }
    $script:undoData = $null
    $btnUndo.Enabled = $false
    Load-Files
    Run-Preview
})

# Live preview on option change
@($txtFind,$txtReplace,$txtPrefix,$txtSuffix,$txtRemPfx,$txtRemSfx,$txtExt,$txtNumStart,$txtNumPad,$txtNumSep) |
    ForEach-Object { $_.Add_TextChanged({ Run-Preview }) }
@($chkRegex,$chkCase,$chkNumber) | ForEach-Object { $_.Add_CheckedChanged({ Run-Preview }) }
$cmbCase.Add_SelectedIndexChanged({ Run-Preview })

# ── Init ──────────────────────────────────────────────────────────────────────
if ($script:folderPath -and (Test-Path $script:folderPath)) { Load-Files; Run-Preview }
[System.Windows.Forms.Application]::Run($form)
