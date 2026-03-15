; ============================================================================
;  TextExpander.ahk  — AHK v2
;  Keyword-triggered text snippet expander with a GUI editor.
;  Requires: AutoHotkey v2.0+
;
;  HOW IT WORKS
;  ------------
;  Type any registered trigger word (e.g. ";email") anywhere.
;  The trigger is automatically deleted and replaced with the snippet text.
;  Supports multi-line snippets, cursor positioning via {|}
;  and dynamic fields: {date}, {time}, {clipboard}, {filename}
;
;  HOTKEY
;  ------
;  Win+Alt+E   Open the snippet editor / manager GUI
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

DataFile := A_ScriptDir "\TextSnippets.json"

; ── Default snippets ──────────────────────────────────────────────────────────
DefaultSnippets := [
    Map("trigger", ";email",   "title", "Email signature",
        "body", "Best regards,`n{|}"),
    Map("trigger", ";date",    "title", "Today's date",
        "body", "{date}"),
    Map("trigger", ";now",     "title", "Date + time",
        "body", "{date} {time}"),
    Map("trigger", ";shrug",   "title", "Shrug emoji",
        "body", "¯\_(ツ)_/¯"),
    Map("trigger", ";lorem",   "title", "Lorem ipsum",
        "body", "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."),
    Map("trigger", ";todo",    "title", "TODO comment",
        "body", "// TODO: {|}"),
    Map("trigger", ";fixme",   "title", "FIXME comment",
        "body", "// FIXME: {|}"),
    Map("trigger", ";log",     "title", "Console log",
        "body", "console.log('{|}')"),
    Map("trigger", ";tern",    "title", "Ternary template",
        "body", "{|} ? '' : ''"),
    Map("trigger", ";arrow",   "title", "Arrow function",
        "body", "({|}) => {`n  `n}"),
    Map("trigger", ";async",   "title", "Async arrow",
        "body", "async ({|}) => {`n  `n}"),
    Map("trigger", ";try",     "title", "Try/catch block",
        "body", "try {`n  {|}`n} catch (error) {`n  console.error(error)`n}"),
    Map("trigger", ";clog",    "title", "Clipboard content",
        "body", "{clipboard}"),
    Map("trigger", ";myip",    "title", "Fetch my public IP",
        "body", "{myip}")
]

; ── Load / save ───────────────────────────────────────────────────────────────
LoadSnippets() {
    if FileExist(DataFile) {
        try {
            raw  := FileRead(DataFile)
            data := Jxon_Load(&raw)
            if IsObject(data)
                return data
        }
    }
    return DefaultSnippets
}

SaveSnippets(snippets) {
    FileDelete(DataFile)
    FileAppend(Jxon_Dump(snippets, 2), DataFile)
}

global Snippets := LoadSnippets()

; ── Dynamic substitutions ─────────────────────────────────────────────────────
ExpandDynamic(body) {
    body := StrReplace(body, "{date}", FormatTime(, "yyyy-MM-dd"))
    body := StrReplace(body, "{time}", FormatTime(, "HH:mm:ss"))
    body := StrReplace(body, "{clipboard}", A_Clipboard)
    if InStr(body, "{myip}") {
        try {
            whr := ComObject("WinHttp.WinHttpRequest.5.1")
            whr.Open("GET", "https://api.ipify.org", false)
            whr.Send()
            body := StrReplace(body, "{myip}", whr.ResponseText)
        } catch {
            body := StrReplace(body, "{myip}", "[IP unavailable]")
        }
    }
    return body
}

; ── Type snippet ──────────────────────────────────────────────────────────────
TypeSnippet(trigger, body) {
    ; Delete the trigger text
    loop StrLen(trigger)
        Send("{Backspace}")

    body := ExpandDynamic(body)

    ; Find cursor placeholder
    cursorPos := InStr(body, "{|}")
    if cursorPos {
        before := SubStr(body, 1, cursorPos - 1)
        after  := SubStr(body, cursorPos + 3)
        SendText(before)
        if after != ""
            SendText(after)
        ; Move cursor back to placeholder position
        loop StrLen(after)
            Send("{Left}")
    } else {
        SendText(body)
    }
}

