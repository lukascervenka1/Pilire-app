import Foundation
import SwiftData

@Model
final class DayRecord {
    var date: Date
    var pillars: [Pillar]
    var isCompleted: Bool
    @Relationship(deleteRule: .nullify, inverse: \Building.dayRecord)
    var buildings: [Building] = []
    /// Habits taken off this day on purpose, so they aren't added back.
    var skippedHabits: [String] = []

    init(date: Date = .now) {
        self.date = Calendar.current.startOfDay(for: date)
        self.pillars = []
        self.isCompleted = false
    }

    var completedCount: Int { pillars.filter(\.isCompleted).count }
}

struct Pillar: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var isCompleted: Bool = false
    var order: Int
    var isFromPool: Bool = false
    var isHabit: Bool = false             // auto-added from a recurring habit
    var scheduledAt: Date? = nil          // optional time anchor for the task
    var calendarEventID: String? = nil    // EventKit event, when exported
    var woodAwarded: Int = 0              // reward granted on completion (refunded on undo)

    init(text: String, order: Int, isFromPool: Bool = false,
         isHabit: Bool = false, scheduledAt: Date? = nil) {
        self.text = text
        self.order = order
        self.isFromPool = isFromPool
        self.isHabit = isHabit
        self.scheduledAt = scheduledAt
    }

    // Tolerant decoding: pillars saved before a field existed simply use its
    // default (SwiftData stores [Pillar] as an encoded blob, so adding a
    // property would otherwise crash old data with keyNotFound).
    private enum CodingKeys: String, CodingKey {
        case id, text, isCompleted, order, isFromPool, isHabit, scheduledAt, calendarEventID, woodAwarded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self,   forKey: .id)          ?? UUID()
        text            = try c.decodeIfPresent(String.self, forKey: .text)        ?? ""
        isCompleted     = try c.decodeIfPresent(Bool.self,   forKey: .isCompleted) ?? false
        order           = try c.decodeIfPresent(Int.self,    forKey: .order)       ?? 0
        isFromPool      = try c.decodeIfPresent(Bool.self,   forKey: .isFromPool)  ?? false
        isHabit         = try c.decodeIfPresent(Bool.self,   forKey: .isHabit)     ?? false
        scheduledAt     = try c.decodeIfPresent(Date.self,   forKey: .scheduledAt)
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        woodAwarded     = try c.decodeIfPresent(Int.self,    forKey: .woodAwarded)    ?? 0
    }
}

@Model
final class Building {
    var type: BuildingType
    var gridX: Int
    var gridY: Int
    var builtDate: Date
    var isComplete: Bool
    var dayRecord: DayRecord?
    var rotation: Int = 0        // 0–3 × 90°

    // Customization (future upgrade UI) — 0 = default look
    var roofColorIndex: Int = 0
    var facadeIndex: Int = 0

    /// Tidied away into the inventory instead of standing on the map. The record
    /// is kept rather than deleted, so the calendar and chronicle still remember
    /// the day it was built, and badges never slip away.
    var isStored: Bool = false

    init(type: BuildingType, gridX: Int, gridY: Int, builtDate: Date = .now, isComplete: Bool = true) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.builtDate = builtDate
        self.isComplete = isComplete
    }
}

// MARK: - Materials

