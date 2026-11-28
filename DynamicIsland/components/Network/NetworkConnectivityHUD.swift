/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI

enum NetworkConnectivityHUDMetrics {
    static func isPresented(
        state: ConnectivityHUDState,
        notchState: NotchState,
        hideOnClosed: Bool,
        isLocked: Bool
    ) -> Bool {
        notchState == .closed
            && state.isVisible
            && !hideOnClosed
            && !isLocked
    }

    static func size(
        for state: ConnectivityHUDState,
        closedNotchSize: CGSize,
        effectiveClosedNotchHeight: CGFloat
    ) -> CGSize? {
        switch state {
        case .hidden:
            return nil
        case .noConnection:
            return CGSize(
                width: closedNotchSize.width + 210,
                height: effectiveClosedNotchHeight + 125
            )
        case .wifi, .hotspot:
            return CGSize(
                width: max(closedNotchSize.width + 220, 450),
                height: closedNotchSize.height
            )
        }
    }
}

struct NetworkConnectivityHUD: View {
    let state: ConnectivityHUDState
    let closedNotchSize: CGSize
    let effectiveClosedNotchHeight: CGFloat

    @ObservedObject private var manager = NetworkConnectivityManager.shared

    private let accent = Color(red: 0.36, green: 0.88, blue: 0.42)

    var body: some View {
        if let size = NetworkConnectivityHUDMetrics.size(
            for: state,
            closedNotchSize: closedNotchSize,
            effectiveClosedNotchHeight: effectiveClosedNotchHeight
        ) {
            content
                .frame(width: size.width, height: size.height)
                .accessibilityElement(children: .contain)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .noConnection:
            noConnectionContent
        case .wifi(let name):
            connectedNetworkContent(name: name, isHotspot: false)
        case .hotspot(let name):
            connectedNetworkContent(name: name, isHotspot: true)
        }
    }

    private var noConnectionContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: max(effectiveClosedNotchHeight + 2, 30))

            HStack(spacing: 14) {
                ZStack {
                    // The grey copy stays visible while the green copy reveals
                    // the antenna layers progressively from the centre outward.
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.gray.opacity(0.62))

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(accent)
                        .symbolEffect(
                            .variableColor.iterative.reversing,
                            options: .repeating.speed(0.82)
                        )
                }
                .font(.system(size: 31, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("No Internet Connection")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Connect to Wi-Fi, Ethernet, or Personal Hotspot.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                connectivityButton(
                    title: "OK",
                    foreground: .white,
                    background: Color.white.opacity(0.13),
                    action: manager.dismissNoConnection
                )
                .accessibilityIdentifier("ConnectivityHUD.OK")

                connectivityButton(
                    title: "Settings",
                    foreground: Color(red: 0.28, green: 0.58, blue: 1),
                    background: Color(red: 0.08, green: 0.16, blue: 0.27),
                    action: manager.openNetworkSettings
                )
                .accessibilityIdentifier("ConnectivityHUD.Settings")
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
        }
        .accessibilityIdentifier("ConnectivityHUD.NoConnection")
    }

    private func connectedNetworkContent(name: String, isHotspot: Bool) -> some View {
        let totalWidth = NetworkConnectivityHUDMetrics.size(
            for: state,
            closedNotchSize: closedNotchSize,
            effectiveClosedNotchHeight: effectiveClosedNotchHeight
        )?.width ?? closedNotchSize.width
        let wingWidth = max(0, (totalWidth - closedNotchSize.width) / 2)

        return HStack(spacing: 0) {
            Image(systemName: isHotspot ? "personalhotspot" : "wifi")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.leading, 18)
                .frame(
                    width: wingWidth,
                    height: closedNotchSize.height,
                    alignment: .leading
                )

            Color.clear
                .frame(
                    width: closedNotchSize.width,
                    height: closedNotchSize.height
                )

            VStack(alignment: .trailing, spacing: 1) {
                Text(isHotspot ? "Hotspot connected" : "Wi-Fi connected")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
            }
            .padding(.trailing, 18)
            .frame(
                width: wingWidth,
                height: closedNotchSize.height,
                alignment: .trailing
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isHotspot ? "Hotspot" : "Wi-Fi") connected, \(name)")
        .accessibilityIdentifier(isHotspot ? "ConnectivityHUD.Hotspot" : "ConnectivityHUD.WiFi")
    }

    private func connectivityButton(
        title: LocalizedStringKey,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 35)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
