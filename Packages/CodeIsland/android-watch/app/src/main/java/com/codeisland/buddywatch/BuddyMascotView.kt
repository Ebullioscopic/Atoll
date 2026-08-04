package com.codeisland.buddywatch

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class BuddyMascotView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }

    private var displayMode: DisplayMode = DisplayMode.STANDBY
    private var agentStatus: AgentStatusCode = AgentStatusCode.IDLE
    private var mascot: Mascot = Mascot.CODEX
    private var startAtMs: Long = SystemClock.uptimeMillis()

    fun render(mascot: Mascot, displayMode: DisplayMode, agentStatus: AgentStatusCode) {
        val changed = this.mascot != mascot || this.displayMode != displayMode || this.agentStatus != agentStatus
        this.mascot = mascot
        this.displayMode = displayMode
        this.agentStatus = agentStatus
        if (changed) {
            startAtMs = SystemClock.uptimeMillis()
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return

        val t = (SystemClock.uptimeMillis() - startAtMs) / 1000f
        when (currentScene()) {
            Scene.SLEEP -> drawSleep(canvas, t)
            Scene.WORK -> drawWork(canvas, t)
            Scene.ALERT -> drawAlert(canvas, t)
        }

        if (isAttachedToWindow && visibility == VISIBLE) {
            postInvalidateOnAnimation()
        }
    }

    private fun currentScene(): Scene {
        return when (agentStatus) {
            AgentStatusCode.PROCESSING,
            AgentStatusCode.RUNNING -> Scene.WORK

            AgentStatusCode.WAITING_APPROVAL,
            AgentStatusCode.WAITING_QUESTION -> Scene.ALERT

            AgentStatusCode.IDLE -> if (displayMode == DisplayMode.DEMO) Scene.SLEEP else Scene.SLEEP
        }
    }

    private fun drawSleep(canvas: Canvas, t: Float) {
        when (mascot) {
            Mascot.CLAUDE -> drawClaudeSleep(canvas, t)
            Mascot.CODEX -> drawCodexSleep(canvas, t)
            Mascot.GEMINI -> drawGeminiSleep(canvas, t)
            Mascot.COPILOT -> drawCopilotSleep(canvas, t)
            Mascot.TRAE -> drawTraeSleep(canvas, t)
            Mascot.WORKBUDDY -> drawWorkBuddySleep(canvas, t)
            Mascot.OPENCODE -> drawOpenCodeSleep(canvas, t)
            Mascot.HERMES -> drawHermesSleep(canvas, t)
            Mascot.STEPFUN -> drawStepFunSleep(canvas, t)
            else -> {
                val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 13f, 3f)
                val floatY = sin((t % 4f) / 4f * (PI * 2f).toFloat()) * 0.6f
                drawShadow(canvas, viewport, 7f + abs(floatY) * 0.3f, 0.2f)
                drawLegs(canvas, viewport)
                drawBuddyBody(canvas, viewport, floatY)
                drawEyes(canvas, viewport, floatY, detailColor().withAlpha(0.3f), 0.3f)
                drawZParticles(canvas, t)
                drawSourceMark(canvas, viewport, floatY)
            }
        }
    }

    private fun drawWork(canvas: Canvas, t: Float) {
        when (mascot) {
            Mascot.CLAUDE -> drawClaudeWork(canvas, t)
            Mascot.CODEX -> drawCodexWork(canvas, t)
            Mascot.GEMINI -> drawGeminiWork(canvas, t)
            Mascot.COPILOT -> drawCopilotWork(canvas, t)
            Mascot.TRAE -> drawTraeWork(canvas, t)
            Mascot.WORKBUDDY -> drawWorkBuddyWork(canvas, t)
            Mascot.OPENCODE -> drawOpenCodeWork(canvas, t)
            Mascot.HERMES -> drawHermesWork(canvas, t)
            Mascot.STEPFUN -> drawStepFunWork(canvas, t)
            else -> {
                val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
                val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1.0f
                val blinkPhase = t % 2.5f
                val eyeScale = if (blinkPhase > 2.2f && blinkPhase < 2.35f) 0.1f else 1f
                val keyPhase = ((t / 0.1f).toInt()).mod(6)

                drawShadow(canvas, viewport, 8f - abs(bounce) * 0.3f, max(0.1f, 0.35f - abs(bounce) * 0.03f))
                drawLegs(canvas, viewport)
                drawKeyboard(canvas, viewport, keyPhase)
                drawBuddyBody(canvas, viewport, bounce)
                drawEyes(canvas, viewport, bounce, detailColor(), eyeScale)
                drawSourceMark(canvas, viewport, bounce)
            }
        }
    }

    private fun drawAlert(canvas: Canvas, t: Float) {
        when (mascot) {
            Mascot.CLAUDE -> drawClaudeAlert(canvas, t)
            Mascot.CODEX -> drawCodexAlert(canvas, t)
            Mascot.GEMINI -> drawGeminiAlert(canvas, t)
            Mascot.COPILOT -> drawCopilotAlert(canvas, t)
            Mascot.TRAE -> drawTraeAlert(canvas, t)
            Mascot.WORKBUDDY -> drawWorkBuddyAlert(canvas, t)
            Mascot.OPENCODE -> drawOpenCodeAlert(canvas, t)
            Mascot.HERMES -> drawHermesAlert(canvas, t)
            Mascot.STEPFUN -> drawStepFunAlert(canvas, t)
            else -> {
                val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
                val pct = (t % 3.5f) / 3.5f
                val jumpY = lerp(
                    listOf(
                        0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                        0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                        0.275f to -6f, 0.30f to -6f, 0.35f to 1.0f,
                        0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                        0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                        0.62f to 0f, 1f to 0f,
                    ),
                    pct,
                )
                val squashX = if (jumpY > 0.5f) 1f + jumpY * 0.03f else 1f
                val squashY = if (jumpY > 0.5f) 1f - jumpY * 0.02f else 1f
                val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
                val eyeFlash = pct > 0.03f && pct < 0.55f && sin(pct * 25f) > 0f
                val eyeColor = if (eyeFlash) ALERT_COLOR else detailColor()
                val glowAlpha = 0.1f + ((sin(t * 3f) + 1f) * 0.5f) * 0.12f

                drawGlow(canvas, glowAlpha)
                drawShadow(canvas, viewport, 8f * (1f - abs(min(0f, jumpY)) * 0.04f), max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f))
                drawLegs(canvas, viewport)

                canvas.save()
                canvas.translate(shakeX * viewport.scale, 0f)
                drawBuddyBody(canvas, viewport, jumpY, squashX, squashY)
                drawEyes(canvas, viewport, jumpY, eyeColor, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f)
                drawSourceMark(canvas, viewport, jumpY)
                canvas.restore()

                val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
                val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)
                if (bangOpacity > 0.01f) {
                    drawBang(canvas, viewport, jumpY, bangOpacity, bangScale)
                }
            }
        }
    }

    private fun drawClaudeSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 17f, 7f, 9f)
        val phase = (t % 4.5f) / 4.5f
        val breathe = if (phase < 0.4f) sin(phase / 0.4f * PI.toFloat()) else 0f
        val shadowScale = 1f + breathe * 0.03f

        rect(canvas, viewport, -1f, 15f, 17f * shadowScale, 1f, Color.BLACK.withAlpha(0.35f + breathe * 0.08f))
        for (x in listOf(3f, 5f, 9f, 11f)) {
            rect(canvas, viewport, x, 8.5f, 1f, 1.5f, CLAUDE_BODY)
        }

        val puff = max(0f, breathe) * 0.25f
        val torsoH = 5f * (1f + puff)
        val torsoY = 15f - torsoH
        val torsoW = 13f * (1f + breathe * 0.015f)
        val torsoX = 1f - (torsoW - 13f) / 2f
        rect(canvas, viewport, torsoX, torsoY, torsoW, torsoH, CLAUDE_BODY)
        rect(canvas, viewport, -1f, 13f, 2f, 2f, CLAUDE_BODY)
        rect(canvas, viewport, 14f, 13f, 2f, 2f, CLAUDE_BODY)

        val eyeY = 12.2f - puff * 2.5f
        rect(canvas, viewport, 3f, eyeY, 2.5f, 1f, Color.BLACK)
        rect(canvas, viewport, 9.5f, eyeY, 2.5f, 1f, Color.BLACK)
        drawClaudeZParticles(canvas, t)
    }

    private fun drawClaudeWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 11f, 5.5f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.35f) * 1.2f
        val breathe = sin(t * 2f * PI.toFloat() / 3.2f)
        val armLRaw = sin(t * 2f * PI.toFloat() / 0.15f)
        val armL = armLRaw * 22.5f - 32.5f
        val armRRaw = sin(t * 2f * PI.toFloat() / 0.12f)
        val armR = armRRaw * 22.5f + 32.5f
        val leftHit = armLRaw > 0.3f
        val rightHit = armRRaw > 0.3f
        val leftKeyCol = ((t / 0.15f).toInt()).mod(3)
        val rightKeyCol = 3 + ((t / 0.12f).toInt()).mod(3)
        val scanPhase = t % 10f
        val eyeScale = if (scanPhase > 5.7f && scanPhase < 6.9f) 1f else 0.5f
        val eyeDY = if (eyeScale < 0.8f) 1f else -0.5f
        val blinkPhase = t % 3.5f
        val finalEyeScale = if (blinkPhase > 1.4f && blinkPhase < 1.55f) 0.1f else eyeScale

        val shadowW = 9f - abs(bounce) * 0.3f
        rect(canvas, viewport, 3f + (9f - shadowW) / 2f, 15f, shadowW, 1f, Color.BLACK.withAlpha(max(0.1f, 0.4f - abs(bounce) * 0.03f)))
        for (x in listOf(3f, 5f, 9f, 11f)) {
            rect(canvas, viewport, x, 13f, 1f, 2f, CLAUDE_BODY)
        }

        val bodyScale = 1f + breathe * 0.015f
        val torsoW = 11f * bodyScale
        rect(canvas, viewport, 2f - (torsoW - 11f) / 2f, 6f, torsoW, 7f, CLAUDE_BODY, bounce)

        val eyeH = 2f * finalEyeScale
        val eyeY = 8f + (2f - eyeH) / 2f + eyeDY
        rect(canvas, viewport, 4f, eyeY, 1f, eyeH, Color.BLACK, bounce)
        rect(canvas, viewport, 10f, eyeY, 1f, eyeH, Color.BLACK, bounce)

        rect(canvas, viewport, -0.5f, 11.8f, 16f, 3.5f, CLAUDE_KB_BASE)
        for (row in 0 until 3) {
            val ky = 12.2f + row * 1f
            for (col in 0 until 6) {
                val kx = 0.3f + col * 2.5f
                val w = if (col == 2 && row == 1) 4.5f else 2f
                rect(canvas, viewport, kx, ky, w, 0.7f, CLAUDE_KB_KEY)
            }
        }
        if (leftHit) {
            val row = leftKeyCol % 3
            rect(canvas, viewport, 0.3f + leftKeyCol * 2.5f, 12.2f + row * 1f, 2f, 0.7f, CLAUDE_KB_HI.withAlpha(0.9f))
        }
        if (rightHit) {
            val row = (rightKeyCol - 3) % 3
            rect(canvas, viewport, 0.3f + rightKeyCol * 2.5f, 12.2f + row * 1f, 2f, 0.7f, CLAUDE_KB_HI.withAlpha(0.9f))
        }

        rotatedRect(canvas, viewport, 0f, 9f, 2f, 2f, 2f, 10f, armL, CLAUDE_BODY, bounce)
        rotatedRect(canvas, viewport, 13f, 9f, 2f, 2f, 13f, 10f, armR, CLAUDE_BODY, bounce)
    }

    private fun drawClaudeAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -10f, 0.20f to -10f, 0.25f to 1.5f,
                0.275f to -8f, 0.30f to -8f, 0.35f to 1.2f,
                0.375f to -5f, 0.40f to -5f, 0.45f to 1f,
                0.475f to -3f, 0.50f to -3f, 0.55f to 0.5f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val scaleX = if (jumpY > 0.5f) 1f + jumpY * 0.05f else 1f
        val scaleY = if (jumpY > 0.5f) 1f - jumpY * 0.04f else 1f
        val armL = lerp(listOf(0f to 0f, 0.03f to 0f, 0.10f to 25f, 0.15f to 30f, 0.20f to 155f, 0.25f to 115f, 0.30f to 140f, 0.35f to 100f, 0.40f to 115f, 0.45f to 80f, 0.50f to 80f, 0.55f to 40f, 0.62f to 0f, 1f to 0f), pct)
        val armR = -lerp(listOf(0f to 0f, 0.03f to 0f, 0.10f to 30f, 0.15f to 30f, 0.20f to 155f, 0.25f to 115f, 0.30f to 140f, 0.35f to 100f, 0.40f to 115f, 0.45f to 80f, 0.50f to 80f, 0.55f to 40f, 0.62f to 0f, 1f to 0f), pct)
        val eyeScale = if (pct > 0.03f && pct < 0.15f) 1.3f else 1f
        val eyeDY = if (pct > 0.03f && pct < 0.15f) -0.5f else 0f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        val shadowW = 9f * (1f - abs(min(0f, jumpY)) * 0.04f)
        rect(canvas, viewport, 3f + (9f - shadowW) / 2f, 15f, shadowW, 1f, Color.BLACK.withAlpha(max(0.08f, 0.5f - abs(min(0f, jumpY)) * 0.04f)))
        for (x in listOf(3f, 5f, 9f, 11f)) {
            rect(canvas, viewport, x, 11f, 1f, 4f, CLAUDE_BODY)
        }

        val torsoW = 11f * scaleX
        val torsoH = 7f * scaleY
        val torsoX = 2f - (torsoW - 11f) / 2f
        val torsoY = 6f + (7f - torsoH)
        rect(canvas, viewport, torsoX, torsoY, torsoW, torsoH, CLAUDE_BODY, jumpY)

        val eyeH = 2f * eyeScale
        val eyeY = 8f + (2f - eyeH) / 2f + eyeDY
        rect(canvas, viewport, 4f, eyeY, 1f, eyeH, Color.BLACK, jumpY)
        rect(canvas, viewport, 10f, eyeY, 1f, eyeH, Color.BLACK, jumpY)

        rotatedRect(canvas, viewport, 0f, 9f, 2f, 2f, 2f, 10f, armL, CLAUDE_BODY, jumpY)
        rotatedRect(canvas, viewport, 13f, 9f, 2f, 2f, 13f, 10f, armR, CLAUDE_BODY, jumpY)
        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4.5f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
        }
    }

    private fun drawTraeSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val blinkCycle = t % 4f
        val blink = if (blinkCycle > 3.5f && blinkCycle < 3.7f) 0.15f else 0.5f

        drawShadow(canvas, viewport, 6f + abs(floatY) * 0.3f, 0.2f)
        drawTraeLegs(canvas, viewport, floatY)
        drawTraeBody(canvas, viewport, floatY, 1f, 0.95f)
        drawTraeEyes(canvas, viewport, floatY, 1f, blink)
        drawTraeZParticles(canvas, t)
    }

    private fun drawTraeWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val blinkCycle = t % 2.5f
        val blink = if (blinkCycle > 2.2f && blinkCycle < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        val shadowW = 7f - abs(bounce) * 0.3f
        rect(canvas, viewport, 4f + (7f - shadowW) / 2f, 16f, shadowW, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawTraeLegs(canvas, viewport, bounce)

        rect(canvas, viewport, 0f, 13f, 15f, 3f, TRAE_KB_BASE)
        for (row in 0 until 2) {
            val ky = 13.5f + row * 1.2f
            for (col in 0 until 6) {
                val kx = 0.5f + col * 2.4f
                rect(canvas, viewport, kx, ky, 1.8f, 0.7f, TRAE_KB_KEY)
            }
        }
        val flashRow = keyPhase / 3
        val flashCol = keyPhase % 6
        rect(canvas, viewport, 0.5f + flashCol * 2.4f, 13.5f + flashRow * 1.2f, 1.8f, 0.7f, TRAE_KB_HI.withAlpha(0.9f))

        drawTraeBody(canvas, viewport, bounce)
        drawTraeEyes(canvas, viewport, bounce, 1f, blink)
    }

    private fun drawTraeAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val pulseScale = if (pct > 0.03f && pct < 0.55f) 1f + sin(pct * 20f) * 0.08f else 1f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        val shadowW = 7f * (1f - abs(min(0f, jumpY)) * 0.04f)
        rect(canvas, viewport, 4f + (7f - shadowW) / 2f, 16f, shadowW, 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawTraeLegs(canvas, viewport, jumpY)

        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawTraeBody(canvas, viewport, jumpY, pulseScale, pulseScale)
        drawTraeEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f, 1f)
        canvas.restore()

        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
        }
    }

    private fun drawCodexSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val cursorOn = (t % 1.2f) < 0.6f

        drawShadow(canvas, viewport, 7f + abs(floatY) * 0.3f, 0.2f)
        drawCodexLegs(canvas, viewport)
        drawCodexCloud(canvas, viewport, floatY)
        drawCodexPrompt(canvas, viewport, floatY, showChevron = false, cursorOn = cursorOn, color = CODEX_PROMPT.withAlpha(0.35f))
        drawZParticles(canvas, t, Color.WHITE, 0.08f)
    }

    private fun drawCodexWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val cursorOn = (t % 0.3f) < 0.15f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4f + abs(bounce) * 0.15f, 16f, 8f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawCodexLegs(canvas, viewport)

        rect(canvas, viewport, 0f, 13f, 15f, 3f, CODEX_KB_BASE)
        for (row in 0 until 2) {
            val ky = 13.5f + row * 1.2f
            for (col in 0 until 6) {
                val kx = 0.5f + col * 2.4f
                rect(canvas, viewport, kx, ky, 1.8f, 0.7f, CODEX_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, CODEX_KB_HI.withAlpha(0.9f))

        drawCodexCloud(canvas, viewport, bounce)
        drawCodexPrompt(canvas, viewport, bounce, showChevron = true, cursorOn = cursorOn)
    }

    private fun drawCodexAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val squashX = if (jumpY > 0.5f) 1f + jumpY * 0.03f else 1f
        val squashY = if (jumpY > 0.5f) 1f - jumpY * 0.02f else 1f
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val promptColor = if (pct > 0.03f && pct < 0.55f && sin(pct * 25f) > 0f) CODEX_ALERT else CODEX_PROMPT
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, CODEX_ALERT, 0.12f)
        rect(canvas, viewport, 4f + abs(min(0f, jumpY)) * 0.16f, 16f, 8f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawCodexLegs(canvas, viewport)

        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawCodexCloud(canvas, viewport, jumpY, squashX, squashY)
        drawCodexPrompt(canvas, viewport, jumpY, showChevron = true, cursorOn = true, color = promptColor)
        canvas.restore()

        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, CODEX_ALERT.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, CODEX_ALERT.withAlpha(bangOpacity))
        }
    }

    private fun drawGeminiSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val blinkCycle = t % 4f
        val blink = if (blinkCycle > 3.5f && blinkCycle < 3.7f) 0.15f else 0.5f
        val spin = sin(phase * (PI * 2f).toFloat()) * 5f

        drawShadow(canvas, viewport, 6f + abs(floatY) * 0.3f, 0.2f)
        drawGeminiLegs(canvas, viewport, floatY)
        drawGeminiStar(canvas, viewport, floatY, 0.92f, spin)
        drawGeminiEyes(canvas, viewport, floatY, 1f, blink)
        drawZParticles(canvas, t)
    }

    private fun drawGeminiWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val spin = sin(t * 2f * PI.toFloat() / 1.2f) * 15f
        val blinkCycle = t % 2.5f
        val blink = if (blinkCycle > 2.2f && blinkCycle < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4.5f + abs(bounce) * 0.15f, 16f, 7f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawGeminiLegs(canvas, viewport, bounce)

        rect(canvas, viewport, 0f, 13f, 15f, 3f, GEMINI_KB_BASE)
        for (row in 0 until 2) {
            val ky = 13.5f + row * 1.2f
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, ky, 1.8f, 0.7f, GEMINI_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, GEMINI_KB_HI.withAlpha(0.9f))

        drawGeminiStar(canvas, viewport, bounce, 1f, spin)
        drawGeminiEyes(canvas, viewport, bounce, 1f, blink)
    }

    private fun drawGeminiAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val pulseScale = if (pct > 0.03f && pct < 0.55f) 1f + sin(pct * 20f) * 0.15f else 1f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        rect(canvas, viewport, 4.5f + abs(min(0f, jumpY)) * 0.14f, 16f, 7f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawGeminiLegs(canvas, viewport, jumpY)

        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawGeminiStar(canvas, viewport, jumpY, pulseScale, 0f)
        drawGeminiEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f, 1f)
        canvas.restore()

        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, ALERT_COLOR.withAlpha(bangOpacity))
        }
    }

    private fun drawCopilotSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.7f
        val blink = if ((t % 4f) > 3.5f && (t % 4f) < 3.7f) 0.25f else 0.6f

        drawShadow(canvas, viewport, 6.5f + abs(floatY) * 0.3f, 0.2f)
        drawCopilotLegs(canvas, viewport, floatY)
        drawCopilotEars(canvas, viewport, floatY)
        drawCopilotBody(canvas, viewport, floatY)
        drawCopilotEyes(canvas, viewport, floatY, 1f, blink)
        drawZParticles(canvas, t, Color.WHITE, 0.04f)
    }

    private fun drawCopilotWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 0.9f
        val blink = if ((t % 2.5f) > 2.2f && (t % 2.5f) < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)
        val signal = sin(t * 2f * PI.toFloat() / 0.35f) > 0f

        rect(canvas, viewport, 4.5f + abs(bounce) * 0.15f, 16f, 7f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawCopilotLegs(canvas, viewport, bounce)
        rect(canvas, viewport, 0f, 13f, 15f, 3f, COPILOT_KB_BASE)
        for (row in 0 until 2) {
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, 13.5f + row * 1.2f, 1.8f, 0.7f, COPILOT_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, Color.WHITE.withAlpha(0.9f))
        drawCopilotEars(canvas, viewport, bounce, signal = signal)
        drawCopilotBody(canvas, viewport, bounce)
        drawCopilotEyes(canvas, viewport, bounce, 1f, blink)
    }

    private fun drawCopilotAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, COPILOT_ALERT, 0.12f)
        rect(canvas, viewport, 4.5f + abs(min(0f, jumpY)) * 0.14f, 16f, 7f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawCopilotLegs(canvas, viewport, jumpY)

        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawCopilotEars(canvas, viewport, jumpY, color = COPILOT_ALERT, signal = true)
        drawCopilotBody(canvas, viewport, jumpY, shellColor = COPILOT_BODY.lighter(0.1f))
        drawCopilotEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f, 1f, color = COPILOT_EYE)
        canvas.restore()

        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, COPILOT_ALERT.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, COPILOT_ALERT.withAlpha(bangOpacity))
        }
    }

    private fun drawWorkBuddySleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val blink = if ((t % 4f) > 3.5f && (t % 4f) < 3.7f) 0.15f else 0.5f

        drawShadow(canvas, viewport, 6f + abs(floatY) * 0.3f, 0.2f)
        drawWorkBuddyLegs(canvas, viewport, floatY)
        drawWorkBuddyBody(canvas, viewport, floatY, 0.9f)
        drawWorkBuddyEyes(canvas, viewport, floatY, 1f, blink)
        drawZParticles(canvas, t)
    }

    private fun drawWorkBuddyWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val blink = if ((t % 2.5f) > 2.2f && (t % 2.5f) < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4.5f + abs(bounce) * 0.15f, 16f, 7f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawWorkBuddyLegs(canvas, viewport, bounce)
        rect(canvas, viewport, 0f, 13f, 15f, 3f, WORKBUDDY_KB_BASE)
        for (row in 0 until 2) {
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, 13.5f + row * 1.2f, 1.8f, 0.7f, WORKBUDDY_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, Color.WHITE.withAlpha(0.9f))
        drawWorkBuddyBody(canvas, viewport, bounce)
        drawWorkBuddyEyes(canvas, viewport, bounce, 1f, blink)
    }

    private fun drawWorkBuddyAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val pulseScale = if (pct > 0.03f && pct < 0.55f) 1f + sin(pct * 20f) * 0.08f else 1f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        rect(canvas, viewport, 4.5f + abs(min(0f, jumpY)) * 0.14f, 16f, 7f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawWorkBuddyLegs(canvas, viewport, jumpY)

        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawWorkBuddyBody(canvas, viewport, jumpY, 0.9f * pulseScale)
        drawWorkBuddyEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f, 1f)
        canvas.restore()
        if (bangOpacity > 0.01f) drawBang(canvas, viewport, jumpY, bangOpacity, bangScale)
    }

    private fun drawOpenCodeSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.7f
        val eyeScale = if ((t % 4f) > 3.5f && (t % 4f) < 3.7f) 0.35f else 0.8f

        drawShadow(canvas, viewport, 6.5f + abs(floatY) * 0.3f, 0.2f)
        drawOpenCodeLegs(canvas, viewport, floatY)
        drawOpenCodeBlock(canvas, viewport, floatY, 1f, 0.95f)
        drawOpenCodeFace(canvas, viewport, floatY, OPENCODE_FACE, eyeScale)
        drawZParticles(canvas, t, Color.WHITE, 0.05f)
    }

    private fun drawOpenCodeWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 0.9f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4f + abs(bounce) * 0.15f, 16f, 8f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawOpenCodeLegs(canvas, viewport, bounce)
        rect(canvas, viewport, 0f, 13f, 15f, 3f, OPENCODE_KB_BASE)
        for (row in 0 until 2) {
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, 13.5f + row * 1.2f, 1.8f, 0.7f, OPENCODE_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, Color.WHITE.withAlpha(0.9f))
        drawOpenCodeBlock(canvas, viewport, bounce)
        drawOpenCodeFace(canvas, viewport, bounce, OPENCODE_FACE)
    }

    private fun drawOpenCodeAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, OPENCODE_ALERT, 0.12f)
        rect(canvas, viewport, 4f + abs(min(0f, jumpY)) * 0.16f, 16f, 8f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawOpenCodeLegs(canvas, viewport, jumpY)
        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawOpenCodeBlock(canvas, viewport, jumpY)
        drawOpenCodeFace(canvas, viewport, jumpY, OPENCODE_ALERT)
        canvas.restore()
        if (bangOpacity > 0.01f) {
            val bw = 2f * bangScale
            val by = 4f + jumpY * 0.15f
            rect(canvas, viewport, 13f, by, bw, 3.5f * bangScale, OPENCODE_ALERT.withAlpha(bangOpacity))
            rect(canvas, viewport, 13f, by + 4f * bangScale, bw, 1.5f * bangScale, OPENCODE_ALERT.withAlpha(bangOpacity))
        }
    }

    private fun drawHermesSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val blink = if ((t % 4f) > 3.5f && (t % 4f) < 3.7f) 0.15f else 0.5f

        drawShadow(canvas, viewport, 6f + abs(floatY) * 0.3f, 0.2f)
        drawHermesLegs(canvas, viewport, floatY)
        drawHermesBody(canvas, viewport, floatY, 1f)
        drawHermesEyes(canvas, viewport, floatY, 1f, blink)
        drawZParticles(canvas, t, Color.WHITE, 0.05f)
    }

    private fun drawHermesWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val blink = if ((t % 2.5f) > 2.2f && (t % 2.5f) < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4.5f + abs(bounce) * 0.15f, 16f, 7f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawHermesLegs(canvas, viewport, bounce)
        rect(canvas, viewport, 0f, 13f, 15f, 3f, HERMES_KB_BASE)
        for (row in 0 until 2) {
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, 13.5f + row * 1.2f, 1.8f, 0.7f, HERMES_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, HERMES_KB_HI.withAlpha(0.9f))
        drawHermesBody(canvas, viewport, bounce)
        drawHermesEyes(canvas, viewport, bounce, 1f, blink)
    }

    private fun drawHermesAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        rect(canvas, viewport, 4.5f + abs(min(0f, jumpY)) * 0.14f, 16f, 7f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawHermesLegs(canvas, viewport, jumpY)
        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawHermesBody(canvas, viewport, jumpY)
        drawHermesEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f, 1f)
        canvas.restore()
        if (bangOpacity > 0.01f) drawBang(canvas, viewport, jumpY, bangOpacity, bangScale)
    }

    private fun drawStepFunSleep(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 15f, 12f, 4f)
        val phase = (t % 4f) / 4f
        val floatY = sin(phase * (PI * 2f).toFloat()) * 0.8f
        val blink = if ((t % 4f) > 3.5f && (t % 4f) < 3.7f) 0.15f else 0.5f

        drawShadow(canvas, viewport, 6f + abs(floatY) * 0.3f, 0.2f)
        drawStepFunLegs(canvas, viewport, floatY)
        drawStepFunBody(canvas, viewport, floatY, 1f, 0.95f)
        drawStepFunEyes(canvas, viewport, floatY, blink)
        drawZParticles(canvas, t)
    }

    private fun drawStepFunWork(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val bounce = sin(t * 2f * PI.toFloat() / 0.4f) * 1f
        val blink = if ((t % 2.5f) > 2.2f && (t % 2.5f) < 2.35f) 0.1f else 1f
        val keyPhase = ((t / 0.1f).toInt()).mod(6)

        rect(canvas, viewport, 4.5f + abs(bounce) * 0.15f, 16f, 7f - abs(bounce) * 0.3f, 1f, Color.BLACK.withAlpha(max(0.1f, 0.35f - abs(bounce) * 0.03f)))
        drawStepFunLegs(canvas, viewport, bounce)
        rect(canvas, viewport, 0f, 13f, 15f, 3f, STEPFUN_KB_BASE)
        for (row in 0 until 2) {
            for (col in 0 until 6) {
                rect(canvas, viewport, 0.5f + col * 2.4f, 13.5f + row * 1.2f, 1.8f, 0.7f, STEPFUN_KB_KEY)
            }
        }
        rect(canvas, viewport, 0.5f + (keyPhase % 6) * 2.4f, 13.5f + (keyPhase / 3) * 1.2f, 1.8f, 0.7f, STEPFUN_KB_HI.withAlpha(0.9f))
        drawStepFunBody(canvas, viewport, bounce)
        drawStepFunEyes(canvas, viewport, bounce, blink)
    }

    private fun drawStepFunAlert(canvas: Canvas, t: Float) {
        val viewport = Viewport(width.toFloat(), height.toFloat(), 16f, 14f, 3f)
        val pct = (t % 3.5f) / 3.5f
        val jumpY = lerp(
            listOf(
                0f to 0f, 0.03f to 0f, 0.10f to -1f, 0.15f to 1.5f,
                0.175f to -8f, 0.20f to -8f, 0.25f to 1.5f,
                0.275f to -6f, 0.30f to -6f, 0.35f to 1f,
                0.375f to -4f, 0.40f to -4f, 0.45f to 0.8f,
                0.475f to -2f, 0.50f to -2f, 0.55f to 0.3f,
                0.62f to 0f, 1f to 0f,
            ),
            pct,
        )
        val shakeX = if (pct > 0.15f && pct < 0.55f) sin(pct * 80f) * 0.6f else 0f
        val pulseScale = if (pct > 0.03f && pct < 0.55f) 1f + sin(pct * 20f) * 0.08f else 1f
        val bangOpacity = lerp(listOf(0f to 0f, 0.03f to 1f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0f, 1f to 0f), pct)
        val bangScale = lerp(listOf(0f to 0.3f, 0.03f to 1.3f, 0.10f to 1f, 0.55f to 1f, 0.62f to 0.6f, 1f to 0.6f), pct)

        drawGlow(canvas, ALERT_COLOR, 0.12f)
        rect(canvas, viewport, 4.5f + abs(min(0f, jumpY)) * 0.14f, 16f, 7f * (1f - abs(min(0f, jumpY)) * 0.04f), 1f, Color.BLACK.withAlpha(max(0.08f, 0.4f - abs(min(0f, jumpY)) * 0.04f)))
        drawStepFunLegs(canvas, viewport, jumpY)
        canvas.save()
        canvas.translate(shakeX * viewport.scale, 0f)
        drawStepFunBody(canvas, viewport, jumpY, pulseScale, pulseScale)
        drawStepFunEyes(canvas, viewport, jumpY, if (pct > 0.03f && pct < 0.15f) 1.3f else 1f)
        canvas.restore()
        if (bangOpacity > 0.01f) drawBang(canvas, viewport, jumpY, bangOpacity, bangScale)
    }

    private fun drawCodexCloud(canvas: Canvas, viewport: Viewport, dy: Float, squashX: Float = 1f, squashY: Float = 1f) {
        val centerX = 7.5f
        val rows = listOf(
            Triple(14f, 4f, 7f), Triple(13f, 3f, 9f), Triple(12f, 2f, 11f),
            Triple(11f, 1f, 13f), Triple(10f, 1f, 13f), Triple(9f, 1f, 13f),
            Triple(8f, 2f, 11f), Triple(7f, 2f, 11f), Triple(6f, 3f, 3f),
            Triple(6f, 6f, 3f), Triple(6f, 9f, 3f), Triple(5f, 4f, 2f),
            Triple(5f, 6.5f, 2f), Triple(5f, 9f, 2f),
        )
        fun sx(x: Float) = centerX + (x - centerX) * squashX
        fun sy(y: Float) = y * squashY + (1f - squashY) * 10f
        rows.forEach { (y, x, w) -> rect(canvas, viewport, sx(x), sy(y), w * squashX, 1f * squashY, CODEX_CLOUD, dy) }
    }

    private fun drawCodexPrompt(canvas: Canvas, viewport: Viewport, dy: Float, showChevron: Boolean, cursorOn: Boolean, color: Int = CODEX_PROMPT) {
        if (showChevron) {
            rect(canvas, viewport, 3f, 10f, 1f, 1f, color, dy)
            rect(canvas, viewport, 4f, 11f, 1f, 1f, color, dy)
            rect(canvas, viewport, 3f, 12f, 1f, 1f, color, dy)
        }
        if (cursorOn) {
            rect(canvas, viewport, 6f, 12f, 3f, 1f, color, dy)
        }
    }

    private fun drawCodexLegs(canvas: Canvas, viewport: Viewport) {
        rect(canvas, viewport, 5f, 14.5f, 1f, 1.5f, CODEX_CLOUD_DARK)
        rect(canvas, viewport, 9f, 14.5f, 1f, 1.5f, CODEX_CLOUD_DARK)
    }

    private fun drawGeminiStar(canvas: Canvas, viewport: Viewport, dy: Float, scale: Float, rotateDeg: Float) {
        fun point(cx: Float, cy: Float, radius: Float, angleDeg: Float): Pair<Float, Float> {
            val radians = angleDeg / 180f * PI.toFloat()
            return (cx + kotlin.math.cos(radians) * radius) to (cy + kotlin.math.sin(radians) * radius)
        }
        val cx = 7.5f
        val cy = 10f
        val outer = 4.4f * scale
        val inner = 1.8f * scale
        val path = Path()
        for (i in 0 until 8) {
            val radius = if (i % 2 == 0) outer else inner
            val (px, py) = point(cx, cy, radius, rotateDeg + i * 45f - 90f)
            val x = viewport.left + px * viewport.scale
            val y = viewport.top + (py - viewport.y0 + dy) * viewport.scale
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        fillPaint.color = GEMINI_PURPLE
        canvas.drawPath(path, fillPaint)
        val top = Path()
        top.moveTo(viewport.left + cx * viewport.scale, viewport.top + (cy - outer - viewport.y0 + dy) * viewport.scale)
        top.lineTo(viewport.left + (cx - inner) * viewport.scale, viewport.top + (cy - inner - viewport.y0 + dy) * viewport.scale)
        top.lineTo(viewport.left + cx * viewport.scale, viewport.top + (cy - 0.2f - viewport.y0 + dy) * viewport.scale)
        top.lineTo(viewport.left + (cx + inner) * viewport.scale, viewport.top + (cy - inner - viewport.y0 + dy) * viewport.scale)
        top.close()
        fillPaint.color = GEMINI_BLUE
        canvas.drawPath(top, fillPaint)
        val bottom = Path()
        bottom.moveTo(viewport.left + cx * viewport.scale, viewport.top + (cy + outer - viewport.y0 + dy) * viewport.scale)
        bottom.lineTo(viewport.left + (cx - inner) * viewport.scale, viewport.top + (cy + inner - viewport.y0 + dy) * viewport.scale)
        bottom.lineTo(viewport.left + cx * viewport.scale, viewport.top + (cy + 0.2f - viewport.y0 + dy) * viewport.scale)
        bottom.lineTo(viewport.left + (cx + inner) * viewport.scale, viewport.top + (cy + inner - viewport.y0 + dy) * viewport.scale)
        bottom.close()
        fillPaint.color = GEMINI_ROSE
        canvas.drawPath(bottom, fillPaint)
    }

    private fun drawGeminiEyes(canvas: Canvas, viewport: Viewport, dy: Float, eyeScale: Float, blinkPhase: Float) {
        val eyeH = 1.5f * eyeScale * blinkPhase
        val eyeY = 9.5f + (1.5f - eyeH) / 2f
        rect(canvas, viewport, 5.5f, eyeY, 1.2f, max(0.3f, eyeH), Color.WHITE, dy)
        rect(canvas, viewport, 8.3f, eyeY, 1.2f, max(0.3f, eyeH), Color.WHITE, dy)
    }

    private fun drawGeminiLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.5f, 14f, 1f, 2f, GEMINI_PURPLE.withAlpha(0.7f), legDy)
        rect(canvas, viewport, 8.5f, 14f, 1f, 2f, GEMINI_PURPLE.withAlpha(0.7f), legDy)
    }

    private fun drawCopilotEars(canvas: Canvas, viewport: Viewport, dy: Float, color: Int = COPILOT_EAR, signal: Boolean = false) {
        rect(canvas, viewport, 3f, 5f, 3f, 1f, color, dy)
        rect(canvas, viewport, 3f, 6f, 1f, 1f, color, dy)
        rect(canvas, viewport, 5f, 6f, 1f, 1f, color, dy)
        rect(canvas, viewport, 3f, 7f, 3f, 1f, color, dy)
        rect(canvas, viewport, 9f, 5f, 3f, 1f, color, dy)
        rect(canvas, viewport, 9f, 6f, 1f, 1f, color, dy)
        rect(canvas, viewport, 11f, 6f, 1f, 1f, color, dy)
        rect(canvas, viewport, 9f, 7f, 3f, 1f, color, dy)
        rect(canvas, viewport, 4f, 8f, 1f, 1f, color, dy)
        rect(canvas, viewport, 10f, 8f, 1f, 1f, color, dy)
        if (signal) {
            rect(canvas, viewport, 4f, 6f, 1f, 1f, COPILOT_EYE.withAlpha(0.5f), dy)
            rect(canvas, viewport, 10f, 6f, 1f, 1f, COPILOT_EYE.withAlpha(0.5f), dy)
        }
    }

    private fun drawCopilotBody(canvas: Canvas, viewport: Viewport, dy: Float, shellColor: Int = COPILOT_BODY) {
        rect(canvas, viewport, 2f, 9f, 11f, 1f, shellColor, dy)
        rect(canvas, viewport, 2f, 10f, 2f, 3f, shellColor, dy)
        rect(canvas, viewport, 11f, 10f, 2f, 3f, shellColor, dy)
        rect(canvas, viewport, 4f, 10f, 7f, 3f, COPILOT_FACE, dy)
        rect(canvas, viewport, 2f, 13f, 11f, 1f, shellColor, dy)
        rect(canvas, viewport, 4f, 14f, 7f, 1f, shellColor, dy)
    }

    private fun drawCopilotEyes(canvas: Canvas, viewport: Viewport, dy: Float, eyeScale: Float, blinkPhase: Float, color: Int = COPILOT_EYE) {
        val height = max(0.2f, eyeScale * blinkPhase)
        rect(canvas, viewport, 5f, 10f + (1f - height) / 2f, 1f, height, color, dy)
        rect(canvas, viewport, 9f, 10f + (1f - height) / 2f, 1f, height, color, dy)
        rect(canvas, viewport, 6.5f, 11.7f, 2f, 0.5f, COPILOT_BODY.lighter(0.08f), dy)
    }

    private fun drawCopilotLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 6f, 14.5f, 1f, 1.5f, COPILOT_BODY.withAlpha(0.6f), legDy)
        rect(canvas, viewport, 8f, 14.5f, 1f, 1.5f, COPILOT_BODY.withAlpha(0.6f), legDy)
    }

    private fun drawWorkBuddyBody(canvas: Canvas, viewport: Viewport, dy: Float, scale: Float = 1f) {
        val cx = 7.5f
        val cy = 10.5f
        val r = 4.5f * scale
        oval(canvas, viewport, cx - r, cy - r, r * 2f, r * 2f, WORKBUDDY_BODY, dy)
        rect(canvas, viewport, 7f, cy - r - 2f, 1f, 2f, WORKBUDDY_BODY_DARK, dy)
        oval(canvas, viewport, 6.2f, cy - r - 3.2f, 2.6f, 2f, WORKBUDDY_BODY_LIGHT, dy)
    }

    private fun drawWorkBuddyEyes(canvas: Canvas, viewport: Viewport, dy: Float, eyeScale: Float, blinkPhase: Float) {
        val eyeH = 1.8f * eyeScale * blinkPhase
        val eyeY = 10f + (1.8f - eyeH) / 2f
        oval(canvas, viewport, 5f, eyeY, 1.5f, max(0.3f, eyeH), Color.WHITE, dy)
        oval(canvas, viewport, 8.5f, eyeY, 1.5f, max(0.3f, eyeH), Color.WHITE, dy)
    }

    private fun drawWorkBuddyLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.5f, 14f, 1f, 2f, WORKBUDDY_BODY_DARK.withAlpha(0.7f), legDy)
        rect(canvas, viewport, 8.5f, 14f, 1f, 2f, WORKBUDDY_BODY_DARK.withAlpha(0.7f), legDy)
    }

    private fun drawOpenCodeBlock(canvas: Canvas, viewport: Viewport, dy: Float, squashX: Float = 1f, squashY: Float = 1f) {
        val centerX = 7.5f
        val bodyRows = listOf(
            Triple(5f, 3f, 9f), Triple(6f, 2f, 11f), Triple(7f, 2f, 11f), Triple(8f, 2f, 11f),
            Triple(9f, 2f, 11f), Triple(10f, 2f, 11f), Triple(11f, 2f, 11f), Triple(12f, 2f, 11f), Triple(13f, 3f, 9f),
        )
        fun sx(x: Float) = centerX + (x - centerX) * squashX
        fun sy(y: Float) = y * squashY + (1f - squashY) * 10f
        bodyRows.forEach { (y, x, w) -> rect(canvas, viewport, sx(x), sy(y), w * squashX, 1f * squashY, OPENCODE_BODY, dy) }
        rect(canvas, viewport, sx(3f), sy(6f), 9f * squashX, 0.7f * squashY, OPENCODE_FRAME.withAlpha(0.6f), dy)
        rect(canvas, viewport, sx(3f), sy(12f), 9f * squashX, 0.7f * squashY, OPENCODE_FRAME.withAlpha(0.6f), dy)
        for (y in 7..11) {
            rect(canvas, viewport, sx(3f), sy(y.toFloat()), 0.7f * squashX, 1f * squashY, OPENCODE_FRAME.withAlpha(0.4f), dy)
            rect(canvas, viewport, sx(11.3f), sy(y.toFloat()), 0.7f * squashX, 1f * squashY, OPENCODE_FRAME.withAlpha(0.4f), dy)
        }
    }

    private fun drawOpenCodeFace(canvas: Canvas, viewport: Viewport, dy: Float, color: Int, eyeScale: Float = 1f) {
        val eyeH = 2f * eyeScale
        val eyeY = 8.5f + (2f - eyeH) / 2f
        rect(canvas, viewport, 4.5f, eyeY, 0.8f, max(0.3f, eyeH), color, dy)
        rect(canvas, viewport, 4.9f, eyeY - 0.4f, 0.8f, 0.5f, color, dy)
        rect(canvas, viewport, 4.9f, eyeY + eyeH - 0.1f, 0.8f, 0.5f, color, dy)
        rect(canvas, viewport, 9.8f, eyeY, 0.8f, max(0.3f, eyeH), color, dy)
        rect(canvas, viewport, 9.4f, eyeY - 0.4f, 0.8f, 0.5f, color, dy)
        rect(canvas, viewport, 9.4f, eyeY + eyeH - 0.1f, 0.8f, 0.5f, color, dy)
    }

    private fun drawOpenCodeLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.4f, 14f, 1f, 2f, OPENCODE_LEG, legDy)
        rect(canvas, viewport, 8.6f, 14f, 1f, 2f, OPENCODE_LEG, legDy)
    }

    private fun drawHermesBody(canvas: Canvas, viewport: Viewport, dy: Float, scale: Float = 1f) {
        val cx = 7.5f
        val cy = 10.5f
        val bw = 9f * scale
        val bh = 6f * scale
        roundRect(canvas, viewport, cx - bw / 2f, cy - bh / 2f + 1f, bw, bh, 1.5f * viewport.scale, HERMES_BODY, dy)
        val path = Path()
        val topX = viewport.left + cx * viewport.scale
        val topY = viewport.top + (cy - bh / 2f - 3f * scale - viewport.y0 + dy) * viewport.scale
        val leftX = viewport.left + (cx - bw / 2f - 0.5f) * viewport.scale
        val leftY = viewport.top + (cy - bh / 2f + 2f - viewport.y0 + dy) * viewport.scale
        val rightX = viewport.left + (cx + bw / 2f + 0.5f) * viewport.scale
        path.moveTo(topX, topY)
        path.lineTo(rightX, leftY)
        path.lineTo(leftX, leftY)
        path.close()
        fillPaint.color = HERMES_HOOD
        canvas.drawPath(path, fillPaint)
    }

    private fun drawHermesEyes(canvas: Canvas, viewport: Viewport, dy: Float, eyeScale: Float, blinkPhase: Float) {
        val eyeH = 1.2f * eyeScale * blinkPhase
        val eyeW = 1.8f * eyeScale
        val eyeY = 10.5f + (1.2f - eyeH) / 2f
        if (blinkPhase > 0.3f) {
            oval(canvas, viewport, 4.8f, eyeY - 0.3f, eyeW + 0.6f, eyeH + 0.6f, HERMES_EYE.withAlpha(0.15f), dy)
            oval(canvas, viewport, 8.4f, eyeY - 0.3f, eyeW + 0.6f, eyeH + 0.6f, HERMES_EYE.withAlpha(0.15f), dy)
        }
        oval(canvas, viewport, 5.1f, eyeY, eyeW, max(0.2f, eyeH), HERMES_EYE, dy)
        oval(canvas, viewport, 8.7f, eyeY, eyeW, max(0.2f, eyeH), HERMES_EYE, dy)
    }

    private fun drawHermesLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.5f, 14f, 1f, 2f, HERMES_BODY_DARK.withAlpha(0.7f), legDy)
        rect(canvas, viewport, 8.5f, 14f, 1f, 2f, HERMES_BODY_DARK.withAlpha(0.7f), legDy)
    }

    private fun drawStepFunBody(canvas: Canvas, viewport: Viewport, dy: Float, squashX: Float = 1f, squashY: Float = 1f) {
        val cx = 7.5f
        val bw = 9f * squashX
        val bh = 7f * squashY
        val bx = cx - bw / 2f
        val by = 7f + (7f - bh) / 2f
        rect(canvas, viewport, bx, by, bw, bh, STEPFUN_BODY, dy)
        rect(canvas, viewport, bx + bw - 2.5f * squashX, by - 1.5f * squashY, 2.5f * squashX, 1.5f * squashY, STEPFUN_BODY_LIGHT, dy)
        rect(canvas, viewport, bx + bw - 5f * squashX, by - 1.5f * squashY, 2.5f * squashX, 1.5f * squashY, STEPFUN_BODY_DARK, dy)
    }

    private fun drawStepFunEyes(canvas: Canvas, viewport: Viewport, dy: Float, blinkPhase: Float) {
        val eyeH = 1.5f * blinkPhase
        val eyeY = 10f + (1.5f - eyeH) / 2f
        rect(canvas, viewport, 5.2f, eyeY, 1.3f, max(0.3f, eyeH), Color.WHITE, dy)
        rect(canvas, viewport, 8.5f, eyeY, 1.3f, max(0.3f, eyeH), Color.WHITE, dy)
    }

    private fun drawStepFunLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.5f, 14f, 1f, 2f, STEPFUN_BODY_DARK.withAlpha(0.7f), legDy)
        rect(canvas, viewport, 8.5f, 14f, 1f, 2f, STEPFUN_BODY_DARK.withAlpha(0.7f), legDy)
    }

    private fun drawClaudeZParticles(canvas: Canvas, t: Float) {
        drawZParticles(canvas, t, Color.WHITE, 0.08f)
    }

    private fun drawTraeZParticles(canvas: Canvas, t: Float) {
        drawZParticles(canvas, t, TRAE_BODY, 0.15f)
    }

    private fun drawZParticles(canvas: Canvas, t: Float, color: Int, baseXFactor: Float) {
        textPaint.color = color
        textPaint.typeface = android.graphics.Typeface.MONOSPACE
        for (i in 0 until 3) {
            val cycle = 2.8f + i * 0.3f
            val delay = i * 0.9f
            val raw = ((t - delay) % cycle + cycle) % cycle
            val phase = raw / cycle
            val fontSize = max(18f, width * (0.12f + phase * 0.07f))
            val baseOpacity = 0.7f - i * 0.1f
            val opacity = if (phase < 0.8f) baseOpacity else (1f - phase) * 3.5f * baseOpacity
            textPaint.textSize = fontSize
            textPaint.alpha = (255 * opacity.coerceIn(0f, 1f)).toInt()
            canvas.drawText(
                "z",
                width * (0.62f + baseXFactor + i * 0.08f),
                height * (0.34f - phase * 0.22f),
                textPaint,
            )
        }
        textPaint.alpha = 255
    }

    private fun drawTraeLegs(canvas: Canvas, viewport: Viewport, dy: Float) {
        val legDy = dy * 0.3f
        rect(canvas, viewport, 5.5f, 14f, 1f, 2f, TRAE_BODY_DARK.withAlpha(0.7f), legDy)
        rect(canvas, viewport, 8.5f, 14f, 1f, 2f, TRAE_BODY_DARK.withAlpha(0.7f), legDy)
    }

    private fun drawTraeBody(canvas: Canvas, viewport: Viewport, dy: Float, squashX: Float = 1f, squashY: Float = 1f) {
        val centerX = 7.5f
        val bodyW = 10f * squashX
        val bodyH = 7f * squashY
        val bodyX = centerX - bodyW / 2f
        val bodyY = 7f + (7f - bodyH) / 2f
        roundRect(canvas, viewport, bodyX, bodyY, bodyW, bodyH, 1.5f * viewport.scale, TRAE_BODY, dy)

        val inset = 1.2f
        roundRect(canvas, viewport, bodyX + inset, bodyY + inset, bodyW - inset * 2f, bodyH - inset * 2f, 0.8f * viewport.scale, TRAE_SCREEN, dy)
    }

    private fun drawTraeEyes(canvas: Canvas, viewport: Viewport, dy: Float, eyeScale: Float, blinkPhase: Float) {
        val eyeH = 1.8f * eyeScale * blinkPhase
        val eyeW = 1.8f * eyeScale
        val eyeY = 10f + (1.8f - eyeH) / 2f
        if (blinkPhase > 0.3f) {
            oval(canvas, viewport, 4.5f, eyeY - 0.5f, eyeW + 1f, eyeH + 1f, TRAE_EYE.withAlpha(0.2f), dy)
            oval(canvas, viewport, 8.2f, eyeY - 0.5f, eyeW + 1f, eyeH + 1f, TRAE_EYE.withAlpha(0.2f), dy)
        }
        oval(canvas, viewport, 5f, eyeY, eyeW, max(0.3f, eyeH), TRAE_EYE, dy)
        oval(canvas, viewport, 8.7f, eyeY, eyeW, max(0.3f, eyeH), TRAE_EYE, dy)
    }

    private fun drawGlow(canvas: Canvas, alpha: Float) {
        drawGlow(canvas, detailColor(), alpha)
    }

    private fun drawGlow(canvas: Canvas, color: Int, alpha: Float) {
        fillPaint.color = color.withAlpha(alpha)
        canvas.drawOval(
            width * 0.12f,
            height * 0.12f,
            width * 0.88f,
            height * 0.88f,
            fillPaint,
        )
    }

    private fun drawKeyboard(canvas: Canvas, viewport: Viewport, keyPhase: Int) {
        rect(canvas, viewport, 0f, 13f, 15f, 3f, KB_BASE)
        for (row in 0 until 2) {
            val y = 13.5f + row * 1.2f
            for (col in 0 until 6) {
                val x = 0.5f + col * 2.4f
                rect(canvas, viewport, x, y, 1.8f, 0.7f, KB_KEY)
            }
        }
        val focusCol = keyPhase % 6
        val focusRow = keyPhase / 3
        rect(canvas, viewport, 0.5f + focusCol * 2.4f, 13.5f + focusRow * 1.2f, 1.8f, 0.7f, detailColor().withAlpha(0.9f))
    }

    private fun drawZParticles(canvas: Canvas, t: Float) {
        drawZParticles(canvas, t, Color.WHITE, 0f)
    }

    private fun drawShadow(canvas: Canvas, viewport: Viewport, widthUnits: Float, opacity: Float) {
        rect(canvas, viewport, 7.5f - widthUnits / 2f, 15.5f, widthUnits, 1f, Color.BLACK.withAlpha(opacity))
    }

    private fun drawLegs(canvas: Canvas, viewport: Viewport) {
        rect(canvas, viewport, 4f, 14.5f, 1.5f, 1.5f, bodyDarkColor())
        rect(canvas, viewport, 9.5f, 14.5f, 1.5f, 1.5f, bodyDarkColor())
    }

    private fun drawBuddyBody(
        canvas: Canvas,
        viewport: Viewport,
        dy: Float,
        squashX: Float = 1f,
        squashY: Float = 1f,
    ) {
        val centerX = 7.5f
        val rows = listOf(
            Triple(14f, 3f, 9f),
            Triple(13f, 2f, 11f),
            Triple(12f, 2f, 11f),
            Triple(11f, 2f, 11f),
            Triple(10f, 3f, 9f),
            Triple(9f, 3f, 9f),
            Triple(8f, 3f, 9f),
            Triple(7f, 3f, 9f),
            Triple(6f, 4f, 7f),
        )

        fun transformX(x: Float): Float = centerX + (x - centerX) * squashX
        fun transformY(y: Float): Float = y * squashY + (1f - squashY) * 10f

        rows.forEach { (y, x, w) ->
            rect(canvas, viewport, transformX(x), transformY(y), w * squashX, 1f * squashY, BODY, dy)
        }

        val earY = 4f * squashY + (1f - squashY) * 10f
        rect(canvas, viewport, transformX(2.5f), earY, 2.5f * squashX, 2f * squashY, BODY, dy)
        rect(canvas, viewport, transformX(10f), earY, 2.5f * squashX, 2f * squashY, BODY, dy)
        rect(canvas, viewport, transformX(3f), earY + 0.5f * squashY, 1.5f * squashX, 1.2f * squashY, detailColor().withAlpha(0.6f), dy)
        rect(canvas, viewport, transformX(10.5f), earY + 0.5f * squashY, 1.5f * squashX, 1.2f * squashY, detailColor().withAlpha(0.6f), dy)
        rect(canvas, viewport, transformX(3.5f), 7f * squashY + (1f - squashY) * 10f, 8f * squashX, 2.5f * squashY, bodyDarkColor(), dy)
        rect(canvas, viewport, transformX(7f), 8.8f * squashY + (1f - squashY) * 10f, 1f, 0.8f * squashY, detailColor().withAlpha(0.4f), dy)
        rect(canvas, viewport, transformX(12f), 12f * squashY + (1f - squashY) * 10f, 2f * squashX, 1f * squashY, BODY, dy)
        rect(canvas, viewport, transformX(13f), 11f * squashY + (1f - squashY) * 10f, 1f * squashX, 1f * squashY, BODY, dy)
    }

    private fun drawSourceMark(canvas: Canvas, viewport: Viewport, dy: Float) {
        val accent = mascot.accentColor
        val inverse = if (luma(accent) > 0.55f) BODY else Color.WHITE
        when (mascot) {
            Mascot.CLAUDE -> {
                rect(canvas, viewport, 11.8f, 5.5f, 1f, 3f, accent, dy)
                rect(canvas, viewport, 10.8f, 6.5f, 3f, 1f, accent, dy)
            }
            Mascot.TRAE -> {
                val panel = Color.rgb(17, 24, 39)
                rect(canvas, viewport, 10.6f, 5.4f, 3.4f, 3.4f, accent, dy)
                rect(canvas, viewport, 11f, 5.8f, 2.6f, 2.6f, panel, dy)
                rect(canvas, viewport, 11.45f, 6.55f, 0.55f, 0.55f, accent, dy)
                rect(canvas, viewport, 12.35f, 6.55f, 0.55f, 0.55f, accent, dy)
                rect(canvas, viewport, 11.7f, 7.55f, 1.05f, 0.35f, accent, dy)
            }
            Mascot.CODEX -> {
                rect(canvas, viewport, 10.5f, 5.8f, 0.8f, 3f, accent, dy)
                rect(canvas, viewport, 12.9f, 5.8f, 0.8f, 3f, accent, dy)
                rect(canvas, viewport, 11.6f, 6.6f, 1f, 0.8f, accent, dy)
            }
            Mascot.CURSOR -> {
                rect(canvas, viewport, 11f, 5.8f, 2.2f, 0.9f, accent, dy)
                rect(canvas, viewport, 11f, 5.8f, 0.9f, 3f, accent, dy)
                rect(canvas, viewport, 12.2f, 7.6f, 1f, 1f, accent, dy)
            }
            Mascot.GEMINI -> {
                rect(canvas, viewport, 10.9f, 5.8f, 0.9f, 0.9f, accent, dy)
                rect(canvas, viewport, 12.3f, 7.1f, 0.9f, 0.9f, accent, dy)
                rect(canvas, viewport, 11.5f, 6.5f, 1f, 0.8f, accent, dy)
            }
            Mascot.COPILOT -> {
                rect(canvas, viewport, 10.8f, 5.6f, 3f, 0.55f, accent, dy)
                rect(canvas, viewport, 10.8f, 7.95f, 3f, 0.55f, accent, dy)
                rect(canvas, viewport, 10.8f, 6.15f, 0.55f, 1.25f, accent, dy)
                rect(canvas, viewport, 13.25f, 6.15f, 0.55f, 1.25f, accent, dy)
                rect(canvas, viewport, 11.55f, 6.55f, 0.55f, 0.55f, COPILOT_EYE, dy)
                rect(canvas, viewport, 12.45f, 6.55f, 0.55f, 0.55f, COPILOT_EYE, dy)
            }
            Mascot.WORKBUDDY -> {
                oval(canvas, viewport, 10.6f, 5.4f, 3.2f, 3.2f, accent, dy)
                rect(canvas, viewport, 11.85f, 4.3f, 0.55f, 0.9f, WORKBUDDY_BODY_DARK, dy)
                oval(canvas, viewport, 11.25f, 3.6f, 1.7f, 1.1f, WORKBUDDY_BODY_LIGHT, dy)
            }
            Mascot.OPENCODE -> {
                rect(canvas, viewport, 10.6f, 5.4f, 3.4f, 3.4f, accent, dy)
                rect(canvas, viewport, 11f, 5.8f, 2.6f, 0.35f, OPENCODE_FRAME, dy)
                rect(canvas, viewport, 11f, 8.05f, 2.6f, 0.35f, OPENCODE_FRAME, dy)
                rect(canvas, viewport, 11.2f, 6.1f, 0.4f, 1.6f, OPENCODE_FACE, dy)
                rect(canvas, viewport, 11.45f, 5.85f, 0.55f, 0.35f, OPENCODE_FACE, dy)
                rect(canvas, viewport, 11.45f, 7.55f, 0.55f, 0.35f, OPENCODE_FACE, dy)
                rect(canvas, viewport, 12.9f, 6.1f, 0.4f, 1.6f, OPENCODE_FACE, dy)
                rect(canvas, viewport, 12.5f, 5.85f, 0.55f, 0.35f, OPENCODE_FACE, dy)
                rect(canvas, viewport, 12.5f, 7.55f, 0.55f, 0.35f, OPENCODE_FACE, dy)
            }
            Mascot.HERMES -> {
                val hood = Path().apply {
                    moveTo(viewport.left + 12.25f * viewport.scale, viewport.top + (5.1f - viewport.y0 + dy) * viewport.scale)
                    lineTo(viewport.left + 13.8f * viewport.scale, viewport.top + (7.8f - viewport.y0 + dy) * viewport.scale)
                    lineTo(viewport.left + 10.7f * viewport.scale, viewport.top + (7.8f - viewport.y0 + dy) * viewport.scale)
                    close()
                }
                fillPaint.color = HERMES_HOOD
                canvas.drawPath(hood, fillPaint)
                roundRect(canvas, viewport, 10.7f, 6.4f, 3.1f, 2.5f, 0.8f * viewport.scale, accent, dy)
                oval(canvas, viewport, 11.2f, 7.0f, 0.55f, 0.45f, HERMES_EYE, dy)
                oval(canvas, viewport, 12.7f, 7.0f, 0.55f, 0.45f, HERMES_EYE, dy)
            }
            Mascot.STEPFUN -> {
                rect(canvas, viewport, 10.7f, 5.7f, 3.2f, 2.6f, accent, dy)
                rect(canvas, viewport, 12.6f, 4.8f, 1.3f, 0.9f, STEPFUN_BODY_LIGHT, dy)
                rect(canvas, viewport, 11.3f, 4.8f, 1.3f, 0.9f, STEPFUN_BODY_DARK, dy)
                rect(canvas, viewport, 11.2f, 6.6f, 0.55f, 0.75f, Color.WHITE, dy)
                rect(canvas, viewport, 12.6f, 6.6f, 0.55f, 0.75f, Color.WHITE, dy)
            }
            else -> {
                rect(canvas, viewport, 10.8f, 5.5f, 3f, 3f, accent, dy)
                rect(canvas, viewport, 11.5f, 6.2f, 1.6f, 1.6f, inverse, dy)
            }
        }
    }

    private fun bodyDarkColor(): Int = mascot.accentColor.darker(0.26f)

    private fun detailColor(): Int = mascot.accentColor.lighter(0.18f)

    private fun luma(color: Int): Float {
        return (0.299f * Color.red(color) + 0.587f * Color.green(color) + 0.114f * Color.blue(color)) / 255f
    }

    private fun drawEyes(canvas: Canvas, viewport: Viewport, dy: Float, color: Int, scale: Float) {
        val eyeHeight = max(0.2f, 1.2f * scale)
        val eyeY = 7.5f + (1.2f - eyeHeight) / 2f
        rect(canvas, viewport, 5f, eyeY, 1.2f, eyeHeight, color, dy)
        rect(canvas, viewport, 8.8f, eyeY, 1.2f, eyeHeight, color, dy)
    }

    private fun drawBang(canvas: Canvas, viewport: Viewport, jumpY: Float, opacity: Float, scale: Float) {
        val widthUnits = 2f * scale
        val baseX = 13f
        val baseY = 4f + jumpY * 0.15f
        rect(canvas, viewport, baseX, baseY, widthUnits, 3.5f * scale, ALERT_COLOR.withAlpha(opacity))
        rect(canvas, viewport, baseX, baseY + 4f * scale, widthUnits, 1.5f * scale, ALERT_COLOR.withAlpha(opacity))
    }

    private fun rect(
        canvas: Canvas,
        viewport: Viewport,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        color: Int,
        dy: Float = 0f,
    ) {
        fillPaint.color = color
        val left = viewport.left + x * viewport.scale
        val top = viewport.top + (y - viewport.y0 + dy) * viewport.scale
        val rect = RectF(left, top, left + w * viewport.scale, top + h * viewport.scale)
        canvas.drawRect(rect, fillPaint)
    }

    private fun roundRect(
        canvas: Canvas,
        viewport: Viewport,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        radiusPx: Float,
        color: Int,
        dy: Float = 0f,
    ) {
        fillPaint.color = color
        val left = viewport.left + x * viewport.scale
        val top = viewport.top + (y - viewport.y0 + dy) * viewport.scale
        val rect = RectF(left, top, left + w * viewport.scale, top + h * viewport.scale)
        canvas.drawRoundRect(rect, radiusPx, radiusPx, fillPaint)
    }

    private fun oval(
        canvas: Canvas,
        viewport: Viewport,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        color: Int,
        dy: Float = 0f,
    ) {
        fillPaint.color = color
        val left = viewport.left + x * viewport.scale
        val top = viewport.top + (y - viewport.y0 + dy) * viewport.scale
        val rect = RectF(left, top, left + w * viewport.scale, top + h * viewport.scale)
        canvas.drawOval(rect, fillPaint)
    }

    private fun rotatedRect(
        canvas: Canvas,
        viewport: Viewport,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        pivotX: Float,
        pivotY: Float,
        angleDeg: Float,
        color: Int,
        dy: Float = 0f,
    ) {
        val px = viewport.left + pivotX * viewport.scale
        val py = viewport.top + (pivotY - viewport.y0 + dy) * viewport.scale
        canvas.save()
        canvas.rotate(angleDeg, px, py)
        rect(canvas, viewport, x, y, w, h, color, dy)
        canvas.restore()
    }

    private fun lerp(keyframes: List<Pair<Float, Float>>, pct: Float): Float {
        val clamped = pct.coerceIn(0f, 1f)
        if (clamped <= keyframes.first().first) return keyframes.first().second
        for (index in 1 until keyframes.size) {
            val (endPct, endValue) = keyframes[index]
            if (clamped <= endPct) {
                val (startPct, startValue) = keyframes[index - 1]
                val progress = (clamped - startPct) / (endPct - startPct)
                return startValue + (endValue - startValue) * progress
            }
        }
        return keyframes.last().second
    }

    private data class Viewport(
        val viewWidth: Float,
        val viewHeight: Float,
        val unitsWidth: Float,
        val unitsHeight: Float,
        val y0: Float,
    ) {
        val scale: Float = min(viewWidth / unitsWidth, viewHeight / unitsHeight)
        val left: Float = (viewWidth - unitsWidth * scale) / 2f
        val top: Float = (viewHeight - unitsHeight * scale) / 2f
    }

    private enum class Scene {
        SLEEP,
        WORK,
        ALERT,
    }

    private companion object {
        val BODY = Color.rgb(108, 77, 255)
        val ALERT_COLOR = Color.rgb(255, 61, 0)
        val KB_BASE = Color.rgb(46, 39, 77)
        val KB_KEY = Color.rgb(89, 77, 140)
        val CLAUDE_BODY = Color.rgb(222, 136, 109)
        val CLAUDE_KB_BASE = Color.rgb(97, 112, 128)
        val CLAUDE_KB_KEY = Color.rgb(153, 168, 184)
        val CLAUDE_KB_HI = Color.WHITE
        val TRAE_BODY = Color.rgb(34, 197, 94)
        val TRAE_BODY_DARK = Color.rgb(16, 143, 81)
        val TRAE_SCREEN = Color.rgb(36, 51, 36)
        val TRAE_EYE = Color.rgb(34, 197, 94)
        val TRAE_KB_BASE = Color.rgb(26, 36, 26)
        val TRAE_KB_KEY = Color.rgb(51, 77, 51)
        val TRAE_KB_HI = Color.rgb(34, 197, 94)
        val CODEX_CLOUD = Color.rgb(235, 235, 237)
        val CODEX_CLOUD_DARK = Color.rgb(179, 179, 184)
        val CODEX_PROMPT = Color.BLACK
        val CODEX_ALERT = Color.rgb(255, 140, 0)
        val CODEX_KB_BASE = Color.rgb(46, 46, 51)
        val CODEX_KB_KEY = Color.rgb(102, 102, 107)
        val CODEX_KB_HI = Color.WHITE
        val GEMINI_BLUE = Color.rgb(71, 150, 228)
        val GEMINI_PURPLE = Color.rgb(132, 122, 206)
        val GEMINI_ROSE = Color.rgb(195, 103, 127)
        val GEMINI_KB_BASE = Color.rgb(56, 64, 97)
        val GEMINI_KB_KEY = Color.rgb(102, 112, 148)
        val GEMINI_KB_HI = Color.WHITE
        val COPILOT_EAR = Color.rgb(51, 51, 51)
        val COPILOT_BODY = Color.rgb(204, 51, 102)
        val COPILOT_FACE = Color.rgb(33, 33, 41)
        val COPILOT_EYE = Color.rgb(255, 214, 0)
        val COPILOT_ALERT = Color.rgb(254, 76, 37)
        val COPILOT_KB_BASE = Color.rgb(31, 20, 26)
        val COPILOT_KB_KEY = Color.rgb(89, 38, 56)
        val WORKBUDDY_BODY = Color.rgb(121, 97, 222)
        val WORKBUDDY_BODY_DARK = Color.rgb(97, 74, 191)
        val WORKBUDDY_BODY_LIGHT = Color.rgb(148, 122, 240)
        val WORKBUDDY_KB_BASE = Color.rgb(26, 46, 41)
        val WORKBUDDY_KB_KEY = Color.rgb(46, 82, 71)
        val OPENCODE_BODY = Color.rgb(56, 56, 61)
        val OPENCODE_FRAME = Color.rgb(140, 140, 145)
        val OPENCODE_FACE = Color.rgb(217, 217, 222)
        val OPENCODE_LEG = Color.rgb(89, 89, 94)
        val OPENCODE_ALERT = Color.rgb(255, 140, 0)
        val OPENCODE_KB_BASE = Color.rgb(31, 31, 36)
        val OPENCODE_KB_KEY = Color.rgb(77, 77, 82)
        val HERMES_BODY = Color.rgb(122, 88, 176)
        val HERMES_BODY_DARK = Color.rgb(97, 66, 148)
        val HERMES_HOOD = Color.rgb(102, 71, 158)
        val HERMES_EYE = Color.WHITE
        val HERMES_KB_BASE = Color.rgb(31, 20, 46)
        val HERMES_KB_KEY = Color.rgb(61, 46, 87)
        val HERMES_KB_HI = Color.rgb(217, 217, 242)
        val STEPFUN_BODY = Color.rgb(46, 191, 179)
        val STEPFUN_BODY_DARK = Color.rgb(31, 153, 143)
        val STEPFUN_BODY_LIGHT = Color.rgb(77, 222, 209)
        val STEPFUN_KB_BASE = Color.rgb(31, 46, 43)
        val STEPFUN_KB_KEY = Color.rgb(56, 82, 77)
        val STEPFUN_KB_HI = Color.WHITE

        fun Int.withAlpha(alpha: Float): Int {
            return Color.argb((255 * alpha.coerceIn(0f, 1f)).toInt(), Color.red(this), Color.green(this), Color.blue(this))
        }

        fun Int.lighter(amount: Float): Int {
            val t = amount.coerceIn(0f, 1f)
            return Color.rgb(
                (Color.red(this) + (255 - Color.red(this)) * t).toInt(),
                (Color.green(this) + (255 - Color.green(this)) * t).toInt(),
                (Color.blue(this) + (255 - Color.blue(this)) * t).toInt(),
            )
        }

        fun Int.darker(amount: Float): Int {
            val t = (1f - amount.coerceIn(0f, 1f)).coerceIn(0f, 1f)
            return Color.rgb(
                (Color.red(this) * t).toInt(),
                (Color.green(this) * t).toInt(),
                (Color.blue(this) * t).toInt(),
            )
        }
    }
}
