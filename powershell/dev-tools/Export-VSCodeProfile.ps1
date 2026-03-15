#Requires -Version 5.1
<#
.SYNOPSIS
    Back up and restore a VS Code profile (extensions + settings).

.DESCRIPTION
    EXPORT  Lists every installed extension and copies settings.json,
            keybindings.json and snippets/ into a dated backup folder or
            a specified destination.

    IMPORT  Installs all extensions listed in the backup manifest and
            copies the settings files back.

    The extension manifest is a plain text file (one extension ID per line)
    compatible with `code --install-extension`.

.PARAMETER Mode
    Export | Import.

.PARAMETER BackupDir
    Destination (Export) or source (Import) directory.
    Defaults to  ~/VSCodeBackups/<date>  for Export, or prompts for Import.

.PARAMETER IncludeSettings
    Include settings.json, keybindings.json and snippets/ (default: true).

.PARAMETER Force
    Overwrite existing backup directory without prompting.

.EXAMPLE
    .\Export-VSCodeProfile.ps1 -Mode Export
    .\Export-VSCodeProfile.ps1 -Mode Export -BackupDir D:\Backups\VSCode
    .\Export-VSCodeProfile.ps1 -Mode Import -BackupDir D:\Backups\VSCode\2024-11-05
#>
[CmdletBinding()]
param(
    [ValidateSet('Export','Import')]
    [string] $Mode           = 'Export',
    [string] $BackupDir      = '',
    [bool]   $IncludeSettings = $true,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

function Write-Step  ([string]$msg) { Write-Host "  ▶ $msg" -ForegroundColor Cyan }
function Write-Done  ([string]$msg) { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Info  ([string]$msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Warn  ([string]$msg) { Write-Host "  ⚠ $msg" -ForegroundColor Yellow }
function Write-Err   ([string]$msg) { Write-Host "  ✗ $msg" -ForegroundColor Red }

# ── Locate VS Code binary ─────────────────────────────────────────────────────
function Find-CodeBinary {
    $candidates = @('code','code-insiders','codium')
    foreach ($c in $candidates) {
        $found = Get-Command $c -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    # common install paths on Windows
    @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$codeBin = Find-CodeBinary
if (-not $codeBin) {
    Write-Err 'Could not find VS Code binary (code / code-insiders / codium) in PATH or common locations.'
    exit 1
}

# ── Locate VS Code user-data directory ───────────────────────────────────────
$vscodeUserDir = switch ($true) {
    ($IsLinux -or $IsMacOS) { "$HOME/.config/Code/User" }
    default { "$env:APPDATA\Code\User" }
}

if (-not (Test-Path $vscodeUserDir)) {
    # Try Insiders
    $vscodeUserDir = "$env:APPDATA\Code - Insiders\User"
}

Write-Host ''
Write-Host '  VS Code Profile Manager' -ForegroundColor Cyan
Write-Host "  User dir : $vscodeUserDir" -ForegroundColor DarkGray
Write-Host "  Mode     : $Mode" -ForegroundColor DarkGray
Write-Host ''

# ─────────────────────────────────────────────────────────────────────────────
#  EXPORT
# ─────────────────────────────────────────────────────────────────────────────
if ($Mode -eq 'Export') {
    if (-not $BackupDir) {
        $BackupDir = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) `
                        "VSCodeBackups\$(Get-Date -Format 'yyyy-MM-dd_HH-mm')"
    }

    if (Test-Path $BackupDir) {
        if (-not $Force) {
            $ans = Read-Host "  Backup dir already exists. Overwrite? [y/N]"
            if ($ans -notmatch '^[Yy]') { exit 0 }
        }
        Remove-Item $BackupDir -Recurse -Force
    }
    New-Item $BackupDir -ItemType Directory | Out-Null

    # Extensions
    Write-Step 'Listing installed extensions...'
    $extensions = & $codeBin --list-extensions 2>&1
    $extFile    = Join-Path $BackupDir 'extensions.txt'
    $extensions | Set-Content $extFile -Encoding UTF8
    Write-Done "Saved $($extensions.Count) extension IDs to $extFile"

    # Settings files
    if ($IncludeSettings -and (Test-Path $vscodeUserDir)) {
        Write-Step 'Copying settings files...'
        $settingsFiles = @('settings.json','keybindings.json')
        $settingsDest  = Join-Path $BackupDir 'settings'
        New-Item $settingsDest -ItemType Directory | Out-Null

        foreach ($f in $settingsFiles) {
            $src = Join-Path $vscodeUserDir $f
            if (Test-Path $src) {
                Copy-Item $src $settingsDest
                Write-Info "  Copied $f"
            }
        }

        $snippetsDir = Join-Path $vscodeUserDir 'snippets'
        if (Test-Path $snippetsDir) {
            Copy-Item $snippetsDir (Join-Path $settingsDest 'snippets') -Recurse
            Write-Info '  Copied snippets/'
        }
        Write-Done 'Settings backed up'
    }

    # Manifest
    $manifest = @{
        exportedAt   = (Get-Date -Format 'o')
        codeVersion  = (& $codeBin --version 2>&1 | Select-Object -First 1)
        extensionCount = $extensions.Count
        settingsIncluded = $IncludeSettings
    }
    $manifest | ConvertTo-Json | Set-Content (Join-Path $BackupDir 'manifest.json') -Encoding UTF8

    Write-Host ''
    Write-Done "Backup complete → $BackupDir"
    Write-Host ''
}

# ─────────────────────────────────────────────────────────────────────────────
#  IMPORT
# ─────────────────────────────────────────────────────────────────────────────
else {
    if (-not $BackupDir) {
        # Find most recent backup
        $backupsRoot = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) 'VSCodeBackups'
        if (Test-Path $backupsRoot) {
            $latest = Get-ChildItem $backupsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($latest) {
                $BackupDir = $latest.FullName
                Write-Info "Auto-selected most recent backup: $BackupDir"
            }
        }
        if (-not $BackupDir) {
            $BackupDir = Read-Host '  Path to backup folder'
        }
    }

    if (-not (Test-Path $BackupDir)) {
        Write-Err "Backup directory not found: $BackupDir"
        exit 1
    }

    $extFile = Join-Path $BackupDir 'extensions.txt'
    if (-not (Test-Path $extFile)) {
        Write-Err "No extensions.txt found in $BackupDir"
        exit 1
    }

    # Extensions
    $extensions = Get-Content $extFile | Where-Object { $_.Trim() }
    Write-Step "Installing $($extensions.Count) extensions..."
    $installed = 0; $failed = 0

    foreach ($ext in $extensions) {
        $ext = $ext.Trim()
        Write-Host "  Installing $ext..." -ForegroundColor DarkGray -NoNewline
        $result = & $codeBin --install-extension $ext --force 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host ' ✓' -ForegroundColor Green
            $installed++
        } else {
            Write-Host ' ✗' -ForegroundColor Red
            $failed++
            Write-Verbose ($result -join ' ')
        }
    }

    Write-Done "Extensions: $installed installed, $failed failed"

    # Settings
    $settingsDir = Join-Path $BackupDir 'settings'
    if ($IncludeSettings -and (Test-Path $settingsDir)) {
        Write-Step 'Restoring settings files...'
        foreach ($f in @('settings.json','keybindings.json')) {
            $src = Join-Path $settingsDir $f
            $dst = Join-Path $vscodeUserDir $f
            if (Test-Path $src) {
                # Backup existing
                if (Test-Path $dst) {
                    Copy-Item $dst "$dst.bak" -Force
                }
                Copy-Item $src $dst -Force
                Write-Info "  Restored $f"
            }
        }
        $snippetsSrc = Join-Path $settingsDir 'snippets'
        if (Test-Path $snippetsSrc) {
            $snippetsDst = Join-Path $vscodeUserDir 'snippets'
            if (-not (Test-Path $snippetsDst)) { New-Item $snippetsDst -ItemType Directory | Out-Null }
            Copy-Item "$snippetsSrc\*" $snippetsDst -Recurse -Force
            Write-Info '  Restored snippets/'
        }
        Write-Done 'Settings restored'
    }

    Write-Host ''
    Write-Done 'Import complete — restart VS Code to apply changes'
    Write-Host ''
}
