import Foundation
import SwiftData

@Model
final class PlacedDecoration {
    var type: DecorationItem
    var gridX: Int
    var gridY: Int
    var placedDate: Date
    var rotation: Int = 0    // 0–3 × 90°

    /// Small greenery can sit on a tile *corner* instead of a tile centre, which
    /// fills the gaps where four rounded road tiles meet. Corners form their own
    /// lattice: (gridX, gridY) then ranges 0…cols and each corner is shared by
    /// the four tiles around it, so one corner holds at most one decoration.
    var isCornerAnchor: Bool = false

    /// Which look this piece rolled from its type's pool (fruit trees, bushes).
    /// Stored so a decoration keeps its appearance when moved.
    var variant: Int = 0

    /// Doghouse only: there's food in the bowl waiting for a pet.
    var hasFood: Bool = false

    /// Player-written name shown on the doghouse sign.
    var label: String = ""

    init(type: DecorationItem, gridX: Int, gridY: Int,
         isCornerAnchor: Bool = false, variant: Int = 0) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.placedDate = .now
        self.isCornerAnchor = isCornerAnchor
        self.variant = variant
    }
}

enum DecorationItem: String, Codable, CaseIterable {
    case road
    case tree          // jehličnan
    case leafTree      // listnáč
    case fruitTree     // ovocný strom (jabloň / švestka / pomerančovník)
    case bush          // keř (3 podoby)
    case bench
    case fountain
    case pond          // rybníček s kachničkou (2 pole)
    case doghouse      // psí bouda — pes v ní v noci spí, miska na žrádlo
    case birdFeeder    // krmítko — slétají se na něj ptáci
    case firePit       // ohniště — přes den studené, v noci hoří

    // Tolerant decode so older saves (and any future trimming) never crash.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DecorationItem(rawValue: raw) ?? .bush
    }

    /// Grid footprint (cells along x × cells along z). Anchor = first cell.
    var footprint: (w: Int, l: Int) {
        self == .pond ? (2, 1) : (1, 1)
    }

    /// How many looks this item can roll. Fruit trees and bushes come as a
    /// small pool so a row of them never looks copy-pasted.
    var variantCount: Int {
        switch self {
        case .fruitTree, .bush: 3
        default:                1
        }
    }

    /// Small cosmetic items may snap to a tile corner as well as its centre.
    /// Anything with a real footprint (roads, pond, fountain) stays on centres.
    var canUseCornerAnchor: Bool {
        switch self {
        case .tree, .leafTree, .fruitTree, .bush, .bench, .birdFeeder: true
        case .road, .fountain, .pond, .doghouse, .firePit:             false
        }
    }

    var displayName: String {
        switch self {
        case .road:       "Cesta"
        case .tree:       "Jehličnan"
        case .leafTree:   "Listnáč"
        case .fruitTree:  "Ovocný strom"
        case .bush:       "Keř"
        case .bench:      "Lavička"
        case .fountain:   "Fontána"
        case .pond:       "Rybníček"
        case .doghouse:   "Psí bouda"
        case .birdFeeder: "Krmítko"
        case .firePit:    "Ohniště"
        }
    }

    var emoji: String {
        switch self {
        case .road:       "🪨"
        case .tree:       "🌲"
        case .leafTree:   "🌳"
        case .fruitTree:  "🍎"
        case .bush:       "🌿"
        case .bench:      "🪑"
        case .fountain:   "⛲"
        case .pond:       "🦆"
        case .doghouse:   "🐕"
        case .birdFeeder: "🐦"
        case .firePit:    "🔥"
        }
    }

    var symbolName: String {
        switch self {
        case .road:       "road.lanes"
        case .tree:       "tree.fill"
        case .leafTree:   "tree.fill"
        case .fruitTree:  "tree.circle.fill"
        case .bush:       "leaf.fill"
        case .bench:      "chair.lounge.fill"
        case .fountain:   "drop.fill"
        case .pond:       "water.waves"
        case .doghouse:   "dog.fill"
        case .birdFeeder: "bird.fill"
        case .firePit:    "flame.fill"
        }
    }

    var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .road:       (0.64, 0.55, 0.42)
        case .tree:       (0.30, 0.52, 0.32)
        case .leafTree:   (0.42, 0.64, 0.34)
        case .fruitTree:  (0.82, 0.42, 0.34)
        case .bush:       (0.48, 0.68, 0.40)
        case .bench:      (0.62, 0.45, 0.30)
        case .fountain:   (0.36, 0.62, 0.80)
        case .pond:       (0.30, 0.58, 0.78)
        case .doghouse:   (0.72, 0.48, 0.28)
        case .birdFeeder: (0.55, 0.62, 0.42)
        case .firePit:    (0.90, 0.48, 0.20)
        }
    }

    var cost: Int {
        switch self {
        case .road:       20
        case .tree:       15
        case .leafTree:   15
        case .fruitTree:  25
        case .bush:       8
        case .bench:      15
        case .fountain:   40
        case .pond:       60
        case .doghouse:   70
        case .birdFeeder: 45
        case .firePit:    55
        }
    }

    /// Coins to fill the doghouse bowl once.
    static let dogFoodPrice = 15

    var description: String {
        switch self {
        case .road:       "Táhni prstem po mapě, platíš za políčko"
        case .tree:       "Štíhlý a stálezelený"
        case .leafTree:   "Košatá koruna do parku"
        case .fruitTree:  "Jabloň, švestka nebo pomerančovník, co ti padne"
        case .bush:       "Drobná zeleň kamkoli, pokaždé trochu jiná"
        case .bench:      "Místo k odpočinku"
        case .fountain:   "Dominanta náměstí"
        case .pond:       "Kachnička v ceně (2 pole)"
        case .doghouse:   "V noci v ní spí pes. Můžeš mu nasypat do misky"
        case .birdFeeder: "Slétají se na něj ptáci"
        case .firePit:    "Po setmění se rozhoří"
        }
    }
}
