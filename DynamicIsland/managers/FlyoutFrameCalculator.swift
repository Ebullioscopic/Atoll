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

/// Geometry for the small control panel that flies out beside the notch.
///
/// The screen frame is supplied by the caller so a refresh can reuse the
/// already-resolved display geometry. Keeping this separate from NSWindow and
/// SwiftUI also makes the hot path constant-time and straightforward to test
enum FlyoutFrameCalculator {
    private static let screenInset: CGFloat = 8

    static func frame(
        for contentSize: CGSize,
        screenFrame: NSRect,
        notchWidth: CGFloat,
        rightWingWidth: CGFloat,
        spacing: CGFloat
    ) -> NSRect {
        // The notch's right edge is screen midX + half its width. Avoid
        // constructing an intermediate notch rect on every hover refresh
        let rawOriginX = screenFrame.midX
            + notchWidth * 0.5
            + rightWingWidth
            + spacing
        let maximumOriginX = screenFrame.maxX - contentSize.width - screenInset
        let originX = max(
            screenFrame.minX + screenInset,
            min(rawOriginX, maximumOriginX)
        )
        let originY = screenFrame.maxY - contentSize.height

        return NSRect(
            x: originX.rounded(),
            y: originY.rounded(),
            width: contentSize.width.rounded(),
            height: contentSize.height.rounded()
        )
    }
}
#endif
