package com.codeisland.buddywatch

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

internal enum class HostUplinkDeliveryMode {
    NOTIFICATION,
    INDICATION,
}

private val cccEnableNotificationValue = byteArrayOf(0x01, 0x00)
private val cccEnableIndicationValue = byteArrayOf(0x02, 0x00)
private val cccDisableValue = byteArrayOf(0x00, 0x00)

internal fun hostUplinkDeliveryModeForDescriptorValue(value: ByteArray): HostUplinkDeliveryMode? {
    return when {
        value.contentEquals(cccEnableNotificationValue) -> HostUplinkDeliveryMode.NOTIFICATION
        value.contentEquals(cccEnableIndicationValue) -> HostUplinkDeliveryMode.INDICATION
        else -> null
    }
}

internal fun cccDescriptorValueFor(mode: HostUplinkDeliveryMode?): ByteArray {
    return when (mode) {
        HostUplinkDeliveryMode.NOTIFICATION -> cccEnableNotificationValue.copyOf()
        HostUplinkDeliveryMode.INDICATION -> cccEnableIndicationValue.copyOf()
        null -> cccDisableValue.copyOf()
    }
}

class BuddyPeripheralService : Service() {
    private var bluetoothManager: BluetoothManager? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var gattServer: BluetoothGattServer? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var connectedDevice: BluetoothDevice? = null
    private val subscribedDeviceDeliveryModes = linkedMapOf<String, HostUplinkDeliveryMode>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastAttentionKey: String? = null
    private var lastAttentionAtMs: Long = 0L
    private val attentionNotificationRunnable = Runnable { postAttentionNotificationIfNeeded() }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_ON -> startPeripheral()
                BluetoothAdapter.STATE_OFF,
                BluetoothAdapter.STATE_TURNING_OFF -> {
                    stopPeripheral()
                    BuddyRepository.onBluetoothOff()
                    refreshNotification()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        bluetoothManager = getSystemService(BluetoothManager::class.java)
        BuddyRepository.onStarting("服务已启动，准备检查权限与 BLE 状态…")
        createNotificationChannel()
        startForeground(notificationId, buildNotification(getString(R.string.notification_waiting)))
        registerReceiver(bluetoothStateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        startPeripheral()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_REQUEST_FOCUS -> notifyHostFocusRequest()
            ACTION_TOGGLE_DEMO -> BuddyRepository.toggleDemoMode()
            ACTION_CYCLE_DEMO -> BuddyRepository.cycleDemoMascot()
            ACTION_APPROVE_CURRENT_PERMISSION -> notifyHostControl(BleProtocol.approveCurrentPermissionMarker)
            ACTION_DENY_CURRENT_PERMISSION -> notifyHostControl(BleProtocol.denyCurrentPermissionMarker)
            ACTION_SKIP_CURRENT_QUESTION -> notifyHostControl(BleProtocol.skipCurrentQuestionMarker)
            else -> startPeripheral()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(attentionNotificationRunnable)
        unregisterReceiver(bluetoothStateReceiver)
        stopPeripheral()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startPeripheral() {
        val manager = bluetoothManager
        val adapter = manager?.adapter
        val baseDiagnostics = buildDiagnostics(manager, adapter)
        BuddyRepository.onStarting("开始检查手表蓝牙能力…\n$baseDiagnostics")
        val advertiseSupportWarning = if (adapter?.isMultipleAdvertisementSupported == false) {
            "系统报告 `isMultipleAdvertisementSupported=false`，但仍继续尝试启动广播。"
        } else {
            null
        }

        if (!hasRequiredPermissions()) {
            stopPeripheral()
            BuddyRepository.onPermissionsMissing(missingPermissionsDetail())
            refreshNotification()
            return
        }

        val resolvedManager = manager ?: run {
            BuddyRepository.onUnsupported("无法获取蓝牙管理器", baseDiagnostics)
            refreshNotification()
            return
        }
        val resolvedAdapter = adapter ?: run {
            stopPeripheral()
            BuddyRepository.onUnsupported("当前设备不支持蓝牙", baseDiagnostics)
            refreshNotification()
            return
        }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)) {
            stopPeripheral()
            BuddyRepository.onUnsupported(
                "当前设备不支持 BLE 外设模式",
                buildDiagnostics(resolvedManager, resolvedAdapter),
            )
            refreshNotification()
            return
        }
        if (!resolvedAdapter.isEnabled) {
            stopPeripheral()
            BuddyRepository.onBluetoothOff(buildDiagnostics(resolvedManager, resolvedAdapter))
            refreshNotification()
            return
        }
        val bleAdvertiser = resolvedAdapter.bluetoothLeAdvertiser ?: run {
            stopPeripheral()
            BuddyRepository.onUnsupported(
                "当前手表不支持 BLE 广播",
                listOfNotNull(
                    buildDiagnostics(resolvedManager, resolvedAdapter),
                    advertiseSupportWarning,
                    "系统未向应用暴露 `BluetoothLeAdvertiser`。",
                ).joinToString("\n"),
            )
            refreshNotification()
            return
        }

        advertiser = bleAdvertiser
        ensureGattServer(resolvedManager)
        startAdvertising(bleAdvertiser, advertiseSupportWarning)
    }

