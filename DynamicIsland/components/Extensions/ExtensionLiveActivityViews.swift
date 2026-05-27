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
import AtollExtensionKit

struct ExtensionStandaloneLayout {
    let totalWidth: CGFloat
    let outerHeight: CGFloat
    let contentHeight: CGFloat
    let leadingWidth: CGFloat
    let centerWidth: CGFloat
    let trailingWidth: CGFloat
}

struct ExtensionLiveActivityStandaloneView: View {
    let payload: ExtensionLiveActivityPayload
    let layout: ExtensionStandaloneLayout
    let isHovering: Bool

    private var descriptor: AtollLiveActivityDescriptor { payload.descriptor }
    private var contentHeight: CGFloat { layout.contentHeight }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }
    private var resolvedLeadingContent: AtollTrailingContent {
        resolvedExtensionLeadingContent(for: descriptor)
    }
    var body: some View {
        HStack(spacing: 0) {
            ExtensionLeadingContentView(
                bundleIdentifier: payload.bundleIdentifier,
                content: resolvedLeadingContent,
                badge: descriptor.badgeIcon,
                accent: accentColor,
                frameWidth: layout.leadingWidth,
                frameHeight: contentHeight,
                defaultIcon: descriptor.leadingIcon
            )
            .frame(width: layout.leadingWidth, height: contentHeight)

            Rectangle()
                .fill(Color.black)
                .frame(width: layout.centerWidth, height: contentHeight)
                .overlay(EmptyView())

            ExtensionMusicWingView(
                payload: payload,
                notchHeight: contentHeight,
                trailingWidth: layout.trailingWidth
            )
                .frame(width: layout.trailingWidth, height: contentHeight)
        }
        .frame(width: layout.totalWidth, height: layout.outerHeight + (isHovering ? 8 : 0))
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.4, dampingFraction: 0.8)),
                removal: .scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.9))
            )
        )
        .animation(.smooth(duration: 0.25), value: payload.id)
        .onAppear {
            logExtensionDiagnostics("Displaying extension live activity \(payload.descriptor.id) for \(payload.bundleIdentifier) as standalone view")
        }
        .onDisappear {
            logExtensionDiagnostics("Hid extension live activity \(payload.descriptor.id) standalone view")
        }
    }

}

struct ExtensionMusicWingView: View {
    let payload: ExtensionLiveActivityPayload
    let notchHeight: CGFloat
    let trailingWidth: CGFloat

