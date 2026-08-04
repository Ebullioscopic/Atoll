package com.codeisland.buddywatch

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.codeisland.buddywatch.databinding.ActivityMainBinding
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.math.abs

class MainActivity : ComponentActivity() {
    private lateinit var binding: ActivityMainBinding
    private var lastPulseToken: Long = -1L
    private var recoveryPermissionRequested = false
    private var notificationPermissionRequested = false
    private var touchDownX = 0f
    private var touchDownY = 0f

    private val bluetoothPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
            if (results.values.all { it }) {
                maybeRequestNotificationPermission(forceRequest = true)
                BuddyPeripheralService.start(this)
            } else {
                BuddyRepository.onPermissionsMissing(missingPermissionsDetail())
            }
        }

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            notificationPermissionRequested = true
            if (granted) {
                BuddyPeripheralService.start(this)
            } else {
                BuddyRepository.onPermissionsMissing(missingPermissionsDetail())
            }
        }

    private val appSettingsLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            BuddyRepository.onStarting("已从系统设置返回，重新检查蓝牙权限与广播状态…")
            ensurePermissionsAndStart(forceRequest = false)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        BuddyRepository.onStarting("界面已加载，准备检查权限与广播状态…")

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        binding.toolName.isSelected = true

        binding.rootContainer.setOnClickListener {
            handlePrimaryAction(BuddyRepository.uiState.value)
        }
        binding.rootContainer.setOnLongClickListener {
            handleSecondaryAction(BuddyRepository.uiState.value)
            true
        }
        binding.rootContainer.setOnTouchListener { _, event ->
            handleSwipe(event)
        }
        binding.actionPrimary.setOnClickListener {
            handlePrimaryAction(BuddyRepository.uiState.value)
        }
        binding.actionSecondary.setOnClickListener {
            handleSecondaryAction(BuddyRepository.uiState.value)
        }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                BuddyRepository.uiState.collectLatest(::render)
            }
        }

        ensurePermissionsAndStart(forceRequest = true)
    }

    override fun onResume() {
        super.onResume()
        ensurePermissionsAndStart(forceRequest = false)
    }

    private fun ensurePermissionsAndStart(forceRequest: Boolean) {
        val missingBluetooth = missingBluetoothPermissions()
        if (missingBluetooth.isEmpty()) {
            maybeRequestNotificationPermission(forceRequest)
            BuddyPeripheralService.start(this)
        } else {
            BuddyRepository.onPermissionsMissing(missingPermissionsDetail())
            if (forceRequest || !recoveryPermissionRequested) {
                recoveryPermissionRequested = true
                bluetoothPermissionLauncher.launch(missingBluetooth.toTypedArray())
            }
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun requiredBluetoothPermissions(): List<String> {
        val permissions = mutableListOf<String>()
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
            permissions += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_SCAN
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_ADVERTISE
        }
        return permissions
    }

    private fun missingBluetoothPermissions(): List<String> {
        return requiredBluetoothPermissions().filterNot(::hasPermission)
    }

    private fun maybeRequestNotificationPermission(forceRequest: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasPermission(Manifest.permission.POST_NOTIFICATIONS)) return
        if (forceRequest || !notificationPermissionRequested) {
            notificationPermissionRequested = true
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private fun isNotificationPermissionMissing(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPermission(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun handlePrimaryAction(state: BuddyUiState) {
        when {
            state.peripheralState == PeripheralState.PERMISSION_REQUIRED -> ensurePermissionsAndStart(forceRequest = true)
            state.peripheralState == PeripheralState.UNSUPPORTED -> requestPermissionRecovery()
            state.peripheralState == PeripheralState.ERROR -> BuddyPeripheralService.start(this)
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> BuddyPeripheralService.approveCurrentPermission(this)
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> BuddyPeripheralService.requestFocus(this)
            isNotificationPermissionMissing() -> maybeRequestNotificationPermission(forceRequest = true)
            state.displayMode == DisplayMode.DEMO -> BuddyPeripheralService.cycleDemoMascot(this)
            state.displayMode == DisplayMode.AGENT -> BuddyPeripheralService.requestFocus(this)
        }
    }

    private fun handleSecondaryAction(state: BuddyUiState) {
        when {
            state.peripheralState == PeripheralState.PERMISSION_REQUIRED -> ensurePermissionsAndStart(forceRequest = true)
            state.peripheralState == PeripheralState.UNSUPPORTED -> requestPermissionRecovery()
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> BuddyPeripheralService.denyCurrentPermission(this)
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> BuddyPeripheralService.skipCurrentQuestion(this)
            else -> BuddyPeripheralService.toggleDemo(this)
        }
    }

    private fun requestPermissionRecovery() {
        val missingBluetooth = missingBluetoothPermissions()
        if (missingBluetooth.isNotEmpty()) {
            BuddyRepository.onPermissionsMissing("重新发起权限申请: ${missingBluetooth.joinToString()}")
            recoveryPermissionRequested = true
            bluetoothPermissionLauncher.launch(missingBluetooth.toTypedArray())
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasPermission(Manifest.permission.POST_NOTIFICATIONS)) {
            BuddyRepository.onPermissionsMissing("需要通知权限，手表才能弹出审批提醒。")
            maybeRequestNotificationPermission(forceRequest = true)
            return
        }

        BuddyRepository.onPermissionsMissing("权限已授予，但系统仍未开放 BLE 外设广播。即将打开应用设置页，请确认“附近设备/蓝牙”相关权限。")
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        }
        appSettingsLauncher.launch(intent)
    }

    private fun handleSwipe(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touchDownX = event.x
                touchDownY = event.y
            }

            MotionEvent.ACTION_UP -> {
                val state = BuddyRepository.uiState.value
                if (state.messages.size <= 1) return false

                val deltaX = event.x - touchDownX
                val deltaY = event.y - touchDownY
                val threshold = ViewConfiguration.get(this).scaledTouchSlop * 4
                if (abs(deltaX) > threshold && abs(deltaX) > abs(deltaY) * 1.3f) {
                    if (deltaX < 0) {
                        BuddyRepository.showNextMessage()
                    } else {
                        BuddyRepository.showPreviousMessage()
                    }
                    return true
                }
            }
        }
        return false
    }

    private fun missingPermissionsDetail(): String {
        val missing = buildList {
            addAll(missingBluetoothPermissions())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !hasPermission(Manifest.permission.POST_NOTIFICATIONS)) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        return if (missing.isEmpty()) {
            "权限已授予，正在启动 BLE 服务"
        } else {
            "缺少权限: ${missing.joinToString()}"
        }
    }

    private fun render(state: BuddyUiState) {
        val issueScreen = state.peripheralState in issueStates
        val onboardingScreen = !issueScreen && state.displayMode == DisplayMode.STANDBY
        val mascotScreen = !issueScreen && !onboardingScreen
        val toolLabel = toolLabel(state)
        val workspaceLabel = workspaceLabel(state)
        val messagePreview = currentMessage(state)
        val detailPreview = detailPreview(state, messagePreview)
        val aggregateWaitingDetail = aggregateWaitingDetail(state)
        val showWaitingDetail = aggregateWaitingDetail != null

        binding.rootContainer.rotation = if (state.orientation == ScreenOrientation.DOWN) 180f else 0f
        applyBrightness(state.brightnessPercent)

        binding.statusIndicator.backgroundTintList = ColorStateList.valueOf(statusIndicatorColor(state))
        binding.sceneChip.text = "DEMO"
        binding.mascotView.render(state.mascot, state.displayMode, state.agentStatus)
        binding.mascotName.text = state.mascot.title
        binding.statusTitle.text = statusTitle()
        binding.statusDetail.text = statusDetail(state)
        binding.connectionChip.text = connectionLabel(state)

        binding.toolName.text = toolLabel.orEmpty()
        binding.workspaceName.text = workspaceLabel.orEmpty()
        binding.messageRoleChip.text = messageRoleLabel(state, messagePreview)
        binding.messageText.text = (aggregateWaitingDetail ?: detailPreview).orEmpty()
        binding.messagePager.text = messagePagerLabel(state)
        binding.actionPrimary.text = primaryActionLabel(state).orEmpty()
        binding.actionSecondary.text = secondaryActionLabel(state).orEmpty()
        binding.hintText.text = hintMessage(state)
        binding.diagnosticText.text = diagnosticMessage(state)

        binding.statusTitle.isVisible = onboardingScreen || issueScreen
        binding.statusDetail.isVisible = onboardingScreen || issueScreen
        binding.diagnosticText.isVisible = onboardingScreen || issueScreen
        binding.connectionChip.isVisible = onboardingScreen
        binding.hintText.isVisible = onboardingScreen || issueScreen
        binding.sceneChip.isVisible = state.displayMode == DisplayMode.DEMO && mascotScreen
        binding.mascotView.isVisible = mascotScreen
        binding.mascotName.isVisible = mascotScreen
        binding.workspaceName.isVisible = mascotScreen && !workspaceLabel.isNullOrBlank()
        binding.toolName.isVisible = mascotScreen && !toolLabel.isNullOrBlank()
        binding.messageRoleChip.isVisible = mascotScreen && detailPreview != null
        binding.messageText.isVisible = mascotScreen && detailPreview != null
        binding.messagePager.isVisible = mascotScreen && messagePreview != null && !showWaitingDetail
        binding.actionRow.isVisible = mascotScreen && primaryActionLabel(state) != null && secondaryActionLabel(state) != null

        tintView(binding.sceneChip, 0xFF3C3C46.toInt(), 220)
        tintView(binding.connectionChip, connectionAccent(state), 160)
        tintView(binding.workspaceName, state.mascot.accentColor, 144)
        tintView(binding.messageRoleChip, state.mascot.accentColor, 176)
        tintView(binding.messagePager, 0xFF3C3C46.toInt(), 180)
        tintView(binding.actionPrimary, state.mascot.accentColor, 210)
        tintView(binding.actionSecondary, 0xFF3C3C46.toInt(), 220)

        if (state.focusPulseToken != lastPulseToken) {
            lastPulseToken = state.focusPulseToken
            binding.mascotView.animate()
                .scaleX(1.08f)
                .scaleY(1.08f)
                .setDuration(120)
                .withEndAction {
                    binding.mascotView.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(160)
                        .start()
                }
                .start()
        }
    }

    private fun applyBrightness(percent: Int) {
        val params = window.attributes
        params.screenBrightness = (percent.coerceIn(10, 100) / 100f)
        window.attributes = params
    }

    private fun connectionLabel(state: BuddyUiState): String {
        return if (state.peripheralState == PeripheralState.CONNECTED) {
            "Bluetooth connected"
        } else {
            "Waiting for Buddy..."
        }
    }

    private fun statusTitle(): String {
        return "Buddy"
    }

    private fun statusDetail(state: BuddyUiState): String {
        return when (state.peripheralState) {
            PeripheralState.STARTING -> "Checking Bluetooth..."
            PeripheralState.PERMISSION_REQUIRED -> "Nearby devices permission"
            PeripheralState.BLUETOOTH_OFF -> "Bluetooth is off"
            PeripheralState.UNSUPPORTED -> "BLE peripheral unavailable"
            PeripheralState.ERROR -> "Buddy start failed"
            else -> when {
                state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> "Approval needed"
                state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> "Question waiting"
                isNotificationPermissionMissing() -> "Notifications are off"
                else -> Build.MODEL?.takeIf { it.isNotBlank() } ?: "Android Watch"
            }
        }
    }

    private fun hintMessage(state: BuddyUiState): String {
        return when (state.peripheralState) {
            PeripheralState.STARTING -> "Checking BLE status"
            PeripheralState.PERMISSION_REQUIRED -> "Tap to request permissions again"
            PeripheralState.BLUETOOTH_OFF -> "Turn on Bluetooth, then reopen Buddy"
            PeripheralState.UNSUPPORTED -> "Tap to retry permission recovery"
            PeripheralState.ERROR -> "Tap to restart Buddy"
            else -> when {
                state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> "Use buttons to approve or deny"
                state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> "Use buttons to open or skip"
                state.messages.size > 1 -> "Swipe: messages · Hold: demo"
                isNotificationPermissionMissing() -> "Tap to enable notifications"
                state.displayMode == DisplayMode.AGENT -> "Tap: focus Mac · Hold: demo"
                else -> "Long press: demo"
            }
        }
    }

    private fun diagnosticMessage(state: BuddyUiState): String {
        return if (state.peripheralState in issueStates) {
            state.diagnosticMessage ?: state.errorMessage ?: "Bluetooth diagnostics unavailable"
        } else {
            "Open CodeIsland\nSettings > Buddy\nConnect by Bluetooth"
        }
    }

    private fun connectionAccent(state: BuddyUiState): Int {
        return if (state.peripheralState == PeripheralState.CONNECTED) 0xFF32E6B9.toInt() else 0xFF3C3C46.toInt()
    }

    private fun statusIndicatorColor(state: BuddyUiState): Int {
        return if (state.peripheralState == PeripheralState.CONNECTED) 0xFF32E6B9.toInt() else 0xFF64646F.toInt()
    }

    private fun toolLabel(state: BuddyUiState): String? {
        if (state.displayMode != DisplayMode.AGENT) return null
        return when (state.agentStatus) {
            AgentStatusCode.PROCESSING,
            AgentStatusCode.RUNNING,
            AgentStatusCode.WAITING_APPROVAL,
            AgentStatusCode.WAITING_QUESTION -> state.toolName?.takeIf { it.isNotBlank() }
            else -> null
        }
    }

    private fun workspaceLabel(state: BuddyUiState): String? {
        return state.workspaceName?.takeIf { it.isNotBlank() && state.displayMode == DisplayMode.AGENT }
    }

    private fun currentMessage(state: BuddyUiState): WatchMessagePreview? {
        if (state.displayMode != DisplayMode.AGENT) return null
        val messages = state.messages.sortedBy { it.index }
        if (messages.isEmpty()) return null
        return messages.firstOrNull { it.index == state.selectedMessageSlot } ?: messages.last()
    }

    private fun detailPreview(state: BuddyUiState, messagePreview: WatchMessagePreview?): String? {
        if (state.displayMode != DisplayMode.AGENT) return null
        val waitingApproval = state.agentStatus == AgentStatusCode.WAITING_APPROVAL
        val waitingQuestion = state.agentStatus == AgentStatusCode.WAITING_QUESTION
        if (!waitingApproval && !waitingQuestion) return messagePreview?.text?.takeIf { it.isNotBlank() }

        val parts = linkedSetOf<String>()
        if (waitingApproval) {
            messagePreview?.text?.takeIf { it.isNotBlank() }?.let(parts::add)
            state.workspaceName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Workspace: $it") }
        } else {
            messagePreview?.text?.takeIf { it.isNotBlank() }?.let(parts::add)
            state.toolName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Action: $it") }
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString("\n")
    }

    private fun aggregateWaitingDetail(state: BuddyUiState): String? {
        val waiting = state.displayMode == DisplayMode.AGENT &&
            (state.agentStatus == AgentStatusCode.WAITING_APPROVAL || state.agentStatus == AgentStatusCode.WAITING_QUESTION)
        if (!waiting) return null

        return state.messages
            .sortedBy { it.index }
            .mapNotNull { it.text.takeIf(String::isNotBlank) }
            .distinct()
            .takeIf { it.isNotEmpty() }
            ?.joinToString("")
    }

    private fun messageRoleLabel(state: BuddyUiState, messagePreview: WatchMessagePreview?): String {
        return when {
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> "APPROVAL"
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> "QUESTION"
            messagePreview?.isUser == true -> "YOU"
            else -> state.mascot.title.uppercase()
        }
    }

    private fun messagePagerLabel(state: BuddyUiState): String {
        val messages = state.messages.sortedBy { it.index }
        if (messages.isEmpty()) return ""
        val currentIndex = messages.indexOfFirst { it.index == state.selectedMessageSlot }
            .takeIf { it >= 0 }
            ?: (messages.size - 1)
        return "${currentIndex + 1} / ${messages.size}"
    }

    private fun primaryActionLabel(state: BuddyUiState): String? {
        return when {
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> "Allow"
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> "Open"
            else -> null
        }
    }

    private fun secondaryActionLabel(state: BuddyUiState): String? {
        return when {
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_APPROVAL -> "Deny"
            state.displayMode == DisplayMode.AGENT && state.agentStatus == AgentStatusCode.WAITING_QUESTION -> "Skip"
            else -> null
        }
    }

    private fun tintView(view: TextView, color: Int, alpha: Int) {
        view.backgroundTintList = ColorStateList.valueOf(ColorUtils.setAlphaComponent(color, alpha))
    }

    companion object {
        private val issueStates = setOf(
            PeripheralState.STARTING,
            PeripheralState.PERMISSION_REQUIRED,
            PeripheralState.BLUETOOTH_OFF,
            PeripheralState.UNSUPPORTED,
            PeripheralState.ERROR,
        )
    }
}
