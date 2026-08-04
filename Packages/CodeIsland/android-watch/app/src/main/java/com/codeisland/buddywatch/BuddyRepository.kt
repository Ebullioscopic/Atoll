package com.codeisland.buddywatch

import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

object BuddyRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val _uiState = MutableStateFlow(BuddyUiState())
    val uiState: StateFlow<BuddyUiState> = _uiState.asStateFlow()

    private val demoStatuses = listOf(
        AgentStatusCode.IDLE,
        AgentStatusCode.PROCESSING,
        AgentStatusCode.RUNNING,
        AgentStatusCode.WAITING_APPROVAL,
        AgentStatusCode.WAITING_QUESTION,
    )

    @Volatile
    private var lastAgentFrameAt: Long = 0L

    @Volatile
    private var lastDemoSwapAt: Long = 0L

    @Volatile
    private var demoPinned: Boolean = false

    @Volatile
    private var demoIndex: Int = 0

    init {
        scope.launch {
            while (isActive) {
                delay(1_000)
                handleTick(SystemClock.elapsedRealtime())
            }
        }
    }

    fun onStarting(detail: String) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.STARTING,
                diagnosticMessage = detail,
                errorMessage = null,
            )
        }
    }

    fun onPermissionsMissing(detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.PERMISSION_REQUIRED,
                errorMessage = null,
                diagnosticMessage = detail,
            )
        }
    }

    fun onAdvertisingReady(detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = if (it.peripheralState == PeripheralState.CONNECTED) {
                    PeripheralState.CONNECTED
                } else {
                    PeripheralState.ADVERTISING
                },
                errorMessage = null,
                diagnosticMessage = detail,
            )
        }
    }

    fun onBluetoothOff(detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.BLUETOOTH_OFF,
                connectedDeviceName = null,
                errorMessage = null,
                diagnosticMessage = detail,
            )
        }
    }

    fun onUnsupported(message: String, detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.UNSUPPORTED,
                connectedDeviceName = null,
                errorMessage = message,
                diagnosticMessage = detail ?: message,
            )
        }
    }

    fun onError(message: String, detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.ERROR,
                errorMessage = message,
                diagnosticMessage = detail ?: message,
            )
        }
    }

    fun onDeviceConnected(deviceName: String?, detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.CONNECTED,
                connectedDeviceName = deviceName,
                errorMessage = null,
                diagnosticMessage = detail,
            )
        }
    }

    fun onDeviceDisconnected(detail: String? = null) {
        _uiState.update {
            it.copy(
                peripheralState = PeripheralState.ADVERTISING,
                connectedDeviceName = null,
                diagnosticMessage = detail ?: it.diagnosticMessage,
            )
        }
    }

    fun onCommand(command: IncomingCommand) {
        when (command) {
            is IncomingCommand.AgentFrame -> applyAgentFrame(command)
            is IncomingCommand.WorkspaceFrame -> applyWorkspaceFrame(command)
            is IncomingCommand.MessagePreviewFrame -> applyMessagePreview(command)
            is IncomingCommand.Brightness -> {
                _uiState.update { state ->
                    state.copy(brightnessPercent = command.percent)
                }
            }

            is IncomingCommand.Orientation -> {
                _uiState.update { state ->
                    state.copy(orientation = ScreenOrientation.fromWireValue(command.wireValue))
                }
            }
        }
    }

    fun toggleDemoMode() {
        demoPinned = !demoPinned
        if (demoPinned) {
            advanceDemoFrame(SystemClock.elapsedRealtime(), force = true)
        } else {
            val shouldStayInAgent = SystemClock.elapsedRealtime() - lastAgentFrameAt < BleProtocol.firmwareInactivityTimeoutMs
            _uiState.update { state ->
                state.copy(
                    displayMode = if (shouldStayInAgent) DisplayMode.AGENT else DisplayMode.STANDBY,
                    toolName = if (shouldStayInAgent) state.toolName else null,
                )
            }
        }
    }

    fun cycleDemoMascot() {
        if (_uiState.value.displayMode != DisplayMode.DEMO) return
        advanceDemoFrame(SystemClock.elapsedRealtime(), force = true)
    }

    fun noteFocusRequest() {
        _uiState.update { state ->
            state.copy(focusPulseToken = state.focusPulseToken + 1)
        }
    }

    fun noteHostActionResult(detail: String) {
        _uiState.update { state ->
            state.copy(diagnosticMessage = detail)
        }
    }

    fun showNextMessage() {
        rotateMessage(step = 1)
    }

    fun showPreviousMessage() {
        rotateMessage(step = -1)
    }

    private fun applyAgentFrame(frame: IncomingCommand.AgentFrame) {
        lastAgentFrameAt = SystemClock.elapsedRealtime()
        _uiState.update { state ->
            state.copy(
                displayMode = DisplayMode.AGENT,
                mascot = Mascot.fromWireId(frame.mascotId),
                agentStatus = AgentStatusCode.fromWireId(frame.statusId),
                toolName = frame.toolName,
                errorMessage = null,
                diagnosticMessage = state.diagnosticMessage,
            )
        }
    }

    private fun applyWorkspaceFrame(frame: IncomingCommand.WorkspaceFrame) {
        _uiState.update { state ->
            state.copy(workspaceName = frame.workspaceName)
        }
    }

    private fun applyMessagePreview(frame: IncomingCommand.MessagePreviewFrame) {
        _uiState.update { state ->
            if (frame.total <= 0 || frame.text.isNullOrBlank()) {
                return@update state.copy(messages = emptyList(), selectedMessageSlot = 0)
            }

            val filtered = state.messages
                .filter { it.index != frame.index && it.index < frame.total }
                .toMutableList()
            filtered += WatchMessagePreview(
                index = frame.index,
                isUser = frame.isUser,
                text = frame.text,
            )

            val messages = filtered
                .distinctBy { it.index }
                .sortedBy { it.index }

            val selectedSlot = when {
                state.messages.isEmpty() -> frame.index
                frame.index == frame.total - 1 -> frame.index
                state.selectedMessageSlot >= frame.total -> (frame.total - 1).coerceAtLeast(0)
                else -> state.selectedMessageSlot
            }

            state.copy(
                messages = messages,
                selectedMessageSlot = selectedSlot,
            )
        }
    }

    private fun handleTick(now: Long) {
        maybeExpireAgentMode(now)
        maybeAdvanceDemo(now)
    }

    private fun maybeExpireAgentMode(now: Long) {
        val current = _uiState.value
        if (current.displayMode != DisplayMode.AGENT) return
        if (lastAgentFrameAt == 0L) return
        if (now - lastAgentFrameAt < BleProtocol.firmwareInactivityTimeoutMs) return

        _uiState.update { state ->
            state.copy(
                displayMode = if (demoPinned) DisplayMode.DEMO else DisplayMode.STANDBY,
                toolName = null,
            )
        }

        if (demoPinned) {
            advanceDemoFrame(now, force = true)
        }
    }

    private fun maybeAdvanceDemo(now: Long) {
        if (_uiState.value.displayMode != DisplayMode.DEMO) return
        if (now - lastDemoSwapAt < BleProtocol.demoCycleMs) return
        advanceDemoFrame(now, force = true)
    }

    private fun advanceDemoFrame(now: Long, force: Boolean) {
        if (!force && now - lastDemoSwapAt < BleProtocol.demoCycleMs) return
        lastDemoSwapAt = now

        val mascot = Mascot.entries[demoIndex % Mascot.entries.size]
        val status = demoStatuses[demoIndex % demoStatuses.size]
        demoIndex += 1

        _uiState.update { state ->
            state.copy(
                displayMode = DisplayMode.DEMO,
                mascot = mascot,
                agentStatus = status,
                toolName = "Demo · ${status.sceneLabel}",
            )
        }
    }

    private fun rotateMessage(step: Int) {
        _uiState.update { state ->
            val messageCount = state.messages.size
            if (messageCount <= 1) return@update state

            val sortedSlots = state.messages.map { it.index }.sorted()
            val currentPosition = sortedSlots.indexOf(state.selectedMessageSlot).takeIf { it >= 0 } ?: 0
            val nextPosition = (currentPosition + step).mod(sortedSlots.size)
            state.copy(selectedMessageSlot = sortedSlots[nextPosition])
        }
    }
}
