; ============================================================================
;  WindowManager.ahk  — AHK v2
;  Save and restore named window layouts, plus snap windows to grid positions.
;  Requires: AutoHotkey v2.0+
;
;  HOTKEYS
;  -------
;  Win+Alt+S          Save current layout (prompts for name)
;  Win+Alt+R          Restore a saved layout (pick from list)
;  Win+Alt+L          Open layout manager GUI
;
;  SNAP (Win + Numpad)
;  Win+Numpad7  →  top-left quarter
;  Win+Numpad8  →  top half
;  Win+Numpad9  →  top-right quarter
;  Win+Numpad4  →  left half
;  Win+Numpad5  →  centre (70%)
;  Win+Numpad6  →  right half
;  Win+Numpad1  →  bottom-left quarter
;  Win+Numpad2  →  bottom half
;  Win+Numpad3  →  bottom-right quarter
;  Win+Numpad0  →  maximise
;  Win+NumpadDot→  restore / normal
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── Data file ─────────────────────────────────────────────────────────────────
DataFile := A_ScriptDir "\WindowLayouts.ini"

; ── Snap helpers ──────────────────────────────────────────────────────────────
SnapWindow(x, y, w, h) {
    hwnd := WinGetID("A")
    if !hwnd
        return
    WinRestore(hwnd)
    WinMove(x, y, w, h, hwnd)
}

MonitorInfo() {
    MonitorGetWorkArea(, &ml, &mt, &mr, &mb)
    return Map("l", ml, "t", mt, "w", mr - ml, "h", mb - mt)
}

; ── Snap hotkeys ──────────────────────────────────────────────────────────────
#Numpad7:: { m := MonitorInfo() ; SnapWindow(m["l"],           m["t"],           m["w"]//2, m["h"]//2) }
#Numpad8:: { m := MonitorInfo() ; SnapWindow(m["l"],           m["t"],           m["w"],    m["h"]//2) }
#Numpad9:: { m := MonitorInfo() ; SnapWindow(m["l"]+m["w"]//2, m["t"],           m["w"]//2, m["h"]//2) }
#Numpad4:: { m := MonitorInfo() ; SnapWindow(m["l"],           m["t"],           m["w"]//2, m["h"])    }
#Numpad5:: { m := MonitorInfo() ; SnapWindow(m["l"]+m["w"]*15//100, m["t"]+m["h"]*10//100, m["w"]*70//100, m["h"]*80//100) }
#Numpad6:: { m := MonitorInfo() ; SnapWindow(m["l"]+m["w"]//2, m["t"],           m["w"]//2, m["h"])    }
#Numpad1:: { m := MonitorInfo() ; SnapWindow(m["l"],           m["t"]+m["h"]//2, m["w"]//2, m["h"]//2) }
#Numpad2:: { m := MonitorInfo() ; SnapWindow(m["l"],           m["t"]+m["h"]//2, m["w"],    m["h"]//2) }
#Numpad3:: { m := MonitorInfo() ; SnapWindow(m["l"]+m["w"]//2, m["t"]+m["h"]//2, m["w"]//2, m["h"]//2) }
#Numpad0:: { WinMaximize("A") }
#NumpadDot:: { WinRestore("A") }

; ── Layout capture ────────────────────────────────────────────────────────────
CaptureLayout() {
    entries := []
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle(hwnd)
            if !title || title = "Program Manager"
                continue
            cls   := WinGetClass(hwnd)
            pid   := WinGetPID(hwnd)
            proc  := ProcessGetName(pid)
            WinGetPos(&x, &y, &w, &h, hwnd)
            state := WinGetMinMax(hwnd)   ; -1=min, 0=normal, 1=max
            entries.Push(Map(
                "title", title, "class", cls, "proc", proc,
                "x", x, "y", y, "w", w, "h", h, "state", state
            ))
        }
    }
    return entries
}

; ── Save layout ───────────────────────────────────────────────────────────────
SaveLayout(name) {
    entries := CaptureLayout()
    ; Delete old section
    IniDelete(DataFile, name)
    IniWrite(entries.Length, DataFile, name, "count")
    IniWrite(A_Now, DataFile, name, "savedAt")
    for i, e in entries {
        prefix := "w" . i . "_"
        IniWrite(e["title"], DataFile, name, prefix . "title")
        IniWrite(e["proc"],  DataFile, name, prefix . "proc")
        IniWrite(e["x"],     DataFile, name, prefix . "x")
        IniWrite(e["y"],     DataFile, name, prefix . "y")
        IniWrite(e["w"],     DataFile, name, prefix . "w")
        IniWrite(e["h"],     DataFile, name, prefix . "h")
        IniWrite(e["state"], DataFile, name, prefix . "state")
    }
}

