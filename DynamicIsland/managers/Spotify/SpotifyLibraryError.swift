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

/// Raw failure states of the Spotify library integration. Cases carry no
/// user-facing text: the settings view owns the wording and localization.
enum SpotifyLibraryError: Error, Equatable {
    /// The user has not pasted a Client ID from their Spotify Developer app.
    case missingClientID
    /// SecRandomCopyBytes failed; continuing would use predictable PKCE material.
    case secureRandomUnavailable
    /// The user closed the Spotify login window. Not surfaced as an error.
    case canceled
    case missingAuthorizationCode
    case authSessionFailed(String)
    case tokenExchangeFailed(String)
    /// Spotify rejected the refresh token: the user revoked the app or changed
    /// their password. The token pair has been cleared; the user must reconnect.
    case refreshTokenRevoked
}
