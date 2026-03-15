#Requires -Version 5.1
<#
.SYNOPSIS
    Persistent clipboard history manager with a searchable GUI.

.DESCRIPTION
    Monitors the clipboard in the background and stores every unique text entry.
    A searchable, copy-on-click overlay window lets you quickly find and paste
    any previous clipboard item.

    Features
    --------
    - Captures text, file paths and URLs from the clipboard automatically
    - Searchable list with instant filtering
    - Double-click or Enter to copy an item back to clipboard
    - Pin important items so they survive the ring buffer
    - Delete individual items or clear all history
    - History persists to a JSON file between sessions
    - System-tray icon; Win+Shift+V global hotkey to show the window

.PARAMETER DataFile
    Path to history JSON.  Defaults to ClipboardHistory.json next to script.

.PARAMETER MaxItems
    Maximum unpinned items to keep (default 200).

.EXAMPLE
    .\Invoke-ClipboardManager.ps1
#>
[CmdletBinding()]
param(
    [string] $DataFile = (Join-Path $PSScriptRoot 'ClipboardHistory.json'),
    [int]    $MaxItems = 200
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Win32 for global hotkey ───────────────────────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HotkeyHelper {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@

$MOD_WIN    = 0x0008
$MOD_SHIFT  = 0x0004
$VK_V       = 0x56
$HOTKEY_ID  = 9001
$WM_HOTKEY  = 0x0312

# ── Colours ───────────────────────────────────────────────────────────────────
$C = @{
    Bg      = [System.Drawing.Color]::FromArgb(15,17,23)
    BgMid   = [System.Drawing.Color]::FromArgb(22,27,34)
    BgLight = [System.Drawing.Color]::FromArgb(33,38,50)
    Accent  = [System.Drawing.Color]::FromArgb(56,139,253)
    Text    = [System.Drawing.Color]::FromArgb(201,209,217)
    TextMut = [System.Drawing.Color]::FromArgb(110,118,129)
    Green   = [System.Drawing.Color]::FromArgb(63,185,80)
    Border  = [System.Drawing.Color]::FromArgb(48,54,61)
    Pin     = [System.Drawing.Color]::FromArgb(210,153,34)
}
$FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FontMono = New-Object System.Drawing.Font('Cascadia Code', 8)
$FontH1   = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)

# ── Data helpers ──────────────────────────────────────────────────────────────
function Load-History {
    if (Test-Path $DataFile) {
        try { return [System.Collections.Generic.List[hashtable]](Get-Content $DataFile -Raw | ConvertFrom-Json -AsHashtable) }
        catch {}
    }
    return [System.Collections.Generic.List[hashtable]]::new()
}

function Save-History {
    $script:history | ConvertTo-Json -Depth 5 | Set-Content $DataFile -Encoding UTF8
}

$script:history    = Load-History
$script:lastClip   = ''
$script:filterText = ''

function Trim-History {
    $pinned   = @($script:history | Where-Object { $_.pinned })
    $unpinned = @($script:history | Where-Object { -not $_.pinned })
    if ($unpinned.Count -gt $MaxItems) {
        $unpinned = $unpinned | Select-Object -Last $MaxItems
    }
    $script:history = [System.Collections.Generic.List[hashtable]]($pinned + $unpinned)
}

function Add-ClipEntry ([string]$text) {
    $text = $text.Trim()
    if ([string]::IsNullOrEmpty($text)) { return }
    if ($text -eq $script:lastClip) { return }
    # Remove duplicate (move to top)
    $dup = $script:history | Where-Object { $_.text -eq $text } | Select-Object -First 1
    if ($dup) { $script:history.Remove($dup) | Out-Null }

    $script:history.Add(@{
        id      = [Guid]::NewGuid().ToString()
        text    = $text
        copied  = (Get-Date -Format 'o')
        pinned  = $false
    }) | Out-Null
    $script:lastClip = $text
    Trim-History
    Save-History
}

# ── Form ──────────────────────────────────────────────────────────────────────
$form               = New-Object System.Windows.Forms.Form
$form.Text          = '📋 Clipboard History'
$form.Size          = New-Object System.Drawing.Size(520, 560)
$form.MinimumSize   = New-Object System.Drawing.Size(380, 400)
$form.BackColor     = $C.Bg
$form.ForeColor     = $C.Text
$form.Font          = $FontUI
$form.StartPosition = 'CenterScreen'
$form.ShowInTaskbar = $false
$form.TopMost       = $true
$form.Icon          = [System.Drawing.SystemIcons]::Application

# Top bar
$pnlTop             = New-Object System.Windows.Forms.Panel
$pnlTop.Dock        = 'Top'
$pnlTop.Height      = 48
$pnlTop.BackColor   = $C.BgMid

$lblH               = New-Object System.Windows.Forms.Label
$lblH.Text          = '📋 Clipboard History'
$lblH.Font          = $FontH1
$lblH.ForeColor     = $C.Accent
$lblH.AutoSize      = $true
$lblH.Location      = New-Object System.Drawing.Point(10,13)

$txtSearch          = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(220,14)
$txtSearch.Size     = New-Object System.Drawing.Size(200,22)
$txtSearch.BackColor= $C.BgLight
$txtSearch.ForeColor= $C.TextMut
$txtSearch.Text     = 'Filter...'
$txtSearch.BorderStyle = 'FixedSingle'

$btnClear           = New-Object System.Windows.Forms.Button
$btnClear.Text      = '🗑 Clear All'
$btnClear.Location  = New-Object System.Drawing.Point(428,13)
$btnClear.Size      = New-Object System.Drawing.Size(78,24)
$btnClear.BackColor = $C.BgLight
$btnClear.ForeColor = $C.Text
$btnClear.FlatStyle = 'Flat'
$btnClear.FlatAppearance.BorderColor = $C.Border

$pnlTop.Controls.AddRange(@($lblH,$txtSearch,$btnClear))

# List
$lstHistory         = New-Object System.Windows.Forms.ListBox
$lstHistory.Dock    = 'Fill'
$lstHistory.BackColor = $C.Bg
$lstHistory.ForeColor = $C.Text
$lstHistory.Font    = $FontUI
$lstHistory.BorderStyle = 'None'
$lstHistory.ItemHeight  = 56
$lstHistory.DrawMode    = 'OwnerDrawFixed'

$lstHistory.Add_DrawItem({
    param($s,$e)
    $e.DrawBackground()
    if ($e.Index -lt 0) { return }
    $item = $e.Item
    if ($null -eq $item) { return }
    $b = $e.Bounds

    $bg = if ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) { $C.BgLight } else { $C.Bg }
    $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $b)

    if ($item.pinned) {
        $e.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($C.Pin)), $b.X, $b.Y, 3, $b.Height)
    }

    # Preview text (first line, truncated)
    $preview = ($item.text -split "`n" | Select-Object -First 1).Trim()
    if ($preview.Length -gt 70) { $preview = $preview.Substring(0,67) + '...' }
    $e.Graphics.DrawString($preview, $FontUI, (New-Object System.Drawing.SolidBrush($C.Text)), ($b.X+10), ($b.Y+8))

    # Second line preview
    $lines = $item.text -split "`n"
    if ($lines.Count -gt 1) {
        $line2 = $lines[1].Trim()
        if ($line2.Length -gt 70) { $line2 = $line2.Substring(0,67) + '...' }
        $e.Graphics.DrawString($line2, $FontMono, (New-Object System.Drawing.SolidBrush($C.TextMut)), ($b.X+10), ($b.Y+26))
    }

    # Timestamp
    try {
        $ts = [datetime]$item.copied
        $ago = (Get-Date) - $ts
        $timeStr = if     ($ago.TotalMinutes -lt 1)  { 'just now' }
                   elseif ($ago.TotalHours   -lt 1)  { "$([int]$ago.TotalMinutes)m ago" }
                   elseif ($ago.TotalDays    -lt 1)  { "$([int]$ago.TotalHours)h ago" }
                   else                               { $ts.ToString('MMM d') }
        $e.Graphics.DrawString($timeStr, $FontUI, (New-Object System.Drawing.SolidBrush($C.TextMut)), ($b.Right-55), ($b.Y+8))
    } catch {}

    $e.Graphics.DrawLine((New-Object System.Drawing.Pen($C.Border,1)), $b.X, $b.Bottom-1, $b.Right, $b.Bottom-1)
    $e.DrawFocusRectangle()
})

