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
    var applications: [DockPreviewApplication] = []
    var hideEmptyState = false
    var showAppStrip = true
    var showBackgroundProcesses = true
    var isKeyboardSwitching = false
    var selectApplication: (DockPreviewApplication) -> Void = { _ in }
    var hideApplication: () -> Void = {}
    var quitApplication: () -> Void = {}
    var moveWindow: (DockPreviewWindow) -> Void = { _ in }
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: session.applicationURL.path))
                    .resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                Text(session.applicationName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text("\(session.windows.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if isLoading { ProgressView().controlSize(.mini) }
                Menu {
                    Button("Open application", action: activateApplication)
                    Button("Hide application", action: hideApplication).disabled(session.processID == nil)
                    Button("Quit application", action: quitApplication).disabled(session.processID == nil)
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Application actions")
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh window previews")
                Button(action: dismiss) { Image(systemName: "xmark") }.accessibilityLabel("Dismiss Dock preview")
            }.buttonStyle(.borderless).foregroundStyle(.white.opacity(0.75))
            if session.windows.isEmpty { if !hideEmptyState { emptyState } } else { cards }
            if showAppStrip, applications.count > 1 { appStrip }
            if isKeyboardSwitching {
                Text("⇧Tab / ← → to switch · Release ⌘ to open · Esc to cancel")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            if let error = actionError {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            } else if !hasScreenRecording {
                Label("Enable Screen Recording for window snapshots", systemImage: "lock.shield")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, DockPreviewLayout.panelInset).padding(.top, 6).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: page)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: showBackgroundProcesses && session.processID != nil ? "app.badge" : "macwindow")
                .font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            Text(isLoading ? "Loading windows…" : showBackgroundProcesses && session.processID != nil ? "Running in background" : "No open windows")
                .font(.system(size: 11, weight: .medium))
            if !isLoading {
                if showBackgroundProcesses, let pid = session.processID {
                    Text("Process \(pid) · No window open").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Open", action: activateApplication)
                    if showBackgroundProcesses, session.processID != nil {
                        Button("Hide", action: hideApplication)
                        Button("Quit", action: quitApplication).tint(.red)
                    }
                }.buttonStyle(.bordered).controlSize(.mini)
            }
        }.frame(maxWidth: .infinity, minHeight: 118)
    }

    private var cards: some View {
        GeometryReader { viewport in
            let width = DockPreviewLayout.fittedCardWidth(available: viewport.size.width, preferred: cardWidth)
            let count = DockPreviewLayout.cardsPerPage(available: viewport.size.width, cardWidth: width)
            let pages = max(1, Int(ceil(Double(session.windows.count) / Double(count))))
            let current = min(page, pages - 1)
            let start = current * count
            VStack(spacing: 5) {
                HStack(alignment: .top, spacing: DockPreviewLayout.gap) {
                    ForEach(Array(session.windows.dropFirst(start).prefix(count))) { window in
                        DockPreviewCard(window: window, image: thumbnails[window.id], applicationURL: session.applicationURL,
                            width: width, perform: perform, move: { moveWindow(window) })
                    }
                }.frame(maxWidth: .infinity, alignment: .center)
                if pages > 1 {
                    HStack(spacing: 14) {
                        Button { page = max(0, current - 1) } label: { Image(systemName: "chevron.left") }
                            .disabled(current == 0).accessibilityLabel("Previous windows")
                        Text("\(start + 1)–\(min(session.windows.count, start + count)) of \(session.windows.count)")
                            .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                        Button { page = min(pages - 1, current + 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(current == pages - 1).accessibilityLabel("Next windows")
                    }.buttonStyle(.borderless).font(.system(size: 9, weight: .semibold))
                }
            }.frame(width: viewport.size.width, alignment: .top)
        }.frame(height: 143)
    }

    private var appStrip: some View {
        ViewThatFits(in: .horizontal) {
            chips.frame(maxWidth: .infinity, alignment: .center)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) { chips }
                    .onChange(of: session.processID) { _, pid in if let pid { proxy.scrollTo(pid, anchor: .center) } }
                    .onAppear { if let pid = session.processID { proxy.scrollTo(pid, anchor: .center) } }
            }.frame(height: 35)
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(applications) { app in
                Button { selectApplication(app) } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 20, height: 20)
                        if app.windowCount > 1 {
                            Text("\(app.windowCount)").font(.system(size: 7, weight: .bold)).padding(.horizontal, 2)
                                .background(Capsule().fill(.white.opacity(0.3))).offset(x: 4, y: -4)
                        } else if app.windowCount == 0 { Circle().fill(.green).frame(width: 4, height: 4).offset(x: 2, y: -2) }
                    }.padding(4).background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(app.id == session.processID ? 0.16 : 0)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(app.id == session.processID ? .white.opacity(0.35) : .clear))
                }.buttonStyle(.plain).help(app.name).accessibilityLabel("Preview \(app.name)").id(app.id)
            }
        }.padding(3)
    }
}

private struct DockPreviewCard: View {
    let window: DockPreviewWindow
    let image: CGImage?
    let applicationURL: URL
    let width: CGFloat
    let perform: (DockPreviewAction, DockPreviewWindow) -> Void
    let move: () -> Void
    @State private var hovering = false
    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Button { perform(.activate, window) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
                        if let image {
                            Image(decorative: image, scale: 1).resizable().scaledToFit().padding(3).opacity(window.isMinimized ? 0.55 : 1)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path)).resizable().frame(width: 38, height: 38).opacity(0.85)
                        }
                    }.frame(width: width, height: 98).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel("Activate \(window.title)")
                HStack(spacing: 4) {
                    if window.isMinimized || window.isFullScreen || (NSScreen.screens.count > 1 && !window.displayName.isEmpty) {
                        let state = window.isFullScreen ? "Full Screen" : window.isMinimized ? "Minimized" : ""
                        let label = [state, NSScreen.screens.count > 1 ? window.displayName : ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        Text(label).font(.system(size: 8)).lineLimit(1).padding(4).background(Capsule().fill(.black.opacity(0.7)))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        if NSScreen.screens.count > 1 { action("rectangle.on.rectangle", "Move to this display", enabled: true, move) }
                        action(window.isMinimized ? "arrow.up.left.and.arrow.down.right" : "minus", window.isMinimized ? "Restore window" : "Minimize window", enabled: window.canMinimize) { perform(.minimize, window) }
                        action("xmark", "Close window", enabled: window.canClose) { perform(.close, window) }
                    }.opacity(hovering ? 1 : 0).accessibilityHidden(false)
                }.padding(5)
            }.frame(width: width, height: 98)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(hovering ? 0.45 : 0.12), lineWidth: hovering ? 1.2 : 0.8).allowsHitTesting(false))
            Text(window.title).font(.system(size: 10.5)).foregroundStyle(.white.opacity(hovering ? 0.95 : 0.6))
                .lineLimit(1).truncationMode(.middle).frame(width: width).help(window.title)
        }.frame(width: width).onHover { hovering = $0 }
    }
    private func action(_ symbol: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 16, height: 16).background(Circle().fill(.black.opacity(0.65)))
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }.buttonStyle(.plain).disabled(!enabled).help(label).accessibilityLabel(label + " " + window.title)
    }
}
