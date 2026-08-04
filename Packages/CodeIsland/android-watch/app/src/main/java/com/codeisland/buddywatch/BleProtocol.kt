package com.codeisland.buddywatch

import java.nio.charset.StandardCharsets
import java.util.UUID

object BleProtocol {
    val serviceUuid: UUID = UUID.fromString("0000beef-0000-1000-8000-00805f9b34fb")
    val writeCharacteristicUuid: UUID = UUID.fromString("0000beef-0001-1000-8000-00805f9b34fb")
    val notifyCharacteristicUuid: UUID = UUID.fromString("0000beef-0002-1000-8000-00805f9b34fb")
    val cccDescriptorUuid: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    const val maxToolNameBytes = 17
    const val maxWorkspaceNameBytes = 18
    const val maxMessagePreviewBytes = 16
    const val brightnessFrameMarker = 0xFE
    const val orientationFrameMarker = 0xFD
    const val workspaceFrameMarker = 0xFC
    const val messagePreviewFrameMarker = 0xFB
    const val approveCurrentPermissionMarker = 0xF0
    const val denyCurrentPermissionMarker = 0xF1
    const val skipCurrentQuestionMarker = 0xF2
    const val minBrightnessPercent = 10
    const val maxBrightnessPercent = 100
    const val defaultBrightnessPercent = 70
    const val firmwareInactivityTimeoutMs = 60_000L
    const val demoCycleMs = 8_000L
}

sealed interface IncomingCommand {
    data class AgentFrame(
        val mascotId: Int,
        val statusId: Int,
        val toolName: String?
    ) : IncomingCommand

    data class WorkspaceFrame(val workspaceName: String?) : IncomingCommand

    data class MessagePreviewFrame(
        val index: Int,
        val total: Int,
        val isUser: Boolean,
        val text: String?
    ) : IncomingCommand

    data class Brightness(val percent: Int) : IncomingCommand
    data class Orientation(val wireValue: Int) : IncomingCommand
}

object BuddyFrameParser {
    fun parse(payload: ByteArray): IncomingCommand? {
        if (payload.isEmpty()) return null

        val marker = payload[0].toUByte().toInt()
        if (marker == BleProtocol.brightnessFrameMarker && payload.size >= 2) {
            return IncomingCommand.Brightness(clampBrightness(payload[1].toUByte().toInt()))
        }

        if (marker == BleProtocol.orientationFrameMarker && payload.size >= 2) {
            return IncomingCommand.Orientation(if (payload[1].toInt() == 1) 1 else 0)
        }

        if (marker == BleProtocol.workspaceFrameMarker && payload.size >= 2) {
            val declaredLength = payload[1].toUByte().toInt()
            val availableLength = (payload.size - 2).coerceAtLeast(0)
            val workspaceLength = minOf(declaredLength, availableLength, BleProtocol.maxWorkspaceNameBytes)
            val workspaceName = decodeString(payload, offset = 2, length = workspaceLength)
            return IncomingCommand.WorkspaceFrame(workspaceName)
        }

        if (marker == BleProtocol.messagePreviewFrameMarker && payload.size >= 4) {
            val index = payload[1].toUByte().toInt()
            val total = payload[2].toUByte().toInt()
            val flagLength = payload[3].toUByte().toInt()
            val isUser = (flagLength and 0x80) != 0
            val declaredLength = flagLength and 0x7F
            val availableLength = (payload.size - 4).coerceAtLeast(0)
            val textLength = minOf(declaredLength, availableLength, BleProtocol.maxMessagePreviewBytes)
            val text = decodeString(payload, offset = 4, length = textLength)
            return IncomingCommand.MessagePreviewFrame(index = index, total = total, isUser = isUser, text = text)
        }

        if (payload.size < 3) return null

        val mascotId = payload[0].toUByte().toInt()
        val statusId = payload[1].toUByte().toInt()
        val declaredToolLength = payload[2].toUByte().toInt()
        val availableLength = (payload.size - 3).coerceAtLeast(0)
        val toolLength = minOf(declaredToolLength, availableLength, BleProtocol.maxToolNameBytes)
        val toolName = decodeString(payload, offset = 3, length = toolLength)

        return IncomingCommand.AgentFrame(
            mascotId = mascotId,
            statusId = statusId,
            toolName = toolName
        )
    }

    private fun decodeString(payload: ByteArray, offset: Int, length: Int): String? {
        if (length <= 0) return null
        return String(payload, offset, length, StandardCharsets.UTF_8).trim().ifBlank { null }
    }

    private fun clampBrightness(value: Int): Int {
        return value.coerceIn(BleProtocol.minBrightnessPercent, BleProtocol.maxBrightnessPercent)
    }
}
