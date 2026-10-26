#Requires AutoHotkey v2.0
#SingleInstance Force

InstallKeybdHook()
InstallMouseHook()

; ========================================================
; 1. 中英文切换：单按 Shift
; ========================================================
~LShift Up::
~RShift Up::
{
    ; 过滤其它键组合（如果在按住 Shift 期间按了字母、鼠标或 CapsLock，均直接拦截）
    if (A_PriorKey != "LShift" && A_PriorKey != "RShift")
        return

    ; 过滤修饰键（Ctrl+Shift、Alt+Shift、Win+Shift）
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return

    Sleep 50
    state := GetImeState()
    if (state != -1)
        ShowMacHud(state == 1 ? "中" : "英")
}

; ========================================================
; 2. 大小写切换：仅 Shift + CapsLock 触发
; ========================================================
+CapsLock::
{
    newState := !GetKeyState("CapsLock", "T")
    SetCapsLockState(newState)
    ShowMacHud(newState ? "A" : "a")
}

; ========================================================
; 核心：获取当前窗口输入法状态 (1:中文, 0:英文)
; ========================================================
GetImeState() {
    hWnd := DllCall("GetForegroundWindow", "Ptr")
    if !hWnd
        return -1

    threadId := DllCall("GetWindowThreadProcessId", "Ptr", hWnd, "Ptr", 0, "UInt")
    guiInfo := Buffer(48, 0)
    NumPut("UInt", 48, guiInfo, 0)

    targetHwnd := hWnd
    if DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", guiInfo) {
        focusedHwnd := NumGet(guiInfo, 16, "Ptr")
        if focusedHwnd
            targetHwnd := focusedHwnd
    }

    defaultIme := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", targetHwnd, "Ptr")
    if !defaultIme
        return -1

    return DllCall("SendMessage", "Ptr", defaultIme, "UInt", 0x0283, "Ptr", 0x0005, "Ptr", 0)
}

; ========================================================
; 核心：在所有显示器中心同时绘制类似 macOS 的半透明提示框
; ========================================================
ShowMacHud(displayText) {
    static hudGuis := []
    static hudTexts := []
    static hideTimer := ""

    ; 初始化统一的隐藏回调，防止多次按键产生竞态
    if !hideTimer {
        hideTimer := (*) => HideAllHuds()
        HideAllHuds() {
            for guiObj in hudGuis
                try guiObj.Hide()
        }
    }

    monCount := MonitorGetCount()

    ; 动态扩展 GUI 实例数组，确保每个显示器都有一个专属 HUD
    while (hudGuis.Length < monCount) {
        guiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        guiObj.BackColor := "1E1E1E"
        guiObj.MarginX := 25
        guiObj.MarginY := 18
        guiObj.SetFont("s30 bold cWhite", "Microsoft YaHei UI")
        txtObj := guiObj.AddText("Center w90", "")
        WinSetTransparent(215, guiObj)

        hudGuis.Push(guiObj)
        hudTexts.Push(txtObj)
    }

    ; 重置隐藏计时器
    SetTimer(hideTimer, 0)

    ; 遍历所有显示器，计算中心并显示
    Loop monCount {
        idx := A_Index
        hudTexts[idx].Value := displayText

        ; 预先刷新尺寸
        hudGuis[idx].Show("NoActivate AutoSize Hide")
        hudGuis[idx].GetPos(,, &guiW, &guiH)

        ; 获取当前显示器的边界坐标（适配负坐标与非对称排列）
        MonitorGet(idx, &mLeft, &mTop, &mRight, &mBottom)
        posX := mLeft + ((mRight - mLeft) - guiW) // 2
        posY := mTop + ((mBottom - mTop) - guiH) // 2

        ; 移动至对应显示器中心并显示
        hudGuis[idx].Show("NoActivate X" posX " Y" posY)

        ; 钉在最高 Z 轴层级，避免被全屏程序覆盖
        DllCall("SetWindowPos", "Ptr", hudGuis[idx].Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0053)
    }

    ; 650ms 后同时隐藏所有屏幕上的提示
    SetTimer(hideTimer, -650)
}