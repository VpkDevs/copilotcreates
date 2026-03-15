; ============================================================================
;  AppLauncher.ahk  — AHK v2
;  Fuzzy-search quick launcher for apps, files and URLs.
;  Requires: AutoHotkey v2.0+
;
;  HOTKEY
;  ------
;  Win+Space        Open / close launcher
;  Type to filter, ↑/↓ to navigate, Enter to launch, Esc to dismiss
;
;  CONFIGURATION
;  Add your apps/URLs to the Entries array below, or use the tray icon
;  to open the config file (LauncherEntries.json) for editing.
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

DataFile := A_ScriptDir "\LauncherEntries.json"

; ── Default entries ───────────────────────────────────────────────────────────
DefaultEntries := [
    Map("name", "Visual Studio Code",   "path", "code",                     "icon", "🖥"),
    Map("name", "Windows Terminal",     "path", "wt.exe",                   "icon", "⚡"),
    Map("name", "Notepad",              "path", "notepad.exe",              "icon", "📄"),
    Map("name", "File Explorer",        "path", "explorer.exe",             "icon", "📁"),
    Map("name", "Task Manager",         "path", "taskmgr.exe",              "icon", "📊"),
    Map("name", "Calculator",           "path", "calc.exe",                 "icon", "🔢"),
    Map("name", "Chrome",               "path", "chrome.exe",               "icon", "🌐"),
    Map("name", "Firefox",              "path", "firefox.exe",              "icon", "🦊"),
    Map("name", "Paint",                "path", "mspaint.exe",              "icon", "🎨"),
    Map("name", "Snipping Tool",        "path", "snippingtool.exe",         "icon", "✂"),
    Map("name", "GitHub",               "path", "https://github.com",       "icon", "🐙"),
    Map("name", "ChatGPT",              "path", "https://chat.openai.com",  "icon", "🤖"),
    Map("name", "Claude",               "path", "https://claude.ai",        "icon", "🧠"),
    Map("name", "Localhost 3000",       "path", "http://localhost:3000",    "icon", "🚀"),
    Map("name", "Localhost 8080",       "path", "http://localhost:8080",    "icon", "🚀"),
    Map("name", "NPM Docs",             "path", "https://docs.npmjs.com",   "icon", "📦"),
    Map("name", "MDN Web Docs",         "path", "https://developer.mozilla.org", "icon", "📚"),
    Map("name", "Stack Overflow",       "path", "https://stackoverflow.com","icon", "💬")
]

; ── Load / save entries ───────────────────────────────────────────────────────
LoadEntries() {
    if FileExist(DataFile) {
        try {
            raw  := FileRead(DataFile, "UTF-8")
            data := LJ_Load(raw)
            if data is Array && data.Length > 0
                return data
        }
    }
    return DefaultEntries
}

SaveEntries(entries) {
    FileDelete(DataFile)
    FileAppend(LJ_Dump(entries, 2), DataFile, "UTF-8")
}

global Entries := LoadEntries()

; ── Fuzzy match ───────────────────────────────────────────────────────────────
FuzzyMatch(query, target) {
    if query = ""
        return true
    q := StrLower(query)
    t := StrLower(target)
    ; Substring match first
    if InStr(t, q)
        return true
    ; Character-by-character fuzzy
    qi := 1
    loop StrLen(t) {
        if SubStr(q, qi, 1) = SubStr(t, A_Index, 1) {
            qi++
            if qi > StrLen(q)
                return true
        }
    }
    return false
}

FuzzyScore(query, target) {
    if query = ""
        return 0
    q := StrLower(query)
    t := StrLower(target)
    if t = q                          return 100
    if SubStr(t, 1, StrLen(q)) = q   return 90
    if InStr(t, q)                    return 70
    return 50
}

; ── Launcher window ───────────────────────────────────────────────────────────
global LauncherGui := 0

#Space:: ToggleLauncher()

