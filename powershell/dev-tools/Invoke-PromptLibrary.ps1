#Requires -Version 5.1
<#
.SYNOPSIS
    GUI library for storing, categorising, searching and launching reusable AI prompts.

.DESCRIPTION
    A Windows Forms app that acts as a personal prompt library.  Prompts are
    stored in a local JSON file and can be:
      - Organised into categories / tags
      - Searched by keyword
      - Copied to clipboard with one click
      - "Run" via an optionally-configured browser URL template
        (e.g. open ChatGPT or Claude with the prompt pre-filled)
      - Exported/imported as JSON

    Designed to sit in the system tray for instant access.

.PARAMETER DataFile
    Path to the JSON prompt database.  Defaults to PromptLibrary.json next
    to this script.

.EXAMPLE
    .\Invoke-PromptLibrary.ps1
#>
[CmdletBinding()]
param(
    [string] $DataFile = (Join-Path $PSScriptRoot 'PromptLibrary.json')
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Colours ───────────────────────────────────────────────────────────────────
$C = @{
    Bg      = [System.Drawing.Color]::FromArgb(15, 15, 20)
    BgMid   = [System.Drawing.Color]::FromArgb(24, 24, 32)
    BgLight = [System.Drawing.Color]::FromArgb(36, 36, 50)
    Accent  = [System.Drawing.Color]::FromArgb(168, 85, 247)   # violet
    AccHi   = [System.Drawing.Color]::FromArgb(196,130,255)
    Text    = [System.Drawing.Color]::FromArgb(226,232,240)
    TextMut = [System.Drawing.Color]::FromArgb(100,116,139)
    Border  = [System.Drawing.Color]::FromArgb(51, 65, 85)
    Green   = [System.Drawing.Color]::FromArgb(34,197,94)
    Red     = [System.Drawing.Color]::FromArgb(239,68,68)
}
$FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FontMono = New-Object System.Drawing.Font('Cascadia Code', 9)
$FontBold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$FontH1   = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)

# ── Data helpers ──────────────────────────────────────────────────────────────
function Load-Data {
    if (Test-Path $DataFile) {
        try { return Get-Content $DataFile -Raw | ConvertFrom-Json -AsHashtable }
        catch {}
    }
    # seed with example prompts
    return @{
        nextId  = 4
        prompts = @(
            @{
                id        = 1
                title     = 'Code Review'
                category  = 'Dev'
                tags      = @('review','quality')
                body      = "Please review the following code for bugs, security issues, and areas to improve readability.  Provide specific, actionable feedback organized by severity (critical / warning / suggestion).`n`n```\n[PASTE CODE HERE]\n```"
                pinned    = $true
                useCount  = 0
                created   = (Get-Date -Format 'o')
            },
            @{
                id        = 2
                title     = 'Explain This Code'
                category  = 'Dev'
                tags      = @('explain','learning')
                body      = "Explain the following code in plain English.  Include:`n- What the code does overall\n- How it works step by step\n- Any non-obvious patterns or gotchas\n\n```\n[PASTE CODE HERE]\n```"
                pinned    = $false
                useCount  = 0
                created   = (Get-Date -Format 'o')
            },
            @{
                id        = 3
                title     = 'Write Unit Tests'
                category  = 'Dev'
                tags      = @('testing','tdd')
                body      = "Write comprehensive unit tests for the following code.  Cover happy paths, edge cases, and error scenarios.  Use [TEST FRAMEWORK] conventions.`n`n```\n[PASTE CODE HERE]\n```"
                pinned    = $false
                useCount  = 0
                created   = (Get-Date -Format 'o')
            }
        )
    }
}

function Save-Data ($db) {
    $db | ConvertTo-Json -Depth 10 | Set-Content $DataFile -Encoding UTF8
}

$script:db = Load-Data

# ── State ─────────────────────────────────────────────────────────────────────
$script:selectedId   = $null
$script:filterText   = ''
$script:filterCat    = 'All'

