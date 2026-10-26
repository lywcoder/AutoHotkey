#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#MaxThreadsBuffer false

; ======================================================================
; Windows 10/11 + AutoHotkey v2
; 修复：普通原生 CapsLock 切换、关闭频率弹窗、原版 HUD
;   单独按 Shift        : 保留系统输入法的 Shift 中/英文切换，并显示「中/英」
;   Shift + CapsLock    : 松开组合后切换真正的 CapsLock 大小写锁定，显示「A/a」
;   单击 CapsLock       : Esc + 尝试切到英文输入模式
;   按住 CapsLock + 按键: 左 Ctrl（支持 Ctrl+C/V/鼠标点击等）
;   单独长按 CapsLock   : 只作为 Ctrl，松开不会额外发送 Esc
;
; 注意：Shift 中/英文切换依赖 Windows 输入法本身将 Shift 配置为切换键。
;       本脚本读取切换后的输入法状态，而不会再切换一次造成双重反转。
;       Windows IME 可能拦截 Shift+Caps；在物理组合松开后才发送锁定事件。
;       请先退出旧版同类脚本，再运行本文件，避免多个键盘钩子互相改写。
; ======================================================================

DetectHiddenWindows True
InstallKeybdHook()
InstallMouseHook()
; 使用普通的 Windows CapsLock 开关，不使用 AlwaysOn/AlwaysOff 持续强制属性。
global CapsCtrlDown := false
SetCapsLockState()
SetCapsLockState "Off"
SetStoreCapsLockMode false
OnExit(CleanupKeyboard)
; 用户要求不再出现热键频率确认框。鼠标滚轮已不再注册为热键。
A_HotkeyInterval := 0

; ================== 用户可调参数与状态 ==================
global CAPS_TAP_MS := 260
global SuppressShiftHud := false
global KeyboardActionSerial := 0

; ================== 1. Shift：显示中/英文状态 ==================
~*LShift Up::
~*RShift Up::
{
    global SuppressShiftHud, CapsCtrlDown, KeyboardActionSerial

    ; 整个 Shift+CapsLock 周期仅显示 A/a；两侧 Shift 都松开后再清除标记。
    if SuppressShiftHud {
        if !GetKeyState("LShift", "P") && !GetKeyState("RShift", "P")
            SuppressShiftHud := false
        return
    }

    ; Caps 映射产生的 Ctrl 不是物理 Ctrl，也必须排除；鼠标组合不弹输入法 HUD。
    if CapsCtrlDown || GetKeyState("CapsLock", "P")
        return

    ; 如果按 Shift 的过程中按过其他键，不认为是单按 Shift
    if (A_PriorKey != "LShift" && A_PriorKey != "RShift")
        return

    ; 忽略 Ctrl+Shift / Alt+Shift / Win+Shift 等组合
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        || GetKeyState("Shift", "P")
        return

    ; 允许输入法先处理 Shift 松开。等待期间切换窗口时，不向新窗口显示旧提示。
    actionBefore := KeyboardActionSerial
    foregroundBefore := DllCall("user32\GetForegroundWindow", "Ptr")
    Sleep 60
    if (actionBefore != KeyboardActionSerial)
        return
    imeState := GetImeState()
    if (imeState = -1) {
        Sleep 60
        imeState := GetImeState()
    }

    ; 无法可靠查询状态时不显示猜测结果
    if (imeState != -1 && actionBefore = KeyboardActionSerial
        && foregroundBefore = DllCall("user32\GetForegroundWindow", "Ptr"))
        ShowMacHud(imeState = 1 ? "中" : "英")
}

