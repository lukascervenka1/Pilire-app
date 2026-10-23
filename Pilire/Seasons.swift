import Foundation

// MARK: - Seasonal events
//
// A stretch of the year with its own buildings and decorations for sale. What
// you buy during one is yours for good and can be put out any time — the
// inventory is what lets you tidy it away afterwards and bring it back next
// year, the way you'd put the Christmas tree back in the attic.

enum SeasonalEvent: String, CaseIterable, Identifiable {
    case halloween, christmas
    var id: String { rawValue }

    /// First and last day, inclusive, as (month, day). Christmas wraps over
    /// New Year.
    private var window: (start: (m: Int, d: Int), end: (m: Int, d: Int)) {
        switch self {
        case .halloween: ((10, 1), (11, 3))
        case .christmas: ((12, 1), (1, 6))
        }
    }

    func contains(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        let c = cal.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return false }
        let v = m * 100 + d
        let s = window.start.m * 100 + window.start.d
        let e = window.end.m * 100 + window.end.d
        return s <= e ? (v >= s && v <= e) : (v >= s || v <= e)
    }

    static func current(at date: Date = .now) -> SeasonalEvent? {
        allCases.first { $0.contains(date) }
    }

    /// First day of the next run that hasn't started yet.
    func nextStart(after date: Date = .now, calendar cal: Calendar = .current) -> Date {
        let today = cal.startOfDay(for: date)
        let year = cal.component(.year, from: date)
        for y in [year, year + 1] {
            if let d = cal.date(from: DateComponents(year: y, month: window.start.m, day: window.start.d)),
               d > today {
                return d
            }
        }
        return today
    }

    /// Last day of the run that's on at `date`.
    func lastDay(around date: Date = .now, calendar cal: Calendar = .current) -> Date {
        let year = cal.component(.year, from: date)
        let month = cal.component(.month, from: date)
        let wraps = window.start.m > window.end.m
        let endYear = wraps && month >= window.start.m ? year + 1 : year
        return cal.date(from: DateComponents(year: endYear, month: window.end.m, day: window.end.d)) ?? date
    }

    /// The event that starts soonest after `date`.
    static func upcoming(after date: Date = .now) -> (event: SeasonalEvent, start: Date) {
        allCases
            .map { (event: $0, start: $0.nextStart(after: date)) }
            .min { $0.start < $1.start }!
    }

    @MainActor
    var title: String {
        switch self {
        case .halloween: L(T(cs: "Halloween", sk: "Halloween", en: "Halloween"))
        case .christmas: L(T(cs: "Vánoce", sk: "Vianoce", en: "Christmas"))
        }
    }

    var symbolName: String {
        switch self {
        case .halloween: "moon.stars.fill"
        case .christmas: "snowflake"
        }
    }

    var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .halloween: (0.93, 0.50, 0.16)
        case .christmas: (0.78, 0.22, 0.24)
        }
    }
}

// MARK: - Build menu categories

enum BuildCategory: String, CaseIterable, Identifiable {
    case all, housing, countryside, crafts, civic, landmarks, decorations, animals, seasonal
    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .all:         L(T(cs: "Vše", sk: "Všetko", en: "All"))
        case .housing:     L(T(cs: "Bydlení", sk: "Bývanie", en: "Homes"))
        case .countryside: L(T(cs: "Venkov", sk: "Vidiek", en: "Countryside"))
        case .crafts:      L(T(cs: "Řemesla a obchod", sk: "Remeslá a obchod", en: "Trade & crafts"))
        case .civic:       L(T(cs: "Obec", sk: "Obec", en: "Civic"))
        case .landmarks:   L(T(cs: "Dominanty", sk: "Dominanty", en: "Landmarks"))
        case .decorations: L(T(cs: "Dekorace", sk: "Dekorácie", en: "Decorations"))
        case .animals:     L(T(cs: "Zvířata", sk: "Zvieratá", en: "Animals"))
        case .seasonal:    L(T(cs: "Sezónní", sk: "Sezónne", en: "Seasonal"))
        }
    }

    var symbolName: String {
        switch self {
        case .all:         "square.grid.2x2.fill"
        case .housing:     "house.fill"
        case .countryside: "leaf.fill"
        case .crafts:      "hammer.fill"
        case .civic:       "building.columns.fill"
        case .landmarks:   "crown.fill"
        case .decorations: "tree.fill"
        case .animals:     "pawprint.fill"
        case .seasonal:    "sparkles"
        }
    }
}

extension BuildingType {
    var category: BuildCategory {
        switch self {
        case .tent, .cottage, .house:                                   .housing
        case .barn, .well, .farm, .homestead, .stables:                 .countryside
        case .tavern, .blacksmith, .market, .shop, .flowerShop, .cafe, .post: .crafts
        case .townhall, .school, .church, .fireStation, .policeStation,
             .hospital, .fortress, .tower:                              .civic
        case .cathedral, .chateau, .castle:                             .landmarks
        case .hauntedHouse, .gingerbreadHouse:                          .seasonal
        }
    }

    /// The event it belongs to, if it's only sold for part of the year.
    var event: SeasonalEvent? {
        switch self {
        case .hauntedHouse:     .halloween
        case .gingerbreadHouse: .christmas
        default:                nil
        }
    }

    func isForSale(at date: Date = .now) -> Bool {
        event.map { $0.contains(date) } ?? true
    }
}

extension DecorationItem {
    var event: SeasonalEvent? {
        switch self {
        case .pumpkins, .scarecrow:     .halloween
        case .christmasTree, .snowman:  .christmas
        default:                        nil
        }
    }

    func isForSale(at date: Date = .now) -> Bool {
        event.map { $0.contains(date) } ?? true
    }
}
