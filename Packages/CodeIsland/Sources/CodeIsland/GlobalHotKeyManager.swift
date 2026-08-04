import AppKit
import Carbon.HIToolbox
import os.log

/// Registers global hotkeys via Carbon's `RegisterEventHotKey`. Unlike an
/// `NSEvent.addGlobalMonitorForEvents` keyboard monitor, Carbon hotkeys do NOT
/// require Accessibility permission and fire from any frontmost app — which is
/// exactly what an LSUIElement menu-bar app needs (it is almost never the key
/// app, so an NSEvent local monitor only fires while our own window is focused).
/// See #217.
final class GlobalHotKeyManager {
    nonisolated private static let log = Logger(subsystem: "com.codeisland", category: "GlobalHotKey")

    /// One installed Carbon hotkey plus the callback to run when it fires.
    private struct Entry {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    /// FourCharCode signature shared by every hotkey we register. The per-hotkey
    /// `id` field disambiguates which binding fired.
    private static let signature: OSType = {
        // "CISL" — CodeISLand
        let chars: [UInt8] = Array("CISL".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16)
            | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// Translate an AppKit keyCode (CG/virtual keycode) + modifier flags into a
    /// Carbon modifier mask. Exposed for unit testing.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    /// Register a global hotkey. The handler is invoked on the main thread when
    /// the key combo is pressed from any app. Returns false if registration
    /// fails (e.g. the combo is already owned by another app).
    @discardableResult
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(from: modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            Self.log.warning("RegisterEventHotKey failed (status \(status)) for keyCode \(keyCode)")
            return false
        }
        entries[id] = Entry(ref: ref, handler: handler)
        return true
    }

    /// Unregister every hotkey and remove the shared Carbon event handler.
    func unregisterAll() {
        for entry in entries.values {
            UnregisterEventHotKey(entry.ref)
        }
        entries.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Dispatch a fired hotkey to its handler. Called from the C trampoline.
    fileprivate func handle(id: UInt32) {
        entries[id]?.handler()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Pass `self` as the user-data context so the C trampoline can route
        // back to this instance without a global. Unretained: the manager owns
        // the handler and tears it down in unregisterAll/deinit.
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &spec,
            context,
            &eventHandler
        )
    }

    deinit {
        unregisterAll()
    }
}

/// C-compatible trampoline for the Carbon hotkey handler. Extracts the
/// `EventHotKeyID` from the event and routes it back to the owning manager via
/// the unretained context pointer.
private func globalHotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    // Carbon delivers on the main run loop already, but hop explicitly so the
    // handler can touch @MainActor UI state safely.
    DispatchQueue.main.async {
        manager.handle(id: id)
    }
    return noErr
}
