import Foundation

@main
struct BatteryPowerRegression {
    static func main() {
        func reading(_ extra: [String: Any] = [:]) -> BatteryPowerReading {
            var properties: [String: Any] = [
                "ExternalConnected": true, "IsCharging": true,
                "Voltage": 12000, "Amperage": 4000,
                "PowerTelemetryData": ["SystemPowerIn": 65085]
            ]
            properties.merge(extra) { _, new in new }
            return BatteryPowerReading(properties: properties)
        }
        precondition(reading().chargingWatts == 48)
        precondition(reading().inputWatts == 65.085)
        precondition(reading(["IsCharging": false]).chargingWatts == nil)
        precondition(reading(["IsCharging": false]).inputWatts == 65.085)
        precondition(reading(["ExternalConnected": false]).chargingWatts == nil)
        precondition(reading(["ExternalConnected": false]).inputWatts == nil)
        precondition(reading(["Amperage": -4000]).chargingWatts == nil)
        precondition(reading(["Amperage": NSNumber(value: UInt64.max)]).chargingWatts == nil)
        precondition(reading(["Voltage": 0]).chargingWatts == nil)
        precondition(reading(["Amperage": Double.nan]).chargingWatts == nil)
        precondition(reading(["Amperage": 0]).chargingWatts == 0)
        precondition(reading(["PowerTelemetryData": ["SystemPowerIn": -1]]).inputWatts == nil)
        precondition(reading(["PowerTelemetryData": ["SystemPowerIn": 0]]).inputWatts == 0)
        precondition(BatteryPowerReading(properties: [:]).chargingWatts == nil)
        precondition(BatteryPowerReading(properties: [:]).inputWatts == nil)
        precondition(reading(["PowerTelemetryData": [:], "AdapterDetails": ["Watts": 100]]).inputWatts == nil)
        print("Battery power regression checks passed")
    }
}