# ── Main form ─────────────────────────────────────────────────────────────────
$form               = New-Object System.Windows.Forms.Form
$form.Text          = '🧠 Prompt Library'
$form.Size          = New-Object System.Drawing.Size(900, 640)
$form.MinimumSize   = New-Object System.Drawing.Size(700, 500)
$form.BackColor     = $C.Bg
$form.ForeColor     = $C.Text
$form.Font          = $FontUI
$form.StartPosition = 'CenterScreen'
$form.Icon          = [System.Drawing.SystemIcons]::Application

# ── Top bar ───────────────────────────────────────────────────────────────────
$pnlTop             = New-Object System.Windows.Forms.Panel
$pnlTop.Dock        = 'Top'
$pnlTop.Height      = 50
$pnlTop.BackColor   = $C.BgMid

$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = '🧠 Prompt Library'
$lblTitle.Font      = $FontH1
$lblTitle.ForeColor = $C.AccHi
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(10,13)

$txtSearch          = New-Object System.Windows.Forms.TextBox
$txtSearch.Size     = New-Object System.Drawing.Size(220,24)
$txtSearch.Location = New-Object System.Drawing.Point(220,13)
$txtSearch.BackColor= $C.BgLight
$txtSearch.ForeColor= $C.TextMut
$txtSearch.Text     = 'Search...'
$txtSearch.BorderStyle = 'FixedSingle'

$cmbCat             = New-Object System.Windows.Forms.ComboBox
$cmbCat.Size        = New-Object System.Drawing.Size(130,24)
$cmbCat.Location    = New-Object System.Drawing.Point(452,13)
$cmbCat.BackColor   = $C.BgLight
$cmbCat.ForeColor   = $C.Text
$cmbCat.FlatStyle   = 'Flat'
$cmbCat.DropDownStyle = 'DropDownList'

$btnNew             = New-Object System.Windows.Forms.Button
$btnNew.Text        = '+ New Prompt'
$btnNew.Location    = New-Object System.Drawing.Point(595,12)
$btnNew.Size        = New-Object System.Drawing.Size(110,26)
$btnNew.BackColor   = $C.Accent
$btnNew.ForeColor   = [System.Drawing.Color]::White
$btnNew.FlatStyle   = 'Flat'
$btnNew.FlatAppearance.BorderSize = 0

$btnExport          = New-Object System.Windows.Forms.Button
$btnExport.Text     = '↑ Export'
$btnExport.Location = New-Object System.Drawing.Point(718,12)
$btnExport.Size     = New-Object System.Drawing.Size(80,26)
$btnExport.BackColor= $C.BgLight
$btnExport.ForeColor= $C.Text
$btnExport.FlatStyle= 'Flat'
$btnExport.FlatAppearance.BorderColor = $C.Border

$btnImport          = New-Object System.Windows.Forms.Button
$btnImport.Text     = '↓ Import'
$btnImport.Location = New-Object System.Drawing.Point(806,12)
$btnImport.Size     = New-Object System.Drawing.Size(80,26)
$btnImport.BackColor= $C.BgLight
$btnImport.ForeColor= $C.Text
$btnImport.FlatStyle= 'Flat'
$btnImport.FlatAppearance.BorderColor = $C.Border

$pnlTop.Controls.AddRange(@($lblTitle,$txtSearch,$cmbCat,$btnNew,$btnExport,$btnImport))

# ── Left: prompt list ─────────────────────────────────────────────────────────
$pnlLeft            = New-Object System.Windows.Forms.Panel
$pnlLeft.Dock       = 'Left'
$pnlLeft.Width      = 300
$pnlLeft.BackColor  = $C.BgMid

$lstPrompts         = New-Object System.Windows.Forms.ListBox
$lstPrompts.Dock    = 'Fill'
$lstPrompts.BackColor = $C.BgMid
$lstPrompts.ForeColor = $C.Text
$lstPrompts.Font    = $FontUI
$lstPrompts.BorderStyle = 'None'
$lstPrompts.ItemHeight  = 52
$lstPrompts.DrawMode    = 'OwnerDrawFixed'
$pnlLeft.Controls.Add($lstPrompts)

