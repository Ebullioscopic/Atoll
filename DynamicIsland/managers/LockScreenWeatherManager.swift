import Foundation
import Defaults
import CoreLocation
import Combine

@MainActor
final class LockScreenWeatherManager: ObservableObject {
    static let shared = LockScreenWeatherManager()

    @Published private(set) var snapshot: LockScreenWeatherSnapshot?

    private let provider = LockScreenWeatherProvider()
    private let locationProvider = LockScreenWeatherLocationProvider()
    private var lastFetchDate: Date?
    private var latestWeatherPayload: LockScreenWeatherSnapshot?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeAccessoryChanges()
    }

    func prepareLocationAccess() {
        locationProvider.prepareAuthorization()
    }

    func showWeatherWidget() {
        guard Defaults[.enableLockScreenWeatherWidget] else {
            LockScreenWeatherPanelManager.shared.hide()
            return
        }

        locationProvider.prepareAuthorization()

        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await self.refresh(force: self.snapshot == nil)

            guard LockScreenManager.shared.currentLockStatus else {
                LockScreenWeatherPanelManager.shared.hide()
                return
            }

            if let snapshot {
                self.deliver(snapshot, forceShow: true)
            } else {
                LockScreenWeatherPanelManager.shared.hide()
            }
        }
    }

    func hideWeatherWidget() {
        LockScreenWeatherPanelManager.shared.hide()
    }

    @discardableResult
    func refresh(force: Bool = false) async -> LockScreenWeatherSnapshot? {
        let interval = Defaults[.lockScreenWeatherRefreshInterval]
        if !force, let lastFetchDate, Date().timeIntervalSince(lastFetchDate) < interval {
            if let payload = latestWeatherPayload {
                if Defaults[.lockScreenWeatherShowsBluetooth] {
                    BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
                }
                let snapshot = makeSnapshot(from: payload)
                self.snapshot = snapshot
                deliver(snapshot, forceShow: false)
                return snapshot
            } else if let snapshot = snapshot {
                deliver(snapshot, forceShow: false)
                return snapshot
            }
            return snapshot
        }

        do {
            let location = await locationProvider.currentLocation()
            let payload = try await provider.fetchSnapshot(location: location)
            latestWeatherPayload = payload
            if Defaults[.lockScreenWeatherShowsBluetooth] {
                BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
            }
            let snapshot = makeSnapshot(from: payload)
            self.snapshot = snapshot
            lastFetchDate = Date()
            deliver(snapshot, forceShow: false)
            return snapshot
        } catch {
            NSLog("LockScreenWeatherManager: failed to fetch weather - \(error.localizedDescription)")

            let fallback = LockScreenWeatherSnapshot(
                temperatureText: snapshot?.temperatureText ?? "--",
                symbolName: snapshot?.symbolName ?? "cloud.fill",
                description: snapshot?.description ?? "",
                locationName: snapshot?.locationName,
                charging: Defaults[.lockScreenWeatherShowsCharging] ? makeChargingInfo() : nil,
                bluetooth: Defaults[.lockScreenWeatherShowsBluetooth] ? makeBluetoothInfo() : nil,
                showsLocation: snapshot?.showsLocation ?? false
            )

            self.snapshot = fallback
            deliver(fallback, forceShow: false)
            return fallback
        }
    }

    private func observeAccessoryChanges() {
        let bluetoothManager = BluetoothAudioManager.shared

        bluetoothManager.$connectedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        bluetoothManager.$lastConnectedDevice
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        let battery = BatteryStatusViewModel.shared
        let batteryPublishers: [AnyPublisher<Void, Never>] = [
            battery.$isCharging.map { _ in () }.eraseToAnyPublisher(),
            battery.$isPluggedIn.map { _ in () }.eraseToAnyPublisher(),
            battery.$timeToFullCharge.map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(batteryPublishers)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: false)
            }
            .store(in: &cancellables)

        let defaultsPublishers: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.lockScreenWeatherShowsLocation, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsCharging, options: [])
                .map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsBluetooth, options: [])
                .map { _ in () }.eraseToAnyPublisher()
        ]

        Publishers.MergeMany(defaultsPublishers)
            .sink { [weak self] in
                self?.handleAccessoryUpdate(triggerBluetoothRefresh: true)
            }
            .store(in: &cancellables)
    }

    private func handleAccessoryUpdate(triggerBluetoothRefresh: Bool) {
        guard let payload = latestWeatherPayload else { return }

        if triggerBluetoothRefresh {
            BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
        }

        let snapshot = makeSnapshot(from: payload)
        self.snapshot = snapshot
        deliver(snapshot, forceShow: false)
    }

    private func deliver(_ snapshot: LockScreenWeatherSnapshot, forceShow: Bool) {
        guard LockScreenManager.shared.currentLockStatus else { return }

        if forceShow {
            LockScreenWeatherPanelManager.shared.show(with: snapshot)
        } else {
            LockScreenWeatherPanelManager.shared.update(with: snapshot)
        }
    }

    private func makeSnapshot(from payload: LockScreenWeatherSnapshot) -> LockScreenWeatherSnapshot {
        let locationName = payload.locationName
        let shouldShowLocation = Defaults[.lockScreenWeatherShowsLocation] && !(locationName?.isEmpty ?? true)
        let chargingInfo = Defaults[.lockScreenWeatherShowsCharging] ? makeChargingInfo() : nil
        let bluetoothInfo = Defaults[.lockScreenWeatherShowsBluetooth] ? makeBluetoothInfo() : nil

        return LockScreenWeatherSnapshot(
            temperatureText: payload.temperatureText,
            symbolName: payload.symbolName,
            description: payload.description,
            locationName: locationName,
            charging: chargingInfo,
            bluetooth: bluetoothInfo,
            showsLocation: shouldShowLocation
        )
    }

    private func makeChargingInfo() -> LockScreenWeatherSnapshot.ChargingInfo? {
        let battery = BatteryStatusViewModel.shared
        let macStatus = MacBatteryManager.shared.currentStatus()

        let isPluggedIn = battery.isPluggedIn || battery.isCharging
        let isCharging = macStatus.isCharging || battery.isCharging

        guard isPluggedIn || isCharging else {
            return nil
        }

        let rawMinutes = macStatus.timeRemainingMinutes ?? (battery.timeToFullCharge > 0 ? battery.timeToFullCharge : nil)
        let remaining = (rawMinutes ?? 0) > 0 ? rawMinutes : nil

        return LockScreenWeatherSnapshot.ChargingInfo(
            minutesRemaining: remaining,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn
        )
    }

    private func makeBluetoothInfo() -> LockScreenWeatherSnapshot.BluetoothInfo? {
        let manager = BluetoothAudioManager.shared

        guard manager.isBluetoothAudioConnected else {
            return nil
        }

        let device = manager.connectedDevices.last ?? manager.lastConnectedDevice

        guard let device else {
            return nil
        }

        guard let batteryLevel = device.batteryLevel else {
            return nil
        }

        return LockScreenWeatherSnapshot.BluetoothInfo(
            deviceName: device.name,
            batteryLevel: clampBluetoothBatteryLevel(batteryLevel),
            iconName: device.deviceType.sfSymbol
        )
    }

    private func clampBluetoothBatteryLevel(_ level: Int) -> Int {
        min(max(level, 0), 100)
    }
}

