/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import SwiftUI
import WebKit

/// The window Telegram is signed in through, which closes itself as soon as the
/// engine reports success.
///
/// It shows a web view of its own rather than a picture of a QR code: Telegram
/// offers a QR code *and* a phone number with a login code, and the second
/// needs somewhere to type. A live client covers both, and leaves the
/// credentials where they belong -- inside Telegram's own page, never passing
/// through this app.
///
/// Its own view, sharing the engine's data store, rather than the engine's
/// view moved here for the duration. A view has one superview, so borrowing it
/// took the client out of the window it monitors from and handed AppKit a live
/// web view to re-parent while a window was being torn down. Two views over
/// one store is what WebKit is built for; one view in two windows is not.
@MainActor
final class TelegramSignInWindowManager: NSObject, NSWindowDelegate {
    static let shared = TelegramSignInWindowManager()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        TelegramWebEngine.shared.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == .authenticated { self?.close() }
            }
            .store(in: &cancellables)
    }

    func show() {
        // Nothing to sign into until the engine is running, and it only runs
        // while the feature is on.
        TelegramWebEngine.shared.start()

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: TelegramSignInScreen(webView: TelegramWebEngine.shared.makeSignInWebView()))
        if #available(macOS 13.0, *) {
            // The web view inside reports the size it happens to be laid out
            // at -- the offscreen monitoring size -- and a hosting view that
            // forwards its content's size makes the window that tall. The
            // window's own size is the one that should win here.
            hosting.sizingOptions = []
        }

        // Telegram's sign-in is a phone number, then a code, then possibly a
        // password, each centred in a column: it needs height more than width,
        // but never more height than the screen has.
        let available = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size
            ?? CGSize(width: 1440, height: 900)
        let size = CGSize(
            width: min(520, available.width - 80),
            height: min(760, available.height - 80)
        )
        hosting.frame = NSRect(origin: .zero, size: size)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Connect Telegram"
        win.contentView = hosting
        win.contentMinSize = CGSize(width: 420, height: 480)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct TelegramSignInScreen: View {
    /// This window's own view onto Telegram. It shares the engine's data
    /// store, so signing in here signs in the client the engine watches.
    let webView: WKWebView

    @ObservedObject private var engine = TelegramWebEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if engine.authState == .signInRequired {
                instructions
            }

            if engine.authState == .authenticated {
                connected
            } else {
                TelegramWebViewHost(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: ChatService.telegram.badgeGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Telegram")
                    .font(.headline)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
        .padding(16)
        .background(.bar)
    }

    private var instructions: some View {
        HStack(spacing: 8) {
            Image(systemName: "qrcode.viewfinder")
                .foregroundStyle(.secondary)
            Text("Scan the code with Telegram on your phone — Settings › Devices › Link Desktop Device — or sign in with your phone number.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
    }

    private var connected: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(ChatService.telegram.accent)
            Text("Telegram connected")
                .font(.title2.weight(.semibold))
            Text("This window will close on its own.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusLabel: String {
        switch engine.authState {
        case .idle: return "Waiting…"
        case .loading: return "Loading…"
        case .signInRequired: return "Sign in to continue"
        case .authenticated: return "Connected ✓"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var statusColor: Color {
        switch engine.authState {
        case .authenticated: return .green
        case .error: return .red
        case .signInRequired: return .orange
        default: return .gray
        }
    }
}

struct TelegramWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