# Context menu for list
$ctx                = New-Object System.Windows.Forms.ContextMenuStrip
$ctx.BackColor      = $C.BgMid
$ctx.ForeColor      = $C.Text
$mnuCopy            = $ctx.Items.Add('Copy to clipboard')
$mnuPin             = $ctx.Items.Add('Toggle pin')
$mnuDel             = $ctx.Items.Add('Delete')
$lstHistory.ContextMenuStrip = $ctx

# Status bar
$statusBar          = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor= $C.BgMid
$statusLbl          = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLbl.ForeColor= $C.TextMut
$statusLbl.Text     = 'Win+Shift+V to show  ·  Double-click to copy'
$statusBar.Items.Add($statusLbl) | Out-Null

$form.Controls.AddRange(@($lstHistory,$pnlTop,$statusBar))

# ── Refresh list ──────────────────────────────────────────────────────────────
function Refresh-List {
    $lstHistory.BeginUpdate()
    $lstHistory.Items.Clear()
    $f = if ($txtSearch.Text -eq 'Filter...') { '' } else { $txtSearch.Text }
    $items = @($script:history | Where-Object {
        $f -eq '' -or $_.text -like "*$f*"
    })
    # Show newest first
    [array]::Reverse($items)
    foreach ($i in $items) { $lstHistory.Items.Add($i) | Out-Null }
    $statusLbl.Text = "$($lstHistory.Items.Count) items  ·  Win+Shift+V to show  ·  Double-click to copy"
    $lstHistory.EndUpdate()
}

