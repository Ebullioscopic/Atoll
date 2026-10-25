/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Unified audio visualizer that conditionally uses real-time audio spectrum
 * or the original animated spectrum based on user preference.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

/// Unified audio visualizer view that switches between real-time and animated based on user preference
struct AudioVisualizerView: View {
    @Binding var isPlaying: Bool
    @Default(.enableRealTimeWaveform) private var enableRealTimeWaveform
    @ObservedObject private var bluetoothAudioManager = BluetoothAudioManager.shared

    var body: some View {
        // Bluetooth output can't be tapped, so capture is stopped and the animated spectrum stands in.
        if enableRealTimeWaveform && !bluetoothAudioManager.isBluetoothAudioConnected {
            RealTimeAudioSpectrumView(isPlaying: $isPlaying)
        } else {
            AudioSpectrumView(isPlaying: $isPlaying)
        }
    }
}

#Preview("Animated") {
    AudioVisualizerView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
