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

struct ExtensionLeadingContentView: View {
    let content: AtollTrailingContent
    let badge: AtollIconDescriptor?
    let accent: Color
    let frameWidth: CGFloat
    let frameHeight: CGFloat
    let defaultIcon: AtollIconDescriptor

    var body: some View {
        Group {
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
        .frame(width: frameWidth, height: frameHeight)
    }
}

private func logExtensionDiagnostics(_ message: String) {
    guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
    Logger.log(message, category: .extensions)
}

struct ExtensionNotchExperienceTabView: View {
    let payload: ExtensionNotchExperiencePayload

    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var suppressionToken = UUID()

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
                if tabConfiguration.contentLayout == .contentOnly {
                    contentStack(for: tabConfiguration, spacing: 0, clipsWebContent: false)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            header(for: tabConfiguration)
                            contentStack(for: tabConfiguration, spacing: 18, clipsWebContent: true)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
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
        .onHover { hovering in
            vm.setScrollGestureSuppression(hovering, token: suppressionToken)
        }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: suppressionToken)
        }
        .onChange(of: vm.notchState) { _, state in
            if state == .closed {
                vm.setScrollGestureSuppression(false, token: suppressionToken)
            }
        }
    }

    @ViewBuilder
    private func contentStack(
        for configuration: AtollNotchExperienceDescriptor.TabConfiguration,
        spacing: CGFloat,
        clipsWebContent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(configuration.sections.enumerated()), id: \.offset) { index, section in
                ExtensionNotchSectionView(
                    section: section,
                    accent: accentColor,
                    allowWebInteraction: allowInteractiveWebViews
                )
                .accessibilityIdentifier("extension-notch-section-\(payload.descriptor.id)-\(index)")
            }
            if let webDescriptor = configuration.webContent {
                Group {
                    if clipsWebContent {
                        ExtensionWebContentView(
                            descriptor: webDescriptor,
                            allowInteraction: allowInteractiveWebViews
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ExtensionWebContentView(
                            descriptor: webDescriptor,
                            allowInteraction: allowInteractiveWebViews
                        )
                    }
                }
                .frame(height: webDescriptor.preferredHeight)
                .frame(maxWidth: webDescriptor.maximumContentWidth ?? .infinity)
            }
            if let footnote = configuration.footnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