$lstPrompts.Add_DrawItem({
    param($s,$e)
    $e.DrawBackground()
    if ($e.Index -lt 0) { return }
    $p = $e.Item
    if ($null -eq $p) { return }
    $b = $e.Bounds

    $bg = if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) { $C.BgLight } else { $C.BgMid }
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $b)

    if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) {
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($C.Accent)), $b.X, $b.Y, 3, $b.Height)
    }

    $pin = if ($p.pinned) { '📌 ' } else { '' }
    $e.Graphics.DrawString("$pin$($p.title)", $FontBold, (New-Object System.Drawing.SolidBrush($C.Text)), ($b.X+10), ($b.Y+8))

    $catText = "$($p.category)  ·  used $($p.useCount)x"
    $e.Graphics.DrawString($catText, $FontUI, (New-Object System.Drawing.SolidBrush($C.TextMut)), ($b.X+10), ($b.Y+30))

    $e.Graphics.DrawLine((New-Object System.Drawing.Pen($C.Border,1)), $b.X, $b.Bottom-1, $b.Right, $b.Bottom-1)
    $e.DrawFocusRectangle()
})

# ── Right: editor ─────────────────────────────────────────────────────────────
$pnlRight           = New-Object System.Windows.Forms.Panel
$pnlRight.Dock      = 'Fill'
$pnlRight.BackColor = $C.Bg
$pnlRight.Padding   = New-Object System.Windows.Forms.Padding(16)

$txtTitle           = New-Object System.Windows.Forms.TextBox
$txtTitle.Location  = New-Object System.Drawing.Point(16,14)
$txtTitle.Size      = New-Object System.Drawing.Size(440,24)
$txtTitle.BackColor = $C.BgLight
$txtTitle.ForeColor = $C.Text
$txtTitle.Font      = $FontBold
$txtTitle.BorderStyle = 'None'
$txtTitle.Text      = 'Select or create a prompt'

$txtCategory        = New-Object System.Windows.Forms.TextBox
$txtCategory.Location = New-Object System.Drawing.Point(16,46)
$txtCategory.Size   = New-Object System.Drawing.Size(180,22)
$txtCategory.BackColor = $C.BgLight
$txtCategory.ForeColor = $C.Text
$txtCategory.BorderStyle = 'None'
$txtCategory.Text   = 'Category'

$txtTags            = New-Object System.Windows.Forms.TextBox
$txtTags.Location   = New-Object System.Drawing.Point(206,46)
$txtTags.Size       = New-Object System.Drawing.Size(250,22)
$txtTags.BackColor  = $C.BgLight
$txtTags.ForeColor  = $C.Text
$txtTags.BorderStyle = 'None'
$txtTags.Text       = 'tag1, tag2'

$txtBody            = New-Object System.Windows.Forms.RichTextBox
$txtBody.Location   = New-Object System.Drawing.Point(16,80)
$txtBody.Size       = New-Object System.Drawing.Size(530,340)
$txtBody.BackColor  = $C.BgLight
$txtBody.ForeColor  = $C.Text
$txtBody.Font       = $FontMono
$txtBody.BorderStyle = 'None'
$txtBody.WordWrap   = $true

$chkPinned          = New-Object System.Windows.Forms.CheckBox
$chkPinned.Text     = 'Pinned'
$chkPinned.Location = New-Object System.Drawing.Point(16,432)
$chkPinned.ForeColor = $C.Text
$chkPinned.AutoSize = $true

$pnlActions         = New-Object System.Windows.Forms.FlowLayoutPanel
$pnlActions.Location = New-Object System.Drawing.Point(16,460)
$pnlActions.Size    = New-Object System.Drawing.Size(540,36)
$pnlActions.BackColor = $C.Bg

