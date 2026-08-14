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
import Defaults

enum ScreenCaptureScope: Int {
    case panelsOnly
    case entireInterface
    /// The teleprompter, which has its own switch.
    ///
    /// Being invisible to Zoom and to screen recorders is the whole point of a
    /// prompter, so it must not inherit a preference the user set for the notch —
    /// they are unrelated decisions.
    case teleprompter
}

final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let scopedWindows = NSMapTable<NSWindow, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let interfacePublisher = Defaults.publisher(.hideDynamicIslandFromScreenCapture)
            .map { _ in () }
            .eraseToAnyPublisher()

        let teleprompterPublisher = Defaults.publisher(.teleprompterHideFromScreenCapture)
            .map { _ in () }
            .eraseToAnyPublisher()

        interfacePublisher
            .merge(with: teleprompterPublisher)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateAllWindows()
            }
            .store(in: &cancellables)
    }

    func register(_ window: NSWindow, scope: ScreenCaptureScope) {
        scopedWindows.setObject(NSNumber(value: scope.rawValue), forKey: window)
        applyVisibility(to: window, scope: scope)
    }

    func unregister(_ window: NSWindow) {
        scopedWindows.removeObject(forKey: window)
    }

    private func updateAllWindows() {
        guard let windows = scopedWindows.keyEnumerator().allObjects as? [NSWindow] else { return }
        for window in windows {
            guard let raw = scopedWindows.object(forKey: window)?.intValue,
                  let scope = ScreenCaptureScope(rawValue: raw) else { continue }
            applyVisibility(to: window, scope: scope)
        }
    }

    /// The `scope` argument used to be ignored, so every registered window
    /// followed the one notch preference. It is honoured now, because the
    /// teleprompter's invisibility is a separate decision from the notch's.
    private func applyVisibility(to window: NSWindow, scope: ScreenCaptureScope) {
        let shouldHide: Bool
        switch scope {
        case .teleprompter:
            // Either switch hides it; neither alone reveals it.
            shouldHide = Defaults[.teleprompterHideFromScreenCapture]
                || Defaults[.hideDynamicIslandFromScreenCapture]
        case .panelsOnly, .entireInterface:
            shouldHide = Defaults[.hideDynamicIslandFromScreenCapture]
        }
        window.sharingType = shouldHide ? .none : .readOnly
    }
}
