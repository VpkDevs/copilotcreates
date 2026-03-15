; ============================================================================
;  ClipboardHistory.ahk  — AHK v2
;  Win+V-style clipboard history pop-up with persistent storage.
;  Requires: AutoHotkey v2.0+
;
;  HOTKEYS
;  -------
;  Win+V         Show clipboard history pop-up
;  Esc           Close pop-up
;  Enter / Click Paste selected item and close
;  Delete        Remove selected item from history
;  Ctrl+Shift+V  Clear all history (with confirm)
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

DataFile  := A_ScriptDir "\ClipboardHistory.json"
MaxItems  := 200
WinTitle  := "ClipboardHistoryPopup"

global History := []
global LastClip := ""

LoadHistory()
SetTimer(WatchClipboard, 500)

; ── Load / save ───────────────────────────────────────────────────────────────
LoadHistory() {
    global History
    if FileExist(DataFile) {
        try {
            raw  := FileRead(DataFile, "UTF-8")
            data := JSON_Load(raw)
            if data is Array
                History := data
        }
    }
}

SaveHistory() {
    global History
    FileDelete(DataFile)
    FileAppend(JSON_Dump(History), DataFile, "UTF-8")
}

; ── Watch clipboard ───────────────────────────────────────────────────────────
WatchClipboard() {
    global History, LastClip
    if !A_Clipboard || A_Clipboard = LastClip
        return
    text := A_Clipboard
    LastClip := text
    ; Remove duplicate
    for i, item in History {
        if item["text"] = text {
            History.RemoveAt(i)
            break
        }
    }
    History.Push(Map("text", text, "ts", A_Now))
    ; Trim to max
    while History.Length > MaxItems
        History.RemoveAt(1)
    SaveHistory()
}

; ── Show popup ────────────────────────────────────────────────────────────────
#v:: ShowPopup()

ShowPopup() {
    if WinExist(WinTitle) {
        WinActivate(WinTitle)
        return
    }

    g := Gui("-Caption +ToolWindow +AlwaysOnTop", WinTitle)
    g.BackColor := "0x0D1117"
    g.SetFont("s9 cC9D1D9", "Segoe UI")

    ; Header
    g.Add("Text", "x8 y8 c388BFD Bold s10", "📋 Clipboard History")
    g.Add("Text", "x8 y28 c8B949E", "↵/click=paste  Del=remove  Esc=close")

    ; Search
    eSearch := g.Add("Edit", "x8 y50 w384 h22 BackgroundColor161B22 cC9D1D9 -Border")
    eSearch.Value := ""

    ; List
    lb := g.Add("ListBox", "x8 y76 w384 h340 BackgroundColor0D1117 cC9D1D9 -Border AltSubmit")
    FillList(lb, "")

    g.Add("Text", "x8 y420 c30363D", lb.Value . " items")
    statusLbl := g.Add("Text", "x8 y420 w384 c30363D", History.Length . " items stored")

    ; Position near cursor
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    g.Show("x" . (mx - 200) . " y" . (my - 460) . " w400 h448 NoActivate")
    g.Show()   ; activate

    ; ── Events ────────────────────────────────────────────────────────────────
    PasteItem(idx) {
        if !idx
            return
        ; reversed display index
        realIdx := History.Length - idx + 1
        if realIdx < 1 || realIdx > History.Length
            return
        item := History[realIdx]
        global LastClip := item["text"]
        A_Clipboard := item["text"]
        g.Destroy()
        Sleep(50)
        Send("^v")
    }

    eSearch.OnEvent("Change", (*) => FillList(lb, eSearch.Value))

    lb.OnEvent("DoubleClick", (*) => PasteItem(lb.Value))

    g.OnEvent("KeyDown", (ctrl, wParam, *) => {
        if wParam = 0x1B   ; Esc
            g.Destroy()
        else if wParam = 0xD   ; Enter
            PasteItem(lb.Value)
        else if wParam = 0x2E {  ; Delete
            sel := lb.Value
            if !sel
                return
            realIdx := History.Length - sel + 1
            History.RemoveAt(realIdx)
            SaveHistory()
            FillList(lb, eSearch.Value)
            statusLbl.Value := History.Length . " items stored"
        }
    })

    g.OnEvent("Close", (*) => g.Destroy())
}

FillList(lb, filter) {
    global History
    lb.Delete()
    ; Show newest first
    i := History.Length
    while i >= 1 {
        text := History[i]["text"]
        if filter = "" || InStr(text, filter) {
            preview := StrReplace(text, "`n", " ↵ ")
            preview := StrReplace(preview, "`t", " → ")
            if StrLen(preview) > 70
                preview := SubStr(preview, 1, 67) . "..."
            lb.Add([preview])
        }
        i--
    }
}

; ── Clear all ─────────────────────────────────────────────────────────────────
^+v:: {
    result := MsgBox("Clear all clipboard history?", "Confirm", "YesNo Icon?")
    if result = "Yes" {
        global History := []
        SaveHistory()
        TrayTip("Clipboard history cleared", "Clipboard Manager", 1)
    }
}

; ── Minimal JSON ──────────────────────────────────────────────────────────────
JSON_Dump(arr) {
    parts := []
    for item in arr {
        t := StrReplace(StrReplace(item["text"], "\", "\\"), '"', '\"')
        t := StrReplace(t, "`n", "\n")
        t := StrReplace(t, "`r", "\r")
        t := StrReplace(t, "`t", "\t")
        parts.Push('{"text":"' . t . '","ts":"' . item["ts"] . '"}')
    }
    return "[" . parts.Join(",") . "]"
}

JSON_Load(raw) {
    result := []
    pos := 1
    SkipWS(&p) {
        while p <= StrLen(raw) && InStr(" `t`r`n", SubStr(raw, p, 1))
            p++
    }
    ReadStr(&p) {
        p++   ; skip "
        s := ""
        while p <= StrLen(raw) {
            ch := SubStr(raw, p, 1)
            if ch = '"'  { p++ ; return s }
            if ch = "\" {
                p++
                esc := SubStr(raw, p, 1)
                s .= (esc = "n" ? "`n" : esc = "r" ? "`r" : esc = "t" ? "`t" : esc = "\" ? "\" : esc)
            } else
                s .= ch
            p++
        }
        return s
    }
    SkipWS(&pos)
    if SubStr(raw, pos, 1) != "[" return result
    pos++
    loop {
        SkipWS(&pos)
        if pos > StrLen(raw) || SubStr(raw, pos, 1) = "]" { pos++ ; break }
        if SubStr(raw, pos, 1) = "," { pos++ ; continue }
        if SubStr(raw, pos, 1) = "{" {
            pos++
            m := Map()
            loop {
                SkipWS(&pos)
                if pos > StrLen(raw) || SubStr(raw, pos, 1) = "}" { pos++ ; break }
                if SubStr(raw, pos, 1) = "," { pos++ ; continue }
                if SubStr(raw, pos, 1) = '"' {
                    key := ReadStr(&pos)
                    SkipWS(&pos)
                    if SubStr(raw, pos, 1) = ":" pos++
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

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Show History",  (*) => ShowPopup())
A_TrayMenu.Add("Clear History", (*) => {
    if MsgBox("Clear all?","Confirm","YesNo") = "Yes" {
        global History := []
        SaveHistory()
    }
})
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show History"
TrayTip("Clipboard History running`nWin+V to open", "Clipboard Manager", 1)