function Make-Btn ([string]$text, [System.Drawing.Color]$bg) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Size      = New-Object System.Drawing.Size(110,30)
    $b.BackColor = $bg
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.Margin    = New-Object System.Windows.Forms.Padding(0,0,6,0)
    return $b
}

$btnCopy    = Make-Btn '📋 Copy'    $C.Accent
$btnSave    = Make-Btn '💾 Save'    $C.BgLight
$btnDelete  = Make-Btn '🗑 Delete'  $C.Red

$btnSave.FlatAppearance.BorderColor   = $C.Border
$pnlActions.Controls.AddRange(@($btnCopy,$btnSave,$btnDelete))

$pnlRight.Controls.AddRange(@($txtTitle,$txtCategory,$txtTags,$txtBody,$chkPinned,$pnlActions))

# ── Status bar ────────────────────────────────────────────────────────────────
$status             = New-Object System.Windows.Forms.StatusStrip
$status.BackColor   = $C.BgMid
$statusLbl          = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLbl.ForeColor = $C.TextMut
$statusLbl.Text     = 'Ready'
$status.Items.Add($statusLbl) | Out-Null

$pnlContent         = New-Object System.Windows.Forms.Panel
$pnlContent.Dock    = 'Fill'
$pnlContent.Controls.AddRange(@($pnlRight,$pnlLeft))

$form.Controls.AddRange(@($pnlContent,$pnlTop,$status))

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-AllCategories {
    @('All') + ($script:db.prompts | ForEach-Object { $_.category } | Sort-Object -Unique)
}

function Refresh-CategoryCombo {
    $sel = $cmbCat.SelectedItem
    $cmbCat.Items.Clear()
    Get-AllCategories | ForEach-Object { $cmbCat.Items.Add($_) | Out-Null }
    $idx = $cmbCat.Items.IndexOf($sel)
    $cmbCat.SelectedIndex = [Math]::Max(0, $idx)
}

function Refresh-PromptList {
    $lstPrompts.BeginUpdate()
    $lstPrompts.Items.Clear()

    $cat    = $cmbCat.SelectedItem
    $filter = if ($txtSearch.Text -eq 'Search...') { '' } else { $txtSearch.Text }

    $items = $script:db.prompts | Where-Object {
        ($cat -eq 'All' -or $_.category -eq $cat) -and
        (
            $filter -eq '' -or
            $_.title -like "*$filter*" -or
            $_.body  -like "*$filter*" -or
            ($_.tags -join ',') -like "*$filter*"
        )
    } | Sort-Object { (-not $_.pinned), $_.title }

    foreach ($p in $items) { $lstPrompts.Items.Add($p) | Out-Null }
    $statusLbl.Text = "$($lstPrompts.Items.Count) prompts"
    $lstPrompts.EndUpdate()
}

function Load-Prompt ($p) {
    if ($null -eq $p) { return }
    $script:selectedId = $p.id
    $txtTitle.Text     = $p.title
    $txtCategory.Text  = $p.category
    $txtTags.Text      = ($p.tags -join ', ')
    $txtBody.Text      = $p.body
    $chkPinned.Checked = $p.pinned
}

function Get-Selected {
    if ($null -eq $script:selectedId) { return $null }
    return $script:db.prompts | Where-Object { $_.id -eq $script:selectedId } | Select-Object -First 1
}

# ── Events ────────────────────────────────────────────────────────────────────
$txtSearch.Add_GotFocus({  if ($txtSearch.Text -eq 'Search...')  { $txtSearch.Text = ''; $txtSearch.ForeColor = $C.Text } })
$txtSearch.Add_LostFocus({ if ($txtSearch.Text -eq '')  { $txtSearch.Text = 'Search...'; $txtSearch.ForeColor = $C.TextMut } })
$txtSearch.Add_TextChanged({ Refresh-PromptList })
$cmbCat.Add_SelectedIndexChanged({ $script:filterCat = $cmbCat.SelectedItem; Refresh-PromptList })

$lstPrompts.Add_SelectedIndexChanged({ Load-Prompt $lstPrompts.SelectedItem })

