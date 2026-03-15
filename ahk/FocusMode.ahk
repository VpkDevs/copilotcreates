; ============================================================================
;  FocusMode.ahk  — AHK v2
;  Toggle a distraction-free mode that hides all windows except the active one.
;  Requires: AutoHotkey v2.0+
;
;  HOTKEYS
;  -------
;  Win+Alt+F   Enter / exit Focus Mode
;  Win+Alt+`   Quick toggle (same action, alternate hotkey)
;
;  While in focus mode:
;    Win+Alt+F  or  Win+Alt+`  to restore all hidden windows
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global FocusActive := false
global HiddenWindows := []

; System windows to always exclude from hiding
SkipClasses := ["Shell_TrayWnd", "Progman", "WorkerW", "TopLevelWindowForOverflowXamlIsland",
                "Windows.UI.Core.CoreWindow", "ApplicationFrameWindow", "TaskManagerWindow",
                "ClipboardHistoryPopup", "AppLauncher"]

SkipTitles := ["", "Start", "Program Manager", "Task Manager",
               "Window Manager", "App Launcher", "Text Expander",
               "Clipboard Manager", "Focus Mode"]

ShouldSkip(hwnd) {
    cls   := WinGetClass(hwnd)
    title := WinGetTitle(hwnd)
    for c in SkipClasses
        if cls = c return true
    for t in SkipTitles
        if title = t return true
    if !title return true
    return false
}

; ── Toggle ────────────────────────────────────────────────────────────────────
#!f::  ToggleFocus()
#!`::  ToggleFocus()

ToggleFocus() {
    global FocusActive, HiddenWindows

    if FocusActive {
        ; Restore all hidden windows
        for hwnd in HiddenWindows {
            try WinShow(hwnd)
        }
        HiddenWindows := []
        FocusActive   := false
        ShowOSD("Focus Mode OFF", 0x222232, 0xE2E8F0)
        return
    }

    ; Enter focus mode
    activeHwnd := WinGetID("A")
    HiddenWindows := []

    for hwnd in WinGetList() {
        if hwnd = activeHwnd
            continue
        if ShouldSkip(hwnd)
            continue
        try {
            if WinGetMinMax(hwnd) != -1 {   ; not already minimised
                WinHide(hwnd)
                HiddenWindows.Push(hwnd)
            }
        }
    }

    FocusActive := true
    activeTitle := WinGetTitle(activeHwnd)
    ShowOSD("Focus Mode ON — " . HiddenWindows.Length . " windows hidden`n" . activeTitle, 0x1A1A2E, 0xA855F7)
}

; ── On-Screen Display ─────────────────────────────────────────────────────────
ShowOSD(msg, bgColor, fgColor) {
    g := Gui("-Caption +ToolWindow +AlwaysOnTop E0x20", "FocusModeOSD")
    g.BackColor := Format("{:06X}", bgColor)
    g.SetFont("s12 c" . Format("{:06X}", fgColor) . " Bold", "Segoe UI")
    g.MarginX := 20
    g.MarginY := 14

    lines := StrSplit(msg, "`n")
    maxW := 0
    for line in lines {
        w := StrLen(line) * 8   ; rough width estimate
        maxW := Max(maxW, w)
    }

    lbl := g.Add("Text", "w" . Min(maxW + 40, 500) . " Center", msg)

    MonitorGetWorkArea(, &ml, &mt, &mr, &mb)
    g.Show("x" . (ml + (mr-ml)//2 - 250) . " y" . (mt + 40) . " w500 NoActivate")

    ; Round corners via region
    ; Auto-close after 2 seconds
    SetTimer(() => g.Destroy(), -2000)
}

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Toggle Focus Mode", (*) => ToggleFocus())
A_TrayMenu.Add("Restore All Windows", (*) => {
    global FocusActive, HiddenWindows
    for hwnd in HiddenWindows
        try WinShow(hwnd)
    HiddenWindows := []
    FocusActive   := false
})
A_TrayMenu.Add("Exit", (*) => {
    ; Always restore before exit
    global HiddenWindows
    for hwnd in HiddenWindows
        try WinShow(hwnd)
    ExitApp()
})
A_TrayMenu.Default := "Toggle Focus Mode"
TrayTip("Focus Mode ready`nWin+Alt+F to toggle", "Focus Mode", 1)
