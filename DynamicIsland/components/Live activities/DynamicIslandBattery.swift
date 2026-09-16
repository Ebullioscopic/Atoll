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

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {
    @Default(.showPowerStatusIcons) var showPowerStatusIcons
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool
    var showPercentInside: Bool = false

    var animationStyle: DynamicIslandAnimations = DynamicIslandAnimations()

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        if showPercentInside {
            filledBody
        } else {
            outlinedBody
        }
    }

    // MARK: - Filled body

    /// Apple draws the battery as a filled shape with the figure sitting on it:
    /// a light body, the charge as a coloured fill running from the left, and
    /// the percentage in dark type centred over the whole body — not over the
    /// fill, so it does not move as the charge does.
    ///
    /// The outlined drawing below puts a thin `battery.0` symbol around a small
    /// inner bar, which is the older treatment and leaves the figure competing
    /// with the outline for the same few points.
    private var filledBody: some View {
        let height = batteryWidth * 0.52
        let inset: CGFloat = 1.5
        let bodyRadius = height * 0.34
        let fraction = min(max(CGFloat(levelBattery) / 100, 0), 1)

        return HStack(spacing: height * 0.11) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                    .fill(bodyFill)

                RoundedRectangle(cornerRadius: bodyRadius - inset * 0.5, style: .continuous)
                    .fill(batteryColor)
                    // Proportional, with a floor only above zero and only wide
                    // enough to be visible. Flooring it at the body's height
                    // instead -- reasoning that a fill wants to be at least as
                    // wide as it is round -- put the floor at 12.6pt of a 27pt
                    // track on a 30pt battery, so an empty one drew as 47% full
                    // and every level below that was overstated.
                    .frame(width: fillWidth(fraction: fraction, inset: inset))
                    .padding(inset)

                HStack(spacing: height * 0.04) {
                    Text("\(Int(levelBattery))")
                        .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    if let statusSymbol {
                        Image(systemName: statusSymbol)
                            .font(.system(size: height * 0.42, weight: .bold))
                    }
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: batteryWidth, alignment: .center)
            }
            .frame(width: batteryWidth, height: height)

            // The terminal. Apple keeps it detached from the body.
            RoundedRectangle(cornerRadius: height * 0.1, style: .continuous)
                .fill(bodyFill)
                .frame(width: height * 0.11, height: height * 0.36)
        }
        .animation(.smooth(duration: 0.3), value: levelBattery)
        .animation(.smooth(duration: 0.3), value: batteryColor)
    }

    private func fillWidth(fraction: CGFloat, inset: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max((batteryWidth - inset * 2) * fraction, 2)
    }

    /// The unfilled part of the battery, and its terminal. Light enough that
    /// the dark figure reads against it even at a very low charge, when there
    /// is almost no coloured fill behind the number.
    private var bodyFill: Color {
        .white.opacity(0.45)
    }

    private var statusSymbol: String? {
        guard iconStatus != "", isForNotification || showPowerStatusIcons else { return nil }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    // MARK: - Outlined body

    private var outlinedBody: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || showPowerStatusIcons) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

/// Pill battery for the minimalist notch, matching the charging HUD style.
struct MinimalisticBatteryView: View {
    @Default(.showPowerStatusIcons) var showPowerStatusIcons
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var bodyWidth: CGFloat = 28
    var bodyHeight: CGFloat = 16
    var isForNotification: Bool
    var showPercentInside: Bool = false

    private var clamped: CGFloat {
        max(0, min(CGFloat(levelBattery), 100))
    }

