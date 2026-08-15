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
import AuthenticationServices

/// Seam for injecting a stubbed login flow in tests: ASWebAuthenticationSession
/// cannot be driven headlessly.
@MainActor
protocol SpotifyAuthSessionPresenting {
    /// Returns the callback URL, or throws `SpotifyLibraryError.canceled` when
    /// the user closes the login window.
    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL
}

@MainActor
final class WebAuthenticationSessionPresenter: NSObject, SpotifyAuthSessionPresenting {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                // ASWebAuthenticationSession calls this once, but resuming a
                // continuation twice traps: keep the guard as cheap insurance.
                guard !hasResumed else { return }
                hasResumed = true

                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: SpotifyLibraryError.canceled)
                    } else {
                        continuation.resume(
                            throwing: SpotifyLibraryError.authSessionFailed(error.localizedDescription)
                        )
                    }
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: SpotifyLibraryError.missingAuthorizationCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }
}

extension WebAuthenticationSessionPresenter: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