; ================== 2. CapsLock：短按/长按/组合 ==================
; Shift 必须先按下；CapsLock 先按下再按 Shift 仍是 Ctrl+Shift 组合。
; 大小写在 CapsLock 与所有 Shift 都松开后提交，一次组合只切换一次。
*CapsLock::
{
    global CAPS_TAP_MS, SuppressShiftHud, CapsCtrlDown, KeyboardActionSerial
    KeyboardActionSerial++ ; 取消此前尚未显示的 Shift 输入法提示

    if GetKeyState("LShift", "P") || GetKeyState("RShift", "P") || ShiftIsDownAsync() {
        SuppressShiftHud := true

        ; 设置 CapsLock 会产生原生锁定按键事件，Shift 仍按着时可能被 IME 当作组合键。
        ; 等完整的物理组合结束，不发送虚假的 Shift Up，也不进入 Ctrl/Esc 分支。
        KeyWait "CapsLock"
        while GetKeyState("LShift", "P") || GetKeyState("RShift", "P") || ShiftIsDownAsync()
            Sleep 10

        ToggleNativeCapsLock()
        SuppressShiftHud := false
        ShowMacHud(GetKeyState("CapsLock", "T") ? "A" : "a") ; 读取实际状态，不伪造结果
        return
    }

    otherModifier := GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    pressTime := A_TickCount

    ; 立即提供 Ctrl，快速 Caps+C/V 也有效；短按是否发 Esc 在释放后判断。
    CapsCtrlDown := true
    try {
        Send "{Blind}{LCtrl DownR}"
        KeyWait "CapsLock"
    } finally {
        ReleaseCapsCtrl()
    }

    ; 普通 Caps 分支不修改大写锁定，大小写仅由专用分支管理。
    if otherModifier
        return

    if (A_PriorKey = "CapsLock" && A_TickCount - pressTime <= CAPS_TAP_MS) {
        Send "{Esc}"
        SwitchToEnglish()
    }
}

ToggleNativeCapsLock() {
    ; 只发送一次原生 CapsLock。不能根据线程中暂时未刷新的读数立即重发，
    ; 否则第二次按键会把第一次的切换抵消。
    SendLevel 0
    SendEvent "{Blind}{CapsLock}"
    Sleep 30
}

ShiftIsDownAsync() {
    return (DllCall("user32\GetAsyncKeyState", "Int", 0x10, "Short") & 0x8000) != 0
}

ReleaseCapsCtrl() {
    global CapsCtrlDown
    if !CapsCtrlDown
        return
    CapsCtrlDown := false
    ; 用户还按着实体左 Ctrl 时，让它自己的 Key Up 负责释放。
    if !GetKeyState("LCtrl", "P")
        Send "{Blind}{LCtrl Up}"
}

; 实体左 Ctrl 在 Caps 仍按着时松开，继续维持由 Caps 提供的 Ctrl。
#HotIf CapsCtrlDown
~*LCtrl Up::
{
    global CapsCtrlDown
    if CapsCtrlDown && GetKeyState("CapsLock", "P")
        Send "{Blind}{LCtrl DownR}"
}

#HotIf

CleanupKeyboard(*) {
    ReleaseCapsCtrl()
    ; 退出/重载时移除本脚本的强制属性，保留当时的大小写状态。
    SetCapsLockState()
}

; 鼠标动作由已安装的鼠标钩子计入 A_PriorKey，无需注册全局滚轮热键。

; 物理 Esc 保留原始功能，同时尝试切英文
~Esc::SwitchToEnglish()

SwitchToEnglish() {
    SetImeState(0)
}

