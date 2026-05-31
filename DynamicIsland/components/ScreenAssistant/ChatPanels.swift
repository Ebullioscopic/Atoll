/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit

// MARK: - Shared Utilities for Chat Panels

func applyChatPanelCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

// MARK: - Note: Shared Components (MarkdownText, AttachedFileChip, AddFilesButton, RecordingButton, ApiKeyAlertView)
// are defined in ScreenAssistantPanel.swift to avoid redeclaration conflicts.
//
// Chat panel views have been split into the Views/ subdirectory:
// - Views/ChatMessages.swift: ChatMessagesPanel + ChatMessagesView
// - Views/ChatInput.swift: ChatInputPanel + ChatInputView
// - Views/MessageBubble.swift: StreamingChatMessageBubble
// - Views/ScreenshotOptions.swift: ScreenshotButton, ScreenshotOptionsPopover, ScreenshotOptionButton
// - Views/PanelsVisualEffect.swift: ChatPanelsVisualEffectView
// - Views/PopoverBackground.swift: ScreenshotPopoverBackground
