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

import SwiftUI
@preconcurrency import WebKit

struct SpotifyOAuthSheet: View {
    let authorizeURL: URL
    let verifier: String
    var onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Connect Spotify")).font(.headline)
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
            }.padding()
            AuthWebView(url: authorizeURL) { callbackURL in
                let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
                if let code {
                    Task { @MainActor in
                        await SpotifyOAuthManager.shared.exchangeCode(code, verifier: verifier)
                        onFinished()
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            }
        }
        .frame(width: 520, height: 640)
    }
}

private struct AuthWebView: NSViewRepresentable {
    let url: URL
    var onCallback: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCallback: onCallback) }
    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let onCallback: (URL) -> Void
        init(onCallback: @escaping (URL) -> Void) { self.onCallback = onCallback }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = navigationAction.request.url, u.absoluteString.hasPrefix(SpotifyOAuthManager.redirectURI) {
                decisionHandler(.cancel)
                onCallback(u)
                return
            }
            decisionHandler(.allow)
        }
    }
}