    private var descriptor: AtollLiveActivityDescriptor { payload.descriptor }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }
    private var trailingRenderable: ExtensionTrailingRenderable {
        resolvedExtensionTrailingRenderable(for: descriptor)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            switch trailingRenderable {
            case let .content(content):
                if case .none = content {
                    Spacer(minLength: 0)
                } else {
                    ExtensionEdgeContentView(
                        content: content,
                        accent: accentColor,
                        availableWidth: trailingWidth,
                        alignment: .trailing
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            case let .indicator(indicator):
                ExtensionProgressIndicatorView(
                    indicator: indicator,
                    progress: descriptor.progress,
                    accent: accentColor,
                    estimatedDuration: descriptor.estimatedDuration,
                    maxVisualHeight: notchHeight
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .onAppear {
            logExtensionDiagnostics("Displaying extension live activity \(payload.descriptor.id) within music wing")
        }
        .onDisappear {
            logExtensionDiagnostics("Hid extension live activity \(payload.descriptor.id) from music wing")
        }
    }
}

struct PremiumAgentAvatarView: View {
    let bundleIdentifier: String
    let size: CGFloat
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            // Neon radial breathing backdrop
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(0.35), accentColor.opacity(0)],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.6
                    )
                )
                .scaleEffect(isBreathing ? 1.15 : 0.95)
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: isBreathing)
            
            // Outer glowing ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(0.8), accentColor.opacity(0.1), accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: size - 2, height: size - 2)

            // Dynamic agent icon/vector
            agentIcon
                .frame(width: size * 0.65, height: size * 0.65)
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            isBreathing = true
        }
    }

    private var accentColor: Color {
        let id = bundleIdentifier.lowercased()
        if id.contains("antigravity") {
            return Color(red: 0.15, green: 0.67, blue: 0.99) // Tech Cyan/Blue
        } else if id.contains("codex") {
            return Color(red: 0.6, green: 0.6, blue: 0.65) // Dark Gray/Purple
        } else if id.contains("nerv") {
            return Color(red: 0.96, green: 0.31, blue: 0.08) // Eva Orange/Red
        } else if id.contains("claude") {
            return Color(red: 0.85, green: 0.44, blue: 0.28) // Claude Amber
        }
        return Color.purple
    }

    @ViewBuilder
    private var agentIcon: some View {
        let id = bundleIdentifier.lowercased()
        if id.contains("antigravity") {
            VStack(spacing: 1) {
                Capsule()
                    .fill(Color.cyan)
                    .frame(width: size * 0.22, height: size * 0.12)
                    .shadow(color: .cyan, radius: 2)
                
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white, .cyan.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.48, height: size * 0.14)
                
                Path { path in
                    path.move(to: CGPoint(x: size * 0.08, y: 0))
                    path.addLine(to: CGPoint(x: size * 0.40, y: 0))
                    path.addLine(to: CGPoint(x: size * 0.48, y: size * 0.15))
                    path.addLine(to: CGPoint(x: size * 0.0, y: size * 0.15))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [.cyan.opacity(0.4), .cyan.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.48, height: size * 0.15)
            }
        } else if id.contains("codex") {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    .frame(width: size * 0.45, height: size * 0.45)
                
                Text("{ }")
                    .font(.system(size: size * 0.24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: .white, radius: 3)
            }
        } else if id.contains("nerv") {
            ZStack {
                Circle()
                    .stroke(Color.orange, lineWidth: 1)
                    .frame(width: size * 0.52, height: size * 0.52)
                
                Image(systemName: "waveform.path")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .shadow(color: .orange, radius: 4)
            }
        } else if id.contains("claude") {
            VStack(spacing: 2) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: size * 0.08, height: size * 0.08)
                
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 1.5, height: size * 0.08)
                
                RoundedRectangle(cornerRadius: size * 0.08)
                    .stroke(Color.white, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: size * 0.08).fill(Color.black.opacity(0.6)))
                    .frame(width: size * 0.38, height: size * 0.24)
                    .overlay(
                        HStack(spacing: size * 0.06) {
                            Circle().fill(Color.orange).frame(width: size * 0.06, height: size * 0.06)
                            Circle().fill(Color.orange).frame(width: size * 0.06, height: size * 0.06)
                        }
                    )
            }
        } else {
            Image(systemName: "cpu")
                .font(.system(size: size * 0.35, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

struct ExtensionLeadingContentView: View {
    let bundleIdentifier: String
    let content: AtollTrailingContent
    let badge: AtollIconDescriptor?
    let accent: Color
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let defaultIcon: AtollIconDescriptor

    var body: some View {
        Group {
            let isCustomAgent = ["antigravity", "codex", "nerv", "claude"].contains { bundleIdentifier.lowercased().contains($0) }
            if isCustomAgent && Defaults[.enableAgentCustomAvatars] {
                PremiumAgentAvatarView(bundleIdentifier: bundleIdentifier, size: frameHeight)
            } else {
                switch content {
                case let .icon(iconDescriptor):
                    ExtensionCompositeIconView(
                        leading: iconDescriptor,
                        badge: badge,
                        accent: accent,
                        size: frameHeight
                    )
                case let .animation(data, size):
                    let resolvedSize = CGSize(
                        width: min(size.width, frameHeight),
                        height: min(size.height, frameHeight)
                    )
                    ExtensionLottieView(data: data, size: resolvedSize)
                        .frame(width: frameHeight, height: frameHeight)
                        .background(
                            RoundedRectangle(cornerRadius: frameHeight * 0.18, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                default:
                    ExtensionCompositeIconView(
                        leading: defaultIcon,
                        badge: badge,
                        accent: accent,
                        size: frameHeight
                    )
                }
            }
        }
        .frame(width: frameWidth, height: frameHeight)
    }
}

private func logExtensionDiagnostics(_ message: String) {
    guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
    Logger.log(message, category: .extensions)
}

struct ExtensionNotchExperienceTabView: View {
    let payload: ExtensionNotchExperiencePayload

    @Default(.enableExtensionNotchInteractiveWebViews) private var interactiveWebViewsEnabled

    private var descriptor: AtollNotchExperienceDescriptor { payload.descriptor }
    private var tabConfiguration: AtollNotchExperienceDescriptor.TabConfiguration? { descriptor.tab }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }
    private var allowInteractiveWebViews: Bool {
        interactiveWebViewsEnabled && (tabConfiguration?.allowWebInteraction ?? false)
    }

    var body: some View {
        Group {
            if let tabConfiguration {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: tabConfiguration)
                        ForEach(Array(tabConfiguration.sections.enumerated()), id: \.offset) { index, section in
                            ExtensionNotchSectionView(
                                section: section,
                                accent: accentColor,
                                allowWebInteraction: allowInteractiveWebViews
                            )
                            .accessibilityIdentifier("extension-notch-section-\(payload.descriptor.id)-\(index)")
                        }
                        if let webDescriptor = tabConfiguration.webContent {
                            ExtensionWebContentView(descriptor: webDescriptor, allowInteraction: allowInteractiveWebViews)
                                .frame(height: webDescriptor.preferredHeight)
                                .frame(maxWidth: webDescriptor.maximumContentWidth ?? .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        if let footnote = tabConfiguration.footnote {
                            Text(footnote)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            } else {
                Text("Extension tab unavailable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func header(for configuration: AtollNotchExperienceDescriptor.TabConfiguration) -> some View {
        HStack(spacing: 10) {
            Group {
                if let badgeIcon = configuration.badgeIcon {
                    ExtensionIconView(
                        descriptor: badgeIcon,
                        tint: accentColor,
                        size: CGSize(width: 32, height: 32),
                        cornerRadius: 10
                    )
                } else {
                    Image(systemName: configuration.iconSymbolName ?? "puzzlepiece.extension")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(accentColor.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var tabBackground: some View {
        AnyView(
            LinearGradient(
                colors: [Color.white.opacity(0.04), accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct ExtensionNotchSectionView: View {
    let section: AtollNotchContentSection
    let accent: Color
    let allowWebInteraction: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExtensionNotchSectionHeader(section: section)
            layoutContent
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var layoutContent: some View {
        switch section.layout {
        case .stack:
            VStack(alignment: .leading, spacing: 10) {
                elementViews
            }
        case .columns:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                elementViews
            }
        case .metrics:
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                elementViews
            }
        }
    }

    @ViewBuilder
    private var elementViews: some View {
        ForEach(Array(section.elements.enumerated()), id: \.offset) { index, element in
            ExtensionWidgetElementView(
                element: element,
                accent: accent,
                allowWebInteraction: allowWebInteraction
            )
            .accessibilityIdentifier("extension-notch-element-\(index)")
        }
    }
}

struct ExtensionNotchSectionHeader: View {
    let section: AtollNotchContentSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }
}

struct ExtensionMinimalisticExperienceView: View {
    let payload: ExtensionNotchExperiencePayload
    let albumArtNamespace: Namespace.ID

    @Default(.enableExtensionNotchInteractiveWebViews) private var interactiveWebViewsEnabled

    private var descriptor: AtollNotchExperienceDescriptor { payload.descriptor }
    private var configuration: AtollNotchExperienceDescriptor.MinimalisticConfiguration? { descriptor.minimalistic }
    private var accent: Color { descriptor.accentColor.swiftUIColor }

    var body: some View {
        Group {
            if let configuration {
                let hasWebContent = configuration.webContent != nil
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let headline = configuration.headline {
                            Text(headline)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        if let subtitle = configuration.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        ForEach(Array(configuration.sections.enumerated()), id: \.offset) { index, section in
                            ExtensionNotchSectionView(
                                section: section,
                                accent: accent,
                                allowWebInteraction: interactiveWebViewsEnabled
                            )
                            .accessibilityIdentifier("extension-minimalistic-section-\(payload.descriptor.id)-\(index)")
                        }
                        if let webDescriptor = configuration.webContent {
                            ExtensionWebContentView(
                                descriptor: webDescriptor,
                                allowInteraction: interactiveWebViewsEnabled
                            )
                            .frame(height: webDescriptor.preferredHeight)
                            .frame(maxWidth: webDescriptor.maximumContentWidth ?? .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, hasWebContent ? 0 : 10)
                }
            } else {
                MinimalisticMusicPlayerView(albumArtNamespace: albumArtNamespace)
            }
        }
    }
}
