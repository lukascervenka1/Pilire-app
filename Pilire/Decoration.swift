import Foundation
import SwiftData

@Model
final class PlacedDecoration {
    var type: DecorationItem
    var gridX: Int
    var gridY: Int
    var placedDate: Date
    var rotation: Int = 0    // 0–3 × 90°

    init(type: DecorationItem, gridX: Int, gridY: Int) {
        self.type = type
        self.gridX = gridX
        self.gridY = gridY
        self.placedDate = .now
    }
}

enum DecorationItem: String, Codable, CaseIterable {
    case road
    case tree          // jehličnan
    case leafTree      // listnáč
    case bush          // keř
    case bench
    case fountain
    case pond          // rybníček s kachničkou (2 pole)

    /// Grid footprint (cells along x × cells along z). Anchor = first cell.
    var footprint: (w: Int, l: Int) {
        self == .pond ? (2, 1) : (1, 1)
    }

    var displayName: String {
        switch self {
        case .road:     "Cesta"
        case .tree:     "Jehličnan"
        case .leafTree: "Listnáč"
        case .bush:     "Keř"
        case .bench:    "Lavička"
        case .fountain: "Fontána"
        case .pond:     "Rybníček"
        }
    }

    var emoji: String {
        switch self {
        case .road:     "🪨"
        case .tree:     "🌲"
        case .leafTree: "🌳"
        case .bush:     "🌿"
        case .bench:    "🪑"
        case .fountain: "⛲"
        case .pond:     "🦆"
        }
    }

    var symbolName: String {
        switch self {
        case .road:     "road.lanes"
        case .tree:     "tree.fill"
        case .leafTree: "tree.fill"
        case .bush:     "leaf.fill"
        case .bench:    "chair.lounge.fill"
        case .fountain: "drop.fill"
        case .pond:     "water.waves"
        }
    }

    var tint: (r: Double, g: Double, b: Double) {
        switch self {
        case .road:     (0.64, 0.55, 0.42)
        case .tree:     (0.30, 0.52, 0.32)
        case .leafTree: (0.42, 0.64, 0.34)
        case .bush:     (0.48, 0.68, 0.40)
        case .bench:    (0.62, 0.45, 0.30)
        case .fountain: (0.36, 0.62, 0.80)
        case .pond:     (0.30, 0.58, 0.78)
        }
    }

    var cost: Int {
        switch self {
        case .road:     20
        case .tree:     15
        case .leafTree: 15
        case .bush:     8
        case .bench:    15
        case .fountain: 40
        case .pond:     60
        }
    }

    var description: String {
        switch self {
        case .road:     "Táhni prstem po mapě, platíš za políčko"
        case .tree:     "Štíhlý a stálezelený"
        case .leafTree: "Košatá koruna do parku"
        case .bush:     "Drobná zeleň kamkoli"
        case .bench:    "Místo k odpočinku"
        case .fountain: "Dominanta náměstí"
        case .pond:     "Kachnička v ceně (2 pole)"
        }
    }
}
