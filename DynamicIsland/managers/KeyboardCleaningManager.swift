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
import ApplicationServices
import Combine
import CoreGraphics

/// 系统定义事件（功能键行的亮度/音量/播放控制走这个类型）。
/// `CGEventType` 没有对应的 Swift case，只能按原始值写，与 MediaKeyInterceptor 一致。
private let NX_SYSDEFINED_EVENT_TYPE: UInt32 = 14

/// 清洁键盘：临时吞掉所有键盘事件，擦键盘时不会误触发。
///
/// 用 `CGEvent.tapCreate` 以 `.defaultTap` 模式拦截 `keyDown` / `keyUp` / `flagsChanged`
/// 并返回 `nil` 吞掉，需要**辅助功能权限**。
///
/// 已知边界（做不到的部分，不是 bug）：
/// - **电源键 / Touch ID 吞不掉** —— 它们不走 CGEvent 通道。
/// - **secure input 期间 tap 整体失效** —— 例如密码输入框处于激活状态时。
/// - 退出只能靠**鼠标点击**（按键全被吞了，ESC 传不到覆盖层），另有超时兜底。
final class KeyboardCleaningManager: ObservableObject {
    static let shared = KeyboardCleaningManager()

    /// 兜底自动退出时间。万一鼠标也出问题，不至于把键盘永久锁死。
    private static let failsafeTimeout: TimeInterval = 120

    @Published private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayWindows: [CleaningOverlayWindow] = []
    private var failsafeTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?

    private let tapLocations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

    private init() {}

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }

        guard requestAccessibilityPermissionIfNeeded() else {
            NSLog("⚠️ [KeyboardCleaning] 缺少辅助功能权限，无法拦截键盘")
            return false
        }

        guard installEventTap() else {
            NSLog("❌ [KeyboardCleaning] 创建键盘 event tap 失败")
            return false
        }

        // 两种清洁模式互斥：都用同层全屏黑遮罩，同时开会叠在一起，
        // 点一下只关掉最上面那层，另一层黑屏无提示、无从退出。
        ScreenCleaningManager.shared.stop()

        isActive = true
        buildOverlays()
        startFailsafeTimer()

        // observer 只在 start() 注册一次；放进 buildOverlays() 会在它自己的回调里
        // 被反复注册 —— 每次屏幕变更 observer 数量翻倍，进程级泄漏（对齐 ScreenCleaningManager）。
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.tearDownOverlays()
            self.buildOverlays()
        }

        NSLog("✅ [KeyboardCleaning] 清洁键盘已开启")
        return true
    }

    func stop() {
        guard isActive else { return }

        failsafeTimer?.invalidate()
        failsafeTimer = nil

        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        removeEventTap()
        tearDownOverlays()
        isActive = false

        NSLog("✅ [KeyboardCleaning] 清洁键盘已关闭")
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        // 光挂 keyDown/keyUp/flagsChanged 是不够的：功能键行（亮度、音量、播放控制）
        // 走的是 NX_SYSDEFINED 系统定义事件，不在这三类里 —— 漏了它，擦键盘时按到
        // F1/F2 照样调亮度、F8 照样暂停音乐。参见 MediaKeyInterceptor，它处理的正是这类事件。
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << NX_SYSDEFINED_EVENT_TYPE)

        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let manager = Unmanaged<KeyboardCleaningManager>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return manager.handleEvent(cgEvent: cgEvent, type: type)
        }

        var createdTap: CFMachPort?
        for location in tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) {
                createdTap = tap
                break
            }
        }

        guard let tap = createdTap else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(cgEvent: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        // 系统会在 tap 处理超时或用户输入时把它禁掉，必须重新打开，
        // 否则清洁模式看着还开着，键盘却已经放行了。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isActive, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                NSLog(
                    "[KeyboardCleaning] event tap 被%@禁用，已重新启用",
                    type == .tapDisabledByTimeout ? "超时" : "用户输入"
                )
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // 吞掉。
        return nil
    }

    // MARK: - 覆盖层

    private func buildOverlays() {
        let hint = String(
            localized: "Keyboard is locked for cleaning — click anywhere to finish",
            comment: "清洁键盘覆盖层上的退出提示"
        )

        overlayWindows = NSScreen.screens.map { screen in
            let window = CleaningOverlayWindow.make(
                for: screen,
                hint: hint,
                // 按键全被吞了，ESC 到不了这里，只能靠鼠标。
                allowsKeyboardDismiss: false
            ) { [weak self] in
                self?.stop()
            }
            window.orderFrontRegardless()
            return window
        }
    }

    private func tearDownOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func startFailsafeTimer() {
        failsafeTimer?.invalidate()
        failsafeTimer = Timer.scheduledTimer(
            withTimeInterval: Self.failsafeTimeout,
            repeats: false
        ) { [weak self] _ in
            NSLog("[KeyboardCleaning] 达到兜底超时，自动退出清洁模式")
            self?.stop()
        }
    }

    // MARK: - 权限

    @discardableResult
    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
