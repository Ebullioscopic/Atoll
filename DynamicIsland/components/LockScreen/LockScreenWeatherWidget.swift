import SwiftUI

struct LockScreenWeatherWidget: View {
    let snapshot: LockScreenWeatherSnapshot

    private let primaryFont = Font.system(size: 22, weight: .semibold, design: .rounded)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let charging = snapshot.charging {
                chargingSegment(for: charging)
            }

            if let bluetooth = snapshot.bluetooth {
                bluetoothSegment(for: bluetooth)
            }

            weatherSegment

            if shouldShowLocation {
                locationSegment
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color.white.opacity(0.65))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.clear)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var weatherSegment: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(snapshot.temperatureText)
                .font(primaryFont)
                .kerning(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .layoutPriority(2)
        }
    }

    @ViewBuilder
    private func chargingSegment(for info: LockScreenWeatherSnapshot.ChargingInfo) -> some View {
        if let iconName = chargingIconName(for: info) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                if let text = formattedChargingTime(for: info) {
                    Text(text)
                        .font(primaryFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1.2)
                }
            }
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func bluetoothSegment(for info: LockScreenWeatherSnapshot.BluetoothInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: info.iconName)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text("\(clampedBatteryLevel(info.batteryLevel))%")
                .font(primaryFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .layoutPriority(1.4)
        }
    }

    @ViewBuilder
    private var locationSegment: some View {
        if let locationName = snapshot.locationName {
            Text(locationName)
                .font(primaryFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .layoutPriority(0.7)
        }
    }

    private var shouldShowLocation: Bool {
        snapshot.showsLocation && (snapshot.locationName?.isEmpty == false)
    }

    private func chargingIconName(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
        let icon = info.iconName
        return icon.isEmpty ? nil : icon
    }

    private func formattedChargingTime(for info: LockScreenWeatherSnapshot.ChargingInfo) -> String? {
        guard let minutes = info.minutesRemaining, minutes > 0 else {
            return nil
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    private func clampedBatteryLevel(_ level: Int) -> Int {
        min(max(level, 0), 100)
    }

    private var accessibilityLabel: String {
        var components: [String] = []

        if snapshot.showsLocation, let locationName = snapshot.locationName, !locationName.isEmpty {
            components.append(
                String(
                    format: NSLocalizedString("Weather: %@ %@ in %@", comment: "Weather description, temperature, and location"),
                    snapshot.description,
                    snapshot.temperatureText,
                    locationName
                )
            )
        } else {
            components.append(
                String(
                    format: NSLocalizedString("Weather: %@ %@", comment: "Weather description and temperature"),
                    snapshot.description,
                    snapshot.temperatureText
                )
            )
        }

        if let charging = snapshot.charging {
            components.append(accessibilityChargingText(for: charging))
        }

        if let bluetooth = snapshot.bluetooth {
            components.append(accessibilityBluetoothText(for: bluetooth))
        }

        return components.joined(separator: ". ")
    }

    private func accessibilityChargingText(for charging: LockScreenWeatherSnapshot.ChargingInfo) -> String {
        if let minutes = charging.minutesRemaining, minutes > 0 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .full
            let duration = formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) minutes"
            return String(
                format: NSLocalizedString("Battery charging, %@ remaining", comment: "Charging time remaining"),
                duration
            )
        }

        if charging.isPluggedIn && !charging.isCharging {
            return NSLocalizedString("Battery fully charged", comment: "Battery is full")
        }

        return NSLocalizedString("Battery charging", comment: "Battery charging without estimate")
    }

    private func accessibilityBluetoothText(for bluetooth: LockScreenWeatherSnapshot.BluetoothInfo) -> String {
        return String(
            format: NSLocalizedString("Bluetooth device %@ at %d percent", comment: "Bluetooth device battery"),
            bluetooth.deviceName,
            bluetooth.batteryLevel
        )
    }
}
