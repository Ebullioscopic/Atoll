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

import Foundation
import Defaults
import AtollExtensionKit
import SwiftUI

struct ExtensionLiveActivityPayload: Identifiable, Hashable, Codable {
    let bundleIdentifier: String
    let descriptor: AtollLiveActivityDescriptor
    let receivedAt: Date

    var id: String { descriptor.id }

    var priority: AtollLiveActivityPriority { descriptor.priority }
}

struct AgentHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let agentName: String
    let eventType: String
    let details: String
    let statusColorHex: String
}

struct ExtensionLockScreenWidgetPayload: Identifiable, Hashable, Codable {
    let bundleIdentifier: String
    let descriptor: AtollLockScreenWidgetDescriptor
    let receivedAt: Date

    var id: String { descriptor.id }

    var priority: AtollLiveActivityPriority { descriptor.priority }
}

struct ExtensionNotchExperiencePayload: Identifiable, Hashable, Codable {
    let bundleIdentifier: String
    let descriptor: AtollNotchExperienceDescriptor
    let receivedAt: Date

    var id: String { descriptor.id }

    var priority: AtollLiveActivityPriority { descriptor.priority }

    var hasTabConfiguration: Bool { descriptor.tab != nil }

    var hasMinimalisticConfiguration: Bool { descriptor.minimalistic != nil }
}

enum ExtensionValidationError: LocalizedError, Equatable {
    case featureDisabled
    case unauthorized
    case invalidDescriptor(String)
    case rateLimited
    case exceedsCapacity
    case duplicateIdentifier
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "Extensions feature is currently disabled in Atoll."
        case .unauthorized:
            return "Your app is not authorized to post this content."
        case .invalidDescriptor(let reason):
            return "Descriptor validation failed: \(reason)."
        case .rateLimited:
            return "Too many requests in a short period. Please slow down."
        case .exceedsCapacity:
            return "Atoll reached its limit for simultaneous extension content."
        case .duplicateIdentifier:
            return "An item with the same identifier already exists."
        case .unsupportedContent:
            return "Descriptor includes unsupported content for this surface."
        }
    }
}
