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
import Combine

/// 清洁屏幕：把所有显示器涂黑，方便看清污渍擦拭。
///
/// 纯 AppKit 覆盖窗口，不需要任何权限。
/// 监听 `didChangeScreenParametersNotification` 以应对清洁期间插拔显示器、
/// 改分辨率、改排列 —— 否则新接的屏幕会露出桌面。
final class ScreenCleaningManager: ObservableObject {
    static let shared = ScreenCleaningManager()

    @Published private(set) var isActive = false

    private var overlayWindows: [CleaningOverlayWindow] = []
    private var screenChangeObserver: NSObjectProtocol?

    private init() {}

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive else { return }

        // 两种清洁模式互斥：都用同层全屏黑遮罩，同时开会叠在一起，
        // 点一下只关掉最上面那层，另一层黑屏无提示、无从退出。
        KeyboardCleaningManager.shared.stop()

        isActive = true
        buildOverlays()

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            // 显示器拓扑变了，整套重建最省事也最不容易漏屏。
            self.tearDownOverlays()
            self.buildOverlays()
        }

        NSLog("✅ [ScreenCleaning] 清洁屏幕已开启（\(overlayWindows.count) 块屏幕）")
    }

    func stop() {
        guard isActive else { return }

        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        tearDownOverlays()
        isActive = false
        NSLog("✅ [ScreenCleaning] 清洁屏幕已关闭")
    }

    // MARK: - 覆盖窗口

    private func buildOverlays() {
        let hint = String(
            localized: "Click anywhere or press Esc to finish cleaning",
            comment: "清洁屏幕覆盖层上的退出提示"
        )

        overlayWindows = NSScreen.screens.map { screen in
            let window = CleaningOverlayWindow.make(
                for: screen,
                hint: hint,
                allowsKeyboardDismiss: true
            ) { [weak self] in
                self?.stop()
            }
            window.orderFrontRegardless()
            return window
        }

        // 只让第一块屏的窗口成为 key，负责收 ESC。
        overlayWindows.first?.makeKey()
        fadeOutHints()
    }

    private func tearDownOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    /// 提示文案 3 秒后淡出 —— 留着会挡住要擦的那块区域。
    private func fadeOutHints() {
        let labels = overlayWindows.compactMap { window in
            window.contentView?.subviews.first as? NSTextField
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isActive else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.0
                labels.forEach { $0.animator().alphaValue = 0 }
            }
        }
    }
}