# ── Events ────────────────────────────────────────────────────────────────────
$txtSearch.Add_GotFocus({  if ($txtSearch.Text -eq 'Filter...')  { $txtSearch.Text = ''; $txtSearch.ForeColor = $C.Text } })
$txtSearch.Add_LostFocus({ if ($txtSearch.Text -eq '')  { $txtSearch.Text = 'Filter...'; $txtSearch.ForeColor = $C.TextMut } })
$txtSearch.Add_TextChanged({ Refresh-List })

$lstHistory.Add_DoubleClick({
    $item = $lstHistory.SelectedItem
    if ($item) {
        $script:lastClip = $item.text  # prevent re-adding
        Set-Clipboard $item.text
        $form.Hide()
    }
})

$lstHistory.Add_KeyDown({
    param($s,$e)
    if ($e.KeyCode -eq 'Return') {
        $item = $lstHistory.SelectedItem
        if ($item) {
            $script:lastClip = $item.text
            Set-Clipboard $item.text
            $form.Hide()
        }
    } elseif ($e.KeyCode -eq 'Delete') {
        $item = $lstHistory.SelectedItem
        if ($item) {
            $script:history.Remove($item) | Out-Null
            Save-History
            Refresh-List
        }
    } elseif ($e.KeyCode -eq 'Escape') {
        $form.Hide()
    }
})

$mnuCopy.Add_Click({
    $item = $lstHistory.SelectedItem
    if ($item) { $script:lastClip = $item.text; Set-Clipboard $item.text }
})

$mnuPin.Add_Click({
    $item = $lstHistory.SelectedItem
    if ($item) { $item.pinned = -not $item.pinned; Save-History; Refresh-List }
})

$mnuDel.Add_Click({
    $item = $lstHistory.SelectedItem
    if ($item) { $script:history.Remove($item) | Out-Null; Save-History; Refresh-List }
})

$btnClear.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show('Clear all unpinned items?','Confirm','YesNo','Question')
    if ($r -eq 'Yes') {
        $pinned = @($script:history | Where-Object { $_.pinned })
        $script:history = [System.Collections.Generic.List[hashtable]]($pinned)
        Save-History
        Refresh-List
    }
})

$form.Add_FormClosing({
    param($s,$e)
    if ($e.CloseReason -eq 'UserClosing') {
        $e.Cancel = $true
        $form.Hide()
    }
})

# Override WndProc to catch WM_HOTKEY
$form.Add_Shown({
    [HotkeyHelper]::RegisterHotKey($form.Handle, $HOTKEY_ID, ($MOD_WIN -bor $MOD_SHIFT), $VK_V) | Out-Null
})
$form.Add_FormClosed({ [HotkeyHelper]::UnregisterHotKey($form.Handle, $HOTKEY_ID) | Out-Null })

# Message pump override via Application.AddMessageFilter
Add-Type @"
using System;
using System.Windows.Forms;
public class HotkeyFilter : IMessageFilter {
    public int HotkeyId;
    public Action ShowAction;
    public bool PreFilterMessage(ref Message m) {
        if (m.Msg == 0x0312 && m.WParam.ToInt32() == HotkeyId) {
            ShowAction?.Invoke();
            return true;
        }
        return false;
    }
}
"@

$hkFilter = New-Object HotkeyFilter
$hkFilter.HotkeyId    = $HOTKEY_ID
$hkFilter.ShowAction  = [Action]{
    $form.Show()
    $form.WindowState = 'Normal'
    $form.Activate()
    $txtSearch.Clear()
    $txtSearch.Text = 'Filter...'
    $txtSearch.ForeColor = $C.TextMut
    Refresh-List
    if ($lstHistory.Items.Count -gt 0) { $lstHistory.SelectedIndex = 0 }
}
[System.Windows.Forms.Application]::AddMessageFilter($hkFilter)

# ── Tray icon ─────────────────────────────────────────────────────────────────
$tray               = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon          = [System.Drawing.SystemIcons]::Application
$tray.Text          = 'Clipboard Manager'
$tray.Visible       = $true
$tray.Add_DoubleClick({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })

$ctxTray            = New-Object System.Windows.Forms.ContextMenuStrip
$ctxTray.Items.Add('Show History').Add_Click({ $form.Show(); $form.WindowState='Normal'; $form.Activate() })
$ctxTray.Items.Add('Exit').Add_Click({ $tray.Visible=$false; [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $ctxTray

# ── Clipboard polling timer ────────────────────────────────────────────────────
$timer              = New-Object System.Windows.Forms.Timer
$timer.Interval     = 500

$timer.Add_Tick({
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $text = [System.Windows.Forms.Clipboard]::GetText()
            if ($text -ne $script:lastClip) {
                Add-ClipEntry $text
                if ($form.Visible) { Refresh-List }
            }
        }
    } catch {}
})
$timer.Start()

# ── Boot ──────────────────────────────────────────────────────────────────────
Refresh-List
$tray.ShowBalloonTip(2000,'Clipboard Manager','Running in tray. Win+Shift+V to open.','Info')
[System.Windows.Forms.Application]::Run()
$timer.Stop()
$tray.Visible = $false