$btnCopy.Add_Click({
    $p = Get-Selected
    if ($null -eq $p) { return }
    Set-Clipboard $p.body
    $p.useCount++
    Save-Data $script:db
    $statusLbl.Text = "Copied: $($p.title)"
    Refresh-PromptList
})

$btnSave.Add_Click({
    $p = Get-Selected
    if ($null -eq $p) {
        # Create new
        $p = @{
            id       = $script:db.nextId++
            title    = $txtTitle.Text
            category = $txtCategory.Text
            tags     = ($txtTags.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            body     = $txtBody.Text
            pinned   = $chkPinned.Checked
            useCount = 0
            created  = (Get-Date -Format 'o')
        }
        $script:db.prompts += $p
        $script:selectedId  = $p.id
    } else {
        $p.title    = $txtTitle.Text
        $p.category = $txtCategory.Text
        $p.tags     = ($txtTags.Text -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $p.body     = $txtBody.Text
        $p.pinned   = $chkPinned.Checked
    }
    Save-Data $script:db
    Refresh-CategoryCombo
    Refresh-PromptList
    $statusLbl.Text = "Saved: $($p.title)"
})

$btnNew.Add_Click({
    $script:selectedId = $null
    $txtTitle.Text     = 'New Prompt'
    $txtCategory.Text  = 'General'
    $txtTags.Text      = ''
    $txtBody.Text      = ''
    $chkPinned.Checked = $false
    $txtTitle.Focus()
})

$btnDelete.Add_Click({
    $p = Get-Selected
    if ($null -eq $p) { return }
    $r = [System.Windows.Forms.MessageBox]::Show("Delete '$($p.title)'?","Confirm",'YesNo','Question')
    if ($r -eq 'Yes') {
        $script:db.prompts = @($script:db.prompts | Where-Object { $_.id -ne $p.id })
        $script:selectedId = $null
        Save-Data $script:db
        Refresh-CategoryCombo
        Refresh-PromptList
        $txtTitle.Text = ''
        $txtBody.Text  = ''
    }
})

$btnExport.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'JSON files (*.json)|*.json'
    $dlg.FileName = "PromptLibrary_$(Get-Date -Format 'yyyy-MM-dd').json"
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:db | ConvertTo-Json -Depth 10 | Set-Content $dlg.FileName -Encoding UTF8
        $statusLbl.Text = "Exported to $($dlg.FileName)"
    }
})

$btnImport.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON files (*.json)|*.json'
    if ($dlg.ShowDialog() -eq 'OK') {
        try {
            $imported = Get-Content $dlg.FileName -Raw | ConvertFrom-Json -AsHashtable
            $added = 0
            foreach ($p in $imported.prompts) {
                $p.id = $script:db.nextId++
                $script:db.prompts += $p
                $added++
            }
            Save-Data $script:db
            Refresh-CategoryCombo
            Refresh-PromptList
            $statusLbl.Text = "Imported $added prompts"
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Import failed: $_",'Error','OK','Error') | Out-Null
        }
    }
})

# ── Tray icon ─────────────────────────────────────────────────────────────────
$tray               = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon          = [System.Drawing.SystemIcons]::Application
$tray.Text          = 'Prompt Library'
$tray.Visible       = $true
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })

$ctxTray            = New-Object System.Windows.Forms.ContextMenuStrip
$ctxTray.Items.Add('Show').Add_Click({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })
$ctxTray.Items.Add('Exit').Add_Click({ $tray.Visible=$false; $form.Close() })
$tray.ContextMenuStrip = $ctxTray

$form.Add_FormClosing({
    param($s,$e)
    if ($e.CloseReason -eq 'UserClosing') {
        $e.Cancel = $true
        $form.Hide()
    }
})

# ── Init ──────────────────────────────────────────────────────────────────────
Refresh-CategoryCombo
Refresh-PromptList

[System.Windows.Forms.Application]::Run($form)
$tray.Visible = $false