struct LockScreenWeatherSnapshot: Equatable {
    struct ChargingInfo: Equatable {
        let minutesRemaining: Int?
        let isCharging: Bool
        let isPluggedIn: Bool

        var iconName: String {
            if isCharging {
                return "bolt.fill"
            }
            if isPluggedIn {
                return "powerplug.portrait.fill"
            }
            return ""
        }
    }

    struct BluetoothInfo: Equatable {
        let deviceName: String
        let batteryLevel: Int
        let iconName: String
    }

    let temperatureText: String
    let symbolName: String
    let description: String
    let locationName: String?
    let charging: ChargingInfo?
    let bluetooth: BluetoothInfo?
    let showsLocation: Bool
}

private actor LockScreenWeatherProvider {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
    }

    func fetchSnapshot(location: CLLocation?) async throws -> LockScreenWeatherSnapshot {
        let locationSuffix: String
        if let coordinate = location?.coordinate {
            let lat = String(format: "%.4f", coordinate.latitude)
            let lon = String(format: "%.4f", coordinate.longitude)
            locationSuffix = "\(lat),\(lon)"
        } else {
            locationSuffix = ""
        }

        let urlString = locationSuffix.isEmpty ? "https://wttr.in/?format=j1" : "https://wttr.in/\(locationSuffix)?format=j1"

        guard let url = URL(string: urlString) else {
            throw WeatherProviderError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherProviderError.invalidResponse
        }

        let payload = try decoder.decode(WTTRResponse.self, from: data)
        guard let condition = payload.currentCondition.first else {
            throw WeatherProviderError.noData
        }

        let usesMetric = Locale.current.usesMetricSystem
        let temperature = usesMetric ? condition.tempC : condition.tempF
        let temperatureText = "\(temperature)°"

        let code = Int(condition.weatherCode) ?? 113
        let symbol = WeatherSymbolMapper.symbol(for: code)
        let description = condition.localizedDescription

        let nearest = payload.nearestArea.first
        let locationName = nearest?.preferredName

        return LockScreenWeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: symbol,
            description: description,
            locationName: locationName,
            charging: nil,
            bluetooth: nil,
            showsLocation: true
        )
    }
}

