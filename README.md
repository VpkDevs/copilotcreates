# ⚡ copilotcreates — Script Collection

A **massive collection of PowerShell, AHK 2, and Tampermonkey/Violentmonkey scripts** for general Windows use, project organisation, and AI-assisted software development.

---

## 📂 Repository Structure

```
powershell/
  project-management/     Scripts for managing many software projects
  dev-tools/              Developer productivity utilities
  system-utils/           Windows system & UI tools

ahk/                      AutoHotkey v2 scripts (run with AHK v2.0+)

tampermonkey/             Browser userscripts (.user.js)
                          Install via Tampermonkey, Violentmonkey, or Greasemonkey
```

---

## 🖥 PowerShell Scripts

### project-management/

| Script | Description |
|--------|-------------|
| [`Invoke-ProjectManager.ps1`](powershell/project-management/Invoke-ProjectManager.ps1) | **Full dark-themed GUI app** — scan, launch, tag, note and archive hundreds of local software projects. Persists to JSON. Lives in the system tray. |
| [`New-ProjectScaffold.ps1`](powershell/project-management/New-ProjectScaffold.ps1) | **Interactive wizard** — scaffold a new project for node-ts, node-js, python, react, nextjs, dotnet, rust, go, bash, or generic templates in seconds. |
| [`Sync-AllRepos.ps1`](powershell/project-management/Sync-AllRepos.ps1) | **Bulk git sync** — parallel `pull`, `fetch`, or `status` across every git repo found under a root directory. Colour-coded summary table. |

### dev-tools/

| Script | Description |
|--------|-------------|
| [`Clear-BuildArtifacts.ps1`](powershell/dev-tools/Clear-BuildArtifacts.ps1) | Recursively remove `node_modules`, `dist`, `__pycache__`, `target`, `.cache`, etc. Shows size summary and asks for confirmation before deleting. |
| [`Export-VSCodeProfile.ps1`](powershell/dev-tools/Export-VSCodeProfile.ps1) | **Export** all VS Code extensions + settings/keybindings/snippets to a backup folder; **import** them on a new machine with one command. |
| [`Get-ProjectContext.ps1`](powershell/dev-tools/Get-ProjectContext.ps1) | Generate a **rich Markdown context dump** (tree + key files + source) of any project, ready to paste into ChatGPT / Claude. Copy to clipboard with `-Clipboard`. |
| [`Invoke-PromptLibrary.ps1`](powershell/dev-tools/Invoke-PromptLibrary.ps1) | **GUI prompt library** — store, categorise, search, copy and pin reusable AI prompts. Import/export JSON. Lives in the system tray. |

### system-utils/

| Script | Description |
|--------|-------------|
| [`Invoke-ClipboardManager.ps1`](powershell/system-utils/Invoke-ClipboardManager.ps1) | **Persistent clipboard history** — polls the clipboard, stores up to 200 entries, searchable GUI. **Win+Shift+V** global hotkey. Pin important items. |
| [`Invoke-BulkRename.ps1`](powershell/system-utils/Invoke-BulkRename.ps1) | **Bulk-rename wizard** — find/replace, regex, case transform, prefix/suffix, sequence numbering, extension change — all with a **live colour-coded preview**. |
| [`Save-WindowLayout.ps1`](powershell/system-utils/Save-WindowLayout.ps1) | **Save and restore** named window-position layouts (like virtual desktops but per-project). GUI + CLI modes. |
| [`Get-SystemDashboard.ps1`](powershell/system-utils/Get-SystemDashboard.ps1) | **Live TUI dashboard** — CPU per-core sparklines, RAM gauge, disk usage, network delta, top processes by CPU and RAM. Press Q to quit. |

---

## ⌨ AHK 2 Scripts

