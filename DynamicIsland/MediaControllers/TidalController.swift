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

    // MARK: - Favouriting

    @MainActor
    override var canEverFavorite: Bool { true }

    @MainActor
    override var supportsFavoriting: Bool { TidalFavoriting.isAvailable }

    override func isCurrentTrackFavorited() async -> Bool? {
        await TidalFavoriting.isCurrentTrackFavorited()
    }

    @discardableResult
    override func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        await TidalFavoriting.setCurrentTrackFavorited(favorited)
    }
}

// MARK: - Favouriting

/// Favouriting for TIDAL, at file scope so the Now Playing source can reach it
/// without owning a controller -- the same shape as the other sources.
///
/// TIDAL gives us nothing the others do. It registers seven MediaRemote
/// commands and none of them is a like or a rating; it is an Electron app with
/// no scripting dictionary; and it opens no local port. What it does have is an
/// accessibility tree, and the now playing heart sits in it as a real control:
/// an `AXCheckBox` under `#footerPlayer` that answers `AXPress`.
///
/// Reading its state is the awkward half. `AXValue` is empty and `AXSelected`
/// stays `0` whether or not the track is in the collection, and the icon keeps
/// its class in both states -- TIDAL swaps the shape inside the SVG, which
/// accessibility does not describe. The only thing that moves is the label, so
/// that is what we read, and outside the languages we recognise the answer is
/// honestly unknown rather than guessed.
enum TidalFavoriting {
    static let bundleIdentifier = TidalController.bundleIdentifier

    /// Favouriting needs the accessibility permission Atoll already asks for
    /// elsewhere; without it the tree is empty rather than wrong.
    static var isAvailable: Bool {
        AXIsProcessTrusted() && runningApp != nil
    }

    static func isCurrentTrackFavorited() async -> Bool? {
        guard isAvailable else { return nil }
        return await onAccessibilityQueue { currentState() }
    }

    @discardableResult
    static func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        guard isAvailable else { return false }

        return await onAccessibilityQueue {
            // The control is a toggle, and a press made without knowing where
            // it stands is as likely to undo the request as to carry it out.
            guard let button = favoriteButton(),
                  let current = state(of: button) else { return false }
            guard current != favorited else { return true }
            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                return false
            }

            // The label follows the network round trip rather than the press,
            // so a press that never took effect would otherwise report success.
            for _ in 0..<Self.confirmationAttempts {
                usleep(Self.confirmationInterval)
                if state(of: button) == favorited { return true }
            }
            return false
        }
    }

    // MARK: - Reading the label

    /// The two labels TIDAL puts on the control. They are localised, so a
    /// TIDAL running in another language falls through to `nil`: the heart
    /// stays dimmed instead of claiming a state we cannot see.
    private static let notFavoritedLabel = "Add to My Collection"
    private static let favoritedLabel = "Remove from My Collection"

    private static func currentState() -> Bool? {
        guard let button = favoriteButton() else { return nil }
        return state(of: button)
    }

    private static func state(of button: AXUIElement) -> Bool? {
        switch attribute(button, kAXDescriptionAttribute) as? String {
        case notFavoritedLabel: return false
        case favoritedLabel: return true
        default: return nil
        }
    }

    // MARK: - Finding the control

    /// The tree runs to a few thousand nodes, so the element is kept between
    /// calls and only searched for again once it stops answering.
    private static var cachedButton: AXUIElement?

    private static func favoriteButton() -> AXUIElement? {
        if let cached = cachedButton, attribute(cached, kAXDescriptionAttribute) != nil {
            return cached
        }
        cachedButton = nil

        guard let app = runningApp else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, Self.messagingTimeout)

        var budget = Self.searchBudget
        guard let footer = firstDescendant(of: root, budget: &budget, where: {
            attribute($0, "AXDOMIdentifier") as? String == "footerPlayer"
        }) else { return nil }

        budget = Self.searchBudget
        let button = firstDescendant(of: footer, budget: &budget, where: isFavoriteButton)
        if let button {
            AXUIElementSetMessagingTimeout(button, Self.messagingTimeout)
        }
        cachedButton = button
        return button
    }

    /// Anchored on the class rather than the label so the search itself does
    /// not depend on the app's language. The hash on the end changes between
    /// builds; the name in front of it is TIDAL's own.
    private static func isFavoriteButton(_ element: AXUIElement) -> Bool {
        guard attribute(element, kAXRoleAttribute) as? String == kAXCheckBoxRole else { return false }
        let classes = attribute(element, "AXDOMClassList") as? [String] ?? []
        return classes.contains { $0.hasPrefix("_favoriteButton_") }
    }

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

    // MARK: - Plumbing

    private static let messagingTimeout: Float = 1
    private static let searchBudget = 12_000
    private static let confirmationAttempts = 8
    private static let confirmationInterval: UInt32 = 60_000

    /// Accessibility calls block on the other application answering, so they
    /// are kept off the main thread and off each other.
    private static let accessibilityQueue = DispatchQueue(
        label: "com.atoll.tidal.favoriting",
        qos: .userInitiated
    )

    private static var runningApp: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
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
