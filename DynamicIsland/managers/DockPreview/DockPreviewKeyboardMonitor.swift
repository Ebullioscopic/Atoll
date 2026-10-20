/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices

/// Event callbacks only route selection; window discovery runs outside the tap.
@MainActor
final class DockPreviewKeyboardMonitor {
    enum Action: Equatable { case step(Bool), commit, cancel }
    var onAction: (Action) -> Void = { _ in }
    var canBegin: () -> Bool = { true }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumed = Set<Int64>()
    private(set) var isSwitching = false
    var isInstalled: Bool { tap != nil }

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                Unmanaged<DockPreviewKeyboardMonitor>.fromOpaque(context).takeUnretainedValue().process(type: type, event: event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    func reset() { isSwitching = false }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil; tap = nil; reset(); consumed.removeAll()
    }
    func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset(); onAction(.cancel)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, consumed.remove(key) != nil { return nil }
        if type == .flagsChanged, isSwitching, !event.flags.contains(.maskCommand) {
            reset(); onAction(.commit)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        if key == 48, flags == .maskCommand || flags == [.maskCommand, .maskShift] {
            guard isSwitching || canBegin() else { return Unmanaged.passUnretained(event) }
            isSwitching = true; consumed.insert(key); onAction(.step(!flags.contains(.maskShift))); return nil
        }
        if isSwitching {
            if key == 53 { reset(); consumed.insert(key); onAction(.cancel); return nil }
            if key == 36 { reset(); consumed.insert(key); onAction(.commit); return nil }
            if key == 123 || key == 124 { consumed.insert(key); onAction(.step(key == 124)); return nil }
        }
        return Unmanaged.passUnretained(event)
    }
}

struct DockPreviewSwitchSelection {
    let pids: [pid_t]
    private(set) var index: Int
    var selectedPID: pid_t? { pids.indices.contains(index) ? pids[index] : nil }
    init(pids: [pid_t], frontmost: pid_t?, forward: Bool) {
        self.pids = pids
        index = frontmost.flatMap { pids.firstIndex(of: $0) } ?? (forward ? pids.count - 1 : 0)
        step(forward)
    }
    mutating func step(_ forward: Bool) {
        guard !pids.isEmpty else { return }
        index = (index + (forward ? 1 : pids.count - 1)) % pids.count
    }
}
