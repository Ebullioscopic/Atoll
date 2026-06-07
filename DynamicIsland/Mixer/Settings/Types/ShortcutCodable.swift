// Adapted from FineTune/Shortcuts/ShortcutCodable.swift (GPL-3.0, Ronit Singh).
// KeyboardShortcuts-package bridging removed for the Atoll port: the mixer
// does not register global hotkeys, but SettingsManager persists this type,
// so the Codable shape must remain identical for settings.json compatibility.
import Foundation

nonisolated struct ShortcutCodable: Codable, Equatable, Hashable, Sendable {
    var keyCode: Int
    var modifiers: UInt

    init(keyCode: Int, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
