import Foundation
import UIKit

/// Ground-level approach to a door, its bottom step, or an open courtyard gate.
/// Coordinates share the model's local X/Z axes and rotate about its grid anchor.
struct BuildingRoadEntrance {
    let point: SIMD2<Float>
    let outward: SIMD2<Int>
    let roadCells: [SIMD2<Int>]
    let width: Float

    init(x: Float = 0, z: Float, facing: Int = 1, cells: [Int] = [0], width: Float = 0.22) {
        point = SIMD2(x, z)
        outward = SIMD2(0, facing)
        roadCells = cells.map { SIMD2($0, facing) }
        self.width = width
    }

    static func rotate<T: SIMDScalar & SignedNumeric>(_ p: SIMD2<T>, steps: Int) -> SIMD2<T> {
        switch ((steps % 4) + 4) % 4 {
        case 1: SIMD2(p.y, -p.x)
        case 2: SIMD2(-p.x, -p.y)
        case 3: SIMD2(-p.y, p.x)
        default: p
        }
    }
}

extension BuildingType {
    /// Keep these approach points aligned with the model's doorstep, not its bounding box.
    func roadEntrances(variant: Int) -> [BuildingRoadEntrance] {
        let mirror: Float = variant % 3 == 1 ? -1 : 1
        switch self {
        case .tent: return [.init(z: 0.275)]
        case .cottage: return [.init(x: -0.16 * mirror, z: 0.405)]
        case .house: return [.init(x: -0.175 * mirror, z: 0.428)]
        case .barn: return [.init(z: 0.39, width: 0.32), .init(z: -0.39, facing: -1, width: 0.32)]
        case .well: return [.init(z: 0.38, width: 0.24)]
        case .farm: return [.init(x: -0.15, z: 0.402)]
        case .homestead: return [.init(z: 0.443), .init(x: 1.14, z: 0.425, cells: [1])]
        case .stables: return [.init(x: 0.68, z: 0.423, cells: [1])]
        case .tavern: return [.init(x: -0.18, z: 0.433)]
        case .blacksmith: return [.init(x: -0.21, z: 0.405)]
        case .market: return [.init(z: 0.402, width: 0.30), .init(z: -0.402, facing: -1, width: 0.30)]
        case .shop, .flowerShop: return [.init(x: -0.225, z: 0.402, width: 0.20)]
        case .post: return [.init(z: 0.435)]
        case .townhall, .school: return [.init(z: 0.463, width: 0.26)]
        case .church: return [.init(x: -0.24, z: 0.434, width: 0.22)]
        case .fireStation: return [.init(x: -0.19, z: 0.432, width: 0.25), .init(x: 0.19, z: 0.432, width: 0.25)]
        case .policeStation: return [.init(z: 0.442, width: 0.26)]
        case .hospital: return [.init(z: 0.475, width: 0.30)]
        case .fortress: return [.init(z: 0.489, width: 0.235)]
        case .tower: return [.init(z: 0.32)]
        case .cathedral: return [.init(z: 0.484, width: 0.30)]
        case .chateau: return [.init(x: 0.5, z: 0.489, cells: [0, 1], width: 0.43)]
        case .castle: return [.init(z: 0.489, width: 0.24)]
        case .hauntedHouse: return [.init(x: -0.08, z: 0.45, width: 0.21)]
        case .gingerbreadHouse: return [.init(z: 0.34)]
        }
    }
}

/// A short curved spur expressed relative to the owning road tile.
struct RoadEntranceConnection: Equatable {
    let end: SIMD2<Float>
    let outward: SIMD2<Int>
    let width: Float

    func outline(extraWidth: Float) -> UIBezierPath {
        let direction = SIMD2<Float>(Float(outward.x), Float(outward.y))
        let a = -direction * 0.16 // begins inside the road's rounded centre
        let b = -direction * 0.40
        let c = end + direction * 0.16
        let d = end
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...20 {
            let t = Float(i)/20, u = 1-t
            let p = u*u*u*a + 3*u*u*t*b + 3*u*t*t*c + t*t*t*d
            let tangent = 3*u*u*(b-a) + 6*u*t*(c-b) + 3*t*t*(d-c)
            let length = max(0.0001, sqrt(tangent.x*tangent.x + tangent.y*tangent.y))
            let normal = SIMD2(-tangent.y, tangent.x)/length
            let half = (width + extraWidth + 0.06*u)/2
            let l = p + normal*half, r = p - normal*half
            // SCNShape's Y becomes world -Z when laid on the ground.
            left.append(CGPoint(x: CGFloat(l.x), y: CGFloat(-l.y)))
            right.append(CGPoint(x: CGFloat(r.x), y: CGFloat(-r.y)))
        }
        let path = UIBezierPath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        path.close()
        return path
    }
}