; ── Hook keystrokes to detect triggers ───────────────────────────────────────
; We use a simple input buffer approach
global InputBuffer := ""

~*$:: {
    key := A_ThisHotkey
    ; Strip the "~*$" prefix artefact - only single printable chars
    ch := SubStr(key, 1, 1)
    if StrLen(key) = 1 && Ord(ch) >= 32
        global InputBuffer .= ch
    else if key = "Space"
        global InputBuffer .= " "
    else if key = "BackSpace"
        global InputBuffer := SubStr(InputBuffer, 1, Max(0, StrLen(InputBuffer)-1))
    else
        global InputBuffer := ""   ; reset on nav keys etc.

    ; Check all triggers
    for snip in Snippets {
        trigger := snip["trigger"]
        if StrLen(InputBuffer) >= StrLen(trigger) {
            bufEnd := SubStr(InputBuffer, -StrLen(trigger)+1)
            if bufEnd = trigger {
                global InputBuffer := ""
                TypeSnippet(trigger, snip["body"])
                return
            }
        }
    }

    ; Keep buffer bounded
    if StrLen(InputBuffer) > 50
        global InputBuffer := SubStr(InputBuffer, -49)
}

; ── Hotkey: open editor ───────────────────────────────────────────────────────
#!e:: ShowEditor()

ShowEditor() {
    g := Gui("+Resize", "⌨ Text Expander — Snippet Editor")
    g.BackColor := "0x0F0F14"
    g.SetFont("s9 cE2E8F0", "Segoe UI")

    g.Add("Text",   "x10 y8  cA855F7 s11 Bold", "⌨ Text Expander")
    g.Add("Text",   "x10 y32 c64748B", "Snippets  (double-click to edit)")

    lb := g.Add("ListBox", "x10 y54 w220 h320 BackgroundColor0x18181E cE2E8F0 AltSubmit")
    RefreshList(lb)

    g.Add("Text",   "x240 y54  c64748B", "Trigger keyword")
    eTrigger := g.Add("Edit", "x240 y70  w280 h22 BackgroundColor0x222232 cE2E8F0 -Border")

    g.Add("Text",   "x240 y100 c64748B", "Title")
    eTitle   := g.Add("Edit", "x240 y116 w280 h22 BackgroundColor0x222232 cE2E8F0 -Border")

    g.Add("Text",   "x240 y146 c64748B", "Snippet body  (use {|} for cursor position)")
    eBody := g.Add("Edit", "x240 y162 w280 h180 BackgroundColor0x222232 cE2E8F0 -Border Multi")

    btnNew  := g.Add("Button", "x10  y384 w100 h28 BackgroundColor6366F1 cWhite", "+ New")
    btnSave := g.Add("Button", "x120 y384 w100 h28 BackgroundColor22C55E cWhite", "💾 Save")
    btnDel  := g.Add("Button", "x10  y420 w100 h28 BackgroundColor0x222232 cE2E8F0", "🗑 Delete")

    curIdx := 0

    lb.OnEvent("Change", (*) => {
        curIdx := lb.Value
        if !curIdx
            return
        snip := Snippets[curIdx]
        eTrigger.Value := snip["trigger"]
        eTitle.Value   := snip["title"]
        eBody.Value    := snip["body"]
    })

    btnNew.OnEvent("Click", (*) => {
        Snippets.Push(Map("trigger", ";new", "title", "New Snippet", "body", ""))
        SaveSnippets(Snippets)
        RefreshList(lb)
        lb.Choose(Snippets.Length)
        eTrigger.Focus()
    })

    btnSave.OnEvent("Click", (*) => {
        if !curIdx
            return
        Snippets[curIdx]["trigger"] := eTrigger.Value
        Snippets[curIdx]["title"]   := eTitle.Value
        Snippets[curIdx]["body"]    := eBody.Value
        SaveSnippets(Snippets)
        RefreshList(lb)
        lb.Choose(curIdx)
    })

    btnDel.OnEvent("Click", (*) => {
        if !curIdx
            return
        Snippets.RemoveAt(curIdx)
        SaveSnippets(Snippets)
        RefreshList(lb)
        curIdx := 0
        eTrigger.Value := ""
        eTitle.Value   := ""
        eBody.Value    := ""
    })

    g.Show("w540 h460")
}

