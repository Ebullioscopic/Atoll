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
import Defaults

struct NotchTogglView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var togglManager = TogglManager.shared
    @State private var noActiveTimerMessage = false
    @State private var elapsedDraft = ""
    @FocusState private var elapsedFieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            leftColumn
            if !togglManager.recentEntries.isEmpty {
                Divider()
                    .frame(height: max(0, maxTabContentHeight - 8))
                    .opacity(0.2)
                recentColumn
            }
        }
        .frame(maxHeight: maxTabContentHeight, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .transition(.opacity.combined(with: .blurReplace))
        .onAppear { if !elapsedFieldFocused { elapsedDraft = formattedElapsed } }
        .onChange(of: togglManager.isRunning) { _, _ in
            if !elapsedFieldFocused { elapsedDraft = formattedElapsed }
        }
        .onChange(of: togglManager.elapsed) { _, _ in
            // Reflect external changes (e.g. reset) unless the user is typing.
            if !elapsedFieldFocused && !togglManager.isRunning { elapsedDraft = formattedElapsed }
        }
    }

    /// Parses the draft ("H:MM:SS", "M:SS", or plain seconds) into the manager's elapsed.
    private func applyElapsedDraft() {
        let parts = elapsedDraft.split(separator: ":").map {
            Int($0.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let seconds: Int
        switch parts.count {
        case 3: seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: seconds = parts[0] * 60 + parts[1]
        case 1: seconds = parts[0]
        default: seconds = 0
        }
        togglManager.elapsed = TimeInterval(max(0, seconds))
        elapsedDraft = formattedElapsed
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Description
            TextField("Description", text: $togglManager.pendingDescription)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(togglManager.isRunning)

            // Project picker + refresh + sync
            HStack(spacing: 6) {
                Menu {
                    Button("No Project") { togglManager.pendingProjectId = nil }
                    if !togglManager.projects.isEmpty { Divider() }
                    ForEach(togglManager.projects) { project in
                        Button(project.name) { togglManager.pendingProjectId = project.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedProjectName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(togglManager.isRunning ? 0.04 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .disabled(togglManager.isRunning)
                .frame(maxWidth: .infinity, alignment: .leading)

                circleIconButton(
                    systemName: "arrow.clockwise",
                    isLoading: togglManager.isFetchingProjects,
                    help: "Refresh projects"
                ) {
                    Task { await togglManager.fetchProjects() }
                }
                .disabled(togglManager.isRunning || togglManager.isFetchingProjects)

                circleIconButton(
                    systemName: "arrow.triangle.2.circlepath",
                    isLoading: togglManager.isFetchingCurrentTimer,
                    help: "Sync from Toggl"
                ) {
                    syncFromToggl()
                }
                .disabled(togglManager.isRunning || togglManager.isFetchingCurrentTimer)
            }

            // Elapsed + start/stop + reset on the same row
            HStack(alignment: .center, spacing: 10) {
                if togglManager.isRunning {
                    Text(formattedElapsed)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                } else {
                    // Editable when idle: type H:MM:SS (or M:SS) and Start continues from it.
                    TextField("0:00", text: $elapsedDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 28, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(elapsedFieldFocused ? 0.85 : 0.35))
                        .fixedSize()
                        .focused($elapsedFieldFocused)
                        .onSubmit { applyElapsedDraft() }
                        .onChange(of: elapsedFieldFocused) { _, focused in
                            if !focused { applyElapsedDraft() }
                        }
                }

                Spacer(minLength: 0)

                if !togglManager.isRunning && togglManager.elapsed > 0 {
                    Button(action: { togglManager.resetStopwatch() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale))
                }

                Button {
                    if togglManager.isRunning {
                        Task { await togglManager.stopStopwatch() }
                    } else {
                        // Commit any typed value first so Start seeds from it (avoids
                        // a focus/commit race where startStopwatch reads a stale 0).
                        elapsedFieldFocused = false
                        applyElapsedDraft()
                        togglManager.startStopwatch()
                    }
                } label: {
                    Label(togglManager.isRunning ? "Stop" : "Start",
                          systemImage: togglManager.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(togglManager.isRunning ? Color.red.opacity(0.85) : startColor)
                        )
                }
                .buttonStyle(.plain)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .animation(.smooth(duration: 0.2), value: togglManager.elapsed > 0)

            // Status row: saving / error / no-active-timer (only when needed)
            Group {
                if togglManager.isSavingEntry {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("Saving…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                } else if let error = togglManager.saveError {
                    HStack(spacing: 6) {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Retry") { Task { await togglManager.retryPendingEntry() } }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.red).buttonStyle(.plain)
                    }
                } else if noActiveTimerMessage {
                    Text("No active timer on Toggl")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: togglManager.isSavingEntry)
            .animation(.easeInOut(duration: 0.2), value: togglManager.saveError != nil)
            .animation(.easeInOut(duration: 0.2), value: noActiveTimerMessage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxTabContentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    // MARK: - Recent column

    private var recentColumn: some View {
        let count = togglManager.recentEntries.count
        let computedHeight = CGFloat(count) * 64 + 4
        let listHeight = min(max(0, maxTabContentHeight - 16), computedHeight)
        return ZStack {
            List {
                ForEach(togglManager.recentEntries) { entry in
                    TogglRecentCard(entry: entry, isRunning: togglManager.isRunning) {
                        guard !togglManager.isRunning else { return }
                        togglManager.pendingDescription = entry.description
                        togglManager.pendingProjectId   = entry.projectId
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)

            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 16).allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .top)

            LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .frame(height: 16).allowsHitTesting(false)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 210, height: listHeight, alignment: .top)
        .frame(maxHeight: maxTabContentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    // MARK: - Helpers

    private func circleIconButton(systemName: String, isLoading: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().scaleEffect(0.55)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 26)
        .background(Color.white.opacity(0.08))
        .clipShape(Circle())
        .foregroundStyle(.white.opacity(0.7))
        .help(help)
    }

    private var selectedProjectName: String {
        guard let pid = togglManager.pendingProjectId else { return "No Project" }
        return togglManager.projects.first { $0.id == pid }?.name ?? "Project"
    }

    private var formattedElapsed: String {
        TogglSupplementMetrics.formattedElapsed(for: togglManager.elapsed)
    }

    private var startColor: Color { Color(red: 0.142, green: 0.633, blue: 0.265) }

    private var resolvedNotchHeight: CGFloat {
        let h = vm.notchSize.height
        return h > 0 ? h : openNotchSize.height
    }

    private var maxTabContentHeight: CGFloat {
        max(130, resolvedNotchHeight - max(24, vm.effectiveClosedNotchHeight) - 36)
    }

    private func syncFromToggl() {
        Task {
            guard let entry = await togglManager.fetchCurrentTimer(),
                  let parsedStart = entry.parsedStart else {
                withAnimation { noActiveTimerMessage = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { self.noActiveTimerMessage = false }
                }
                return
            }
            togglManager.elapsed = max(0, Date().timeIntervalSince(parsedStart))
            togglManager.setSyncedStart(parsedStart)
            togglManager.pendingDescription = entry.description ?? ""
            togglManager.pendingProjectId   = entry.projectId
            togglManager.startStopwatch()
        }
    }
}

// MARK: - Recent card

private struct TogglRecentCard: View {
    let entry: TogglRecentEntry
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.87, green: 0.36, blue: 0.22).gradient)
                        .frame(width: 30, height: 30)
                    Text("T")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.description.isEmpty ? "(no description)" : entry.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(entry.projectName ?? "No project")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(isRunning ? 0.4 : 1))
                    .padding(6)
                    .background(Color.white.opacity(isRunning ? 0.04 : 0.08))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .opacity(isRunning ? 0.5 : 1)
    }
}

#Preview {
    NotchTogglView()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 600, height: 320)
        .background(.black)
}
