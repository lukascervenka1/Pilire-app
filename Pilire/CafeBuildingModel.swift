import SceneKit
import UIKit
import simd

/// A two-cell patisserie with a mansard house and an open garden room.
/// Local +X is the garden cell; the same thresholds drive the road connections.
enum CafeBuildingModel {
    private static let doorX: CGFloat = -0.255
    private static let gateX: CGFloat = 0.64
    private static let approachZ: CGFloat = 0.44

    static var roadEntrances: [BuildingRoadEntrance] {
        [.init(x: Float(doorX), z: Float(approachZ), width: 0.20),
         .init(x: Float(gateX), z: Float(approachZ), cells: [1], width: 0.20)]
    }

    static func build(into root: SCNNode, facade: SCNMaterial, roof: SCNMaterial,
                      stone: SCNMaterial, glass: SCNMaterial) {
        let cream = material(0.97, 0.92, 0.81)
        let rose = material(0.65, 0.37, 0.35)
        let timber = material(0.43, 0.30, 0.23)
        let oak = material(0.65, 0.49, 0.33)
        let sage = material(0.36, 0.49, 0.37)
        let leaf = material(0.48, 0.59, 0.37)
        let iron = material(0.25, 0.32, 0.31)
        let brass = material(0.72, 0.55, 0.31)
        let recess = material(0.27, 0.23, 0.21)
        let paving = material(0.79, 0.76, 0.66)

        // A taller, rounded plaster volume and steep hipped roof distinguish it
        // from the village's single-storey shops and their striped awnings.
        box(root, 0.79, 0.06, 0.65, at: (-0.045, 0.03, -0.10), material: stone, bevel: 0.018)
        box(root, 0.73, 0.71, 0.59, at: (-0.045, 0.405, -0.10), material: facade, bevel: 0.018)
        box(root, 0.752, 0.085, 0.613, at: (-0.045, 0.101, -0.10), material: rose, bevel: 0.012)
        box(root, 0.773, 0.027, 0.635, at: (-0.045, 0.487, -0.10), material: cream)
        for x: CGFloat in [-0.394, 0.304] {
            box(root, 0.026, 0.60, 0.029, at: (x, 0.44, 0.197), material: cream)
        }
        box(root, 0.80, 0.025, 0.66, at: (-0.045, 0.752, -0.10), material: cream)
        box(root, 0.83, 0.024, 0.69, at: (-0.045, 0.774, -0.10), material: stone)
        mansard(root, at: (-0.045, 0.787, -0.10), roof: roof, trim: iron)

        // The front door has a real landing: the road ends at its lower tread,
        // never under the display, a chair, or the garden's perimeter wall.
        arch(root, width: 0.205, height: 0.384, depth: 0.025,
             at: (doorX, 0.07, 0.208), material: cream)
        arch(root, width: 0.162, height: 0.348, depth: 0.016,
             at: (doorX, 0.075, 0.225), material: rose)
        arch(root, width: 0.115, height: 0.217, depth: 0.008,
             at: (doorX, 0.176, 0.239), material: glass)
        box(root, 0.12, 0.012, 0.012, at: (doorX, 0.264, 0.247), material: cream, bevel: 0.002)
        box(root, 0.10, 0.041, 0.007, at: (doorX, 0.126, 0.237), material: timber)
        sphere(root, radius: 0.009, at: (doorX + 0.054, 0.194, 0.248), material: brass)
        let step = box(root, 0.228, 0.038, 0.20,
                       at: (doorX, 0.019, approachZ - 0.10), material: stone, bevel: 0.007)
        step.name = "cafeDoorstep"
        box(root, 0.202, 0.069, 0.075, at: (doorX, 0.0345, 0.251), material: paving, bevel: 0.006)

        // The deep arched bay has a dark interior, a marble counter and three
        // distinct cakes. The pane is translucent, with a single central mullion.
        arch(root, width: 0.371, height: 0.335, depth: 0.070,
             at: (0.106, 0.131, 0.222), material: cream)
        arch(root, width: 0.325, height: 0.287, depth: 0.012,
             at: (0.106, 0.153, 0.264), material: recess)
        box(root, 0.357, 0.095, 0.105, at: (0.106, 0.110, 0.269), material: rose, bevel: 0.008)
        for x: CGFloat in [0.010, 0.196] {
            box(root, 0.125, 0.046, 0.008, at: (x, 0.110, 0.325), material: timber)
        }
        box(root, 0.394, 0.024, 0.156, at: (0.106, 0.164, 0.267), material: cream, bevel: 0.008)
        let display = SCNNode(); display.name = "cafePastries"; root.addChildNode(display)
        cake(display, x: -0.002, z: 0.295, base: 0.182, pink: true, cream: cream, rose: rose, sponge: oak)
        cake(display, x: 0.111, z: 0.295, base: 0.182, pink: false, cream: cream, rose: rose, sponge: timber)
        // A taller celebration cake gives the window an asymmetric rhythm.
        cake(display, x: 0.219, z: 0.291, base: 0.182, pink: false, cream: cream, rose: rose, sponge: oak)
        cylinder(display, radius: 0.021, height: 0.025, at: (0.219, 0.244, 0.291), material: rose)
        sphere(display, radius: 0.008, at: (0.219, 0.262, 0.291), material: cream)
        let displayGlass = glass.copy() as! SCNMaterial
        displayGlass.transparency = 0.16; displayGlass.writesToDepthBuffer = false
        let glazing = arch(root, width: 0.324, height: 0.282, depth: 0.002,
                           at: (0.106, 0.163, 0.336), material: displayGlass)
        glazing.name = "cafeDisplayGlass"; glazing.castsShadow = false
        for x: CGFloat in [-0.065, 0.277] {
            box(root, 0.016, 0.135, 0.081, at: (x, 0.231, 0.297), material: cream, bevel: 0.002)
        }
        box(root, 0.012, 0.214, 0.014, at: (0.106, 0.278, 0.341), material: cream, bevel: 0.002)

        for x: CGFloat in [-0.247, 0.143] {
            window(root, x: x, bottom: 0.539, z: 0.204, width: 0.152, height: 0.172,
                   trim: cream, glass: glass, sill: stone)
        }
        // A small flower balcony below the upper window, not a full-width awning.
        box(root, 0.194, 0.037, 0.065, at: (0.143, 0.528, 0.236), material: rose)
        for i in 0..<5 {
            let x = CGFloat(i) * 0.034 + 0.075
            sphere(root, radius: 0.024, at: (x, 0.556, 0.246), material: i.isMultiple(of: 2) ? leaf : sage)
            if i.isMultiple(of: 2) { sphere(root, radius: 0.010, at: (x, 0.574, 0.255), material: cream) }
        }
        // Garden-side glazed door makes the terrace part of the café.
        let side = SCNNode(); side.position = SCNVector3(0.327, 0, -0.10)
        side.eulerAngles.y = .pi / 2; root.addChildNode(side)
        arch(side, width: 0.19, height: 0.37, depth: 0.022, at: (0, 0.058, 0), material: cream)
        arch(side, width: 0.148, height: 0.335, depth: 0.012, at: (0, 0.065, 0.017), material: rose)
        arch(side, width: 0.108, height: 0.243, depth: 0.006, at: (0, 0.133, 0.028), material: glass)
        box(side, 0.009, 0.24, 0.009, at: (0, 0.25, 0.034), material: cream, bevel: 0.001)
        sphere(side, radius: 0.007, at: (0.052, 0.20, 0.034), material: brass)
        box(side, 0.22, 0.04, 0.09, at: (0, 0.02, 0.04), material: stone)
        window(side, x: 0, bottom: 0.543, z: 0, width: 0.18, height: 0.166,
               trim: cream, glass: glass, sill: stone)
        for (x, yaw) in [(CGFloat(-0.414), -Float.pi / 2), (CGFloat(-0.045), Float.pi)] {
            let wall = SCNNode(); wall.position = SCNVector3(x, 0, yaw == Float.pi ? -0.400 : -0.10)
            wall.eulerAngles.y = yaw; root.addChildNode(wall)
            for bottom: CGFloat in [0.208, 0.542] {
                window(wall, x: 0, bottom: bottom, z: 0, width: 0.19, height: 0.167,
                       trim: cream, glass: glass, sill: stone)
            }
        }
        // The round dormer and a copper cap break up the mansard roof.
        arch(root, width: 0.216, height: 0.212, depth: 0.180, at: (-0.045, 0.827, 0.149), material: roof)
        arch(root, width: 0.20, height: 0.20, depth: 0.018, at: (-0.045, 0.827, 0.244), material: cream)
        let rim = cylinder(root, radius: 0.060, height: 0.014, at: (-0.045, 0.931, 0.262), material: iron)
        rim.eulerAngles.x = .pi / 2
        let eye = cylinder(root, radius: 0.045, height: 0.017, at: (-0.045, 0.931, 0.272), material: glass)
        eye.eulerAngles.x = .pi / 2
        box(root, 0.009, 0.084, 0.009, at: (-0.045, 0.931, 0.285), material: cream, bevel: 0.001)
        box(root, 0.084, 0.009, 0.009, at: (-0.045, 0.931, 0.285), material: cream, bevel: 0.001)
        box(root, 0.085, 0.17, 0.09, at: (-0.258, 1.027, -0.245), material: stone)
        box(root, 0.108, 0.021, 0.111, at: (-0.258, 1.112, -0.245), material: iron)

        let sign = SCNNode(); sign.name = "cafeCupSign"; root.addChildNode(sign)
        box(sign, 0.168, 0.012, 0.015, at: (0.379, 0.669, 0.248), material: iron, bevel: 0.002)
        box(sign, 0.009, 0.053, 0.009, at: (0.450, 0.646, 0.248), material: brass, bevel: 0.001)
        let badge = cylinder(sign, radius: 0.060, height: 0.018, at: (0.450, 0.575, 0.248), material: rose)
        badge.eulerAngles.x = .pi / 2
        cup(sign, at: (0.443, 0.554, 0.270), scale: 1.13, porcelain: cream, coffee: timber)
        box(root, 0.018, 0.048, 0.012, at: (-0.390, 0.373, 0.211), material: iron, bevel: 0.002)
        box(root, 0.012, 0.012, 0.047, at: (-0.390, 0.373, 0.232), material: iron, bevel: 0.002)
        lantern(root, at: (-0.390, 0.373, 0.250), iron: iron, glass: glass, brass: brass)

        garden(root, stone: stone, paving: paving, cream: cream, rose: rose,
               oak: oak, timber: timber, iron: iron, sage: sage, leaf: leaf, glass: glass, brass: brass)
        batchStaticGeometry(in: root)
    }