; ================== 3. IME 状态获取 / 设置 ==================
; 从当前前台窗口及其焦点控件找到默认 IME 窗口。
GetDefaultImeWnd() {
    foregroundHwnd := DllCall("user32\GetForegroundWindow", "Ptr")
    if !foregroundHwnd || !DllCall("user32\IsWindow", "Ptr", foregroundHwnd, "Int")
        return 0

    targetHwnd := foregroundHwnd
    try {
        focusHwnd := ControlGetFocus("ahk_id " foregroundHwnd)
        if focusHwnd
            targetHwnd := focusHwnd
    }

    if (targetHwnd = foregroundHwnd) {
        threadId := DllCall("user32\GetWindowThreadProcessId", "Ptr", foregroundHwnd, "Ptr", 0, "UInt")
        infoSize := (A_PtrSize = 8) ? 72 : 48
        guiThreadInfo := Buffer(infoSize, 0)
        NumPut("UInt", infoSize, guiThreadInfo, 0)

        if DllCall("user32\GetGUIThreadInfo", "UInt", threadId, "Ptr", guiThreadInfo, "Int") {
            focusOffset := (A_PtrSize = 8) ? 16 : 12
            focusHwnd := NumGet(guiThreadInfo, focusOffset, "Ptr")
            if focusHwnd
                targetHwnd := focusHwnd
        }
    }

    imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", targetHwnd, "Ptr")
    if (!imeHwnd && targetHwnd != foregroundHwnd)
        imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", foregroundHwnd, "Ptr")

    if !imeHwnd {
        try {
            processId := WinGetPID("ahk_id " foregroundHwnd)
            imeHwnd := WinExist("ahk_class IME ahk_pid " processId)
        }
    }
    return imeHwnd
}

; 用超时消息避免 IDE/浏览器无响应时卡住热键线程。
SendImeCommand(imeHwnd, command, param := 0) {
    messageResult := 0
    try {
        success := DllCall("user32\SendMessageTimeoutW",
            "Ptr", imeHwnd,
            "UInt", 0x0283,     ; WM_IME_CONTROL
            "Ptr", command,
            "Ptr", param,
            "UInt", 0x0002,    ; SMTO_ABORTIFHUNG
            "UInt", 150,
            "Ptr*", &messageResult,
            "Ptr")
        return success ? messageResult : -1
    } catch {
        return -1
    }
}

; 返回 1=中文，0=英文，-1=不可查询
GetImeState() {
    imeHwnd := GetDefaultImeWnd()
    if !imeHwnd
        return -1
    result := SendImeCommand(imeHwnd, 0x0005) ; IMC_GETOPENSTATUS
    return (result = 0 || result = 1) ? result : -1
}

; 请求设置 0=英文；某些现代 TSF 输入法可能不支持传统 IMM32 接口
SetImeState(state) {
    imeHwnd := GetDefaultImeWnd()
    if !imeHwnd
        return false
    if (SendImeCommand(imeHwnd, 0x0006, state ? 1 : 0) = -1)
        return false
    ; 消息投递成功不等于输入法已接受设置；返回真正读回的状态。
    return SendImeCommand(imeHwnd, 0x0005) = (state ? 1 : 0)
}

; ================== 4. 原版提示框（尺寸与样式原样保留） ==================
ShowMacHud(displayText) {
    static hudGuis := []
    static hudTexts := []
    static hideTimer := ""

    ; 初始化统一的隐藏回调
    if !hideTimer {
        hideTimer := (*) => HideAllHuds()
        HideAllHuds() {
            for guiObj in hudGuis
                try guiObj.Hide()
        }
    }

    monCount := MonitorGetCount()

    ; 动态扩容 GUI 实例数组，确保每个显示器都有独立的 HUD
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

        hudGuis[idx].Show("NoActivate AutoSize Hide")
        hudGuis[idx].GetPos(,, &guiW, &guiH)

        ; 获取当前显示器的边界坐标（适配负坐标与多分辨率屏幕）
        MonitorGet(idx, &mLeft, &mTop, &mRight, &mBottom)
        posX := mLeft + ((mRight - mLeft) - guiW) // 2
        posY := mTop + ((mBottom - mTop) - guiH) // 2

        hudGuis[idx].Show("NoActivate X" posX " Y" posY)

        ; 钉在最高 Z 轴层级，避免被全屏窗口覆盖
        DllCall("SetWindowPos", "Ptr", hudGuis[idx].Hwnd, "Ptr", -1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0053)
    }

    ; 650ms 后隐藏
    SetTimer(hideTimer, -650)
}