enum Material: String, Codable, CaseIterable, Identifiable {
    case wood, brick, steel
    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .wood:  L(T(cs: "Dřevo", sk: "Drevo", en: "Wood"))
        case .brick: L(T(cs: "Cihly", sk: "Tehly", en: "Bricks"))
        case .steel: L(T(cs: "Ocel", sk: "Oceľ", en: "Steel"))
        }
    }

    /// "3 cihly", "8 cihel", "1 cihla". Czech and Slovak decline the noun with
    /// the number, so "8 cihly" (which is what pasting the plain name produced)
    /// is simply wrong.
    @MainActor
    func amount(_ n: Int) -> String {
        switch Language.shared.current {
        case .cs:
            switch self {
            case .wood:  n == 1 ? "1 dřevo" : "\(n) dřeva"
            case .brick: n == 1 ? "1 cihla" : (n <= 4 ? "\(n) cihly" : "\(n) cihel")
            case .steel: n == 1 ? "1 ocel"  : "\(n) oceli"
            }
        case .sk:
            switch self {
            case .wood:  n == 1 ? "1 drevo" : "\(n) dreva"
            case .brick: n == 1 ? "1 tehla" : (n <= 4 ? "\(n) tehly" : "\(n) tehál")
            case .steel: n == 1 ? "1 oceľ"  : "\(n) ocele"
            }
        case .en:
            switch self {
            case .wood:  "\(n) wood"
            case .brick: n == 1 ? "1 brick" : "\(n) bricks"
            case .steel: "\(n) steel"
            }
        }
    }

    var symbolName: String {
        switch self {
        case .wood:  "tree.fill"
        case .brick: "square.stack.3d.up.fill"
        case .steel: "gearshape.2.fill"
        }
    }

    /// UI tint (r, g, b)
    var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .wood:  (0.58, 0.42, 0.25)
        case .brick: (0.80, 0.42, 0.32)
        case .steel: (0.45, 0.52, 0.60)
        }
    }

    /// Coin price for one unit in the exchange.
    var coinPrice: Int {
        switch self {
        case .wood:  10
        case .brick: 20
        case .steel: 40
        }
    }
}

struct MaterialCost {
    var wood: Int = 0
    var brick: Int = 0
    var steel: Int = 0
}

// MARK: - Building types

enum BuildingType: String, Codable, CaseIterable {
    case tent, cottage, house, barn, well
    case farm, homestead, stables
    case tavern, blacksmith, market, shop, flowerShop, post
    case townhall, school, church, fireStation, policeStation, hospital, fortress, tower
    case cathedral, chateau, castle
    case hauntedHouse, gingerbreadHouse      // seasonal