    private static func garden(_ root: SCNNode, stone: SCNMaterial, paving: SCNMaterial,
                               cream: SCNMaterial, rose: SCNMaterial, oak: SCNMaterial,
                               timber: SCNMaterial, iron: SCNMaterial, sage: SCNMaterial,
                               leaf: SCNMaterial, glass: SCNMaterial, brass: SCNMaterial) {
        let garden = SCNNode(); garden.name = "cafeGarden"; root.addChildNode(garden)
        box(garden, 1.055, 0.026, 0.88, at: (0.9175, 0.013, 0), material: stone, bevel: 0.016)
        // Broad, slightly varied paving slabs keep the garden quiet at map scale.
        for row in 0..<4 {
            for col in 0..<4 {
                box(garden, 0.238, 0.007, 0.197,
                    at: (0.534 + CGFloat(col) * 0.251, 0.028, -0.318 + CGFloat(row) * 0.211),
                    material: (row + col) % 3 == 0 ? stone : paving, bevel: 0.006)
            }
        }
        let threshold = box(garden, 0.208, 0.042, 0.075,
                            at: (gateX, 0.021, approachZ - 0.0375), material: cream, bevel: 0.005)
        threshold.name = "cafeGardenThreshold"
        // The gate opens onto a clear left-hand aisle and the glazed side door.
        for x: CGFloat in [0.512, 0.768, 1.417] {
            box(garden, 0.045, 0.165, 0.047, at: (x, 0.102, 0.414), material: stone)
            box(garden, 0.059, 0.015, 0.059, at: (x, 0.193, 0.414), material: cream)
        }
        fence(garden, from: (0.791, 0.414), to: (1.395, 0.414), iron: iron, stone: stone)
        fence(garden, from: (1.417, -0.40), to: (1.417, 0.391), iron: iron, stone: stone)
        box(garden, 0.90, 0.063, 0.070, at: (0.96, 0.059, -0.416), material: stone)

        // Two small bistro settings, each with two usable chairs. The first is
        // tucked beneath an airy pergola, the other stays open to the sky.
        table(garden, x: 0.99, z: -0.235, oak: oak, iron: iron, cream: cream, coffee: timber, rose: rose)
        chair(garden, x: 0.804, z: -0.235, yaw: .pi / 2, oak: oak, iron: iron)
        chair(garden, x: 1.176, z: -0.235, yaw: -.pi / 2, oak: oak, iron: iron)
        table(garden, x: 1.10, z: 0.188, oak: oak, iron: iron, cream: cream, coffee: timber, rose: rose)
        chair(garden, x: 0.914, z: 0.188, yaw: .pi / 2, oak: oak, iron: iron)
        chair(garden, x: 1.286, z: 0.188, yaw: -.pi / 2, oak: oak, iron: iron)
        let pergola = SCNNode(); pergola.name = "cafePergola"; garden.addChildNode(pergola)
        for x: CGFloat in [0.632, 1.353] {
            for z: CGFloat in [-0.385, -0.055] {
                box(pergola, 0.027, 0.52, 0.027, at: (x, 0.291, z), material: timber, bevel: 0.002)
                box(pergola, 0.044, 0.035, 0.044, at: (x, 0.049, z), material: stone)
            }
            box(pergola, 0.035, 0.036, 0.428, at: (x, 0.560, -0.22), material: oak)
        }
        for z: CGFloat in [-0.399, -0.041] {
            box(pergola, 0.814, 0.035, 0.031, at: (0.9925, 0.550, z), material: oak)
        }
        for i in 0..<6 {
            box(pergola, 0.022, 0.022, 0.424,
                at: (0.650 + CGFloat(i) * 0.137, 0.585, -0.22), material: oak, bevel: 0.002)
        }
        // Climbing foliage stays on the rear beam and one corner: the tables
        // remain visible through the roof, including in the catalogue preview.
        let canopy: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.715, 0.600, -0.388, 0.056), (0.793, 0.617, -0.366, 0.073),
            (0.879, 0.599, -0.402, 0.051), (1.064, 0.609, -0.380, 0.069),
            (1.158, 0.621, -0.351, 0.060), (1.237, 0.596, -0.398, 0.050),
            (1.319, 0.612, -0.365, 0.078)
        ]
        for (i, cluster) in canopy.enumerated() {
            let foliage = sphere(pergola, radius: cluster.3, at: (cluster.0, cluster.1, cluster.2),
                                 material: i.isMultiple(of: 2) ? sage : leaf)
            foliage.scale = SCNVector3(1.12, 0.56, 0.83)
        }
        for i in 0..<5 {
            let y = 0.19 + CGFloat(i) * 0.079
            let x: CGFloat = i.isMultiple(of: 2) ? 1.374 : 1.332
            let foliage = sphere(pergola, radius: i == 2 ? 0.046 : 0.035,
                                 at: (x, y, -0.366), material: i.isMultiple(of: 2) ? leaf : sage)
            foliage.scale = SCNVector3(1, 0.80, 0.65)
            beam(pergola, from: SIMD3(1.353, Float(y - 0.07), -0.367),
                 to: SIMD3(Float(x), Float(y), -0.366), radius: 0.0035, material: timber)
        }
        for (x, y, z) in [(1.318, 0.643, -0.345), (1.166, 0.647, -0.333), (1.379, 0.354, -0.341)] {
            sphere(pergola, radius: 0.012, at: (x, y, z), material: cream)
        }
        // Sagging string lights use the game's existing day/night window tags.
        var previous = SIMD3<Float>(0.65, 0.532, -0.042)
        for i in 1...10 {
            let t = Float(i) / 10
            let next = SIMD3<Float>(0.65 + 0.69 * t, 0.532 - 0.065 * sin(t * .pi), -0.042)
            beam(pergola, from: previous, to: next, radius: 0.0024, material: iron)
            if i.isMultiple(of: 2) && i < 10 {
                cylinder(pergola, radius: 0.005, height: 0.018,
                         at: (CGFloat(next.x), CGFloat(next.y) - 0.010, -0.042), material: brass)
                let bulb = sphere(pergola, radius: 0.012,
                                  at: (CGFloat(next.x), CGFloat(next.y) - 0.026, -0.042), material: glass)
                bulb.castsShadow = false
            }
            previous = next
        }
        cylinder(garden, radius: 0.013, height: 0.022, at: (0.512, 0.209, 0.414), material: iron)
        lantern(garden, at: (0.512, 0.250, 0.414), iron: iron, glass: glass, brass: brass)
        planter(garden, x: 1.355, z: -0.365, pot: rose, soil: timber, leaves: sage)
        planter(garden, x: 0.424, z: 0.307, pot: rose, soil: timber, leaves: leaf)
        menu(garden, x: 0.825, z: 0.353, oak: oak, board: iron, chalk: cream)
    }

    private static func mansard(_ root: SCNNode, at p: (CGFloat, CGFloat, CGFloat),
                                roof: SCNMaterial, trim: SCNMaterial) {
        let holder = SCNNode(); holder.name = "cafeMansard"
        holder.position = SCNVector3(p.0, p.1, p.2); root.addChildNode(holder)
        let bottom: [SIMD3<Float>] = [SIMD3(-0.421, 0, 0.354), SIMD3(0.421, 0, 0.354),
                                      SIMD3(0.421, 0, -0.354), SIMD3(-0.421, 0, -0.354)]
        let top: [SIMD3<Float>] = [SIMD3(-0.275, 0.245, 0.208), SIMD3(0.275, 0.245, 0.208),
                                   SIMD3(0.275, 0.245, -0.208), SIMD3(-0.275, 0.245, -0.208)]
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [UInt16] = []
        for i in 0..<4 {
            let j = (i + 1) % 4
            let face = [bottom[i], bottom[j], top[j], top[i]]
            let n = simd_normalize(simd_cross(face[1] - face[0], face[2] - face[0]))
            let base = UInt16(vertices.count)
            vertices += face.map { SCNVector3($0) }
            normals += Array(repeating: SCNVector3(n), count: 4)
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
            beam(holder, from: bottom[i], to: top[i], radius: 0.006, material: trim)
        }
        let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        mesh.materials = [roof]; holder.addChildNode(SCNNode(geometry: mesh))
        box(holder, 0.574, 0.022, 0.44, at: (0, 0.249, 0), material: roof, bevel: 0.008)
        // Restrained standing seams, kept clear of the dormer on the front slope.
        for x: Float in [-0.30, 0.30] {
            beam(holder, from: SIMD3(x, 0.003, 0.356), to: SIMD3(x * 0.65, 0.248, 0.210), radius: 0.0028, material: trim)
        }
        for z: Float in [-0.18, 0, 0.18] {
            beam(holder, from: SIMD3(0.423, 0.003, z), to: SIMD3(0.277, 0.248, z * 0.59), radius: 0.0028, material: trim)
        }
    }

    private static func window(_ root: SCNNode, x: CGFloat, bottom: CGFloat, z: CGFloat,
                               width: CGFloat, height: CGFloat, trim: SCNMaterial, glass: SCNMaterial, sill: SCNMaterial) {
        arch(root, width: width, height: height, depth: 0.020, at: (x, bottom, z), material: trim)
        arch(root, width: width - 0.034, height: height - 0.033, depth: 0.010,
             at: (x, bottom + 0.015, z + 0.017), material: glass)
        box(root, 0.008, height - 0.028, 0.009, at: (x, bottom + height / 2, z + 0.026), material: trim, bevel: 0.001)
        box(root, width + 0.025, 0.018, 0.054, at: (x, bottom - 0.004, z + 0.014), material: sill)
    }

    private static func table(_ root: SCNNode, x: CGFloat, z: CGFloat, oak: SCNMaterial,
                              iron: SCNMaterial, cream: SCNMaterial, coffee: SCNMaterial, rose: SCNMaterial) {
        let table = SCNNode(); table.name = "cafeBistroTable"; table.position = SCNVector3(x, 0.032, z)
        root.addChildNode(table)
        cylinder(table, radius: 0.088, height: 0.018, at: (0, 0.192, 0), material: oak)
        cylinder(table, radius: 0.010, height: 0.174, at: (0, 0.096, 0), material: iron)
        cylinder(table, radius: 0.051, height: 0.008, at: (0, 0.007, 0), material: iron)
        for dx: CGFloat in [-0.042, 0.042] {
            cylinder(table, radius: 0.025, height: 0.004, at: (dx, 0.204, 0.005), material: cream)
            cup(table, at: (dx - 0.004, 0.207, 0.005), scale: 0.59, porcelain: cream, coffee: coffee)
        }
        box(table, 0.038, 0.003, 0.027, at: (0.015, 0.204, 0.045), material: cream, bevel: 0.002)
        cylinder(table, radius: 0.010, height: 0.024, at: (-0.003, 0.216, -0.035), material: rose)
        sphere(table, radius: 0.012, at: (-0.003, 0.235, -0.035), material: cream)
    }

    private static func chair(_ root: SCNNode, x: CGFloat, z: CGFloat, yaw: Float, oak: SCNMaterial, iron: SCNMaterial) {
        let chair = SCNNode(); chair.position = SCNVector3(x, 0.032, z); chair.eulerAngles.y = yaw
        root.addChildNode(chair)
        box(chair, 0.084, 0.014, 0.080, at: (0, 0.108, 0), material: oak, bevel: 0.006)
        for sx: CGFloat in [-0.031, 0.031] {
            for sz: CGFloat in [-0.028, 0.028] {
                box(chair, 0.009, 0.103, 0.009, at: (sx, 0.0515, sz), material: iron, bevel: 0.001)
            }
            box(chair, 0.009, 0.098, 0.009, at: (sx, 0.164, -0.033), material: iron, bevel: 0.001)
        }
        for y: CGFloat in [0.178, 0.207] {
            box(chair, 0.084, 0.020, 0.012, at: (0, y, -0.033), material: oak, bevel: 0.003)
        }
    }

    private static func fence(_ root: SCNNode, from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat),
                              iron: SCNMaterial, stone: SCNMaterial) {
        let length = hypot(b.0 - a.0, b.1 - a.1)
        let fence = SCNNode(); fence.position = SCNVector3((a.0 + b.0) / 2, 0.032, (a.1 + b.1) / 2)
        fence.eulerAngles.y = -Float(atan2(b.1 - a.1, b.0 - a.0)); root.addChildNode(fence)
        box(fence, length, 0.038, 0.035, at: (0, 0.019, 0), material: stone)
        box(fence, length, 0.010, 0.013, at: (0, 0.120, 0), material: iron, bevel: 0.002)
        let count = max(2, Int(length / 0.075))
        for i in 0...count {
            let x = -length / 2 + CGFloat(i) * length / CGFloat(count)
            box(fence, 0.008, 0.105, 0.008, at: (x, 0.079, 0), material: iron, bevel: 0.001)
        }
    }

    private static func planter(_ root: SCNNode, x: CGFloat, z: CGFloat, pot: SCNMaterial,
                                soil: SCNMaterial, leaves: SCNMaterial) {
        let shape = SCNCone(topRadius: 0.041, bottomRadius: 0.030, height: 0.065)
        shape.radialSegmentCount = 12; shape.materials = [pot]
        let node = SCNNode(geometry: shape); node.position = SCNVector3(x, 0.0645, z); root.addChildNode(node)
        cylinder(root, radius: 0.044, height: 0.012, at: (x, 0.094, z), material: pot)
        cylinder(root, radius: 0.036, height: 0.003, at: (x, 0.100, z), material: soil)
        for i in 0..<5 {
            let angle = CGFloat(i) * 2.4
            let sprig = sphere(root, radius: 0.028, at: (x + cos(angle) * 0.020, 0.144, z + sin(angle) * 0.020), material: leaves)
            sprig.scale = SCNVector3(0.60, 1.6, 0.60)
        }
    }

    private static func lantern(_ root: SCNNode, at p: (CGFloat, CGFloat, CGFloat),
                                iron: SCNMaterial, glass: SCNMaterial, brass: SCNMaterial) {
        let lamp = SCNNode(); lamp.position = SCNVector3(p.0, p.1, p.2); root.addChildNode(lamp)
        box(lamp, 0.040, 0.052, 0.036, at: (0, 0, 0), material: glass, bevel: 0.003)
        for x: CGFloat in [-0.023, 0.023] {
            for z: CGFloat in [-0.021, 0.021] {
                box(lamp, 0.005, 0.060, 0.005, at: (x, 0, z), material: iron, bevel: 0.001)
            }
        }
        box(lamp, 0.057, 0.012, 0.050, at: (0, 0.035, 0), material: iron)
        box(lamp, 0.052, 0.010, 0.047, at: (0, -0.032, 0), material: iron)
        cylinder(lamp, radius: 0.006, height: 0.017, at: (0, 0.050, 0), material: brass)
    }

    private static func menu(_ root: SCNNode, x: CGFloat, z: CGFloat, oak: SCNMaterial, board: SCNMaterial, chalk: SCNMaterial) {
        let menu = SCNNode(); menu.name = "cafeMenu"; menu.position = SCNVector3(x, 0.032, z)
        menu.eulerAngles.y = -0.22; root.addChildNode(menu)
        for side: CGFloat in [-1, 1] {
            let panel = box(menu, 0.081, 0.143, 0.011, at: (0, 0.076, side * 0.022), material: oak)
            panel.eulerAngles.x = Float(side) * 0.18
        }
        box(menu, 0.062, 0.105, 0.004, at: (0, 0.084, 0.043), material: board, bevel: 0.002)
        for (y, width) in [(0.116, 0.034), (0.087, 0.043), (0.068, 0.032)] as [(CGFloat, CGFloat)] {
            box(menu, width, 0.004, 0.002, at: (0, y, 0.046), material: chalk, bevel: 0.001)
        }
    }

    private static func cake(_ root: SCNNode, x: CGFloat, z: CGFloat, base: CGFloat, pink: Bool,
                             cream: SCNMaterial, rose: SCNMaterial, sponge: SCNMaterial) {
        cylinder(root, radius: 0.040, height: 0.004, at: (x, base, z), material: cream)
        for i in 0..<3 {
            cylinder(root, radius: 0.031, height: 0.010, at: (x, base + 0.009 + CGFloat(i) * 0.012, z),
                     material: i == 1 ? cream : sponge)
        }
        cylinder(root, radius: 0.033, height: 0.008, at: (x, base + 0.040, z), material: pink ? rose : cream)
        for dx: CGFloat in [-0.012, 0.012] {
            sphere(root, radius: 0.008, at: (x + dx, base + 0.050, z), material: rose)
        }
    }

    private static func cup(_ root: SCNNode, at p: (CGFloat, CGFloat, CGFloat), scale: Float,
                            porcelain: SCNMaterial, coffee: SCNMaterial) {
        let cup = SCNNode(); cup.position = SCNVector3(p.0, p.1, p.2); cup.scale = SCNVector3(scale, scale, scale)
        root.addChildNode(cup)
        let body = SCNCone(topRadius: 0.023, bottomRadius: 0.017, height: 0.034)
        body.radialSegmentCount = 12; body.materials = [porcelain]
        let bowl = SCNNode(geometry: body); bowl.position.y = 0.017; cup.addChildNode(bowl)
        cylinder(cup, radius: 0.019, height: 0.002, at: (0, 0.0345, 0), material: coffee)
        let loop = SCNTorus(ringRadius: 0.012, pipeRadius: 0.004)
        loop.ringSegmentCount = 12; loop.pipeSegmentCount = 5; loop.materials = [porcelain]
        let handle = SCNNode(geometry: loop); handle.eulerAngles.x = .pi / 2
        handle.position = SCNVector3(0.025, 0.018, 0); cup.addChildNode(handle)
    }

    /// Merge static opaque details by material. Keep glazing separate for
    /// transparent sorting and the existing night-lighting material updates.
    /// Entrance treads retain their identity as precise connection references.
    private static func batchStaticGeometry(in root: SCNNode) {
        let modelBounds = root.boundingBox
        var parts: [SCNNode] = []
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry,
                  node.name != "cafeDoorstep", node.name != "cafeGardenThreshold",
                  geometry.materials.allSatisfy({
                      $0.name != BuildingNightLighting.windowMaterialName && $0.transparency >= 1
                  }) else { return }
            parts.append(node)
        }
        let batch = SCNNode()
        for part in parts {
            let transform = part.convertTransform(SCNMatrix4Identity, to: root)
            part.removeFromParentNode()
            batch.addChildNode(part)
            part.transform = transform
        }
        let merged = batch.flattenedClone()
        // SceneKit resolves a flattened mesh lazily; catalogue framing reads
        // bounds before its first render, so retain the original extents.
        merged.boundingBox = batch.boundingBox
        merged.name = "cafeStaticDetails"
        root.addChildNode(merged)
        root.boundingBox = modelBounds
    }

    @discardableResult
    private static func arch(_ root: SCNNode, width: CGFloat, height: CGFloat, depth: CGFloat,
                             at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial) -> SCNNode {
        let radius = width / 2, spring = height - radius
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -radius, y: 0)); path.addLine(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: radius, y: spring))
        path.addArc(withCenter: CGPoint(x: 0, y: spring), radius: radius, startAngle: 0, endAngle: .pi, clockwise: true)
        path.close()
        path.flatness = 0.006
        let shape = SCNShape(path: path, extrusionDepth: depth); shape.materials = [material]
        let node = SCNNode(geometry: shape); node.position = SCNVector3(p.0, p.1, p.2)
        root.addChildNode(node); return node
    }

    private static func beam(_ root: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>, radius: CGFloat, material: SCNMaterial) {
        let delta = b - a
        let shape = SCNCylinder(radius: radius, height: CGFloat(simd_length(delta)))
        shape.radialSegmentCount = 6; shape.materials = [material]
        let node = SCNNode(geometry: shape); node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(delta))
        root.addChildNode(node)
    }

    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .lambert
        material.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        return material
    }

    @discardableResult
    private static func box(_ root: SCNNode, _ w: CGFloat, _ h: CGFloat, _ d: CGFloat,
                            at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial, bevel: CGFloat = 0.004) -> SCNNode {
        let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: min(bevel, min(w, h, d) / 2))
        geometry.chamferSegmentCount = 2; geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        root.addChildNode(node); return node
    }

    @discardableResult
    private static func cylinder(_ root: SCNNode, radius: CGFloat, height: CGFloat,
                                 at p: (CGFloat, CGFloat, CGFloat), material: SCNMaterial) -> SCNNode {
        let geometry = SCNCylinder(radius: radius, height: height); geometry.radialSegmentCount = 16
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        root.addChildNode(node); return node
    }

    @discardableResult
    private static func sphere(_ root: SCNNode, radius: CGFloat, at p: (CGFloat, CGFloat, CGFloat),
                               material: SCNMaterial) -> SCNNode {
        let geometry = SCNSphere(radius: radius); geometry.segmentCount = 8; geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = SCNVector3(p.0, p.1, p.2)
        root.addChildNode(node); return node
    }
}
