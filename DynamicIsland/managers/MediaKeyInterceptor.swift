/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Foundation
import AppKit
import CoreGraphics
#if canImport(ApplicationServices)
import ApplicationServices
#endif

private let NX_SYSDEFINED_EVENT_TYPE: UInt32 = 14
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
private let NX_KEYTYPE_MUTE: Int32 = 7

enum MediaKeyDirection {
    case up
    case down
}

enum MediaKeyStep {
    case standard
    case fine
}

struct MediaKeyConfiguration {
    var interceptVolume: Bool
    var interceptBrightness: Bool
    var interceptCommandModifiedBrightness: Bool

    static let disabled = MediaKeyConfiguration(
        interceptVolume: false,
        interceptBrightness: false,
        interceptCommandModifiedBrightness: false
    )
}

protocol MediaKeyInterceptorDelegate: AnyObject {
    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveVolumeCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    )
    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveBrightnessCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    )
    func mediaKeyInterceptorDidToggleMute(_ interceptor: MediaKeyInterceptor)
}

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    weak var delegate: MediaKeyInterceptorDelegate?
    var configuration: MediaKeyConfiguration = .disabled {
        didSet {
            updateTapState()
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTapEnabled = false
#if canImport(ApplicationServices)
    private var didRequestAccessibilityPrompt = false
#endif
    private let systemDefinedEventType = CGEventType(rawValue: NX_SYSDEFINED_EVENT_TYPE)
    private let eventTapLocations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

    private init() {}

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else {
            updateTapState()
            return true
        }

#if canImport(ApplicationServices)
        requestAccessibilityPermissionIfNeeded()
#endif

        guard let systemDefinedType = systemDefinedEventType else {
            NSLog("❌ Unable to resolve system-defined event type")
            return false
        }
        let mask = CGEventMask(1) << systemDefinedType.rawValue
        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            return interceptor.handleEvent(cgEvent: cgEvent, type: type)
        }

        var createdTap: CFMachPort?
        for location in eventTapLocations {
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

        guard let tap = createdTap else {
#if canImport(ApplicationServices)
            if !AXIsProcessTrusted() {
                NSLog("⚠️ Accessibility permission missing; grant access in System Settings › Privacy & Security › Accessibility")
            }
#endif
            NSLog("❌ Failed to create media key event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isTapEnabled = true
        NSLog("✅ Media key event tap installed (HID)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTapEnabled = false
    }

    private func updateTapState() {
        guard let tap = eventTap else { return }
        let shouldEnable = configuration.interceptVolume || configuration.interceptBrightness || configuration.interceptCommandModifiedBrightness
        if shouldEnable != isTapEnabled {
            CGEvent.tapEnable(tap: tap, enable: shouldEnable)
            isTapEnabled = shouldEnable
        }
    }

    private func handleEvent(cgEvent: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("⚠️ Media key event tap was disabled by the system (reason: %@); re-enabled",
                      type == .tapDisabledByTimeout ? "timeout" : "user input")
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let systemDefinedType = systemDefinedEventType,
              type == systemDefinedType,
              let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA // 0xA = keyDown, 0xB = keyUp
        let isRepeat = (keyFlags & 0x0001) == 1
        let step = step(for: nsEvent, cgEvent: cgEvent)
        let modifiers = combinedModifiers(nsEvent: nsEvent, cgEvent: cgEvent)

        guard keyState else {
            // Swallow key-up events only when intercepting, otherwise let them pass through
            if shouldHandle(keyCode: Int32(keyCode), modifiers: modifiers) {
                return nil
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        switch Int32(keyCode) {
        case NX_KEYTYPE_SOUND_UP:
            guard configuration.interceptVolume else { return Unmanaged.passUnretained(cgEvent) }
            delegate?.mediaKeyInterceptor(self, didReceiveVolumeCommand: .up, step: step, isRepeat: isRepeat, modifiers: modifiers)
            return nil
        case NX_KEYTYPE_SOUND_DOWN:
            guard configuration.interceptVolume else { return Unmanaged.passUnretained(cgEvent) }
            delegate?.mediaKeyInterceptor(self, didReceiveVolumeCommand: .down, step: step, isRepeat: isRepeat, modifiers: modifiers)
            return nil
        case NX_KEYTYPE_MUTE:
            guard configuration.interceptVolume else { return Unmanaged.passUnretained(cgEvent) }
            delegate?.mediaKeyInterceptorDidToggleMute(self)
            return nil
        case NX_KEYTYPE_BRIGHTNESS_UP:
            guard shouldHandleBrightness(modifiers: modifiers) else { return Unmanaged.passUnretained(cgEvent) }
            delegate?.mediaKeyInterceptor(self, didReceiveBrightnessCommand: .up, step: step, isRepeat: isRepeat, modifiers: modifiers)
            return nil
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            guard shouldHandleBrightness(modifiers: modifiers) else { return Unmanaged.passUnretained(cgEvent) }
            delegate?.mediaKeyInterceptor(self, didReceiveBrightnessCommand: .down, step: step, isRepeat: isRepeat, modifiers: modifiers)
            return nil
        default:
            return Unmanaged.passUnretained(cgEvent)
        }
    }

    private func shouldHandle(keyCode: Int32, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE:
            return configuration.interceptVolume
        case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
            return configuration.interceptBrightness || (configuration.interceptCommandModifiedBrightness && modifiers.contains(.command))
        default:
            return false
        }
    }

    private func shouldHandleBrightness(modifiers: NSEvent.ModifierFlags) -> Bool {
        if configuration.interceptBrightness {
            return true
        }
        return configuration.interceptCommandModifiedBrightness && modifiers.contains(.command)
    }

    private func step(for event: NSEvent, cgEvent: CGEvent) -> MediaKeyStep {
        let modifiers = combinedModifiers(nsEvent: event, cgEvent: cgEvent)
        if modifiers.contains(.option) && modifiers.contains(.shift) {
            return .fine
        }
        return .standard
    }

    /// Combines modifier flags from both NSEvent and the underlying CGEvent.
    /// Karabiner Elements and similar tools may inject synthetic media key events
    /// where the modifier flags are only set on the CGEvent level, not propagated
    /// to the NSEvent's modifierFlags for NX_SYSDEFINED subtype-8 events.
    private func combinedModifiers(nsEvent: NSEvent, cgEvent: CGEvent) -> NSEvent.ModifierFlags {
        let nsFlags = nsEvent.modifierFlags
        let cgFlags = CGEventFlags(rawValue: cgEvent.flags.rawValue)
        var combined = nsFlags
        if cgFlags.contains(.maskAlternate) {
            combined.insert(.option)
        }
        if cgFlags.contains(.maskShift) {
            combined.insert(.shift)
        }
        if cgFlags.contains(.maskCommand) {
            combined.insert(.command)
        }
        if cgFlags.contains(.maskControl) {
            combined.insert(.control)
        }
        return combined
    }
}

#if canImport(ApplicationServices)
extension MediaKeyInterceptor {
    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted(), !didRequestAccessibilityPrompt else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        didRequestAccessibilityPrompt = true
    }
}
#endif
