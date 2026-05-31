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

/// Weather tab view for the notch, showing current conditions and 5-hour forecast.
struct WeatherView: View {
    @StateObject private var weatherManager = WeatherManager.shared

    var body: some View {
        VStack(spacing: 12) {
            if weatherManager.isLoading && weatherManager.currentCondition == "Loading..." {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let error = weatherManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Current conditions
                HStack(spacing: 10) {
                    Image(systemName: weatherManager.currentSymbolName)
                        .font(.system(size: 28))
                        .symbolRenderingMode(.multicolor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(weatherManager.currentTemperature)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text(weatherManager.currentCondition)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 5-hour forecast
                if !weatherManager.hourlyForecast.isEmpty {
                    Divider()
                        .opacity(0.5)

                    HStack(spacing: 0) {
                        ForEach(weatherManager.hourlyForecast) { item in
                            VStack(spacing: 4) {
                                Text(item.hour)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Image(systemName: item.symbolName)
                                    .font(.system(size: 14))
                                    .symbolRenderingMode(.multicolor)
                                Text(item.temperature)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            weatherManager.startMonitoring()
        }
        .onDisappear {
            weatherManager.stopMonitoring()
        }
    }
}
