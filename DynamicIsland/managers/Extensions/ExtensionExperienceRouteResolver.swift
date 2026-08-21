import CoreGraphics

/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

struct ExtensionExperienceRouteCandidate: Equatable {
    let experienceID: String
    let bundleIdentifier: String
    let hasTabConfiguration: Bool
}

enum ExtensionExperienceRouteResolver {
    static let targetExperienceMetadataKey = "atoll.targetNotchExperienceID"

    static func resolveTargetExperienceID(
        liveActivityBundleIdentifier: String,
        metadata: [String: String],
        extensionTabsEnabled: Bool,
        candidates: [ExtensionExperienceRouteCandidate]
    ) -> String? {
        guard extensionTabsEnabled,
              let targetExperienceID = metadata[targetExperienceMetadataKey],
              !targetExperienceID.isEmpty else {
            return nil
        }

        return candidates.first {
            $0.experienceID == targetExperienceID
                && $0.bundleIdentifier == liveActivityBundleIdentifier
                && $0.hasTabConfiguration
        }?.experienceID
    }
}

enum ExtensionExperienceHeightResolver {
    static func preferredHeight(
        requestedHeight: CGFloat?,
        baseHeight: CGFloat,
        standardMaximumHeight: CGFloat,
        builtInMaximumHeight: CGFloat,
        isBuiltInExperience: Bool
    ) -> CGFloat? {
        guard let requestedHeight else { return nil }
        let maximumHeight = isBuiltInExperience ? builtInMaximumHeight : standardMaximumHeight
        return min(max(requestedHeight, baseHeight), maximumHeight)
    }
}
