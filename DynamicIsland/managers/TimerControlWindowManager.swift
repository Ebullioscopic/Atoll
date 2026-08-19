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

#if os(macOS)
import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore

struct TimerControlWindowMetrics: FlyoutWindowMetrics {
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat
    let contentRevision: AnyHashable
}

@MainActor
final class TimerControlWindowManager {
    static let shared = TimerControlWindowManager()

    private let presenter: FlyoutWindowPresenter<TimerControlOverlay, TimerControlWindowMetrics>

    private init() {
        presenter = FlyoutWindowPresenter(initialWindowSize: CGSize(width: 220, height: 64)) { metrics in
            TimerControlOverlay(
                notchHeight: metrics.notchHeight,
                cornerRadius: metrics.cornerRadius
            )
        }
    }

    @discardableResult
    func present(using viewModel: DynamicIslandViewModel, metrics: TimerControlWindowMetrics) -> Bool {
        guard !LockScreenManager.shared.currentLockStatus else {
            hide(animated: false)
            return false
        }
        return presenter.present(using: viewModel, metrics: metrics)
    }

    @discardableResult
    func refresh(using viewModel: DynamicIslandViewModel, metrics: TimerControlWindowMetrics) -> Bool {
        presenter.refresh(using: viewModel, metrics: metrics)
    }

    func hide(animated: Bool = true, tearDown: Bool = true) {
        presenter.hide(animated: animated, tearDown: tearDown)
    }
}

#endif
