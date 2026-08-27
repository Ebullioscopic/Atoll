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

import AppKit
import ApplicationServices
import Foundation

final class TidalController: FilteredNowPlayingController {
    static let bundleIdentifier = "com.tidal.desktop"

    init?() {
        super.init(
            bundleIdentifier: Self.bundleIdentifier,
            controllerName: "TidalController"
        )
    }

    // MARK: - Favouriting, read only

    // TIDAL's heart can be read but not written -- see TidalAccessibility for
    // everything that was tried. Reading is still worth having: the control
    // shows whether the playing track is in the collection, and simply does
    // not take a click.

    @MainActor
    override var canEverFavorite: Bool { true }

    @MainActor
    override var supportsFavoriting: Bool { TidalAccessibility.isAvailable }

    @MainActor
    override var favoritingIsReadOnly: Bool { true }

    override func isCurrentTrackFavorited() async -> Bool? {
        await TidalAccessibility.isCurrentTrackFavorited()
    }

    @discardableResult
    override func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool { false }

    // MARK: - Shuffle and repeat

    // TIDAL registers seven Media Remote commands and neither shuffle nor
    // repeat is among them, so the inherited implementations set a local flag
    // and send a command the app never listens for -- the button moved and
    // nothing happened. Both go through the Playback menu instead, which is
    // the one place TIDAL both reports the state and accepts a change.

    override func toggleShuffle() async {
        let current = await TidalAccessibility.isShuffled() ?? playbackState.isShuffled
        guard await TidalAccessibility.setShuffled(!current) else { return }
        await MainActor.run { applyShuffleState(!current) }
    }

    override func toggleRepeat() async {
        let current = await TidalAccessibility.repeatMode() ?? playbackState.repeatMode
        let next: RepeatMode
        switch current {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        guard await TidalAccessibility.setRepeatMode(next) else { return }
        await MainActor.run { applyRepeatMode(next) }
    }

    /// The Media Remote stream never mentions shuffle or repeat for TIDAL, so
    /// the state has to be asked for rather than waited on. Cheap enough to do
    /// on the same beat as everything else: two menu reads, no tree walk.
    func refreshPlaybackModes() async {
        guard TidalAccessibility.isAvailable else { return }

        if let shuffled = await TidalAccessibility.isShuffled() {
            await MainActor.run { applyShuffleState(shuffled) }
        }
        if let mode = await TidalAccessibility.repeatMode() {
            await MainActor.run { applyRepeatMode(mode) }
        }
    }
}



// MARK: - Accessibility

/// Everything Atoll can drive in TIDAL that TIDAL does not otherwise expose,
/// at file scope so the Now Playing source can reach it without owning a
/// controller.
///
/// TIDAL offers none of the doors the other sources do. It registers seven
/// Media Remote commands -- play, pause, toggle, stop, next, previous, seek --
/// and nothing else: no like, no rating, no shuffle, no repeat. It is an
/// Electron app with no scripting dictionary, and it opens no local port. What
/// it does have is an accessibility tree, and the controls are in it.
///
/// The heart lives in the player bar. Shuffle and repeat are read and written
/// through the Playback menu instead, which unlike the player bar buttons
/// reports its state: a menu item carries a check mark, and pressing a
/// particular repeat item sets that mode outright rather than cycling toward
/// it. Reading a menu this way does not open it on screen.
enum TidalAccessibility {
    static let bundleIdentifier = TidalController.bundleIdentifier

    /// All of this needs the accessibility permission Atoll already asks for
    /// elsewhere; without it the tree is empty rather than wrong.
    static var isAvailable: Bool {
        AXIsProcessTrusted() && runningApp != nil
    }

    // MARK: - Favouriting

    // Reading only. The heart is an AXCheckBox under #footerPlayer whose label
    // says whether the track is in the collection. Writing it is another
    // matter, and every way in was tried against a running TIDAL 2.43.2:
    //
    //   AXPress                      reports success, changes nothing
    //   setting AXValue              reports settable and succeeds, changes nothing
    //   AXShowMenu                   opens an unrelated menu
    //   the menu bar                 has no favourite item to press
    //   a real click via postToPid   changes nothing
    //
    // Shuffle and repeat below work because they are native menu items. The
    // heart is a web component that answers only a genuine user event in a
    // focused window, which is not something a control in the notch can be.
    //
    // So the control reports `favoritingIsReadOnly` and does not take a click.
    // If a way in ever turns up, `setCurrentTrackFavorited` is the only thing
    // that needs writing.

    static func isCurrentTrackFavorited() async -> Bool? {
        guard isAvailable else { return nil }
        return await onAccessibilityQueue { favoriteButton().flatMap(favoriteState(of:)) }
    }

    /// The two labels TIDAL puts on the heart. They are localised, so a TIDAL
    /// running in another language reports its state as unknown rather than
    /// guessed.
    private static let notFavoritedLabel = "Add to My Collection"
    private static let favoritedLabel = "Remove from My Collection"

    private static func favoriteState(of button: AXUIElement) -> Bool? {
        switch attribute(button, kAXDescriptionAttribute) as? String {
        case notFavoritedLabel: return false
        case favoritedLabel: return true
        default: return nil
        }
    }

    /// Kept between calls: the tree runs to a few thousand nodes, and the
    /// element only needs finding again once it stops answering.
    private static var cachedFavoriteButton: AXUIElement?

