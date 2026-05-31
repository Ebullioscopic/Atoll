/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import WeatherKit
import CoreLocation
import Combine

/// Manages weather data fetching using WeatherKit + CoreLocation for the notch weather tab.
@MainActor
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    @Published var currentTemperature: String = "--°"
    @Published var currentCondition: String = "Loading..."
    @Published var currentSymbolName: String = "cloud.fill"
    @Published var hourlyForecast: [HourForecastItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var refreshTimer: Timer?

    struct HourForecastItem: Identifiable {
        let id = UUID()
        let hour: String
        let temperature: String
        let symbolName: String
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func startMonitoring() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorized {
            locationManager.requestLocation()
        }
        // Refresh every 15 minutes
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.locationManager.requestLocation()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func fetchWeather(for location: CLLocation) async {
        isLoading = true
        errorMessage = nil
        do {
            let weather = try await weatherService.weather(for: location)

            // Current conditions
            let current = weather.currentWeather
            currentTemperature = "\(Int(current.temperature.converted(to: .fahrenheit).value))°F"
            currentCondition = current.condition.description
            currentSymbolName = current.symbolName

            // 5-hour forecast
            let formatter = DateFormatter()
            formatter.dateFormat = "ha"
            let nextHours = Array(weather.hourlyForecast.forecast.prefix(5))
            hourlyForecast = nextHours.map { hour in
                HourForecastItem(
                    hour: formatter.string(from: hour.date),
                    temperature: "\(Int(hour.temperature.converted(to: .fahrenheit).value))°",
                    symbolName: hour.symbolName
                )
            }
        } catch {
            errorMessage = "Unable to load weather"
        }
        isLoading = false
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            await self.fetchWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Location unavailable"
            self.isLoading = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            manager.requestLocation()
        }
    }
}