    private fun ensureGattServer(manager: BluetoothManager) {
        if (gattServer != null) return
        gattServer = manager.openGattServer(this, gattServerCallback)
        val server = gattServer
        if (server == null) {
            BuddyRepository.onError(
                "BLE GATT 服务启动失败",
                buildDiagnostics(manager, manager.adapter),
            )
            return
        }
        server.addService(buildGattService())
    }

    private fun buildGattService(): BluetoothGattService {
        val service = BluetoothGattService(
            BleProtocol.serviceUuid,
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        )

        val writeCharacteristic = BluetoothGattCharacteristic(
            BleProtocol.writeCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )

        val notifyCharacteristic = BluetoothGattCharacteristic(
            BleProtocol.notifyCharacteristicUuid,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE,
            BluetoothGattCharacteristic.PERMISSION_READ,
        ).apply {
            addDescriptor(
                BluetoothGattDescriptor(
                    BleProtocol.cccDescriptorUuid,
                    BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
                )
            )
        }
        this.notifyCharacteristic = notifyCharacteristic

        service.addCharacteristic(writeCharacteristic)
        service.addCharacteristic(notifyCharacteristic)
        return service
    }

    private fun startAdvertising(
        bleAdvertiser: BluetoothLeAdvertiser,
        advertiseSupportWarning: String?,
    ) {
        bleAdvertiser.stopAdvertising(advertiseCallback)

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(BleProtocol.serviceUuid))
            .build()

        pendingAdvertiseWarning = advertiseSupportWarning
        bleAdvertiser.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopPeripheral() {
        clearAttentionNotification()
        advertiser?.stopAdvertising(advertiseCallback)
        advertiser = null
        connectedDevice = null
        subscribedDeviceDeliveryModes.clear()
        notifyCharacteristic = null
        gattServer?.close()
        gattServer = null
    }

    private fun notifyHostFocusRequest() {
        BuddyRepository.noteFocusRequest()

        notifyHostPayload(byteArrayOf(BuddyRepository.uiState.value.mascot.wireId.toByte()))
    }

    private fun notifyHostControl(marker: Int) {
        BuddyRepository.noteFocusRequest()
        notifyHostPayload(
            payload = byteArrayOf(marker.toByte()),
            successMessage = when (marker) {
                BleProtocol.approveCurrentPermissionMarker -> "已从手表发送允许操作，请在 Mac 端查看审批结果。"
                BleProtocol.denyCurrentPermissionMarker -> "已从手表发送拒绝操作，请在 Mac 端查看审批结果。"
                BleProtocol.skipCurrentQuestionMarker -> "已从手表发送跳过操作，请在 Mac 端查看结果。"
                else -> "已从手表发送操作，请在 Mac 端查看审批结果。"
            },
            clearAttentionOnSuccess = true,
        )
    }

    private fun clearAttentionNotification() {
        mainHandler.removeCallbacks(attentionNotificationRunnable)
        lastAttentionKey = null
        lastAttentionAtMs = 0L
        getSystemService(NotificationManager::class.java)?.cancel(attentionNotificationId)
    }

    private fun notifyHostPayload(
        payload: ByteArray,
        successMessage: String = "已从手表发送操作，请在 Mac 端查看审批结果。",
        clearAttentionOnSuccess: Boolean = false,
        remainingAttempts: Int = 2,
    ) {
        val device = connectedDevice
        if (device == null) {
            BuddyRepository.noteHostActionResult("手表操作未发送：Mac 还没有连接到 Buddy。")
            return
        }
        val deliveryMode = subscribedDeviceDeliveryModes[device.address]
        if (deliveryMode == null) {
            BuddyRepository.noteHostActionResult("手表操作未发送：Mac 尚未订阅 Buddy 上行通知。")
            return
        }
        val server = gattServer
        if (server == null) {
            BuddyRepository.noteHostActionResult("手表操作未发送：本地 GATT 服务未就绪。")
            return
        }
        val characteristic = notifyCharacteristic
        if (characteristic == null) {
            BuddyRepository.noteHostActionResult("手表操作未发送：上行特征未初始化。")
            return
        }

        @Suppress("DEPRECATION")
        run {
            characteristic.value = payload
        }
        val requireConfirmation = deliveryMode == HostUplinkDeliveryMode.INDICATION
        val sent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            server.notifyCharacteristicChanged(device, characteristic, requireConfirmation, payload) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            server.notifyCharacteristicChanged(device, characteristic, requireConfirmation)
        }

