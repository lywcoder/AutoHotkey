; ========================================================
; Alt + H：一键切换桌面图标显示 / 隐藏 (纯净静默版)
; ========================================================
!h::ToggleDesktopIcons()

ToggleDesktopIcons() {
    hView := GetDesktopDefView()
    if !hView
        return

    ; 发送系统原生命令 (WM_COMMAND = 0x0111, ID = 0x7402)
    DllCall("SendMessage", "Ptr", hView, "UInt", 0x0111, "Ptr", 0x7402, "Ptr", 0)
}

; 核心：Win32 API 精准穿透桌面多层容器
GetDesktopDefView() {
    ; 1. 尝试从标准 Progman 查找桌面视图 SHELLDLL_DefView
    hProgman := DllCall("FindWindow", "Str", "Progman", "Ptr", 0, "Ptr")
    hView := DllCall("FindWindowEx", "Ptr", hProgman, "Ptr", 0, "Str", "SHELLDLL_DefView", "Ptr", 0, "Ptr")

    ; 2. 若未找到（壁纸引擎或分屏状态），遍历所有 WorkerW 窗口匹配
    if !hView {
        hWorker := 0
        while (hWorker := DllCall("FindWindowEx", "Ptr", 0, "Ptr", hWorker, "Str", "WorkerW", "Ptr", 0, "Ptr")) {
            hView := DllCall("FindWindowEx", "Ptr", hWorker, "Ptr", 0, "Str", "SHELLDLL_DefView", "Ptr", 0, "Ptr")
            if hView
                break
        }
    }
    return hView
}