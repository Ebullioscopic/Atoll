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
import Defaults
import SwiftUI

struct NotchSpotifyView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var store = SpotifyLibraryStore.shared
    @ObservedObject private var auth = SpotifyOAuthManager.shared
    @ObservedObject private var player = SpotifyPlayerManager.shared
    @StateObject private var browser = SpotifyBrowser()
    @Default(.spotifyDefaultShuffle) private var defaultShuffle
    @State private var query = ""
    @State private var shuffle = false
    @State private var launchError: String?

    private var launcher: SpotifyPlaybackLauncher {
        SpotifyPlaybackLauncher(desktop: SpotifyController.sharedForLaunch, api: SpotifyWebAPIClient())
    }

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                connectView
            } else if let ctx = browser.currentContext {
                trackListView(ctx)
            } else {
                homeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            shuffle = defaultShuffle
            SpotifyPlayerManager.shared.start()
            if store.playlists.isEmpty { Task { await store.loadHome() } }
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthed in
            if isAuthed {
                SpotifyPlayerManager.shared.restart()   // pick up the freshly-scoped token
                Task { await store.loadHome() }
            } else {
                SpotifyPlayerManager.shared.stop()
            }
        }
    }

    private var connectView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note").font(.largeTitle)
            Text(String(localized: "Connect Spotify")).font(.headline)
            Text(String(localized: "Add a Spotify Client ID in Settings ▸ Spotify and tap Connect."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var homeView: some View {
        VStack(spacing: 6) {
            resumeButton
            // Search intentionally omitted: Spotify blocks /search for personal API apps
            // without Extended Quota Mode (returns 400 "Invalid limit").
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    itemRow(store.likedSongs)
                    section(String(localized: "Playlists"), store.playlists)
                    section(String(localized: "Recently Played"), store.recentlyPlayed)
                }
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) { errorBanner }
    }

    /// Continue the last Spotify session (same queue + position) rather than starting a
    /// fresh context. Prefers Atoll's in-app player when it's the standalone device.
    private var resumeButton: some View {
        Button {
            Task { await launch { try await launcher.resumeLastPlayback() } }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Resume")).font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Continue where you left off")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.top, 4)
    }

    @ViewBuilder private func section(_ title: String, _ items: [SpotifyLibraryItem]) -> some View {
        if !items.isEmpty {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items) { itemRow($0) }
        }
    }

    private func itemRow(_ item: SpotifyLibraryItem) -> some View {
        Button {
            Task {
                switch item.kind {
                case .track:
                    await launch { try await launcher.playTrack(uri: item.contextURI, inContext: nil, shuffle: shuffle) }
                case .album:
                    await launch { try await launcher.playContext(uri: item.contextURI, shuffle: shuffle) }
                case .playlist, .likedSongs:
                    await browser.open(item)
                }
            }
        } label: {
            HStack(spacing: 8) {
                artwork(item.imageURL, fallback: item.kind == .likedSongs ? "heart.fill" : "music.note.list")
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1).font(.system(size: 12))
                    Text(item.subtitle).lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await launch { try await launcher.playItem(item, shuffle: shuffle) } } } label: {
                    Image(systemName: "play.fill").font(.caption)
                }.buttonStyle(.plain)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func trackListView(_ ctx: SpotifyLibraryItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { browser.back() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Text(ctx.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(shuffle ? Color.green : .white) }.buttonStyle(.plain)
                Button { Task { await launch { try await launcher.playItem(ctx, shuffle: shuffle) } } } label: {
                    Label(String(localized: "Play all"), systemImage: "play.fill").font(.caption)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let error = browser.errorMessage {
                inlineMessage(error, systemImage: "exclamationmark.triangle")
            } else if browser.tracks.isEmpty {
                inlineMessage(String(localized: "No tracks"), systemImage: "music.note")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(browser.tracks.enumerated()), id: \.offset) { _, track in
                            Button {
                                Task { await launch { let contextURI = (ctx.kind == .likedSongs && !SpotifyPlayerManager.shared.isReady) ? nil : ctx.contextURI
                                try await launcher.playTrack(uri: track.uri, inContext: contextURI, shuffle: shuffle) } }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(track.name).lineLimit(1).font(.system(size: 12))
                                    Text("·").foregroundStyle(.secondary)
                                    Text(track.artists.map(\.name).joined(separator: ", ")).lineLimit(1).font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .onAppear { if track == browser.tracks.last && browser.canLoadMore { Task { await browser.loadMoreTracks() } } }
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
        .overlay(alignment: .bottom) { errorBanner }
    }

    private func trackSection(_ title: String, _ tracks: [SpotifyTrack], context: String?) -> some View {
        Group {
            if !tracks.isEmpty {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                    Button { Task { await launch { try await launcher.playTrack(uri: track.uri, inContext: context, shuffle: shuffle) } } } label: {
                        HStack(spacing: 8) {
                            artwork(track.album?.images?.first.flatMap { URL(string: $0.url) }, fallback: "music.note")
                            Text(track.name).lineLimit(1).font(.system(size: 12))
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func artwork(_ url: URL?, fallback: String) -> some View {
        Group {
            if let url { AsyncImage(url: url) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) } }
            else { Image(systemName: fallback).frame(width: 28, height: 28) }
        }.frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder private var errorBanner: some View {
        if let msg = launchError ?? store.errorMessage ?? player.statusMessage {
            Text(msg).font(.caption2).padding(6).background(.red.opacity(0.8)).clipShape(Capsule()).padding(.bottom, 6)
        }
    }

    private func inlineMessage(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) { Image(systemName: systemImage); Text(text) }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func launch(_ action: @escaping () async throws -> Void) async {
        do { launchError = nil; try await action() }
        catch is SpotifyLaunchError { launchError = String(localized: "Open Spotify on a device first.") }
        catch { launchError = String(localized: "Couldn't start playback.") }
    }
}

private extension SpotifyPlaybackLauncher {
    func playItem(_ item: SpotifyLibraryItem, shuffle: Bool) async throws {
        if item.kind == .likedSongs { try await playLikedSongs(shuffle: shuffle) }
        else { try await playContext(uri: item.contextURI, shuffle: shuffle) }
    }
}
