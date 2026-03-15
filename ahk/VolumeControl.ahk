; ============================================================================
;  VolumeControl.ahk  — AHK v2
;  Scroll-wheel volume control anywhere with a beautiful on-screen display.
;  Requires: AutoHotkey v2.0+
;
;  USAGE
;  -----
;  Scroll the mouse wheel while holding Alt or on the desktop/taskbar
;  to change the system volume.  An OSD appears showing the current level.
;
;  HOTKEYS
;  -------
;  Alt+Scroll Up/Down   ±2% volume
;  Alt+MButton          Mute / unmute
;  Win+Alt+Up/Down      ±5% volume (keyboard alternative)
;  Win+Alt+M            Mute toggle
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── Volume helpers ────────────────────────────────────────────────────────────
GetVolume() {
    return SoundGetVolume()
}

SetVolume(vol) {
    vol := Max(0, Min(100, vol))
    SoundSetVolume(vol)
    ShowVolumeOSD(vol, SoundGetMute())
}

GetMute() {
    return SoundGetMute()
}

ToggleMute() {
    muted := SoundGetMute()
    SoundSetMute(!muted)
    ShowVolumeOSD(SoundGetVolume(), !muted)
}

; ── OSD ───────────────────────────────────────────────────────────────────────
global OSDGui := 0
global OSDTimer := 0

ShowVolumeOSD(vol, muted) {
    global OSDGui, OSDTimer

    ; Close existing OSD
    if OSDGui {
        try OSDGui.Destroy()
        OSDGui := 0
    }

    g := Gui("-Caption +ToolWindow +AlwaysOnTop E0x20", "VolumeOSD")
    g.BackColor := "0F0F18"
    g.MarginX := 0
    g.MarginY := 0

    ; OSD width
    w := 280
    h := 72

    ; Position: bottom-right of screen
    MonitorGetWorkArea(, &ml, &mt, &mr, &mb)
    x := mr - w - 20
    y := mb - h - 60

    ; Speaker icon
    icon := muted ? "🔇" : (vol = 0 ? "🔇" : (vol < 33 ? "🔈" : (vol < 66 ? "🔉" : "🔊")))

    g.SetFont("s14 cE2E8F0", "Segoe UI")
    g.Add("Text", "x12 y12 w36 h36 Center", icon)

    ; Volume bar background
    g.Add("Text", "x56 y16 w" . (w - 70) . " h12 BackgroundColor1C1C2E cE2E8F0")
    ; Volume bar fill
    fillW := Round((w - 70) * vol / 100)
    barColor := muted ? "EF4444" : (vol < 33 ? "22C55E" : (vol < 70 ? "EAB308" : "EF4444"))
    if fillW > 0
        g.Add("Text", "x56 y16 w" . fillW . " h12 BackgroundColor" . barColor . " cE2E8F0")

    ; Percentage label
    label := muted ? "MUTED" : vol . "%"
    g.SetFont("s10 c" . (muted ? "EF4444" : "E2E8F0") . " Bold", "Segoe UI")
    g.Add("Text", "x56 y32 w" . (w-70) . " h20 Center", label)

    g.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")
    global OSDGui := g

    ; Auto-dismiss after 1.8 seconds
    SetTimer(() => {
        global OSDGui
        if OSDGui {
            try OSDGui.Destroy()
            OSDGui := 0
        }
    }, -1800)
}

; ── Hotkeys ───────────────────────────────────────────────────────────────────
; Alt + scroll wheel
!WheelUp::   SetVolume(Round(GetVolume()) + 2)
!WheelDown:: SetVolume(Round(GetVolume()) - 2)
!MButton::   ToggleMute()

; Win+Alt keyboard shortcuts
#!Up::       SetVolume(Round(GetVolume()) + 5)
#!Down::     SetVolume(Round(GetVolume()) - 5)
#!m::        ToggleMute()

; Desktop / taskbar scroll (no modifier needed when hovering those)
#HotIf WinActive("ahk_class Shell_TrayWnd") || WinActive("ahk_class Progman")
    WheelUp::   SetVolume(Round(GetVolume()) + 2)
    WheelDown:: SetVolume(Round(GetVolume()) - 2)
#HotIf

; ── Tray ──────────────────────────────────────────────────────────────────────
A_TrayMenu.Add()
A_TrayMenu.Add("Show Volume OSD", (*) => ShowVolumeOSD(Round(GetVolume()), GetMute()))
A_TrayMenu.Add("Mute / Unmute",   (*) => ToggleMute())
A_TrayMenu.Add("Volume +10",      (*) => SetVolume(Round(GetVolume()) + 10))
A_TrayMenu.Add("Volume -10",      (*) => SetVolume(Round(GetVolume()) - 10))
A_TrayMenu.Add("Exit",            (*) => ExitApp())
A_TrayMenu.Default := "Show Volume OSD"
TrayTip("Volume Control running`nAlt+Scroll to adjust", "Volume Control", 1)
