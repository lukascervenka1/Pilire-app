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

    @MainActor
    var displayName: String {
        switch self {
        case .road:       L(T(cs: "Cesta", sk: "Cesta", en: "Path"))
        case .tree:       L(T(cs: "Jehličnan", sk: "Ihličnan", en: "Pine tree"))
        case .leafTree:   L(T(cs: "Listnáč", sk: "Listnáč", en: "Leafy tree"))
        case .fruitTree:  L(T(cs: "Ovocný strom", sk: "Ovocný strom", en: "Fruit tree"))
        case .bush:       L(T(cs: "Keř", sk: "Ker", en: "Bush"))
        case .bench:      L(T(cs: "Lavička", sk: "Lavička", en: "Bench"))
        case .fountain:   L(T(cs: "Fontána", sk: "Fontána", en: "Fountain"))
        case .pond:       L(T(cs: "Rybníček", sk: "Rybníček", en: "Pond"))
        case .doghouse:   L(T(cs: "Psí bouda", sk: "Psia búda", en: "Doghouse"))
        case .birdFeeder: L(T(cs: "Krmítko", sk: "Kŕmidlo", en: "Bird feeder"))
        case .firePit:    L(T(cs: "Ohniště", sk: "Ohnisko", en: "Fire pit"))
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

    @MainActor
    var description: String {
        switch self {
        case .road:
            L(T(cs: "Táhni prstem po mapě, platíš za políčko",
                sk: "Ťahaj prstom po mape, platíš za políčko",
                en: "Drag across the map, you pay per tile"))
        case .tree:
            L(T(cs: "Štíhlý a stálezelený", sk: "Štíhly a stálezelený",
                en: "Slim and evergreen"))
        case .leafTree:
            L(T(cs: "Košatá koruna do parku", sk: "Košatá koruna do parku",
                en: "A broad crown for the park"))
        case .fruitTree:
            L(T(cs: "Jabloň, švestka nebo pomerančovník, co ti padne",
                sk: "Jabloň, slivka alebo pomarančovník, čo ti padne",
                en: "Apple, plum or orange tree, whichever you get"))
        case .bush:
            L(T(cs: "Drobná zeleň kamkoli, pokaždé trochu jiná",
                sk: "Drobná zeleň kamkoľvek, zakaždým trochu iná",
                en: "Small greenery anywhere, never quite the same"))
        case .bench:
            L(T(cs: "Místo k odpočinku", sk: "Miesto na oddych", en: "A place to rest"))
        case .fountain:
            L(T(cs: "Dominanta náměstí", sk: "Dominanta námestia",
                en: "The centrepiece of a square"))
        case .pond:
            L(T(cs: "Kachnička v ceně (2 pole)", sk: "Kačička v cene (2 polia)",
                en: "Duck included (2 tiles)"))
        case .doghouse:
            L(T(cs: "V noci v ní spí pes. Můžeš mu nasypat do misky",
                sk: "V noci v nej spí pes. Môžeš mu nasypať do misky",
                en: "Your dog sleeps here at night. You can fill the bowl"))
        case .birdFeeder:
            L(T(cs: "Slétají se na něj ptáci", sk: "Zlietavajú sa naň vtáky",
                en: "Birds come and visit"))
        case .firePit:
            L(T(cs: "Po setmění se rozhoří", sk: "Po zotmení sa rozhorí",
                en: "Lights up after dark"))
        }
    }
}
