/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CoreGraphics

enum NotchHoverGeometry {
    static func containsActivationPoint(
        _ point: CGPoint,
        screenFrame: CGRect,
        closedNotchSize: CGSize,
        horizontalPadding: CGFloat = 8,
        verticalPadding: CGFloat = 10,
        minimumActivationHeight: CGFloat = 14
    ) -> Bool {
        let activationWidth = closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(
            closedNotchSize.height + verticalPadding,
            minimumActivationHeight
        )
        let activationRect = CGRect(
            x: screenFrame.midX - activationWidth / 2,
            y: screenFrame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return containsInclusive(point, in: activationRect)
    }

    static func containsInclusive(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }
}
