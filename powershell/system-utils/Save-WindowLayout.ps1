#Requires -Version 5.1
<#
.SYNOPSIS
    Save and restore named window-position layouts on Windows.

.DESCRIPTION
    Captures the position, size and state (normal/maximized/minimized) of every
    visible window and saves it to a named profile.  Restoring a profile moves
    each window back to its saved position by matching on the process name and
    window title.

    Commands
    --------
    Save    <name>   Capture current layout
    Restore <name>   Restore a saved layout
    List             List saved layouts
    Delete  <name>   Delete a saved layout
    GUI              Open the interactive GUI (default when no args)

.PARAMETER Command
    Save | Restore | List | Delete | GUI

.PARAMETER LayoutName
    Name of the layout profile.

.PARAMETER DataFile
    JSON file to store layouts.  Defaults to WindowLayouts.json next to script.

.EXAMPLE
    .\Save-WindowLayout.ps1
    .\Save-WindowLayout.ps1 -Command Save -LayoutName "Coding Setup"
    .\Save-WindowLayout.ps1 -Command Restore -LayoutName "Coding Setup"
#>
[CmdletBinding()]
param(
    [ValidateSet('Save','Restore','List','Delete','GUI')]
    [string] $Command    = 'GUI',
    [string] $LayoutName = '',
    [string] $DataFile   = (Join-Path $PSScriptRoot 'WindowLayouts.json')
)

