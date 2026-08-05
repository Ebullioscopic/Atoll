/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandUI
import SwiftUI

/// The Atoll-owned notch route for the persistent Code Island tab.
struct NotchCodeIslandView: View {
    @ObservedObject private var host = CodeIslandHost.shared

    var body: some View {
        CodeIslandDashboardView(
            state: host.dashboardState,
            openSettings: {
                SettingsWindowController.shared.showWindow(destination: .codeIsland)
            },
            openOrigin: { item in
                host.openOrigin(item.origin)
            }
        )
    }
}

/// CodeIsland-styled content placed inside Atoll's existing notch geometry.
struct NotchCodeIslandActivityView: View {
    @ObservedObject private var host = CodeIslandHost.shared

    let presentation: CodeIslandHostPresentation
    let centerWidth: CGFloat
    let height: CGFloat
    let isDynamicIslandMode: Bool

    var body: some View {
        HStack(spacing: 9) {
            Button(action: host.showDashboard) {
                HStack(spacing: 7) {
                    CodeIslandCodexMascotView(state: mascotState, size: max(28, height - 10))
                    Text("Codex")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .buttonStyle(.plain)
            .help("Open the Code Island dashboard")

            if !isDynamicIslandMode {
                Color.clear
                    .frame(width: max(72, centerWidth - 18))
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: 6)
            }

            HStack(spacing: 7) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                    if let projectName = presentation.subject.projectDisplayName {
                        Text(projectName)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }

                if presentation.isAttention, presentation.subject.origin != nil {
                    Button {
                        host.openOrigin(presentation.subject.origin)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(accentColor.opacity(0.23), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help("Open in origin")
                    .accessibilityLabel("Open in origin")
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var mascotState: CodeIslandMascotState {
        switch presentation.style {
        case .compact, .sessionStarted:
            return .working
        case .attention:
            return .attention
        case .completed:
            return .success
        case .failed:
            return .failure
        }
    }

    private var statusText: String {
        switch presentation.style {
        case .compact:
            return "Working"
        case .sessionStarted:
            return "Session started"
        case .attention(.approval):
            return "Approval in origin"
        case .attention(.question):
            return "Input in origin"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private var accentColor: Color {
        switch presentation.style {
        case .compact, .sessionStarted:
            return .white.opacity(0.85)
        case .attention:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var accessibilityText: String {
        let project = presentation.subject.projectDisplayName.map { ", \($0)" } ?? ""
        return "Codex, \(statusText)\(project)"
    }
}

/// Small secondary indicator used only by layouts that explicitly coexist.
struct NotchCodeIslandSecondaryActivityView: View {
    let presentation: CodeIslandHostPresentation

    var body: some View {
        ZStack {
            CodeIslandCodexMascotView(state: .working, size: 24)
        }
        .help("Codex is working\(presentation.subject.projectDisplayName.map { " in \($0)" } ?? "")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex is working")
    }
}
