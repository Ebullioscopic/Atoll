package com.codeisland.buddywatch

enum class ScreenOrientation(val wireValue: Int) {
    UP(0),
    DOWN(1);

    companion object {
        fun fromWireValue(value: Int): ScreenOrientation {
            return if (value == DOWN.wireValue) DOWN else UP
        }
    }
}

enum class DisplayMode {
    STANDBY,
    AGENT,
    DEMO,
}

enum class PeripheralState(val label: String) {
    STARTING("启动中"),
    ADVERTISING("可发现"),
    CONNECTED("已连接"),
    PERMISSION_REQUIRED("待授权"),
    UNSUPPORTED("不支持"),
    BLUETOOTH_OFF("蓝牙关闭"),
    ERROR("错误"),
}

enum class Mascot(
    val wireId: Int,
    val title: String,
    val badge: String,
    val accentColor: Int,
) {
    CLAUDE(0, "Claude", "CL", 0xFFDE886D.toInt()),
    CODEX(1, "Codex", "CD", 0xFFEBEBED.toInt()),
    GEMINI(2, "Gemini", "GM", 0xFF847ACE.toInt()),
    CURSOR(3, "Cursor", "CU", 0xFF22C55E.toInt()),
    COPILOT(4, "Copilot", "CP", 0xFFCC3366.toInt()),
    TRAE(5, "Trae", "TR", 0xFF22C55E.toInt()),
    QODER(6, "Qoder", "QD", 0xFFA855F7.toInt()),
    DROID(7, "Factory", "FD", 0xFF14B8A6.toInt()),
    CODEBUDDY(8, "CodeBuddy", "CB", 0xFF06B6D4.toInt()),
    STEPFUN(9, "StepFun", "SF", 0xFF2EBFB3.toInt()),
    OPENCODE(10, "OpenCode", "OC", 0xFF38383D.toInt()),
    QWEN(11, "Qwen", "QW", 0xFF60A5FA.toInt()),
    ANTIGRAVITY(12, "AntiGravity", "AG", 0xFF84CC16.toInt()),
    WORKBUDDY(13, "WorkBuddy", "WB", 0xFF7961DE.toInt()),
    HERMES(14, "Hermes", "HM", 0xFF7A58B0.toInt()),
    KIMI(15, "Kimi", "KM", 0xFFF43F5E.toInt());

    companion object {
        fun fromWireId(value: Int): Mascot {
            return entries.firstOrNull { it.wireId == value } ?: CODEX
        }
    }
}

enum class AgentStatusCode(
    val wireId: Int,
    val title: String,
    val sceneLabel: String,
    val accentColor: Int,
) {
    IDLE(0, "Idle", "Sleep", 0xFF64748B.toInt()),
    PROCESSING(1, "Processing", "Work", 0xFF2563EB.toInt()),
    RUNNING(2, "Running", "Work", 0xFF16A34A.toInt()),
    WAITING_APPROVAL(3, "Waiting Approval", "Alert", 0xFFF59E0B.toInt()),
    WAITING_QUESTION(4, "Waiting Question", "Alert", 0xFFEF4444.toInt());

    companion object {
        fun fromWireId(value: Int): AgentStatusCode {
            return entries.firstOrNull { it.wireId == value } ?: IDLE
        }
    }
}

data class BuddyUiState(
    val peripheralState: PeripheralState = PeripheralState.STARTING,
    val displayMode: DisplayMode = DisplayMode.STANDBY,
    val mascot: Mascot = Mascot.CODEX,
    val agentStatus: AgentStatusCode = AgentStatusCode.IDLE,
    val toolName: String? = null,
    val workspaceName: String? = null,
    val messages: List<WatchMessagePreview> = emptyList(),
    val selectedMessageSlot: Int = 0,
    val brightnessPercent: Int = BleProtocol.defaultBrightnessPercent,
    val orientation: ScreenOrientation = ScreenOrientation.UP,
    val connectedDeviceName: String? = null,
    val focusPulseToken: Long = 0,
    val errorMessage: String? = null,
    val diagnosticMessage: String? = "初始化中，正在检查蓝牙与广播能力…",
)

data class WatchMessagePreview(
    val index: Int,
    val isUser: Boolean,
    val text: String,
)