    // Tolerant decode: a building saved under a removed type (e.g. the old
    // skyscraper) becomes a castle instead of crashing SwiftData.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BuildingType(rawValue: raw) ?? .castle
    }

    /// Grid footprint (cells along x × cells along z). Anchor = first cell.
    /// Multi-cell buildings rotate in 90° steps; the second cell swings around
    /// the anchor (occupancy is rotation-aware).
    var footprint: (w: Int, l: Int) {
        switch self {
        case .tavern, .farm, .homestead, .stables, .chateau: (2, 1)
        default:                                   (1, 1)
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .tent:       L(T(cs: "Stan", sk: "Stan", en: "Tent"))
        case .cottage:    L(T(cs: "Chalupa", sk: "Chalupa", en: "Cottage"))
        case .house:      L(T(cs: "Rodinný domek", sk: "Rodinný domček", en: "Family house"))
        case .barn:       L(T(cs: "Stodola", sk: "Stodola", en: "Barn"))
        case .well:       L(T(cs: "Studna", sk: "Studňa", en: "Well"))
        case .farm:       L(T(cs: "Farma", sk: "Farma", en: "Farm"))
        case .homestead:  L(T(cs: "Statek", sk: "Statok", en: "Homestead"))
        case .stables:    L(T(cs: "Stáje", sk: "Stajne", en: "Stables"))
        case .shop:       L(T(cs: "Obchod", sk: "Obchod", en: "Shop"))
        case .flowerShop: L(T(cs: "Květinářství", sk: "Kvetinárstvo", en: "Flower shop"))
        case .post:       L(T(cs: "Pošta", sk: "Pošta", en: "Post office"))
        case .school:     L(T(cs: "Škola", sk: "Škola", en: "School"))
        case .tower:      L(T(cs: "Věž", sk: "Veža", en: "Tower"))
        case .tavern:     L(T(cs: "Hostinec", sk: "Hostinec", en: "Tavern"))
        case .blacksmith: L(T(cs: "Kovárna", sk: "Kováčstvo", en: "Blacksmith"))
        case .market:     L(T(cs: "Tržiště", sk: "Trhovisko", en: "Market"))
        case .townhall:   L(T(cs: "Radnice", sk: "Radnica", en: "Town hall"))
        case .church:     L(T(cs: "Kostel", sk: "Kostol", en: "Church"))
        case .fireStation:   L(T(cs: "Hasiči", sk: "Hasiči", en: "Fire station"))
        case .policeStation: L(T(cs: "Policie", sk: "Polícia", en: "Police station"))
        case .hospital:      L(T(cs: "Nemocnice", sk: "Nemocnica", en: "Hospital"))
        case .fortress:   L(T(cs: "Pevnost", sk: "Pevnosť", en: "Fortress"))
        case .cathedral:  L(T(cs: "Katedrála", sk: "Katedrála", en: "Cathedral"))
        case .chateau:    L(T(cs: "Zámek", sk: "Zámok", en: "Chateau"))
        case .castle:     L(T(cs: "Hrad", sk: "Hrad", en: "Castle"))
        case .hauntedHouse:     L(T(cs: "Strašidelný dům", sk: "Strašidelný dom", en: "Haunted house"))
        case .gingerbreadHouse: L(T(cs: "Perníková chaloupka", sk: "Perníková chalúpka", en: "Gingerbread house"))
        }
    }

    var emoji: String {
        switch self {
        case .tent:       "⛺"
        case .cottage:    "🏠"
        case .house:      "🏡"
        case .barn:       "🏚"
        case .well:       "⛲"
        case .farm:       "🌾"
        case .homestead:  "🚜"
        case .stables:    "🐎"
        case .shop:       "🏬"
        case .flowerShop: "💐"
        case .post:       "✉️"
        case .school:     "🎓"
        case .tower:      "🗼"
        case .tavern:     "🍺"
        case .blacksmith: "⚒️"
        case .market:     "🏪"
        case .townhall:   "🏛"
        case .church:     "⛪"
        case .fireStation:   "🚒"
        case .policeStation: "🚓"
        case .hospital:      "🏥"
        case .fortress:   "🏯"
        case .cathedral:  "🕌"
        case .chateau:    "👑"
        case .castle:     "🏰"
        case .hauntedHouse:     "🎃"
        case .gingerbreadHouse: "🍪"
        }
    }

    /// Cena v materiálech (viz implementační plán).
    var cost: MaterialCost {
        switch self {
        case .well:       MaterialCost(wood: 6)
        case .tent:       MaterialCost(wood: 4)
        case .cottage:    MaterialCost(wood: 10)
        case .house:      MaterialCost(wood: 12, brick: 4)
        case .barn:       MaterialCost(wood: 14, brick: 2)
        case .farm:       MaterialCost(wood: 16, brick: 4)
        case .homestead:  MaterialCost(wood: 20, brick: 6)
        case .stables:    MaterialCost(wood: 18, brick: 6, steel: 1)
        case .shop:       MaterialCost(wood: 12, brick: 8)
        case .flowerShop: MaterialCost(wood: 10, brick: 6)
        case .post:       MaterialCost(wood: 12, brick: 8, steel: 1)
        case .school:     MaterialCost(wood: 18, brick: 14, steel: 2)
        case .tower:      MaterialCost(wood: 12, brick: 16, steel: 3)
        case .tavern:     MaterialCost(wood: 16, brick: 8)
        case .blacksmith: MaterialCost(wood: 10, brick: 8)
        case .market:     MaterialCost(wood: 14, brick: 10)
        case .townhall:   MaterialCost(wood: 16, brick: 12, steel: 2)
        case .church:     MaterialCost(wood: 18, brick: 14, steel: 3)
        case .fireStation:   MaterialCost(wood: 14, brick: 10, steel: 2)
        case .policeStation: MaterialCost(wood: 12, brick: 12, steel: 2)
        case .hospital:      MaterialCost(wood: 16, brick: 16, steel: 4)
        case .fortress:   MaterialCost(wood: 20, brick: 16, steel: 5)
        case .cathedral:  MaterialCost(wood: 24, brick: 20, steel: 8)
        case .chateau:    MaterialCost(wood: 26, brick: 22, steel: 10)
        case .castle:     MaterialCost(wood: 28, brick: 24, steel: 12)
        case .hauntedHouse:     MaterialCost(wood: 14, brick: 8)
        case .gingerbreadHouse: MaterialCost(wood: 12, brick: 10)
        }
    }
}
