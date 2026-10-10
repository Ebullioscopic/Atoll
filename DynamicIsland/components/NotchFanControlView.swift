import SwiftUI

struct NotchFanControlView: View {
    @ObservedObject private var service = FanControlService.shared
    private let fractions = [0.3, 0.5, 0.7, 1.0]
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Fan speeds", systemImage: "fan")
                    Spacer()
                    if let temperature = service.hottestTemperature {
                        Label("\(Int(temperature))°C", systemImage: "thermometer")
                            .monospacedDigit()
                    }
                }
                .font(.caption).foregroundStyle(.secondary)

                if service.fans.isEmpty {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(service.fans) { fan in
                        fanCard(fan)
                    }
                }
                commandStatus
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service.start() }
        .onDisappear { service.stop() }
    }

    private func fanCard(_ fan: CoolingFan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(fan.name).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(fan.actualRPM)) RPM").font(.subheadline).monospacedDigit()
            }
            ProgressView(value: min(fan.actualRPM, fan.maximumRPM), total: fan.maximumRPM)
                .tint(.cyan)
            HStack(spacing: 6) {
                ForEach(fractions, id: \.self) { fraction in
                    presetButton("\(Int(fraction * 100))%", fan: fan, active: service.presets[fan.id] == fraction) {
                        service.apply(fraction, to: fan.id)
                    }
                    .help("\(Int((try? fan.rpm(at: fraction)) ?? 0)) RPM")
                }
                presetButton("Auto", fan: fan, active: fan.mode == .automatic || fan.mode == .system) {
                    service.apply(nil, to: fan.id)
                }
            }
            HStack {
                Text(modeText(fan.mode))
                Spacer()
                if fan.mode == .manual { Text("Target \(Int(fan.targetRPM)) RPM") }
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var commandStatus: some View {
        if service.isApplying {
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Applying…") }
                .font(.caption).foregroundStyle(.secondary)
        } else if let error = service.controlError {
            VStack(alignment: .leading, spacing: 4) {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if service.needsReconnect {
                    Button("Retry connection") { service.retryConnection() }.buttonStyle(.plain).font(.caption)
                }
            }
        } else {
            Text("Presets use each fan’s minimum-to-maximum range.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func presetButton(_ title: String, fan: CoolingFan, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(active ? Color.cyan.opacity(0.25) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fan.name), \(title)")
        .disabled(service.isApplying || service.needsReconnect || service.status != .ready)
    }

    private func modeText(_ mode: CoolingFan.Mode) -> String {
        switch mode { case .automatic, .system: return "macOS Auto"; case .manual: return "Manual"; case .unknown: return "Mode unavailable" }
    }

    private var statusText: String {
        switch service.status {
        case .ready: return "Live"
        case .discovering: return "Checking fans…"
        case .unavailable(let message): return message
        }
    }
}
