/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import AppKit
import SwiftUI
import WebKit
import Combine

/// Manages the QR-code window shown when WhatsApp needs authentication.
/// Auto-closes as soon as the engine reports `authenticated`.
@MainActor
final class WhatsAppQRWindowManager {
    static let shared = WhatsAppQRWindowManager()

    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        WhatsAppWebEngine.shared.$authState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                if state == .authenticated { self?.close() }
            }
            .store(in: &cancellables)
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: WhatsAppQRScreenView())
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 580)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Connetti WhatsApp"
        win.contentView = hosting
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - QR Screen View

struct WhatsAppQRScreenView: View {
    @ObservedObject private var engine = WhatsAppWebEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.07, green: 0.73, blue: 0.42),
                                Color(red: 0.04, green: 0.52, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("WhatsApp")
                        .font(.headline)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(16)
            .background(.bar)

            Divider()

            // Instruction banner (visible only when QR needed)
            if engine.authState == .qrRequired {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundStyle(.secondary)
                    Text("Apri WhatsApp sul telefono → Dispositivi collegati → Collega un dispositivo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.1))
            }

            if engine.authState == .authenticated {
                // Success screen
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("WhatsApp connesso!")
                        .font(.title2.weight(.semibold))
                    Text("Questa finestra si chiuderà automaticamente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // WebView showing WhatsApp Web (QR or loading)
                WhatsAppWebViewHost(webView: WhatsAppWebEngine.shared.webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var statusLabel: String {
        switch engine.authState {
        case .idle:            return "In attesa…"
        case .loading:         return "Caricamento…"
        case .qrRequired:      return "Scansiona il QR code"
        case .authenticated:   return "Connesso ✓"
        case .error(let e):    return "Errore: \(e)"
        }
    }

    private var statusColor: Color {
        switch engine.authState {
        case .authenticated: return .green
        case .error:         return .red
        case .qrRequired:    return .orange
        default:             return .gray
        }
    }
}

// MARK: - NSViewRepresentable wrapper for WKWebView

struct WhatsAppWebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
