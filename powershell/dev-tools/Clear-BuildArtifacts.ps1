#Requires -Version 5.1
<#
.SYNOPSIS
    Recursively removes common build / dependency artefacts to reclaim disk space.

.DESCRIPTION
    Walks a root directory and deletes folders/files that match a set of
    well-known patterns (node_modules, dist, .cache, __pycache__, etc.).
    Always shows a size summary and asks for confirmation before deleting,
    unless -Force is specified.

.PARAMETER RootDir
    Root directory to scan.  Defaults to current directory.

.PARAMETER Targets
    Override the default list of patterns to remove.  Each entry is a
    folder or file name / glob pattern passed to -Filter.

.PARAMETER MaxDepth
    How deep to recurse.  Defaults to 10.

.PARAMETER Force
    Skip confirmation prompt and delete immediately.

.PARAMETER WhatIf
    Show what would be deleted without actually deleting anything.

.EXAMPLE
    .\Clear-BuildArtifacts.ps1
    .\Clear-BuildArtifacts.ps1 -RootDir C:\Dev -Force
    .\Clear-BuildArtifacts.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]   $RootDir  = (Get-Location).Path,
    [string[]] $Targets  = @(
        'node_modules', 'dist', 'build', '.next', '.nuxt', '.svelte-kit',
        '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache',
        '.venv', 'venv', '.cache', '.parcel-cache', '.turbo',
        'target',          # Rust / Maven
        'bin', 'obj',      # .NET (inside project folders only)
        '.gradle',
        'vendor',          # PHP / Go modules cache
        'coverage',
        '.nyc_output',
        'storybook-static',
        '*.tsbuildinfo',
        '*.pyc',
        '*.pyo',
        'Thumbs.db',
        '.DS_Store'
    ),
    [int]      $MaxDepth = 10,
    [switch]   $Force
)

$ErrorActionPreference = 'Continue'

function Format-Size ([long]$bytes) {
    if     ($bytes -ge 1GB) { '{0:N2} GB' -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { '{0:N2} MB' -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { '{0:N2} KB' -f ($bytes / 1KB) }
    else                    { "$bytes B"  }
}

function Get-FolderSize ([string]$path) {
    try {
        (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum).Sum
    } catch { 0 }
}

Write-Host ''
Write-Host '  Clear-BuildArtifacts' -ForegroundColor Cyan
Write-Host "  Root: $RootDir" -ForegroundColor DarkGray
Write-Host ''

# ── Discover artefacts ────────────────────────────────────────────────────────
Write-Host '  Scanning...' -ForegroundColor DarkGray

$found = [System.Collections.Generic.List[psobject]]::new()

foreach ($pattern in $Targets) {
    # Distinguish file patterns (contain *) from plain folder names
    $isGlob = $pattern -match '\*|\?'

    if ($isGlob) {
        Get-ChildItem -Path $RootDir -Filter $pattern -Recurse -Force `
            -Depth $MaxDepth -ErrorAction SilentlyContinue |
            ForEach-Object {
                $found.Add([pscustomobject]@{
                    Type = 'File'
                    Path = $_.FullName
                    Size = $_.Length
                }) | Out-Null
            }
    } else {
        Get-ChildItem -Path $RootDir -Filter $pattern -Recurse -Force `
            -Depth $MaxDepth -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $sz = Get-FolderSize $_.FullName
                $found.Add([pscustomobject]@{
                    Type = 'Dir'
                    Path = $_.FullName
                    Size = $sz
                }) | Out-Null
            }
    }
}

# Deduplicate: remove items whose parent is already in the list
$paths = $found | ForEach-Object { $_.Path }
$deduped = $found | Where-Object {
    $item = $_
    -not ($found | Where-Object { $item.Path -ne $_.Path -and $item.Path.StartsWith($_.Path + [System.IO.Path]::DirectorySeparatorChar) })
}

if ($deduped.Count -eq 0) {
    Write-Host '  Nothing to clean — workspace is already tidy!' -ForegroundColor Green
    Write-Host ''
    exit 0
}

# ── Show what was found ───────────────────────────────────────────────────────
$totalSize = ($deduped | Measure-Object -Property Size -Sum).Sum

Write-Host "  Found $($deduped.Count) item(s) totalling $(Format-Size $totalSize):`n"

$deduped | Sort-Object Size -Descending | Select-Object -First 30 | ForEach-Object {
    $icon = if ($_.Type -eq 'Dir') { '📁' } else { '📄' }
    $sizeStr = (Format-Size $_.Size).PadLeft(10)
    Write-Host "  $icon $sizeStr  $($_.Path)" -ForegroundColor DarkGray
}

if ($deduped.Count -gt 30) {
    Write-Host "  ... and $($deduped.Count - 30) more items" -ForegroundColor DarkGray
}

Write-Host ''

# ── Confirm ───────────────────────────────────────────────────────────────────
if (-not $Force -and -not $WhatIfPreference) {
    $answer = Read-Host "  Delete these $($deduped.Count) item(s) and reclaim $(Format-Size $totalSize)? [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host '  Aborted.' -ForegroundColor Yellow
        exit 0
    }
}

# ── Delete ────────────────────────────────────────────────────────────────────
$deleted = 0
$errors  = 0
$freedBytes = 0L

foreach ($item in $deduped) {
    if ($PSCmdlet.ShouldProcess($item.Path, 'Remove')) {
        try {
            Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
            $deleted++
            $freedBytes += $item.Size
            Write-Verbose "Removed: $($item.Path)"
        } catch {
            $errors++
            Write-Host "  ✗ Failed to remove: $($item.Path)  ($_)" -ForegroundColor Red
        }
    }
}

Write-Host ''
Write-Host "  ✓ Removed $deleted item(s), freed $(Format-Size $freedBytes)" -ForegroundColor Green
if ($errors -gt 0) {
    Write-Host "  ✗ $errors item(s) could not be deleted (see above)" -ForegroundColor Red
}
Write-Host ''