# ── Win32 API ─────────────────────────────────────────────────────────────────
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class WindowHelper {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINDOWPLACEMENT {
        public int length, flags, showCmd;
        public System.Drawing.Point ptMinPosition, ptMaxPosition;
        public RECT rcNormalPosition;
    }

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int  GetWindowText(IntPtr hWnd, StringBuilder sb, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);
    [DllImport("user32.dll")] public static extern int  GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static List<IntPtr> GetVisibleWindows() {
        var windows = new List<IntPtr>();
        EnumWindows((hWnd, lp) => {
            if (IsWindowVisible(hWnd)) {
                var sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, 256);
                if (sb.Length > 0) windows.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return windows;
    }
}
"@ -ReferencedAssemblies 'System.Drawing'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ── Colours ───────────────────────────────────────────────────────────────────
$C = @{
    Bg      = [System.Drawing.Color]::FromArgb(18,18,24)
    BgMid   = [System.Drawing.Color]::FromArgb(28,28,38)
    BgLight = [System.Drawing.Color]::FromArgb(38,38,56)
    Accent  = [System.Drawing.Color]::FromArgb(245,158,11)
    Text    = [System.Drawing.Color]::FromArgb(226,232,240)
    TextMut = [System.Drawing.Color]::FromArgb(100,116,139)
    Green   = [System.Drawing.Color]::FromArgb(34,197,94)
    Border  = [System.Drawing.Color]::FromArgb(51,65,85)
}
$FontUI   = New-Object System.Drawing.Font('Segoe UI', 9)
$FontH1   = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$FontBold = New-Object System.Drawing.Font('Segoe UI', 9,  [System.Drawing.FontStyle]::Bold)

# ── Data helpers ──────────────────────────────────────────────────────────────
function Load-Layouts {
    if (Test-Path $DataFile) {
        try { return Get-Content $DataFile -Raw | ConvertFrom-Json -AsHashtable }
        catch {}
    }
    return @{ layouts = @{} }
}

function Save-Layouts ($db) {
    $db | ConvertTo-Json -Depth 10 | Set-Content $DataFile -Encoding UTF8
}

$script:db = Load-Layouts

# ── Capture windows ───────────────────────────────────────────────────────────
function Capture-Windows {
    $windows  = [WindowHelper]::GetVisibleWindows()
    $snapshot = @()

    foreach ($hWnd in $windows) {
        $sb = New-Object System.Text.StringBuilder 256
        [WindowHelper]::GetWindowText($hWnd, $sb, 256) | Out-Null
        $title = $sb.ToString()

        $pid = 0
        [WindowHelper]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null
        try { $procName = (Get-Process -Id $pid -ErrorAction Stop).ProcessName } catch { continue }

        $placement = New-Object WindowHelper+WINDOWPLACEMENT
        $placement.length = [System.Runtime.InteropServices.Marshal]::SizeOf($placement)
        [WindowHelper]::GetWindowPlacement($hWnd, [ref]$placement) | Out-Null

        $snapshot += @{
            title    = $title
            process  = $procName
            showCmd  = $placement.showCmd
            left     = $placement.rcNormalPosition.Left
            top      = $placement.rcNormalPosition.Top
            right    = $placement.rcNormalPosition.Right
            bottom   = $placement.rcNormalPosition.Bottom
        }
    }
    return $snapshot
}

# ── Restore windows ───────────────────────────────────────────────────────────
function Restore-Windows ([array]$snapshot) {
    $current = [WindowHelper]::GetVisibleWindows()
    $matched = 0

    foreach ($saved in $snapshot) {
        foreach ($hWnd in $current) {
            $sb = New-Object System.Text.StringBuilder 256
            [WindowHelper]::GetWindowText($hWnd, $sb, 256) | Out-Null
            $title = $sb.ToString()

            $pid = 0
            [WindowHelper]::GetWindowThreadProcessId($hWnd, [ref]$pid) | Out-Null
            try { $procName = (Get-Process -Id $pid -ErrorAction Stop).ProcessName } catch { continue }

            if ($procName -eq $saved.process -and $title -eq $saved.title) {
                $placement = New-Object WindowHelper+WINDOWPLACEMENT
                $placement.length  = [System.Runtime.InteropServices.Marshal]::SizeOf($placement)
                $placement.showCmd = $saved.showCmd
                $placement.rcNormalPosition = [WindowHelper+RECT]@{
                    Left   = $saved.left
                    Top    = $saved.top
                    Right  = $saved.right
                    Bottom = $saved.bottom
                }
                [WindowHelper]::SetWindowPlacement($hWnd, [ref]$placement) | Out-Null
                $matched++
                break
            }
        }
    }
    return $matched
}

# ── CLI mode ──────────────────────────────────────────────────────────────────
function CLI-Save ([string]$name) {
    if (-not $name) { $name = Read-Host 'Layout name' }
    $snap = Capture-Windows
    $script:db.layouts[$name] = @{
        name      = $name
        savedAt   = (Get-Date -Format 'o')
        windows   = $snap
    }
    Save-Layouts $script:db
    Write-Host "✓ Saved layout '$name' with $($snap.Count) windows" -ForegroundColor Green
}

function CLI-Restore ([string]$name) {
    if (-not $name) { $name = Read-Host 'Layout name' }
    if (-not $script:db.layouts.ContainsKey($name)) {
        Write-Host "Layout '$name' not found." -ForegroundColor Red; return
    }
    $count = Restore-Windows $script:db.layouts[$name].windows
    Write-Host "✓ Restored $count window(s) for layout '$name'" -ForegroundColor Green
}

function CLI-List {
    if ($script:db.layouts.Count -eq 0) { Write-Host 'No layouts saved.' -ForegroundColor Yellow; return }
    $script:db.layouts.GetEnumerator() | Sort-Object Key | ForEach-Object {
        Write-Host "  $($_.Key)  —  $($_.Value.windows.Count) windows  (saved $($_.Value.savedAt))" -ForegroundColor Cyan
    }
}

if ($Command -eq 'Save')    { CLI-Save $LayoutName; exit }
if ($Command -eq 'Restore') { CLI-Restore $LayoutName; exit }
if ($Command -eq 'List')    { CLI-List; exit }
if ($Command -eq 'Delete')  {
    $script:db.layouts.Remove($LayoutName)
    Save-Layouts $script:db
    Write-Host "Deleted '$LayoutName'" -ForegroundColor Yellow
    exit
}

# ── GUI ───────────────────────────────────────────────────────────────────────
$form               = New-Object System.Windows.Forms.Form
$form.Text          = '🪟 Window Layout Manager'
$form.Size          = New-Object System.Drawing.Size(680,480)
$form.BackColor     = $C.Bg
$form.ForeColor     = $C.Text
$form.Font          = $FontUI
$form.StartPosition = 'CenterScreen'
$form.Icon          = [System.Drawing.SystemIcons]::Application

$pnlTop             = New-Object System.Windows.Forms.Panel
$pnlTop.Dock        = 'Top'; $pnlTop.Height = 48; $pnlTop.BackColor = $C.BgMid

$lblH               = New-Object System.Windows.Forms.Label
$lblH.Text          = '🪟 Window Layout Manager'
$lblH.Font          = $FontH1; $lblH.ForeColor = $C.Accent
$lblH.AutoSize      = $true; $lblH.Location = New-Object System.Drawing.Point(10,13)

$txtNewName         = New-Object System.Windows.Forms.TextBox
$txtNewName.Location= New-Object System.Drawing.Point(330,13)
$txtNewName.Size    = New-Object System.Drawing.Size(180,22)
$txtNewName.BackColor = $C.BgLight; $txtNewName.ForeColor = $C.Text
$txtNewName.BorderStyle = 'FixedSingle'; $txtNewName.Text = 'Layout name'

$btnSaveLayout      = New-Object System.Windows.Forms.Button
$btnSaveLayout.Text = '💾 Save Current'
$btnSaveLayout.Location = New-Object System.Drawing.Point(518,12)
$btnSaveLayout.Size = New-Object System.Drawing.Size(130,26)
$btnSaveLayout.BackColor = $C.Accent
$btnSaveLayout.ForeColor = [System.Drawing.Color]::White
$btnSaveLayout.FlatStyle = 'Flat'; $btnSaveLayout.FlatAppearance.BorderSize = 0

$pnlTop.Controls.AddRange(@($lblH,$txtNewName,$btnSaveLayout))

$lstLayouts         = New-Object System.Windows.Forms.ListBox
$lstLayouts.Dock    = 'Left'; $lstLayouts.Width = 220
$lstLayouts.BackColor = $C.BgMid; $lstLayouts.ForeColor = $C.Text
$lstLayouts.BorderStyle = 'None'; $lstLayouts.Font = $FontBold

$pnlDetail          = New-Object System.Windows.Forms.Panel
$pnlDetail.Dock     = 'Fill'; $pnlDetail.BackColor = $C.Bg; $pnlDetail.Padding = New-Object System.Windows.Forms.Padding(16)

$lblDetailH         = New-Object System.Windows.Forms.Label
$lblDetailH.Font    = $FontH1; $lblDetailH.ForeColor = $C.Accent
$lblDetailH.AutoSize = $true; $lblDetailH.Location = New-Object System.Drawing.Point(16,16)
$lblDetailH.Text    = 'Select a layout'

$lblInfo            = New-Object System.Windows.Forms.Label
$lblInfo.ForeColor  = $C.TextMut; $lblInfo.AutoSize = $true
$lblInfo.Location   = New-Object System.Drawing.Point(16,46); $lblInfo.Text = ''

$lstWindows         = New-Object System.Windows.Forms.ListBox
$lstWindows.Location= New-Object System.Drawing.Point(16,74)
$lstWindows.Size    = New-Object System.Drawing.Size(400,240)
$lstWindows.BackColor = $C.BgLight; $lstWindows.ForeColor = $C.Text
$lstWindows.BorderStyle = 'None'; $lstWindows.Font = $FontUI

$btnRestore         = New-Object System.Windows.Forms.Button
$btnRestore.Text    = '⚡ Restore Layout'
$btnRestore.Location= New-Object System.Drawing.Point(16,326)
$btnRestore.Size    = New-Object System.Drawing.Size(140,32)
$btnRestore.BackColor = $C.Green
$btnRestore.ForeColor = [System.Drawing.Color]::White
$btnRestore.FlatStyle = 'Flat'; $btnRestore.FlatAppearance.BorderSize = 0

$btnDelLayout       = New-Object System.Windows.Forms.Button
$btnDelLayout.Text  = '🗑 Delete'
$btnDelLayout.Location = New-Object System.Drawing.Point(168,326)
$btnDelLayout.Size  = New-Object System.Drawing.Size(90,32)
$btnDelLayout.BackColor = $C.BgLight; $btnDelLayout.ForeColor = $C.Text
$btnDelLayout.FlatStyle = 'Flat'; $btnDelLayout.FlatAppearance.BorderColor = $C.Border

$pnlDetail.Controls.AddRange(@($lblDetailH,$lblInfo,$lstWindows,$btnRestore,$btnDelLayout))

$statusBar          = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor= $C.BgMid
$statusLbl          = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLbl.ForeColor= $C.TextMut; $statusLbl.Text = 'Ready'
$statusBar.Items.Add($statusLbl) | Out-Null

$pnlContent         = New-Object System.Windows.Forms.Panel
$pnlContent.Dock    = 'Fill'
$pnlContent.Controls.AddRange(@($pnlDetail,$lstLayouts))

$form.Controls.AddRange(@($pnlContent,$pnlTop,$statusBar))

function Refresh-List {
    $lstLayouts.Items.Clear()
    $script:db.layouts.Keys | Sort-Object | ForEach-Object { $lstLayouts.Items.Add($_) | Out-Null }
}

function Load-Detail ([string]$name) {
    if (-not $name -or -not $script:db.layouts.ContainsKey($name)) { return }
    $layout = $script:db.layouts[$name]
    $lblDetailH.Text = $name
    $lblInfo.Text    = "$($layout.windows.Count) windows  ·  saved $(([datetime]$layout.savedAt).ToString('yyyy-MM-dd HH:mm'))"
    $lstWindows.Items.Clear()
    foreach ($w in $layout.windows) { $lstWindows.Items.Add("[$($w.process)]  $($w.title)") | Out-Null }
}

$lstLayouts.Add_SelectedIndexChanged({ Load-Detail $lstLayouts.SelectedItem })

$btnSaveLayout.Add_Click({
    $name = $txtNewName.Text.Trim()
    if (-not $name -or $name -eq 'Layout name') { $name = "Layout $(Get-Date -Format 'HH:mm')" }
    $snap = Capture-Windows
    $script:db.layouts[$name] = @{
        name    = $name
        savedAt = (Get-Date -Format 'o')
        windows = $snap
    }
    Save-Layouts $script:db
    Refresh-List
    $lstLayouts.SelectedItem = $name
    $statusLbl.Text = "Saved '$name' with $($snap.Count) windows"
})

$btnRestore.Add_Click({
    $name = $lstLayouts.SelectedItem
    if (-not $name) { return }
    $count = Restore-Windows $script:db.layouts[$name].windows
    $statusLbl.Text = "Restored $count window(s)"
})

$btnDelLayout.Add_Click({
    $name = $lstLayouts.SelectedItem
    if (-not $name) { return }
    $r = [System.Windows.Forms.MessageBox]::Show("Delete '$name'?","Confirm",'YesNo','Question')
    if ($r -eq 'Yes') {
        $script:db.layouts.Remove($name)
        Save-Layouts $script:db
        Refresh-List
        $lstWindows.Items.Clear()
        $lblDetailH.Text = 'Select a layout'
    }
})

Refresh-List
[System.Windows.Forms.Application]::Run($form)
