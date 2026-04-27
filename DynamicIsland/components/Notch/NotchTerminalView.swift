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
import SwiftTerm
import Defaults

// MARK: - NSViewRepresentable wrapper for SwiftTerm

/// Bridges SwiftTerm's `LocalProcessTerminalView` (NSView) into SwiftUI.
///
/// Returns `TerminalManager.containerView` (a stable NSView) so that
/// SwiftUI's view lifecycle never tears down the actual terminal.  The
/// real `LocalProcessTerminalView` lives as a subview of that container
/// and survives notch close/open and tab-switch cycles.
struct TerminalNSViewRepresentable: NSViewRepresentable {
    @ObservedObject var terminalManager = TerminalManager.shared

    func makeNSView(context: Context) -> NSView {
        context.coordinator.terminalManager = terminalManager
        terminalManager.ensureTerminalView(delegate: context.coordinator)
        if !terminalManager.isProcessRunning {
            terminalManager.startShellProcess()
        }
        return terminalManager.containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-mount terminal if it was restarted (generation bumped).
        terminalManager.ensureTerminalView(delegate: context.coordinator)
        if !terminalManager.isProcessRunning {
            terminalManager.startShellProcess()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminalManager: TerminalManager?

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Terminal resized — no action needed; SwiftTerm handles reflow.
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                terminalManager?.updateTitle(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Could be used for breadcrumbs in the future.
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                terminalManager?.processDidTerminate(exitCode: exitCode)
            }
        }
    }
}

// MARK: - Notch Tab View

/// Guake-style dropdown terminal tab for the notch.
/// Dynamically sizes up to half the screen height; content scrolls when the
/// terminal buffer exceeds the visible area (handled internally by SwiftTerm).
struct NotchTerminalView: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @Default(.cornerRadiusScaling) var cornerRadiusScaling
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    /// Top corners stay mild; bottom follows shell − padding (see `notchTerminalBottomCornerRadii`).
    private static let terminalClipTopCornerRadius: CGFloat = 6

    private var currentScreenName: String {
        vm.screen ?? DynamicIslandViewCoordinator.shared.selectedScreen
    }

    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var terminalClipShape: UnevenRoundedRectangle {
        let innerBottom = notchTerminalBottomCornerRadii(
            isDynamicIslandMode: isDynamicIslandMode,
            notchState: vm.notchState,
            cornerRadiusScaling: cornerRadiusScaling,
            enableMinimalisticUI: enableMinimalisticUI,
            closedNotchHeight: vm.closedNotchSize.height
        ).innerBottom
        return UnevenRoundedRectangle(
            topLeadingRadius: Self.terminalClipTopCornerRadius,
            bottomLeadingRadius: innerBottom,
            bottomTrailingRadius: innerBottom,
            topTrailingRadius: Self.terminalClipTopCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if enableTerminalFeature {
                // Terminal header bar
                HStack {
                    Image(systemName: "apple.terminal")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 11))

                    Text(terminalManager.terminalTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Restart button
                    Button {
                        terminalManager.restartShell()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Restart shell")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)

                Divider()
                    .padding(.horizontal, notchTerminalContentEdgePadding.horizontal)

                // Terminal content — the containerView is stable across
                // notch close/open cycles; updateNSView handles restart.
                TerminalNSViewRepresentable(terminalManager: terminalManager)
                    .clipShape(terminalClipShape)
                    .padding(
                        EdgeInsets(
                            top: notchTerminalContentEdgePadding.top,
                            leading: notchTerminalContentEdgePadding.horizontal,
                            bottom: notchTerminalContentEdgePadding.bottom,
                            trailing: notchTerminalContentEdgePadding.horizontal
                        )
                    )
                    .onHover { hovering in
                        updateSuppression(for: hovering)
                    }
            } else {
                // Feature disabled placeholder
                VStack(spacing: 8) {
                    Image(systemName: "apple.terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("Terminal is disabled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Enable it in Settings → Terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear {
            updateSuppression(for: false)
        }
        .onAppear {
            terminalManager.refreshTerminalAppearanceIfNeeded()
            terminalManager.focusTerminalIfPossible()
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}