RefreshList(lb) {
    lb.Delete()
    for snip in Snippets
        lb.Add([snip["trigger"] . "  —  " . snip["title"]])
}

; ── Minimal JSON helpers (Jxon lite) ─────────────────────────────────────────
; Tiny subset: arrays of Maps with string values only.
Jxon_Dump(obj, indent:=0, depth:=0) {
    pad   := indent ? "`n" . StrRepeat(" ", indent * (depth+1)) : ""
    pad0  := indent ? "`n" . StrRepeat(" ", indent * depth) : ""
    sep   := indent ? " " : ""
    if obj is Array {
        parts := []
        for v in obj
            parts.Push(Jxon_Dump(v, indent, depth+1))
        return "[" . pad . parts.Join("," . pad) . pad0 . "]"
    }
    if obj is Map {
        parts := []
        for k, v in obj
            parts.Push('"' . k . '":' . sep . Jxon_Dump(v, indent, depth+1))
        return "{" . pad . parts.Join("," . pad) . pad0 . "}"
    }
    if obj is String
        return '"' . StrReplace(StrReplace(StrReplace(obj, "\","\\"), '"','\"'), "`n","\n") . '"'
    return String(obj)
}

Jxon_Load(&str) {
    ; Minimal parser for our own output format (arrays of objects, string values)
    result := []
    pos    := 1
    SkipWS(&pos) {
        while pos <= StrLen(str) && InStr(" `t`r`n", SubStr(str, pos, 1))
            pos++
    }
    ReadStr(&pos) {
        pos++   ; skip opening "
        s := ""
        while pos <= StrLen(str) {
            ch := SubStr(str, pos, 1)
            if ch = '"'  { pos++ ; return s }
            if ch = "\" {
                pos++
                esc := SubStr(str, pos, 1)
                if      esc = "n"  s .= "`n"
                else if esc = "t"  s .= "`t"
                else               s .= esc
            } else
                s .= ch
            pos++
        }
        return s
    }
    SkipWS(&pos)
    if SubStr(str, pos, 1) != "["
        return result
    pos++
    loop {
        SkipWS(&pos)
        if pos > StrLen(str) || SubStr(str, pos, 1) = "]" { pos++ ; break }
        if SubStr(str, pos, 1) = ","  { pos++ ; continue }
        if SubStr(str, pos, 1) = "{" {
            pos++
            m := Map()
            loop {
                SkipWS(&pos)
                if pos > StrLen(str) || SubStr(str, pos, 1) = "}" { pos++ ; break }
                if SubStr(str, pos, 1) = ","  { pos++ ; continue }
                if SubStr(str, pos, 1) = '"' {
                    key := ReadStr(&pos)
                    SkipWS(&pos)
                    if SubStr(str, pos, 1) = ":"  pos++
                    SkipWS(&pos)
                    val := ReadStr(&pos)
                    m[key] := val
                } else
                    pos++
            }
            result.Push(m)
        } else
            pos++
    }
    return result
}

StrRepeat(s, n) {
    r := ""
    loop n
        r .= s
    return r
}

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Edit Snippets",  (*) => ShowEditor())
A_TrayMenu.Add("Reload Snippets", (*) => { global Snippets := LoadSnippets() ; TrayTip("Snippets reloaded","Text Expander",1) })
A_TrayMenu.Add("Exit",           (*) => ExitApp())
A_TrayMenu.Default := "Edit Snippets"
TrayTip("Text Expander running`nWin+Alt+E to edit snippets", "Text Expander", 1)