        if (sent) {
            if (clearAttentionOnSuccess) {
                clearAttentionNotification()
            }
            BuddyRepository.noteHostActionResult(successMessage)
            return
        }

        if (remainingAttempts > 0) {
            mainHandler.postDelayed(
                {
                    notifyHostPayload(
                        payload = payload,
                        successMessage = successMessage,
                        clearAttentionOnSuccess = clearAttentionOnSuccess,
                        remainingAttempts = remainingAttempts - 1,
                    )
                },
                120L,
            )
            return
        }

        BuddyRepository.noteHostActionResult("手表操作发送失败：Buddy 已连接，但上行通知未成功送达 Mac。")
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
            return hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return hasPermission(Manifest.permission.BLUETOOTH_SCAN) &&
            hasPermission(Manifest.permission.BLUETOOTH_CONNECT) &&
            hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            notificationChannelId,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        val alertChannel = NotificationChannel(
            alertNotificationChannelId,
            getString(R.string.notification_alert_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = getString(R.string.notification_alert_channel_description)
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
        manager.createNotificationChannel(alertChannel)
    }

    private fun buildNotification(content: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, notificationChannelId)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_notification_buddy)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun refreshNotification() {
        val label = BuddyRepository.uiState.value.connectedDeviceName?.let { "已连接 $it" }
            ?: BuddyRepository.uiState.value.peripheralState.label
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(notificationId, buildNotification(label))
    }

    private fun scheduleAttentionNotificationRefresh() {
        mainHandler.removeCallbacks(attentionNotificationRunnable)
        mainHandler.postDelayed(attentionNotificationRunnable, attentionNotificationDebounceMs)
    }

    private fun postAttentionNotificationIfNeeded() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val state = BuddyRepository.uiState.value
        val status = state.agentStatus
        val attentionKey = when {
            state.displayMode == DisplayMode.AGENT &&
                (status == AgentStatusCode.WAITING_APPROVAL || status == AgentStatusCode.WAITING_QUESTION) -> {
                listOf(
                    status.wireId.toString(),
                    state.mascot.wireId.toString(),
                    state.toolName.orEmpty().trim(),
                    state.workspaceName.orEmpty().trim(),
                    state.messages.size.toString(),
                    state.messages.sortedBy { it.index }.joinToString(separator = "") { it.text },
                ).joinToString("|")
            }

            else -> null
        }

        if (attentionKey == null) {
            clearAttentionNotification()
            return
        }

        val now = SystemClock.elapsedRealtime()
        val shouldRepeatReminder =
            attentionKey == lastAttentionKey && now - lastAttentionAtMs >= attentionReminderIntervalMs
        if (attentionKey == lastAttentionKey && !shouldRepeatReminder) return

        lastAttentionKey = attentionKey
        lastAttentionAtMs = now
        vibrateAttentionIfNeeded(status, repeat = shouldRepeatReminder)

        if (!canPostUserNotifications()) return

        val titleRes = if (status == AgentStatusCode.WAITING_APPROVAL) {
            R.string.notification_attention_title_approval
        } else {
            R.string.notification_attention_title_question
        }
        val message = attentionContent(state)

