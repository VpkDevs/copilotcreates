#Requires -Version 5.1
<#
.SYNOPSIS
    Live terminal system-monitoring dashboard with colour-coded gauges.

.DESCRIPTION
    Renders a refreshing TUI (Terminal UI) in the console showing:
      - CPU usage per core + total (sparkline bar)
      - RAM usage (used / total / %)
      - Top processes by CPU and by memory
      - Disk usage for all drives
      - Network bytes in/out (delta per second)
      - System uptime

    Press Q to quit, P to pause/resume.

.PARAMETER RefreshSeconds
    How often to refresh the display (default 2).

.PARAMETER TopProcessCount
    Number of top processes to show (default 8).

.EXAMPLE
    .\Get-SystemDashboard.ps1
    .\Get-SystemDashboard.ps1 -RefreshSeconds 1 -TopProcessCount 10
#>
[CmdletBinding()]
param(
    [int] $RefreshSeconds  = 2,
    [int] $TopProcessCount = 8
)

$ErrorActionPreference = 'Continue'

# ── Terminal colours (ANSI) ───────────────────────────────────────────────────
function ansi ([int]$c) { "`e[$c`m" }
$RST  = ansi 0;   $BOLD = ansi 1
$RED  = ansi 31;  $GRN  = ansi 32;  $YEL  = ansi 33
$BLU  = ansi 34;  $MAG  = ansi 35;  $CYN  = ansi 36;  $WHT = ansi 37
$DGRY = ansi 90;  $BGBL = ansi 44

function pct-color ([double]$p) {
    if ($p -ge 90) { return $RED }
    if ($p -ge 70) { return $YEL }
    return $GRN
}

function bar ([double]$pct, [int]$width = 20, [string]$fillChar = '█', [string]$emptyChar = '░') {
    $filled = [int]($pct / 100 * $width)
    $empty  = $width - $filled
    $color  = pct-color $pct
    $bar    = $fillChar * $filled + $emptyChar * $empty
    return "$color$bar$RST"
}

function fmt-bytes ([long]$b) {
    if ($b -ge 1GB) { return "{0:N1} GB" -f ($b / 1GB) }
    if ($b -ge 1MB) { return "{0:N1} MB" -f ($b / 1MB) }
    if ($b -ge 1KB) { return "{0:N1} KB" -f ($b / 1KB) }
    return "$b B"
}

function fmt-pct ([double]$p) { "$($p.ToString('F1').PadLeft(5))%" }

function divider ([string]$title, [int]$width = 74) {
    $dash = '─' * [Math]::Max(0, $width - $title.Length - 3)
    return "$CYN── $BOLD$title$RST$CYN $dash$RST"
}

# ── Previous network counters for delta ───────────────────────────────────────
$script:prevNetRx = @{}
$script:prevNetTx = @{}

# ── CPU counters ──────────────────────────────────────────────────────────────
$cpuCounters = @()
try {
    $cpuCounters = Get-Counter '\Processor(*)\% Processor Time' -ErrorAction Stop
} catch {}

# ── Main loop ─────────────────────────────────────────────────────────────────
$paused = $false
$con    = $Host.UI.RawUI

# Hide cursor
$oldCursor = $con.CursorSize
try { $con.CursorSize = 1 } catch {}

[Console]::Clear()
[Console]::CursorVisible = $false

