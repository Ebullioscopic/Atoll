import Foundation

nonisolated struct EQSettings: Codable, Equatable {
    static let bandCount = 10
    static let maxGainDB: Float = 12.0
    static let minGainDB: Float = -12.0

    /// ISO standard frequencies for 10-band graphic EQ
    static let frequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    /// Gain in dB for each band (-12 to +12)
    var bandGains: [Float]

    /// Pre-EQ gain in dB (-12 to +12). Applied before the band filters so
    /// boosted curves can be trimmed back below clipping.
    var preampDB: Float = 0

    /// Whether EQ processing is enabled
    var isEnabled: Bool

    init(bandGains: [Float] = Array(repeating: 0, count: 10), preampDB: Float = 0, isEnabled: Bool = true) {
        self.bandGains = Self.normalizeBands(bandGains)
        self.preampDB = preampDB
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([Float].self, forKey: .bandGains)
            ?? Array(repeating: 0, count: Self.bandCount)
        self.bandGains = Self.normalizeBands(decoded)
        self.preampDB = try container.decodeIfPresent(Float.self, forKey: .preampDB) ?? 0
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    /// Normalize band gains array to exactly `bandCount` elements,
    /// padding with 0 or truncating as needed.
    private static func normalizeBands(_ gains: [Float]) -> [Float] {
        if gains.count == bandCount { return gains }
        if gains.count > bandCount { return Array(gains.prefix(bandCount)) }
        return gains + Array(repeating: Float(0), count: bandCount - gains.count)
    }

    /// Returns gains clamped to valid range
    var clampedGains: [Float] {
        bandGains.map { $0.isFinite ? max(Self.minGainDB, min(Self.maxGainDB, $0)) : 0 }
    }

    /// Preamp clamped to valid range
    var clampedPreampDB: Float {
        preampDB.isFinite ? max(Self.minGainDB, min(Self.maxGainDB, preampDB)) : 0
    }

    /// Flat EQ preset
    static let flat = EQSettings()
}