    private var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if clamped <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || clamped == 100 {
            return .green
        } else {
            return .white
        }
    }

    private var showsStatusGlyph: Bool {
        (isCharging || isPluggedIn) && (isForNotification || showPowerStatusIcons)
    }

    private var statusSymbol: String? {
        guard showsStatusGlyph else { return nil }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    private var glyphColor: Color {
        isCharging ? .white : .black
    }

    private var terminalHeight: CGFloat {
        max(4, bodyHeight * 0.38)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(batteryColor.opacity(0.3))

                GeometryReader { geo in
                    Rectangle()
                        .fill(batteryColor.gradient)
                        .frame(width: max(0, (clamped / 100) * geo.size.width))
                }

                if showPercentInside {
                    HStack(spacing: 0.5) {
                        Text("\(Int(clamped))")
                            .font(.system(size: bodyHeight * 0.6, weight: .heavy, design: .rounded))
                            .foregroundStyle(glyphColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let statusSymbol {
                            Image(systemName: statusSymbol)
                                .font(.system(size: bodyHeight * 0.42, weight: .black))
                                .foregroundStyle(glyphColor)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 2)
                } else if let statusSymbol {
                    Image(systemName: statusSymbol)
                        .font(.system(size: bodyHeight * 0.6, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(clamped == 100 ? batteryColor.gradient : batteryColor.opacity(0.4).gradient)
                .frame(width: 2, height: terminalHeight)
        }
        .animation(.smooth(duration: 0.18), value: clamped)
        .animation(.smooth(duration: 0.18), value: isCharging)
        .animation(.smooth(duration: 0.18), value: isPluggedIn)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Max Capacity: \(Int(maxCapacity))%")
                    .font(.subheadline)
                    .fontWeight(.regular)
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if timeToFullCharge > 0 {
                    Label("Time to Full Charge: \(timeToFullCharge) min", systemImage: "clock")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if !isCharging && isPluggedIn && levelBattery >= 80 {
                    Label("Charging on Hold: Desktop Mode", systemImage: "desktopcomputer")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                    
            }
            .padding(.vertical, 8)

            Divider()

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 280)
        .foregroundStyle(.primary)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}


/// A view that displays the battery status and allows interaction to show detailed information.
struct DynamicIslandBatteryView: View {
    
    @Default(.showBatteryPercentage) var showBatteryPercentage
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringPopover: Bool = false

    @EnvironmentObject var vm: DynamicIslandViewModel

    var body: some View {
        HStack {
            // The number goes in one place or the other, never both.
            if showBatteryPercentage && !showBatteryPercentInside {
                ZStack(alignment: .trailing) {
                    Text("100%")
                        .font(.callout)
                        .hidden()
                    
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification,
                showPercentInside: showBatteryPercentInside
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation {
                        isPressed = false
                        showPopupMenu.toggle()
                    }
                }
        )
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
            }
        }
        .onChange(of: showPopupMenu) { _, _ in
            updateBatteryPopoverActiveState()
        }
        .onChange(of: isHoveringPopover) { _, _ in
            updateBatteryPopoverActiveState()
        }
    }

    private func updateBatteryPopoverActiveState() {
        vm.isBatteryPopoverActive = showPopupMenu && isHoveringPopover
    }
}


private struct BatteryTemporaryHUDMetrics {
    let width: CGFloat
    let height: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
}

private extension BatteryTemporaryHUDKind {
    func metrics(
        style: BatteryNotificationStyle,
        closedNotchWidth: CGFloat,
        baseHeight: CGFloat
    ) -> BatteryTemporaryHUDMetrics {
        let compactBaseRadius = max(baseHeight / 2, 16)
        let compactTopRadius = max(12, compactBaseRadius - 4)

        switch (self, style) {
        case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 180,
                height: baseHeight,
                topRadius: compactTopRadius,
                bottomRadius: compactBaseRadius
            )
        case (.lowBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 150,
                height: baseHeight + 75,
                topRadius: 22,
                bottomRadius: 40
            )
        case (.fullBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 140,
                height: baseHeight + 70,
                topRadius: 18,
                bottomRadius: 36
            )
        }
    }
}

private struct BatteryCompactStatusRow: View {
    let title: String
    let batteryLevel: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(verbatim: title)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 6) {
                Text("\(batteryLevel)%")
                    .font(.system(size: 14))
                    .foregroundColor(tint)

                HStack(spacing: 1.5) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.3))

                        GeometryReader { geo in
                            let clamped = max(0, min(batteryLevel, 100))
                            let width = CGFloat(clamped) / 100 * geo.size.width
                            Rectangle()
                                .fill(tint.gradient)
                                .frame(width: max(0, width))
                        }
                    }
                    .frame(width: 28, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(batteryLevel == 100 ? tint.gradient : tint.opacity(0.3).gradient)
                        .frame(width: 2, height: 6)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

struct BatteryTemporaryActivityView: View {
    let kind: BatteryTemporaryHUDKind
    let batteryLevel: Int
    let isLowPowerMode: Bool
    let closedNotchWidth: CGFloat
    let baseHeight: CGFloat
    let isDynamicIslandMode: Bool
    let topCornerRadius: CGFloat
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    var styleOverride: BatteryNotificationStyle? = nil

    @State private var pulse = false
    @State private var showBatteryIndicator = false
    @State private var changeBatteryIndicator = true

    private var style: BatteryNotificationStyle {
        if kind == .charging {
            return .compact
        }
        if let styleOverride {
            return styleOverride
        }
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }

    private var metrics: BatteryTemporaryHUDMetrics {
        kind.metrics(
            style: style,
            closedNotchWidth: closedNotchWidth,
            baseHeight: baseHeight
        )
    }

    private var batteryTint: Color {
        switch kind {
        case .charging:
            if isLowPowerMode {
                return .yellow
            } else if batteryLevel <= 20 {
                return .red
            }
            return .green
        case .lowBattery:
            return isLowPowerMode ? .yellow : .red
        case .fullBattery:
            return isLowPowerMode ? .yellow : .green
        }
    }


    private var surfaceShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(DynamicIslandPillShape(cornerRadius: dynamicIslandPillCornerRadiusInsets.opened))
        } else {
            return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: metrics.bottomRadius))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .bottom)
        .clipShape(surfaceShape)
        .onAppear(perform: prepareAnimations)
    }

    @ViewBuilder
    private var content: some View {
        if style == .compact {
            BatteryCompactStatusRow(
                title: compactTitle,
                batteryLevel: batteryLevel,
                tint: batteryTint
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: kind == .lowBattery ? 2 : 3) {
                        standardTitle
                        standardDescription
                    }

                    Spacer()

                    standardIndicator
                }
                .padding(.leading, kind == .lowBattery ? 40 : 35)
                .padding(.trailing, kind == .lowBattery ? 45 : 40)
                .padding(.bottom, 20)
            }
        }
    }

    private var compactTitle: String {
        switch kind {
        case .charging:
            return String(localized: "Charging")
        case .lowBattery:
            return String(localized: "Low Battery")
        case .fullBattery:
            return String(localized: "Full Battery")
        }
    }

    @ViewBuilder
    private var standardTitle: some View {
        HStack(spacing: 5) {
            Text(verbatim: kind == .lowBattery ? String(localized: "Battery Low") : String(localized: "Full Battery"))
                .font(.system(size: kind == .lowBattery ? 13 : 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Text("\(batteryLevel)%")
                .font(.system(size: kind == .lowBattery ? 12 : 13, weight: .semibold))
                .foregroundStyle(batteryTint)
        }
    }

    @ViewBuilder
    private var standardDescription: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode {
                (
                    Text(verbatim: String(localized: "Low Power Mode enabled"))
                        .foregroundColor(.yellow)
                        .font(.system(size: 10, weight: .medium))
                    +
                    Text(verbatim: String(localized: ", it is recommended to charge it."))
                        .foregroundColor(.gray.opacity(0.6))
                        .font(.system(size: 10, weight: .medium))
                )
            } else {
                Text(verbatim: String(localized: "Turn on Low Power Mode or it\nis recommended to charge it."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .fullBattery:
            Text(verbatim: String(localized: "Your Mac is fully charged."))
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.6))
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var standardIndicator: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode {
                yellowLowIndicator
            } else {
                redLowIndicator
            }
        case .fullBattery:
            if showBatteryIndicator {
                if isLowPowerMode {
                    yellowFullIndicator
                        .transition(.opacity.combined(with: .scale))
                } else {
                    greenFullIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            } else {
                magSafeIndicator
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var redLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.red.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulse ? 1 : 0.3)
                .offset(x: -15)

            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.red.opacity(0.9), lineWidth: 1.5)
                .frame(width: pulse ? 8 : 30, height: pulse ? 14 : 32)
                .offset(x: -15)
                .opacity(pulse ? 0.3 : 1)
        }
    }

    private var yellowLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(.yellow.gradient)
                .frame(width: 8, height: 14)
                .offset(x: -15)
        }
    }

    private var greenFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.green.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var yellowFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var magSafeIndicator: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)

                Circle()
                    .fill(changeBatteryIndicator ? .orange : .green)
                    .shadow(color: changeBatteryIndicator ? .orange : .green, radius: 5)
                    .frame(width: 5, height: 5)
            }

            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
    }

    private func prepareAnimations() {
        pulse = false
        showBatteryIndicator = kind == .fullBattery && style == .standard
        changeBatteryIndicator = true

        guard style == .standard else { return }

        switch kind {
        case .charging:
            break
        case .lowBattery:
            if !isLowPowerMode {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        case .fullBattery:
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(duration: 0.4)) {
                    showBatteryIndicator = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(duration: 0.2)) {
                    changeBatteryIndicator = false
                }
            }
        }
    }
}

#Preview {
    DynamicIslandBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