while ($true) {
    # ── Non-blocking keypress ─────────────────────────────────────────────────
    if ($con.KeyAvailable) {
        $key = $con.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.Character -match '[Qq]') { break }
        if ($key.Character -match '[Pp]') { $paused = -not $paused }
    }

    if ($paused) {
        Start-Sleep -Milliseconds 200
        continue
    }

    # ── Collect data ──────────────────────────────────────────────────────────
    # CPU
    $cpuTotal = 0.0
    $cpuPerCore = @()
    try {
        $sample = (Get-Counter '\Processor(*)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples
        $cpuTotal = ($sample | Where-Object { $_.InstanceName -eq '_total' }).CookedValue
        $cpuPerCore = @($sample | Where-Object { $_.InstanceName -ne '_total' } | Sort-Object InstanceName | ForEach-Object { $_.CookedValue })
    } catch {}

    # RAM
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramTotal = $os.TotalVisibleMemorySize * 1KB
    $ramFree  = $os.FreePhysicalMemory * 1KB
    $ramUsed  = $ramTotal - $ramFree
    $ramPct   = if ($ramTotal -gt 0) { $ramUsed / $ramTotal * 100 } else { 0 }

    # Disks
    $disks = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Used -gt 0 }

    # Network
    $netAdapters = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue
    $netLines = @()
    foreach ($a in $netAdapters) {
        $name = $a.Name -replace '[^a-zA-Z0-9 \-]','' | ForEach-Object { if ($_.Length -gt 25) { $_.Substring(0,22) + '...' } else { $_ } }
        $rx = fmt-bytes $a.BytesReceivedPerSec
        $tx = fmt-bytes $a.BytesSentPerSec
        $netLines += "  $DGRY$($name.PadRight(30))$RST  ↓ $GRN$($rx.PadLeft(10))$RST  ↑ $YEL$($tx.PadLeft(10))$RST"
    }

    # Top processes by CPU
    $topCpu = Get-Process -ErrorAction SilentlyContinue |
              Sort-Object CPU -Descending |
              Select-Object -First $TopProcessCount

    # Top processes by RAM
    $topRam = Get-Process -ErrorAction SilentlyContinue |
              Sort-Object WorkingSet64 -Descending |
              Select-Object -First $TopProcessCount

    # Uptime
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeStr = '{0}d {1:D2}h {2:D2}m' -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes

    # ── Render ────────────────────────────────────────────────────────────────
    $lines = [System.Collections.Generic.List[string]]::new()
    $ts    = Get-Date -Format 'HH:mm:ss'

    $lines.Add("$BOLD${CYN}  ⚡ System Dashboard$RST$DGRY  $ts  ·  uptime $uptimeStr  ·  Q=quit P=pause$RST")
    $lines.Add('')

    # CPU
    $lines.Add($(divider 'CPU'))
    $cpuStr = fmt-pct $cpuTotal
    $lines.Add("  Total  $(bar $cpuTotal 30)  $($cpuStr.PadLeft(6))")
    # Per-core (max 2 rows of 4)
    $coreRows = [Math]::Ceiling($cpuPerCore.Count / 4)
    for ($row = 0; $row -lt [Math]::Min($coreRows,2); $row++) {
        $rowStr = '  '
        for ($c = 0; $c -lt 4; $c++) {
            $idx = $row * 4 + $c
            if ($idx -ge $cpuPerCore.Count) { break }
            $pct = $cpuPerCore[$idx]
            $col = pct-color $pct
            $rowStr += "C$($idx.ToString().PadLeft(2))[$col$(('▓' * [int]($pct/10)).PadRight(10,'░'))$RST] "
        }
        $lines.Add($rowStr)
    }
    $lines.Add('')

    # RAM
    $lines.Add($(divider 'Memory'))
    $lines.Add("  $(bar $ramPct 30)  $(fmt-pct $ramPct)  $(fmt-bytes $ramUsed) / $(fmt-bytes $ramTotal)")
    $lines.Add('')

    # Disks
    $lines.Add($(divider 'Disk'))
    foreach ($d in $disks) {
        $total = $d.Used + $d.Free
        $pct   = if ($total -gt 0) { $d.Used / $total * 100 } else { 0 }
        $name  = "$($d.Name):"
        $lines.Add("  $($name.PadRight(4))  $(bar $pct 24)  $(fmt-pct $pct)  $(fmt-bytes $d.Used) / $(fmt-bytes $total)")
    }
    $lines.Add('')

    # Network
    if ($netAdapters -and $netAdapters.Count -gt 0) {
        $lines.Add($(divider 'Network'))
        $netLines | Select-Object -First 4 | ForEach-Object { $lines.Add($_) }
        $lines.Add('')
    }

    # Top Processes
    $lines.Add($(divider 'Top Processes by CPU'))
    $lines.Add("  $($DGRY)$('Name'.PadRight(28))$('CPU(s)'.PadLeft(8))$('Threads'.PadLeft(8))$('PID'.PadLeft(8))$RST")
    foreach ($p in $topCpu) {
        $cpu  = if ($p.CPU) { $p.CPU.ToString('F1') } else { '0.0' }
        $lines.Add("  $($(($p.ProcessName).PadRight(28)))$($cpu.PadLeft(8))$($p.Threads.Count.ToString().PadLeft(8))$($p.Id.ToString().PadLeft(8))")
    }
    $lines.Add('')

    $lines.Add($(divider 'Top Processes by RAM'))
    $lines.Add("  $DGRY$('Name'.PadRight(28))$('RAM'.PadLeft(10))$('PID'.PadLeft(8))$RST")
    foreach ($p in $topRam) {
        $lines.Add("  $(($p.ProcessName).PadRight(28))$($(fmt-bytes $p.WorkingSet64).PadLeft(10))$($p.Id.ToString().PadLeft(8))")
    }

    # ── Write to console atomically ───────────────────────────────────────────
    [Console]::SetCursorPosition(0, 0)
    $output = $lines -join "`n"
    [Console]::Write($output)

    Start-Sleep -Seconds $RefreshSeconds
}

# ── Cleanup ───────────────────────────────────────────────────────────────────
[Console]::CursorVisible = $true
try { $con.CursorSize = $oldCursor } catch {}
[Console]::Clear()
Write-Host 'Dashboard closed.' -ForegroundColor Cyan