    private static func favoriteButton() -> AXUIElement? {
        if let cached = cachedFavoriteButton,
           attribute(cached, kAXDescriptionAttribute) != nil {
            return cached
        }
        cachedFavoriteButton = nil

        guard let root = applicationElement() else { return nil }
        var budget = searchBudget
        guard let footer = firstDescendant(of: root, budget: &budget, where: {
            attribute($0, "AXDOMIdentifier") as? String == "footerPlayer"
        }) else { return nil }

        budget = searchBudget
        let button = firstDescendant(of: footer, budget: &budget) { element in
            guard attribute(element, kAXRoleAttribute) as? String == kAXCheckBoxRole else {
                return false
            }
            // Anchored on the class rather than the label so finding it does
            // not depend on the app's language. The hash on the end changes
            // between builds; the name in front of it is TIDAL's own.
            let classes = attribute(element, "AXDOMClassList") as? [String] ?? []
            return classes.contains { $0.hasPrefix("_favoriteButton_") }
        }
        if let button { AXUIElementSetMessagingTimeout(button, messagingTimeout) }
        cachedFavoriteButton = button
        return button
    }

    private static let searchBudget = 12_000

    private static func firstDescendant(
        of element: AXUIElement,
        budget: inout Int,
        where matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard budget > 0 else { return nil }
        budget -= 1

        if matches(element) { return element }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = firstDescendant(of: child, budget: &budget, where: matches) {
                return found
            }
        }
        return nil
    }

    // MARK: - Shuffle

    static func isShuffled() async -> Bool? {
        guard isAvailable else { return nil }
        return await onAccessibilityQueue {
            playbackMenuItem(titled: shuffleTitle).map(isChecked)
        }
    }

    @discardableResult
    static func setShuffled(_ shuffled: Bool) async -> Bool {
        guard isAvailable else { return false }

        return await onAccessibilityQueue {
            guard let item = playbackMenuItem(titled: shuffleTitle) else { return false }
            guard isChecked(item) != shuffled else { return true }
            guard press(item) else { return false }
            return settles {
                playbackMenuItem(titled: shuffleTitle).map(isChecked) == shuffled
            }
        }
    }

    // MARK: - Repeat

    static func repeatMode() async -> RepeatMode? {
        guard isAvailable else { return nil }
        return await onAccessibilityQueue {
            guard let items = repeatItems() else { return nil }
            guard let index = items.firstIndex(where: isChecked) else { return nil }
            return repeatModeOrder[index]
        }
    }

    @discardableResult
    static func setRepeatMode(_ mode: RepeatMode) async -> Bool {
        guard isAvailable else { return false }

        return await onAccessibilityQueue {
            guard let items = repeatItems(),
                  let wanted = repeatModeOrder.firstIndex(of: mode) else { return false }
            guard !isChecked(items[wanted]) else { return true }
            // Each item sets its own mode, so unlike the player bar button
            // there is nothing to cycle through and nothing to overshoot.
            guard press(items[wanted]) else { return false }
            return settles {
                guard let fresh = repeatItems() else { return false }
                return isChecked(fresh[wanted])
            }
        }
    }

    /// The submenu lists the three modes in this order. Read by position
    /// rather than by title, so only finding the submenu depends on language.
    private static let repeatModeOrder: [RepeatMode] = [.off, .all, .one]

    private static func repeatItems() -> [AXUIElement]? {
        guard let parent = playbackMenuItem(titled: repeatTitle),
              let submenu = (attribute(parent, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let items = attribute(submenu, kAXChildrenAttribute) as? [AXUIElement],
              items.count == repeatModeOrder.count else { return nil }
        return items
    }

    // MARK: - The Playback menu

    // Localised like the heart's labels, and unrecognised titles fall through
    // to an unknown state for the same reason.
    private static let playbackMenuTitle = "Playback"
    private static let shuffleTitle = "Shuffle"
    private static let repeatTitle = "Repeat"

    private static func playbackMenuItem(titled title: String) -> AXUIElement? {
        guard let root = applicationElement(),
              let menuBar = attribute(root, kAXMenuBarAttribute) else { return nil }

        let bar = menuBar as! AXUIElement
        guard let menus = attribute(bar, kAXChildrenAttribute) as? [AXUIElement],
              let playback = menus.first(where: {
                  attribute($0, kAXTitleAttribute) as? String == playbackMenuTitle
              }),
              let menu = (attribute(playback, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let items = attribute(menu, kAXChildrenAttribute) as? [AXUIElement] else { return nil }

        return items.first { attribute($0, kAXTitleAttribute) as? String == title }
    }

    /// A menu item carries a mark character only while it is the chosen one.
    private static func isChecked(_ item: AXUIElement) -> Bool {
        let mark = attribute(item, kAXMenuItemMarkCharAttribute) as? String
        return !(mark ?? "").isEmpty
    }

    // MARK: - Plumbing

    private static let messagingTimeout: Float = 1
    // Wide enough for a network round trip: TIDAL does not move these
    // controls until its own server agrees, which is far slower than the press.
    private static let settleAttempts = 20
    private static let settleInterval: UInt32 = 150_000

    /// Accessibility calls block on the other application answering, so they
    /// are kept off the main thread and off each other.
    private static let accessibilityQueue = DispatchQueue(
        label: "com.atoll.tidal.accessibility",
        qos: .userInitiated
    )

    private static var runningApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private static func applicationElement() -> AXUIElement? {
        guard let app = runningApp else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    private static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// TIDAL updates these controls when its own state catches up rather than
    /// when the press lands, so success is whatever the app is showing shortly
    /// afterwards. The condition re-resolves its element each time, because a
    /// control that changes state may not be the same element afterwards.
    private static func settles(_ condition: () -> Bool) -> Bool {
        for _ in 0..<settleAttempts {
            usleep(settleInterval)
            if condition() { return true }
        }
        return false
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func onAccessibilityQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            accessibilityQueue.async { continuation.resume(returning: work()) }
        }
    }
}