> Requires [AutoHotkey v2.0](https://www.autohotkey.com/download/ahk-v2.exe)

| Script | Hotkeys | Description |
|--------|---------|-------------|
| [`WindowManager.ahk`](ahk/WindowManager.ahk) | `Win+Numpad0–9`, `Win+Alt+S/R/L` | **Snap windows** to a 9-zone grid + save/restore named full-desktop layouts. |
| [`TextExpander.ahk`](ahk/TextExpander.ahk) | `Win+Alt+E` (editor), `;trigger` to expand | **Type a keyword to expand** a full snippet anywhere. Supports `{|}` cursor placement, `{date}`, `{time}`, `{clipboard}`. GUI editor. |
| [`ClipboardHistory.ahk`](ahk/ClipboardHistory.ahk) | `Win+V`, `Del`, `Ctrl+Shift+V` | **Win+V clipboard history** popup — fuzzy filter, click/Enter to paste, pin items, persistent JSON storage. |
| [`AppLauncher.ahk`](ahk/AppLauncher.ahk) | `Win+Space` | **Fuzzy-search launcher** — type to filter apps and URLs, arrow keys to navigate, Enter to launch. Configure entries in JSON. |
| [`FocusMode.ahk`](ahk/FocusMode.ahk) | `Win+Alt+F`, `Win+Alt+`` ` | **Hide all windows** except the active one. Toggle to restore. OSD shows how many windows were hidden. |
| [`VolumeControl.ahk`](ahk/VolumeControl.ahk) | `Alt+Scroll`, `Win+Alt+Up/Down`, `Win+Alt+M` | **Scroll-wheel volume** with a beautiful floating OSD bar. Works on desktop/taskbar without any modifier. |

---

## 🌐 Tampermonkey Scripts

> Install via [Tampermonkey](https://www.tampermonkey.net/), [Violentmonkey](https://violentmonkey.github.io/), or [Greasemonkey](https://www.greasespot.net/).
> Click the `.user.js` file link → "Raw" → your browser extension will prompt to install.

| Script | Sites | Description |
|--------|-------|-------------|
| [`github-enhanced.user.js`](tampermonkey/github-enhanced.user.js) | github.com | Copy-path buttons on file rows, line/word counts on blobs, README table of contents, PR diff stat bars, keyboard shortcut `g+f` to find files. |
| [`ai-chat-exporter.user.js`](tampermonkey/ai-chat-exporter.user.js) | ChatGPT, Claude | One-click **export conversations** as Markdown, HTML, or JSON. Floating button appears on every chat page. |
| [`cookie-banner-killer.user.js`](tampermonkey/cookie-banner-killer.user.js) | All sites | **Aggressively dismiss** cookie/GDPR consent banners. Tries to click "Reject All" first, then hides/removes the container. Unfreezes body scroll. |
| [`youtube-enhancer.user.js`](tampermonkey/youtube-enhancer.user.js) | youtube.com | Auto-set video quality, remember playback speed across videos, auto-skip ads (fast-forward method), hide Shorts, theatre mode. Settings panel. |
| [`stackoverflow-enhancer.user.js`](tampermonkey/stackoverflow-enhancer.user.js) | Stack Overflow + SE | Copy buttons on every code block, jump-to-accepted-answer button, age warning on old questions, `Alt+A` hotkey, vote-count bars. |
| [`google-clean.user.js`](tampermonkey/google-clean.user.js) | google.com/search | Remove sponsored results, strip tracking from URLs, add alternative engine links (DDG, Brave, Perplexity, Phind…), highlight trusted domains. |
| [`npm-package-info.user.js`](tampermonkey/npm-package-info.user.js) | npm, PyPI, GitHub, SO | **Hover any package name** to get an instant info card: version, description, license, age, links — fetched live from the registry. |

---

## 🚀 Quick Start

### PowerShell
```powershell
# Run any script directly (requires PowerShell 5.1+)
.\powershell\project-management\Invoke-ProjectManager.ps1

# Or pass parameters
.\powershell\dev-tools\Get-ProjectContext.ps1 -Clipboard
.\powershell\project-management\Sync-AllRepos.ps1 -RootDir C:\Dev -Operation status
```

### AHK 2
```
# Double-click any .ahk file to run it (requires AHK v2 installed)
# Or right-click → "Run with AutoHotkey v2"
# Add to startup: place a shortcut in %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```

### Tampermonkey
```
1. Install Tampermonkey (or Violentmonkey) extension in your browser
2. Navigate to the raw .user.js file on GitHub
3. Click "Install" when prompted by the extension
```

---

## 📋 Tips for Vibe Coders

- **Start your day** with `Sync-AllRepos.ps1` to pull all your repos at once.
- **Before jumping into AI chat**, run `Get-ProjectContext.ps1 -Clipboard` to paste a full project dump.
- **Keep `Invoke-ProjectManager.ps1`** in your startup to have every project one click away.
- **Use `TextExpander.ahk`** with `;log`, `;try`, `;async` etc. for instant boilerplate in any editor.
- **`AppLauncher.ahk`** (Win+Space) replaces the need to hunt for app icons — type 3 chars and press Enter.
- **`Invoke-ClipboardManager.ps1`** means you'll never lose a snippet you copied an hour ago.
- **`Invoke-PromptLibrary.ps1`** is your personal prompt engineering workspace — save the prompts that work.

---

## 🤝 Contributing

Pull requests welcome! If you have a script idea or improvement, open an issue or PR.

## 📄 License

MIT