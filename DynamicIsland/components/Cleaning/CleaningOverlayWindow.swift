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

/// 清洁模式用的全屏覆盖窗口（清洁屏幕 / 清洁键盘共用）。
///
/// 必须能成为 key window，否则收不到 ESC。
final class CleaningOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 覆盖层内容视图：负责接收退出手势并画提示文案。
final class CleaningOverlayView: NSView {
    /// 用户要求退出清洁模式时回调。
    var onDismiss: (() -> Void)?

    /// 是否允许键盘（ESC）退出。
    ///
    /// 清洁键盘模式下按键会被 event tap 吞掉，根本传不到这里，
    /// 所以那种场景只能靠鼠标点击退出 —— 提示文案也要相应改写。
    var allowsKeyboardDismiss = true

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        guard allowsKeyboardDismiss else { return }
        if event.keyCode == 53 { // ESC
            onDismiss?()
        }
    }
}

extension CleaningOverlayWindow {
    /// 在指定屏幕上建一个铺满的黑色覆盖窗口。
    static func make(for screen: NSScreen, hint: String, allowsKeyboardDismiss: Bool, onDismiss: @escaping () -> Void) -> CleaningOverlayWindow {
        let window = CleaningOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        // 盖住菜单栏、Dock 和全屏 App。
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let contentView = CleaningOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView.allowsKeyboardDismiss = allowsKeyboardDismiss
        contentView.onDismiss = onDismiss
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        let label = NSTextField(labelWithString: hint)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        window.contentView = contentView
        return window
    }
}