        manager.notify(
            attentionNotificationId,
            buildAttentionNotification(
                title = getString(titleRes),
                content = message,
            ),
        )
    }

    private fun canPostUserNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || hasPermission(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun attentionContent(state: BuddyUiState): String {
        val fullMessage = state.messages
            .sortedBy { it.index }
            .mapNotNull { it.text.takeIf(String::isNotBlank) }
            .distinct()
            .joinToString(separator = "")
            .takeIf { it.isNotBlank() }

        val parts = linkedSetOf<String>()
        when (state.agentStatus) {
            AgentStatusCode.WAITING_QUESTION -> {
                fullMessage?.let(parts::add)
                state.toolName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Action: $it") }
                state.workspaceName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Workspace: $it") }
            }

            AgentStatusCode.WAITING_APPROVAL -> {
                state.toolName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Tool: $it") }
                fullMessage?.let(parts::add)
                state.workspaceName?.trim()?.takeIf { it.isNotBlank() }?.let { parts.add("Workspace: $it") }
            }

            else -> Unit
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString("\n")
            ?: getString(R.string.notification_attention_fallback_message)
    }

    private fun vibrateAttentionIfNeeded(status: AgentStatusCode, repeat: Boolean) {
        if (status != AgentStatusCode.WAITING_APPROVAL) return

        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        } ?: return

        if (!vibrator.hasVibrator()) return

        val pattern = if (repeat) longArrayOf(0, 120, 60, 180) else longArrayOf(0, 180, 80, 260)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }
    }

    private fun buildAttentionNotification(title: String, content: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val state = BuddyRepository.uiState.value
        val primaryActionIntent = when (state.agentStatus) {
            AgentStatusCode.WAITING_APPROVAL -> servicePendingIntent(
                Intent(this, BuddyPeripheralService::class.java).setAction(ACTION_APPROVE_CURRENT_PERMISSION),
                requestCode = 2,
            )
            AgentStatusCode.WAITING_QUESTION -> contentIntent
            else -> contentIntent
        }
        val secondaryActionIntent = when (state.agentStatus) {
            AgentStatusCode.WAITING_APPROVAL -> servicePendingIntent(
                Intent(this, BuddyPeripheralService::class.java).setAction(ACTION_DENY_CURRENT_PERMISSION),
                requestCode = 3,
            )
            AgentStatusCode.WAITING_QUESTION -> servicePendingIntent(
                Intent(this, BuddyPeripheralService::class.java).setAction(ACTION_SKIP_CURRENT_QUESTION),
                requestCode = 4,
            )
            else -> contentIntent
        }

        return NotificationCompat.Builder(this, alertNotificationChannelId)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setSmallIcon(R.drawable.ic_notification_buddy)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setTicker(title)
            .addAction(
                0,
                if (state.agentStatus == AgentStatusCode.WAITING_APPROVAL) getString(R.string.notification_action_approve) else getString(R.string.notification_action_open),
                primaryActionIntent,
            )
            .addAction(
                0,
                if (state.agentStatus == AgentStatusCode.WAITING_APPROVAL) getString(R.string.notification_action_deny) else getString(R.string.notification_action_skip),
                secondaryActionIntent,
            )
            .build()
    }

    private fun servicePendingIntent(intent: Intent, requestCode: Int = 2): PendingIntent {
        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private var pendingAdvertiseWarning: String? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            BuddyRepository.onAdvertisingReady(
                listOfNotNull(
                    buildDiagnostics(bluetoothManager, bluetoothManager?.adapter),
                    pendingAdvertiseWarning,
                    "广播已启动，等待 Mac 扫描",
                ).joinToString("\n"),
            )
            pendingAdvertiseWarning = null
            refreshNotification()
        }

        override fun onStartFailure(errorCode: Int) {
            BuddyRepository.onError(
                "BLE 广播失败：$errorCode",
                listOfNotNull(
                    buildDiagnostics(bluetoothManager, bluetoothManager?.adapter),
                    pendingAdvertiseWarning,
                    "广播失败码: $errorCode",
                ).joinToString("\n"),
            )
            pendingAdvertiseWarning = null
            refreshNotification()
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                connectedDevice = device
                BuddyRepository.onDeviceConnected(
                    deviceName(device),
                    buildDiagnostics(bluetoothManager, bluetoothManager?.adapter) + "\n已连接主机: ${deviceName(device)}",
                )
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                if (connectedDevice?.address == device.address) {
                    connectedDevice = null
                }
                subscribedDeviceDeliveryModes.remove(device.address)
                BuddyRepository.onDeviceDisconnected(
                    buildDiagnostics(bluetoothManager, bluetoothManager?.adapter) + "\n主机已断开，继续等待扫描",
                )
            }
            refreshNotification()
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (characteristic.uuid == BleProtocol.writeCharacteristicUuid) {
                BuddyFrameParser.parse(value)?.let { command ->
                    BuddyRepository.onCommand(command)
                    if (
                        command is IncomingCommand.AgentFrame ||
                        command is IncomingCommand.WorkspaceFrame ||
                        command is IncomingCommand.MessagePreviewFrame
                    ) {
                        scheduleAttentionNotificationRefresh()
                    }
                    refreshNotification()
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            if (descriptor.uuid == BleProtocol.cccDescriptorUuid) {
                val enabled = cccDescriptorValueFor(subscribedDeviceDeliveryModes[device.address])
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, enabled)
            } else {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, offset, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (descriptor.uuid == BleProtocol.cccDescriptorUuid) {
                when {
                    value.contentEquals(cccDisableValue) -> {
                        subscribedDeviceDeliveryModes.remove(device.address)
                    }

                    else -> {
                        hostUplinkDeliveryModeForDescriptorValue(value)?.let { mode ->
                            subscribedDeviceDeliveryModes[device.address] = mode
                        }
                    }
                }
                @Suppress("DEPRECATION")
                run {
                    descriptor.value = value
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }
    }

    private fun deviceName(device: BluetoothDevice): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            device.address
        } else {
            device.name?.takeIf { it.isNotBlank() } ?: device.address
        }
    }

    private fun missingPermissionsDetail(): String {
        val missing = buildList {
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
                if (!hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)) add("ACCESS_FINE_LOCATION")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (!hasPermission(Manifest.permission.BLUETOOTH_SCAN)) add("BLUETOOTH_SCAN")
                if (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) add("BLUETOOTH_CONNECT")
                if (!hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)) add("BLUETOOTH_ADVERTISE")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (!hasPermission(Manifest.permission.POST_NOTIFICATIONS)) add("POST_NOTIFICATIONS")
            }
        }
        return if (missing.isEmpty()) {
            buildDiagnostics(bluetoothManager, bluetoothManager?.adapter)
        } else {
            "缺少权限: ${missing.joinToString()}\n${buildDiagnostics(bluetoothManager, bluetoothManager?.adapter)}"
        }
    }

    private fun buildDiagnostics(manager: BluetoothManager?, adapter: BluetoothAdapter?): String {
        val name = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasPermission(Manifest.permission.BLUETOOTH_CONNECT)) {
            "未授权"
        } else {
            adapter?.name?.takeIf { it.isNotBlank() } ?: "未知"
        }
        val permissionSummary = buildList {
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
                add("LOC=${hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)}")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                add("SCAN=${hasPermission(Manifest.permission.BLUETOOTH_SCAN)}")
                add("CONNECT=${hasPermission(Manifest.permission.BLUETOOTH_CONNECT)}")
                add("ADV_PERM=${hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)}")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add("NOTIFY=${hasPermission(Manifest.permission.POST_NOTIFICATIONS)}")
            }
        }.joinToString(" · ")
        val bluetoothOn = adapter?.isEnabled?.toString() ?: "false"
        val leSupported = packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE)
        val advSupported = adapter?.isMultipleAdvertisementSupported?.toString() ?: "false"
        val advertiserReady = (adapter?.bluetoothLeAdvertiser != null).toString()
        val sdk = Build.VERSION.SDK_INT
        val managerReady = (manager != null).toString()
        return "SDK=$sdk · 管理器=$managerReady · 蓝牙=$bluetoothOn · LE=$leSupported · ADV=$advSupported · Advertiser=$advertiserReady · $permissionSummary · 名称=$name"
    }

    companion object {
        private const val notificationChannelId = "buddy_watch_bridge"
        private const val alertNotificationChannelId = "buddy_watch_attention"
        private const val notificationId = 1001
        private const val attentionNotificationId = 1002
        private const val attentionNotificationDebounceMs = 250L
        private const val attentionReminderIntervalMs = 30_000L
        const val ACTION_REQUEST_FOCUS = "com.codeisland.buddywatch.action.REQUEST_FOCUS"
        const val ACTION_TOGGLE_DEMO = "com.codeisland.buddywatch.action.TOGGLE_DEMO"
        const val ACTION_CYCLE_DEMO = "com.codeisland.buddywatch.action.CYCLE_DEMO"
        const val ACTION_APPROVE_CURRENT_PERMISSION = "com.codeisland.buddywatch.action.APPROVE_CURRENT_PERMISSION"
        const val ACTION_DENY_CURRENT_PERMISSION = "com.codeisland.buddywatch.action.DENY_CURRENT_PERMISSION"
        const val ACTION_SKIP_CURRENT_QUESTION = "com.codeisland.buddywatch.action.SKIP_CURRENT_QUESTION"

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, BuddyPeripheralService::class.java))
        }

        fun requestFocus(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_REQUEST_FOCUS),
            )
        }

        fun toggleDemo(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_TOGGLE_DEMO),
            )
        }

        fun cycleDemoMascot(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_CYCLE_DEMO),
            )
        }

        fun approveCurrentPermission(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_APPROVE_CURRENT_PERMISSION),
            )
        }

        fun denyCurrentPermission(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_DENY_CURRENT_PERMISSION),
            )
        }

        fun skipCurrentQuestion(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, BuddyPeripheralService::class.java).setAction(ACTION_SKIP_CURRENT_QUESTION),
            )
        }
    }
}
