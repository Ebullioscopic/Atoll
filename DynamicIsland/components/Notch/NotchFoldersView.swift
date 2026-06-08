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
import UniformTypeIdentifiers

struct NotchFoldersView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var store = FolderLocationsStore.shared
    @StateObject private var browser = FolderBrowser()

    @Default(.foldersShowSystemShortcuts) private var showShortcuts
    @Default(.foldersShowRecentFiles) private var showRecentFiles
    @Default(.foldersShowRecentDownloads) private var showRecentDownloads
    @Default(.foldersRecentLimit) private var recentLimit

    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if browser.currentURL == nil {
                homeView
            } else {
                browserView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { store.start(recentLimit: recentLimit) }
        .onDisappear { store.stopRecentFilesQuery() }
    }

    // MARK: - Home

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                section(title: String(localized: "Pinned"), items: store.pinned, show: true)
                if showShortcuts { section(title: String(localized: "Shortcuts"), items: store.shortcuts, show: true) }
                if showRecentFiles { section(title: String(localized: "Recent Files"), items: store.recentFiles, show: true) }
                if showRecentDownloads { section(title: String(localized: "Recent Downloads"), items: store.recentDownloads, show: true) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(6)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private func section(title: String, items: [FolderLocation], show: Bool) -> some View {
        if show && !items.isEmpty {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(items) { location in
                locationRow(location)
            }
        }
    }

    private func locationRow(_ location: FolderLocation) -> some View {
        Button {
            Task {
                if location.isDirectory {
                    await browser.enter(location.url)
                } else {
                    NSWorkspace.shared.open(location.url)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: location.url.path))
                    .resizable().frame(width: 18, height: 18)
                Text(location.name).lineLimit(1).font(.system(size: 12))
                Spacer()
                if location.isDirectory {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if location.kind == .pinned {
                Button(String(localized: "Remove Pin"), role: .destructive) { store.unpin(id: location.id) }
            }
            Button(String(localized: "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([location.url])
            }
        }
    }

    // MARK: - Browser

    private var browserView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { Task { await browser.goBack() } } label: {
                    Image(systemName: "chevron.left")
                }.buttonStyle(.plain)
                Text(browser.currentURL?.lastPathComponent ?? "")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { browser.revealCurrentInFinder() } label: {
                    Image(systemName: "arrow.up.forward.app")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            if let error = browser.errorMessage {
                inlineMessage(error, systemImage: "exclamationmark.triangle")
            } else if browser.entries.isEmpty {
                inlineMessage(String(localized: "Empty folder"), systemImage: "folder")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(browser.entries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
    }

    private func entryRow(_ entry: FolderEntry) -> some View {
        Button { Task { await browser.activate(entry) } } label: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                    .resizable().frame(width: 18, height: 18)
                Text(entry.name).lineLimit(1).font(.system(size: 12))
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
    }

    private func inlineMessage(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                Task { @MainActor in store.pin(url) }
            }
            handled = true
        }
        return handled
    }
}
