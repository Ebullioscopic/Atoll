/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import SwiftUI
import Defaults

struct DockPreviewView: View {
    @ObservedObject var manager: DockPreviewManager
    @ObservedObject private var music = MusicManager.shared
    @Default(.dockPreviewShowAppStrip) private var showAppStrip
    @Default(.dockPreviewShowBackgroundProcesses) private var showBackground
    var body: some View {
        if let session = manager.session {
            VStack(spacing: 5) {
                let isMedia = session.applicationURL == NSWorkspace.shared.urlForApplication(withBundleIdentifier: music.bundleIdentifier ?? "") && !music.isPlayerIdle
                if isMedia {
                    DockPreviewMediaCard(music: music, expanded: session.windows.isEmpty,
                        openMedia: { manager.dismiss(keepNotchOpen: true); DynamicIslandViewCoordinator.shared.currentView = .home },
                        openApplication: { manager.activateApplication() }, quit: { manager.quitApplication() })
                }
                DockPreviewContent(session: session, thumbnails: manager.thumbnails, isLoading: manager.isLoading,
                    actionError: manager.actionError, hasScreenRecording: manager.hasScreenRecording,
                    cardWidth: manager.cardWidth, refresh: { manager.refreshSnapshots() }, dismiss: { manager.dismiss() },
                    activateApplication: { manager.activateApplication() }, perform: { manager.perform($0, window: $1) },
                    applications: manager.applications, hideEmptyState: isMedia && session.windows.isEmpty, showAppStrip: showAppStrip, showBackgroundProcesses: showBackground,
                    isKeyboardSwitching: manager.isKeyboardSwitching, selectApplication: { manager.selectApplication($0) },
                    hideApplication: { manager.hideApplication() }, quitApplication: { manager.quitApplication() }, moveWindow: { manager.moveWindow($0) })
                    .id(session.applicationURL)
            }.frame(maxWidth: .infinity)
        }
    }
}

private struct DockPreviewMediaCard: View {
    @ObservedObject var music: MusicManager
    let expanded: Bool
    let openMedia: () -> Void
    let openApplication: () -> Void
    let quit: () -> Void
    @State private var scrub = 0.0
    @State private var isScrubbing = false
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: openMedia) {
                    HStack(spacing: 8) {
                        Image(nsImage: music.albumArt).resizable().scaledToFill()
                            .frame(width: expanded ? 48 : 22, height: expanded ? 48 : 22).clipped().cornerRadius(5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(music.songTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(music.artistName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }.buttonStyle(.plain).help("Open media controls")
                Spacer(minLength: 4)
                if !expanded { transport }
            }
            if expanded {
                Slider(value: Binding(get: { isScrubbing ? scrub : min(music.songDuration, music.elapsedTime) }, set: { scrub = $0 }),
                    in: 0...max(1, music.songDuration), onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing { music.seek(to: scrub) }
                    }).controlSize(.mini).tint(.white).disabled(music.songDuration <= 0 || music.isLiveStream)
                transport
                HStack {
                    Button("Open app", action: openApplication)
                    Button("Media", action: openMedia)
                    Spacer()
                    Button("Quit", action: quit).foregroundStyle(.red)
                }.font(.system(size: 10)).buttonStyle(.borderless)
            }
        }.padding(10).background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(expanded ? 0.06 : 0)))
    }
    private var transport: some View {
        HStack(spacing: expanded ? 22 : 8) {
            Button(action: music.previousTrack) { Image(systemName: "backward.fill") }.accessibilityLabel("Previous track")
            Button(action: music.playPause) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").foregroundStyle(.black)
                    .frame(width: expanded ? 32 : 22, height: expanded ? 32 : 22).background(Circle().fill(.white))
            }.accessibilityLabel(music.isPlaying ? "Pause" : "Play")
            Button(action: music.nextTrack) { Image(systemName: "forward.fill") }.accessibilityLabel("Next track")
        }.font(.system(size: expanded ? 14 : 9, weight: .semibold)).buttonStyle(.plain).frame(maxWidth: expanded ? .infinity : nil)
    }
}