ToggleLauncher() {
    global LauncherGui
    if LauncherGui && WinExist("ahk_id " . LauncherGui.Hwnd) {
        LauncherGui.Destroy()
        LauncherGui := 0
        return
    }
    ShowLauncher()
}

ShowLauncher() {
    global LauncherGui

    g := Gui("-Caption +ToolWindow +AlwaysOnTop", "AppLauncher")
    g.BackColor := "0x0D1117"
    g.SetFont("s11 cC9D1D9", "Segoe UI")
    g.MarginX := 0
    g.MarginY := 0

    ; Search box
    eSearch := g.Add("Edit", "x0 y0 w440 h36 BackgroundColor0D1117 cC9D1D9 -Border", "")
    eSearch.SetFont("s13")

    ; Results list (owner-drawn via static text controls)
    ResultPanel := g.Add("Text", "x0 y40 w440 h0 BackgroundColor0D1117 cC9D1D9 -Border Hidden")

    ; Position at screen centre
    MonitorGetWorkArea(, &ml, &mt, &mr, &mb)
    cx := ml + (mr - ml) // 2
    cy := mt + (mb - mt) // 3
    g.Show("x" . (cx - 220) . " y" . cy . " w440 h36")

    global LauncherGui := g

    ; Filtered entries state
    filteredEntries := Entries.Clone()
    selectedIdx     := 1

    ; ── Render results ────────────────────────────────────────────────────────
    ResultControls := []

    UpdateResults(query) {
        ; Score and filter
        scored := []
        for e in Entries {
            if FuzzyMatch(query, e["name"]) || FuzzyMatch(query, e["path"])
                scored.Push(Map("entry", e, "score", FuzzyScore(query, e["name"])))
        }
        ; Sort by score desc
        Loop scored.Length - 1 {
            i := A_Index
            Loop scored.Length - i {
                j := i + A_Index
                if scored[j]["score"] > scored[i]["score"] {
                    temp := scored[i]
                    scored[i] := scored[j]
                    scored[j] := temp
                }
            }
        }

        filteredEntries := []
        for s in scored
            filteredEntries.Push(s["entry"])

        selectedIdx := 1
        RenderResults()
        return filteredEntries
    }

    RenderResults() {
        ; Destroy old controls
        for ctrl in ResultControls
            ctrl.Visible := false
        ResultControls := []

        count := Min(filteredEntries.Length, 8)
        newH  := 36 + count * 44
        g.Move(,, 440, newH)

        loop count {
            i    := A_Index
            e    := filteredEntries[i]
            y    := 36 + (i-1) * 44
            bg   := (i = selectedIdx) ? "0x1C2128" : "0x0D1117"
            bar  := g.Add("Text", "x0 y" . y . " w440 h44 BackgroundColor" . SubStr(bg,3) . " cC9D1D9")
            icon := g.Add("Text", "x8 y" . (y+10) . " w24 h24 c388BFD", e["icon"])
            name := g.Add("Text", "x36 y" . (y+6) . " w360 h20 cC9D1D9 Bold", e["name"])
            path := g.Add("Text", "x36 y" . (y+24) . " w360 h16 c8B949E", e["path"])
            ResultControls.Push(bar)
            ResultControls.Push(icon)
            ResultControls.Push(name)
            ResultControls.Push(path)

            ; Click to launch
            bar.OnEvent("Click", MakeLaunchFn(i))
            name.OnEvent("Click", MakeLaunchFn(i))
        }
    }

    MakeLaunchFn(idx) {
        return (*) => LaunchEntry(filteredEntries[idx])
    }

    LaunchEntry(e) {
        g.Destroy()
        global LauncherGui := 0
        path := e["path"]
        if RegExMatch(path, "^https?://")
            Run(path)
        else
            try Run(path)
            catch
                Run(A_ComSpec ' /c "' . path . '"',, "Hide")
    }

    ; ── Events ────────────────────────────────────────────────────────────────
    eSearch.OnEvent("Change", (*) => {
        filteredEntries := UpdateResults(eSearch.Value)
    })

    g.OnEvent("KeyDown", (ctrl, wParam, *) => {
        if wParam = 0x1B {   ; Esc
            g.Destroy()
            global LauncherGui := 0
        } else if wParam = 0xD {   ; Enter
            if filteredEntries.Length >= selectedIdx
                LaunchEntry(filteredEntries[selectedIdx])
        } else if wParam = 0x26 {   ; Up
            selectedIdx := Max(1, selectedIdx - 1)
            RenderResults()
        } else if wParam = 0x28 {   ; Down
            selectedIdx := Min(filteredEntries.Length, selectedIdx + 1)
            RenderResults()
        }
    })

    g.OnEvent("Close", (*) => { g.Destroy() ; global LauncherGui := 0 })

    eSearch.Focus()
    filteredEntries := UpdateResults("")
}

