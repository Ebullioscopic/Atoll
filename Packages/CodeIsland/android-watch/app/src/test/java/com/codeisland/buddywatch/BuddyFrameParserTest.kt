package com.codeisland.buddywatch

import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BuddyFrameParserTest {
    @Test
    fun `parse agent frame with tool name`() {
        val payload = byteArrayOf(5, 2, 4) + "Read".encodeToByteArray()

        val result = BuddyFrameParser.parse(payload)

        assertEquals(
            IncomingCommand.AgentFrame(mascotId = 5, statusId = 2, toolName = "Read"),
            result,
        )
    }

    @Test
    fun `clamp brightness frame`() {
        val result = BuddyFrameParser.parse(byteArrayOf(0xFE.toByte(), 0x01))

        assertEquals(IncomingCommand.Brightness(BleProtocol.minBrightnessPercent), result)
    }

    @Test
    fun `parse orientation frame`() {
        val result = BuddyFrameParser.parse(byteArrayOf(0xFD.toByte(), 0x01))

        assertEquals(IncomingCommand.Orientation(1), result)
    }

    @Test
    fun `parse workspace frame`() {
        val payload = byteArrayOf(0xFC.toByte(), 4) + "proj".encodeToByteArray()

        val result = BuddyFrameParser.parse(payload)

        assertEquals(IncomingCommand.WorkspaceFrame("proj"), result)
    }

    @Test
    fun `parse assistant message preview frame`() {
        val payload = byteArrayOf(0xFB.toByte(), 1, 3, 5) + "hello".encodeToByteArray()

        val result = BuddyFrameParser.parse(payload)

        assertEquals(
            IncomingCommand.MessagePreviewFrame(index = 1, total = 3, isUser = false, text = "hello"),
            result,
        )
    }

    @Test
    fun `parse user message preview frame`() {
        val payload = byteArrayOf(0xFB.toByte(), 0, 2, 0x84.toByte()) + "plan".encodeToByteArray()

        val result = BuddyFrameParser.parse(payload)

        assertEquals(
            IncomingCommand.MessagePreviewFrame(index = 0, total = 2, isUser = true, text = "plan"),
            result,
        )
    }

    @Test
    fun `reject incomplete payload`() {
        assertNull(BuddyFrameParser.parse(byteArrayOf(1, 2)))
    }

    @Test
    fun `map ccc descriptor value to notification mode`() {
        assertEquals(
            HostUplinkDeliveryMode.NOTIFICATION,
            hostUplinkDeliveryModeForDescriptorValue(byteArrayOf(0x01, 0x00)),
        )
    }

    @Test
    fun `map ccc descriptor value to indication mode`() {
        assertEquals(
            HostUplinkDeliveryMode.INDICATION,
            hostUplinkDeliveryModeForDescriptorValue(byteArrayOf(0x02, 0x00)),
        )
    }

    @Test
    fun `emit indication ccc value for indication mode`() {
        val value = cccDescriptorValueFor(HostUplinkDeliveryMode.INDICATION)

        assertTrue(value.contentEquals(byteArrayOf(0x02, 0x00)))
    }

    @Test
    fun `claude accent color matches mac mascot palette`() {
        assertEquals(0xFFDE886D.toInt(), Mascot.CLAUDE.accentColor)
    }

    @Test
    fun `trae accent color matches mac mascot palette`() {
        assertEquals(0xFF22C55E.toInt(), Mascot.TRAE.accentColor)
    }

    @Test
    fun `codex accent color matches mac mascot palette`() {
        assertEquals(0xFFEBEBED.toInt(), Mascot.CODEX.accentColor)
    }

    @Test
    fun `gemini accent color matches mac mascot palette`() {
        assertEquals(0xFF847ACE.toInt(), Mascot.GEMINI.accentColor)
    }

    @Test
    fun `copilot accent color matches mac mascot palette`() {
        assertEquals(0xFFCC3366.toInt(), Mascot.COPILOT.accentColor)
    }

    @Test
    fun `workbuddy accent color matches mac mascot palette`() {
        assertEquals(0xFF7961DE.toInt(), Mascot.WORKBUDDY.accentColor)
    }

    @Test
    fun `opencode accent color matches mac mascot palette`() {
        assertEquals(0xFF38383D.toInt(), Mascot.OPENCODE.accentColor)
    }

    @Test
    fun `hermes accent color matches mac mascot palette`() {
        assertEquals(0xFF7A58B0.toInt(), Mascot.HERMES.accentColor)
    }

    @Test
    fun `stepfun accent color matches mac mascot palette`() {
        assertEquals(0xFF2EBFB3.toInt(), Mascot.STEPFUN.accentColor)
    }
}
