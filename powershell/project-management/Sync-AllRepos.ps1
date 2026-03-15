#Requires -Version 5.1
<#
.SYNOPSIS
    Bulk git-pull (or fetch/status) across every git repository found under a
    root directory.

.DESCRIPTION
    Recursively finds every folder that contains a `.git` sub-directory up to
    a configurable depth, then runs the chosen operation in parallel using
    PowerShell jobs so the whole run is fast even with dozens of repos.

    Operations
    ----------
    pull    git pull --ff-only (default)
    fetch   git fetch --all --prune
    status  git status --short --branch

    Results are printed in a colour-coded summary table.  A detailed log of
    any repos that had errors or uncommitted changes is shown at the end.

.PARAMETER RootDir
    Folder to scan.  Defaults to the current directory.

.PARAMETER Operation
    pull | fetch | status.  Defaults to 'pull'.

.PARAMETER MaxDepth
    How deep to search for .git folders.  Defaults to 3.

.PARAMETER ThrottleLimit
    Max parallel jobs.  Defaults to 6.

.PARAMETER ExcludePaths
    Array of folder-name substrings to skip (e.g. 'node_modules','vendor').

.EXAMPLE
    .\Sync-AllRepos.ps1
    .\Sync-AllRepos.ps1 -RootDir C:\Dev -Operation status
    .\Sync-AllRepos.ps1 -RootDir C:\Dev -ExcludePaths 'archive','old'
#>
[CmdletBinding()]
param(
    [string]   $RootDir      = (Get-Location).Path,
    [ValidateSet('pull','fetch','status')]
    [string]   $Operation    = 'pull',
    [int]      $MaxDepth     = 3,
    [int]      $ThrottleLimit = 6,
    [string[]] $ExcludePaths = @('node_modules','vendor','.cache','__pycache__')
)

$ErrorActionPreference = 'Continue'

# ── Banner ────────────────────────────────────────────────────────────────────
function banner {
    $width = 60
    Write-Host ('─' * $width) -ForegroundColor DarkCyan
    Write-Host "  Sync-AllRepos  [$Operation]  →  $RootDir" -ForegroundColor Cyan
    Write-Host ('─' * $width) -ForegroundColor DarkCyan
}
banner

# ── Discover repos ────────────────────────────────────────────────────────────
Write-Host "`nScanning for git repos (depth $MaxDepth)..." -ForegroundColor DarkGray

$repoPaths = @()
Get-ChildItem -Path $RootDir -Directory -Recurse -Depth $MaxDepth -ErrorAction SilentlyContinue |
    Where-Object {
        $fullPath = $_.FullName
        # skip excluded path fragments
        $skip = $false
        foreach ($ex in $ExcludePaths) {
            if ($fullPath -like "*$ex*") { $skip = $true; break }
        }
        -not $skip -and (Test-Path (Join-Path $fullPath '.git') -PathType Container)
    } |
    ForEach-Object { $repoPaths += $_.FullName }

if ($repoPaths.Count -eq 0) {
    Write-Host "`nNo git repositories found under $RootDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($repoPaths.Count) repositories.`n" -ForegroundColor Green

# ── Run operations in parallel ────────────────────────────────────────────────
$gitCmd = switch ($Operation) {
    'pull'   { { param($p) git -C $p pull --ff-only 2>&1 } }
    'fetch'  { { param($p) git -C $p fetch --all --prune 2>&1 } }
    'status' { { param($p) git -C $p status --short --branch 2>&1 } }
}

$results = @()
$jobs    = [System.Collections.Generic.List[hashtable]]::new()

foreach ($path in $repoPaths) {
    while ($jobs.Count -ge $ThrottleLimit) {
        Start-Sleep -Milliseconds 200
        $done = @($jobs | Where-Object { $_.job.State -in 'Completed','Failed','Stopped' })
        foreach ($d in $done) {
            $out = Receive-Job $d.job -ErrorAction SilentlyContinue
            $results += [pscustomobject]@{
                Repo   = Split-Path $d.path -Leaf
                Path   = $d.path
                Output = ($out -join "`n").Trim()
                ExitCode = 0
            }
            Remove-Job $d.job
            $jobs.Remove($d) | Out-Null
        }
    }
    $j = Start-Job -ScriptBlock $gitCmd -ArgumentList $path
    $jobs.Add(@{ job = $j; path = $path })
}

# collect remaining jobs
while ($jobs.Count -gt 0) {
    Start-Sleep -Milliseconds 300
    $done = @($jobs | Where-Object { $_.job.State -in 'Completed','Failed','Stopped' })
    foreach ($d in $done) {
        $out = Receive-Job $d.job -ErrorAction SilentlyContinue
        $results += [pscustomobject]@{
            Repo   = Split-Path $d.path -Leaf
            Path   = $d.path
            Output = ($out -join "`n").Trim()
            ExitCode = 0
        }
        Remove-Job $d.job
        $jobs.Remove($d) | Out-Null
    }
}

# ── Print results ─────────────────────────────────────────────────────────────
function Classify ($output) {
    if (-not $output) { return 'ok' }
    if ($output -match 'error:|CONFLICT|fatal:') { return 'error' }
    if ($output -match 'Already up to date') { return 'uptodate' }
    if ($output -match 'Fast-forward|Successfully rebased|Fetching') { return 'updated' }
    if ($output -match '^\?\?|^[MAD] |^ M |^ D ') { return 'dirty' }
    return 'info'
}

$statusColors = @{
    'ok'        = 'Green'
    'uptodate'  = 'DarkGray'
    'updated'   = 'Cyan'
    'dirty'     = 'Yellow'
    'error'     = 'Red'
    'info'      = 'White'
}
$statusIcons = @{
    'ok'        = '✓'
    'uptodate'  = '='
    'updated'   = '↑'
    'dirty'     = '~'
    'error'     = '✗'
    'info'      = 'i'
}

$summary = @{ ok=0; uptodate=0; updated=0; dirty=0; error=0; info=0 }
$detailed = @()

foreach ($r in ($results | Sort-Object Repo)) {
    $class = Classify $r.Output
    $summary[$class]++
    $icon  = $statusIcons[$class]
    $color = $statusColors[$class]
    $repoName = $r.Repo.PadRight(35)
    Write-Host "  $icon  $repoName" -ForegroundColor $color -NoNewline
    # show first line of output inline
    $firstLine = ($r.Output -split "`n" | Select-Object -First 1).Trim()
    if ($firstLine) {
        Write-Host "  $firstLine" -ForegroundColor DarkGray
    } else {
        Write-Host ''
    }
    if ($class -in 'dirty','error','updated') { $detailed += $r }
}

# ── Summary line ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('─' * 60) -ForegroundColor DarkCyan
Write-Host "  Total: $($results.Count)  " -NoNewline
Write-Host "Updated: $($summary.updated)  " -ForegroundColor Cyan -NoNewline
Write-Host "Clean: $($summary.uptodate + $summary.ok)  " -ForegroundColor DarkGray -NoNewline
Write-Host "Dirty: $($summary.dirty)  " -ForegroundColor Yellow -NoNewline
Write-Host "Errors: $($summary.error)  " -ForegroundColor Red
Write-Host ('─' * 60) -ForegroundColor DarkCyan

# ── Detailed output for notable repos ─────────────────────────────────────────
if ($detailed.Count -gt 0) {
    Write-Host "`nDetails:" -ForegroundColor White
    foreach ($r in $detailed) {
        $class = Classify $r.Output
        Write-Host "`n  $($r.Path)" -ForegroundColor ($statusColors[$class])
        $r.Output -split "`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
}

Write-Host ''