; ── Edit entries ──────────────────────────────────────────────────────────────
EditEntries() {
    ; Open the JSON file in the default editor
    if !FileExist(DataFile)
        SaveEntries(Entries)
    Run("notepad.exe `"" . DataFile . "`"")
}

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Show Launcher",  (*) => ShowLauncher())
A_TrayMenu.Add("Edit Entries",   (*) => EditEntries())
A_TrayMenu.Add("Reload Entries", (*) => { global Entries := LoadEntries() ; TrayTip("Entries reloaded","App Launcher",1) })
A_TrayMenu.Add("Exit",           (*) => ExitApp())
A_TrayMenu.Default := "Show Launcher"
TrayTip("App Launcher running`nWin+Space to open", "App Launcher", 1)

; ── Minimal JSON (for arrays of Maps with string values) ─────────────────────
LJ_Dump(arr, indent:=0) {
    pad := indent ? "`n" . StrRepeat("  ", 1) : ""
    parts := []
    for m in arr {
        kv := []
        for k, v in m
            kv.Push('"' . k . '": "' . StrReplace(StrReplace(v,"\","\\"),'"','\"') . '"')
        parts.Push("{" . pad . kv.Join(", ") . (indent ? "`n" : "") . "}")
    }
    return "[" . (indent ? "`n" : "") . parts.Join("," . (indent?"`n":"")) . (indent?"`n":"") . "]"
}

LJ_Load(raw) {
    result := []
    pos := 1
    SkipWS(&p) { while p <= StrLen(raw) && InStr(" `t`r`n", SubStr(raw,p,1)) p++ }
    ReadStr(&p) {
        p++ ; skip "
        s := ""
        while p <= StrLen(raw) {
            ch := SubStr(raw, p, 1)
            if ch = '"'  { p++ ; return s }
            if ch = "\" { p++ ; esc := SubStr(raw,p,1) ; s .= (esc="n"?"`n":esc="t"?"`t":esc) }
            else s .= ch
            p++
        }
        return s
    }
    SkipWS(&pos)
    if SubStr(raw,pos,1) != "[" return result
    pos++
    loop {
        SkipWS(&pos)
        ch := SubStr(raw, pos, 1)
        if pos > StrLen(raw) || ch = "]" { pos++ ; break }
        if ch = "," { pos++ ; continue }
        if ch = "{" {
            pos++ ; m := Map()
            loop {
                SkipWS(&pos)
                ch2 := SubStr(raw,pos,1)
                if pos > StrLen(raw) || ch2 = "}" { pos++ ; break }
                if ch2 = "," { pos++ ; continue }
                if ch2 = '"' {
                    key := ReadStr(&pos)
                    SkipWS(&pos) ; skip ':'
                    if SubStr(raw,pos,1) = ":" pos++
                    SkipWS(&pos)
                    val := ReadStr(&pos)
                    m[key] := val
                } else pos++
            }
            result.Push(m)
        } else pos++
    }
    return result
}

StrRepeat(s, n) { r := "" ; loop n r .= s ; return r }
