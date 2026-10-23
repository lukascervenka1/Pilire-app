import Foundation

enum TownWeather {
    case sunny, rain, fog, storm

    var hasPrecipitation: Bool { self == .rain || self == .storm }

    /// Stable for the whole local day. Storms replace a small share of rainy
    /// days; most days remain sunny and saved towns need no new stored state.
    static func seeded(at date: Date, calendar: Calendar = .current) -> TownWeather {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let year = calendar.component(.year, from: date)
        var value = UInt64(day * 131 + year * 17) &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        let roll = Double(value & 0xFFFF) / Double(0xFFFF)
        if roll < 0.70 { return .sunny }
        if roll < 0.80 { return .rain }
        if roll < 0.85 { return .storm }
        return .fog
    }
}
