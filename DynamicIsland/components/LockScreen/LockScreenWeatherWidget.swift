import SwiftUI

struct LockScreenWeatherWidget: View {
    let snapshot: LockScreenWeatherSnapshot

    var body: some View {
        let segments = infoSegments
        HStack(spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .font(.system(size: 26, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(snapshot.temperatureText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .kerning(-0.4)

            if !segments.isEmpty {
                Color.clear.frame(width: 6)
            }

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Color.clear.frame(width: 12)
                }
                segmentView(for: segment)
            }
        }
        .foregroundStyle(Color.white.opacity(0.65))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.clear)
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private enum InfoSegment: Equatable {
        case location(String)
        case charging(String)
        case bluetooth(String, Int)
    }

    private var infoSegments: [InfoSegment] {
        var segments: [InfoSegment] = []

        if snapshot.showsLocation, let locationName = snapshot.locationName, !locationName.isEmpty {
            segments.append(.location(locationName))
        }

        if let charging = snapshot.charging {
            let iconName = charging.iconName
            if !iconName.isEmpty {
                segments.append(.charging(iconName))
            }
        }

        if let bluetooth = snapshot.bluetooth {
            segments.append(.bluetooth(bluetooth.iconName, bluetooth.batteryLevel))
        }

        return segments
    }

    @ViewBuilder
    private func segmentView(for segment: InfoSegment) -> some View {
        switch segment {
        case .location(let value):
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
        case .charging(let icon):
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        case .bluetooth(let icon, let value):
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text("\(clampedBatteryLevel(value))%")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
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