enum WeatherProviderError: Error {
    case invalidURL
    case invalidResponse
    case noData
}

private struct WTTRResponse: Decodable {
    let current_condition: [WTTRCurrentCondition]
    let nearest_area: [WTTRNearestArea]?

    var currentCondition: [WTTRCurrentCondition] { current_condition }
    var nearestArea: [WTTRNearestArea] { nearest_area ?? [] }
}

private struct WTTRCurrentCondition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case tempC = "temp_C"
        case tempF = "temp_F"
        case weatherCode
        case weatherDesc
        case langEn = "lang_en"
    }

    let tempC: String
    let tempF: String
    let weatherCode: String
    let weatherDesc: [WTTRTextValue]?
    let langEn: [WTTRTextValue]?

    var localizedDescription: String {
        if let english = langEn?.first?.value, !english.isEmpty {
            return english
        }
        if let desc = weatherDesc?.first?.value, !desc.isEmpty {
            return desc
        }
        return ""
    }
}

private struct WTTRTextValue: Decodable {
    let value: String
}

private struct WTTRNearestArea: Decodable {
    let areaName: [WTTRTextValue]?
    let region: [WTTRTextValue]?
    let country: [WTTRTextValue]?

    private enum CodingKeys: String, CodingKey {
        case areaName = "areaName"
        case region
        case country
    }

    var preferredName: String? {
        if let name = areaName?.first?.value, !name.isEmpty {
            return name
        }
        if let regionName = region?.first?.value, !regionName.isEmpty {
            return regionName
        }
        if let countryName = country?.first?.value, !countryName.isEmpty {
            return countryName
        }
        return nil
    }
}

private enum WeatherSymbolMapper {
    static func symbol(for code: Int) -> String {
        switch code {
        case 113:
            return "sun.max.fill"
        case 116:
            return "cloud.sun.fill"
        case 119, 122:
            return "cloud.fill"
        case 143, 248, 260:
            return "cloud.fog.fill"
        case 176, 263, 266, 293, 296, 299, 302, 353, 356, 359:
            return "cloud.rain.fill"
        case 179, 182, 185, 311, 314, 317, 320, 362, 365:
            return "cloud.sleet.fill"
        case 227, 230, 281, 284, 317, 320, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377:
            return "cloud.snow.fill"
        case 200, 386, 389, 392, 395:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.sun.fill"
        }
    }
}

@MainActor
private final class LockScreenWeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var lastLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func prepareAuthorization() {
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentLocation() async -> CLLocation? {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 1800 {
                return lastLocation
            }
            manager.requestLocation()
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        default:
            return nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        continuation?.resume(returning: lastLocation)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
