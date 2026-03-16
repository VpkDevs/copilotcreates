# 🖥 Windows 11 PC Organization Scripts

> **God-tier powerful, robustly safe, and beautifully designed PowerShell tools for Windows 11 organization.**

A suite of five self-contained PowerShell scripts with full WPF GUIs styled in the Windows 11 Fluent dark-mode aesthetic.  
Every tool features preview/dry-run modes, real-time progress bars, persistent logging, undo support, and graceful error handling.

---

## 📦 Scripts

| Script | Description |
|--------|-------------|
| [`PC-Organizer-Hub.ps1`](#pc-organizer-hub) | Central launcher dashboard with live system stats |
| [`Desktop-Organizer.ps1`](#desktop-organizer) | Sort Desktop (or any folder) files into type sub-folders |
| [`Downloads-Organizer.ps1`](#downloads-organizer) | Organise Downloads by type/date, detect duplicates, archive old files |
| [`System-Cleanup.ps1`](#system-cleanup-pro) | Scan and safely delete junk files to reclaim disk space |
| [`Startup-Manager.ps1`](#startup-manager) | Enable, disable, or remove Windows startup entries |

All scripts are in the [`scripts/`](scripts/) directory.

---

## 🚀 Quick Start

```powershell
# Run the hub launcher (opens a dashboard to launch any tool)
powershell -ExecutionPolicy Bypass -File "scripts\PC-Organizer-Hub.ps1"

# Or launch individual tools directly:
powershell -ExecutionPolicy Bypass -File "scripts\Desktop-Organizer.ps1"
powershell -ExecutionPolicy Bypass -File "scripts\Downloads-Organizer.ps1"
powershell -ExecutionPolicy Bypass -File "scripts\System-Cleanup.ps1"
powershell -ExecutionPolicy Bypass -File "scripts\Startup-Manager.ps1"
```

> **Requirements:** Windows 10/11 · PowerShell 5.1 or PowerShell 7+  
> No external modules or internet access required.

---

## PC Organizer Hub

**File:** `scripts/PC-Organizer-Hub.ps1`

The central dashboard. Open this to get a live system overview and launch any of the four tools with one click.

**Features:**
- Live disk-usage gauge bars (per drive, colour-coded by fill %)
- RAM and CPU usage at a glance
- OS name, build number, and last boot time
- Recent activity feed pulled from all tool log files
- One-click launch buttons for each tool
- Refresh button to update all stats

---

## Desktop Organizer

**File:** `scripts/Desktop-Organizer.ps1`

Scans any folder (defaults to your Desktop) and moves files into neatly named sub-folders based on their file extension.

**Categories:** Images · Documents · Videos · Music · Archives · Code · Programs · Shortcuts · Other

**Features:**
- 🔎 **Preview / Dry-Run** – see exactly what will be moved before anything happens
- 📊 **File inventory table** – name, category, size, modified date, destination path
- ▶ **Execute** – real-time progress bar with per-file status
- ↩ **Undo** – moves all files back to their original locations and removes empty folders
- Options to skip Shortcuts and/or Hidden files
- Collision handling (auto numeric suffix)
- Persistent log in `%APPDATA%\CopilotOrganizer\Logs\`

---

## Downloads Organizer

**File:** `scripts/Downloads-Organizer.ps1`

Intelligently organises your Downloads folder (or any folder).

**Sort Modes:**
1. **By Type** – `Downloads\Images\photo.jpg`
2. **By Date** – `Downloads\2024\03\photo.jpg`
3. **By Type + Date** – `Downloads\2024\03\Images\photo.jpg`

**Features:**
- 🔁 **Duplicate detection** via MD5 hash – shows all duplicates in a dedicated tab with wasted-space estimate; one-click delete keeping first occurrence
- 📦 **Archive old files** – moves files older than N days to an `Archive\` sub-folder
- 🔎 Preview / Dry-Run mode
- ↩ Undo last run
- Two-tab UI: All Files + Duplicates

---

## System Cleanup Pro

**File:** `scripts/System-Cleanup.ps1`

Scans common junk-file locations and shows you exactly how much space can be recovered before you delete anything.

**Cleanup Targets:**

| Target | Admin Required |
|--------|:--------------:|
| User Temp (`%TEMP%`) | No |
| Windows Temp (`C:\Windows\Temp`) | ✅ |
| Windows Update Download Cache | ✅ |
| Thumbnail Cache | No |
| Windows Error Reports | No |
| Crash Dumps | No |
| Prefetch Files | ✅ |
| Google Chrome Cache | No |
| Microsoft Edge Cache | No |
| Mozilla Firefox Cache | No |
| Brave Browser Cache | No |
| Recycle Bin (all drives) | No |

**Features:**
- 🔐 Self-elevating UAC prompt – falls back gracefully if declined
- Admin / Non-Admin badge clearly shown in the title bar
- Per-target size labels coloured by urgency (green → yellow → red)
- **Scan First** button – no files are touched until you explicitly click **Clean Now**
- Double-confirmation dialog before any deletion
- "Targets requiring admin" are automatically greyed-out when running without elevation

---

## Startup Manager

**File:** `scripts/Startup-Manager.ps1`

Shows every startup entry from all registry hives and startup folders in a unified, sortable table.

**Sources:**
- `HKCU\...\Run` / `RunOnce`
- `HKLM\...\Run` / `Run` (WOW64) / `RunOnce`
- User Startup folder
- Common (all-users) Startup folder

**Features:**
- 🔐 Self-elevating for full HKLM read/write access
- ⏸ **Disable / ▶ Enable** individual entries (writes to `StartupApproved` registry key – same mechanism as Task Manager)
- 🗑 **Remove** an entry with confirmation; auto-backs up removed entries to `%APPDATA%\CopilotOrganizer\startup_backup.json`
- 📂 **Open File Location** – opens Explorer at the executable
- 🔍 **Real-time search/filter** across name, publisher, source, and command
- Publisher resolved from Authenticode certificate or `FileVersionInfo.CompanyName`

---

## 📁 Log Files

All tools write timestamped logs to:

```
%APPDATA%\CopilotOrganizer\Logs\
├── DesktopOrganizer_YYYYMMDD_HHmmss.log
├── DownloadsOrganizer_YYYYMMDD_HHmmss.log
├── SystemCleanup_YYYYMMDD_HHmmss.log
└── StartupManager_YYYYMMDD_HHmmss.log
```

Every tool has an **Open Log** button in the UI.

---

## 🛡 Safety & Security

- **No deletions without explicit confirmation** – all destructive actions require a `Yes/No` dialog.
- **Dry-Run / Preview mode** in all file-moving tools.
- **Undo support** – Desktop Organizer and Downloads Organizer can reverse every move.
- **Backup before remove** – Startup Manager backs up entries before deleting them.
- **Locked / access-denied files** are skipped and reported; the rest of the operation continues.
- **Path traversal protection** – all paths are validated with `Test-Path` before use.
- **No internet access** – everything runs entirely locally.
- **No data collection** – logs stay on your machine in your own AppData folder.

---

## 🎨 Design

All scripts share a consistent Windows 11 Fluent **dark-mode** theme:

- Background: `#1C1C1C` / Surface: `#2D2D2D`  
- Accent: `#0078D4` (Windows blue)  
- Rounded corners on all panels and buttons  
- Font: Segoe UI  
- Colour-coded status indicators (green/yellow/red)  
- Real-time progress bars  
