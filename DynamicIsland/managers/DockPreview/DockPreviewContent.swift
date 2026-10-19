/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit
import SwiftUI

struct DockPreviewContent: View {
    let session: DockPreviewSession
    let thumbnails: [UInt: CGImage]
    let isLoading: Bool
    let actionError: String?
    let hasScreenRecording: Bool
    let cardWidth: CGFloat
    let refresh: () -> Void
    let dismiss: () -> Void
    let activateApplication: () -> Void
    let perform: (DockPreviewAction, DockPreviewWindow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: session.applicationURL.path))
                    .resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                Text(session.applicationName).font(.headline).lineLimit(1)
                Text(session.windows.count, format: .number).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh window previews").accessibilityLabel("Refresh window previews")
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .help("Dismiss Dock preview").accessibilityLabel("Dismiss Dock preview")
            }
            .buttonStyle(.borderless)
            if session.windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow").font(.title2).foregroundStyle(.secondary)
                    Text(isLoading ? "Loading windows…" : "No open windows").font(.callout)
                    if !isLoading {
                        Button("Open application") { activateApplication() }.buttonStyle(.bordered)
                    }
                }.frame(maxWidth: .infinity, minHeight: 125)
            } else {
                GeometryReader { viewport in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(session.windows) { window in card(window, applicationURL: session.applicationURL) }
                        }
                        .frame(minWidth: viewport.size.width, alignment: .center)
                        .padding(.vertical, 2)
                    }.scrollIndicators(.hidden)
                }.frame(height: 150)
            }
            if let error = actionError {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else if !hasScreenRecording {
                HStack(spacing: 5) {
                    Image(systemName: "lock.shield")
                    Text("Screen Recording enables thumbnails. Window controls still work.")
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }


    private func card(_ window: DockPreviewWindow, applicationURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { perform(.activate, window) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.06))
                    if let image = thumbnails[window.id] {
                        Image(decorative: image, scale: 2).resizable().scaledToFit().padding(3)
                    } else {
                        VStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path)).resizable().frame(width: 36, height: 36)
                            if window.isMinimized { Text("Minimized").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                .frame(width: cardWidth, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Activate \(window.title)")
            HStack(spacing: 7) {
                Text(window.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Button { perform(.minimize, window) } label: {
                    Image(systemName: window.isMinimized ? "arrow.up.right.and.arrow.down.left" : "minus")
                }
                .disabled(!window.canMinimize)
                .help(window.isMinimized ? "Restore window" : "Minimize window")
                .accessibilityLabel("\(window.isMinimized ? "Restore" : "Minimize") \(window.title)")
                Button { perform(.close, window) } label: { Image(systemName: "xmark") }
                    .disabled(!window.canClose).help("Close window").accessibilityLabel("Close \(window.title)")
            }.buttonStyle(.borderless).foregroundStyle(.secondary)
        }.frame(width: cardWidth)
    }
}
