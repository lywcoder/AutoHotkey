#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------
; 全局设置
; ---------------------------------------------------------
InstallKeybdHook()
; 初始状态关闭大写
SetCapsLockState "Off"

; ---------------------------------------------------------
; 修改后：控制当前输入法中英文状态的底层函数
; State: 0 表示英文，1 表示中文
; ---------------------------------------------------------
SetImeState(State) {
    hWnd := WinActive("A")
    if !hWnd
        return
    
    ; 获取当前活动窗口的默认输入法窗口句柄
    DefaultIMEWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hWnd, "Ptr")
    
    if DefaultIMEWnd {
        ; 【修复核心】：开启检测隐藏窗口，因为输入法窗口是隐藏状态
        OriginalDetect := A_DetectHiddenWindows
        DetectHiddenWindows True
        
        ; 使用 try 忽略极少数情况下窗口瞬间消失导致的报错
        try {
            ; 0x0283 = WM_IME_CONTROL, 0x006 = IMC_SETOPENSTATUS
            SendMessage(0x0283, 0x006, State, , "ahk_id " DefaultIMEWnd)
        }
        
        ; 恢复原本的隐藏窗口检测状态
        DetectHiddenWindows OriginalDetect
    }
}

; ---------------------------------------------------------
; 切换为英文模式的独立函数
; ---------------------------------------------------------
SwitchToEnglish() {
    SetImeState(0)
}

; 物理上的 Esc 键：保留原本退出功能的同时，强制切回英文
~Esc::SwitchToEnglish()


; ---------------------------------------------------------
; 1. Shift + CapsLock 切换大写锁定状态
; ---------------------------------------------------------
+CapsLock::
{
    if GetKeyState("CapsLock", "T")
        SetCapsLockState "AlwaysOff"
    else
        SetCapsLockState "AlwaysOn"
    
    ; 屏幕右下角显示提示
    State := GetKeyState("CapsLock", "T") ? "ON" : "OFF"
    ToolTip "Caps Lock: " . State
    SetTimer () => ToolTip(), -1000 ; 1秒后自动消失
}

; ---------------------------------------------------------
; 2. CapsLock 映射：短按 Esc，长按/组合 Ctrl
; ---------------------------------------------------------
*CapsLock::
{
    Send "{LControl Down}"
    KeyWait "CapsLock"
    Send "{LControl Up}"
    
    if (A_PriorKey = "CapsLock")
    {
        Send "{Esc}"
        SwitchToEnglish()  ; 短按触发 Esc 后，强制中文输入法进入纯英文模式
    }
}