; ── Restore layout ────────────────────────────────────────────────────────────
RestoreLayout(name) {
    count := IniRead(DataFile, name, "count", 0)
    matched := 0
    loop count {
        i := A_Index
        prefix := "w" . i . "_"
        savedTitle := IniRead(DataFile, name, prefix . "title", "")
        savedProc  := IniRead(DataFile, name, prefix . "proc",  "")
        x     := IniRead(DataFile, name, prefix . "x", 0)
        y     := IniRead(DataFile, name, prefix . "y", 0)
        w     := IniRead(DataFile, name, prefix . "w", 800)
        h     := IniRead(DataFile, name, prefix . "h", 600)
        state := IniRead(DataFile, name, prefix . "state", 0)

        for hwnd in WinGetList() {
            try {
                if WinGetTitle(hwnd) = savedTitle {
                    WinRestore(hwnd)
                    WinMove(x, y, w, h, hwnd)
                    if state = 1
                        WinMaximize(hwnd)
                    else if state = -1
                        WinMinimize(hwnd)
                    matched++
                    break
                }
            }
        }
    }
    return matched
}

; ── Get all saved layout names ────────────────────────────────────────────────
GetLayoutNames() {
    names := []
    if !FileExist(DataFile)
        return names
    content := FileRead(DataFile)
    for line in StrSplit(content, "`n") {
        line := Trim(line)
        if RegExMatch(line, "^\[(.+)\]$", &m)
            names.Push(m[1])
    }
    return names
}

; ── Hotkeys ───────────────────────────────────────────────────────────────────
#!s:: {                                          ; Win+Alt+S  Save
    name := InputBox("Layout name:", "Save Layout", "w300 h120", "Layout " . FormatTime(, "HH:mm"))
    if name.Result = "Cancel" || name.Value = ""
        return
    SaveLayout(name.Value)
    TrayTip("Saved layout: " . name.Value, "Window Manager", 1)
}

#!r:: {                                          ; Win+Alt+R  Restore
    names := GetLayoutNames()
    if !names.Length {
        MsgBox("No layouts saved yet.  Use Win+Alt+S to save one.", "Window Manager")
        return
    }
    list := ""
    for i, n in names
        list .= i . ". " . n . "`n"
    choice := InputBox("Enter number to restore:`n`n" . list, "Restore Layout", "w300 h200")
    if choice.Result = "Cancel"
        return
    idx := Integer(choice.Value)
    if idx >= 1 && idx <= names.Length {
        n := RestoreLayout(names[idx])
        TrayTip("Restored " . n . " window(s)", "Window Manager", 1)
    }
}

#!l:: ShowManagerGui()                          ; Win+Alt+L  GUI

; ── GUI ───────────────────────────────────────────────────────────────────────
ShowManagerGui() {
    g := Gui("+Resize", "🪟 Window Layout Manager")
    g.BackColor := "0x12121a"
    g.SetFont("s10 cE2E8F0", "Segoe UI")

    g.Add("Text", "x10 y10 cF59E0B", "🪟 Window Layout Manager")
    g.Add("Text", "x10 y36 c64748B", "Saved Layouts")

    lb := g.Add("ListBox", "x10 y58 w260 h200 BackgroundColor0x1C1C26 cE2E8F0")
    names := GetLayoutNames()
    for n in names
        lb.Add([n])

    btnRestore := g.Add("Button", "x10 y270 w120 h30 BackgroundColor22C55E cWhite", "⚡ Restore")
    btnSave    := g.Add("Button", "x140 y270 w120 h30 BackgroundColor6366F1 cWhite", "💾 Save Current")
    btnDelete  := g.Add("Button", "x10 y310 w120 h30 BackgroundColor0x1C1C26 cE2E8F0", "🗑 Delete")

    btnRestore.OnEvent("Click", (*) => {
        sel := lb.Value
        if !sel
            return
        n := RestoreLayout(lb.Text)
        TrayTip("Restored " . n . " windows", "Window Manager", 1)
    })

    btnSave.OnEvent("Click", (*) => {
        name := InputBox("Layout name:", "Save Layout", "w300 h120", "Layout " . FormatTime(, "HH:mm"))
        if name.Result = "Cancel" || name.Value = ""
            return
        SaveLayout(name.Value)
        lb.Delete()
        for n in GetLayoutNames()
            lb.Add([n])
        TrayTip("Saved: " . name.Value, "Window Manager", 1)
    })

    btnDelete.OnEvent("Click", (*) => {
        sel := lb.Text
        if !sel
            return
        IniDelete(DataFile, sel)
        lb.Delete(lb.Value)
    })

    g.Show("w280 h360")
}

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Open Manager", (*) => ShowManagerGui())
A_TrayMenu.Add("Save Current Layout", (*) => {
    name := InputBox("Layout name:", "Save Layout", "w300 h120", "Layout " . FormatTime(, "HH:mm"))
    if name.Result != "Cancel" && name.Value != ""
        SaveLayout(name.Value)
})
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Open Manager"
TrayTip("Window Manager running`nWin+Alt+L for GUI", "Window Manager", 1)
