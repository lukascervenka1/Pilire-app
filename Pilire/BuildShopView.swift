import SwiftUI
import SceneKit

// MARK: - Offscreen 3D preview renderer (cached per building type)

@MainActor
enum BuildingPreview {
    private static var cache: [BuildingType: UIImage] = [:]

    static func image(for type: BuildingType) -> UIImage {
        if let img = cache[type] { return img }

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let model = BuildingFactory.node(for: type)
        let (minB, maxB) = model.boundingBox
        let h = CGFloat(maxB.y - minB.y)
        let w = CGFloat(maxB.x - minB.x)
        // Center on the bounding box so wide models (tavern + garden) sit mid-frame
        let cx: Float = (minB.x + maxB.x) / 2
        let cz: Float = (minB.z + maxB.z) / 2
        let cy: Float = Float(h) / 2
        model.position = SCNVector3(-cx, -cy, -cz)

        let holder = SCNNode()
        holder.addChildNode(model)
        holder.eulerAngles.y = -.pi / 5          // slight three-quarter view
        scene.rootNode.addChildNode(holder)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 950
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, -0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 620
        amb.color = UIColor(red: 0.85, green: 0.90, blue: 0.96, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(max(0.75, h * 0.62, w * 0.42))
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0.1, 10)
        scene.rootNode.addChildNode(camNode)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camNode
        let img = renderer.snapshot(atTime: 0,
                                    with: CGSize(width: 300, height: 300),
                                    antialiasingMode: .multisampling4X)
        cache[type] = img
        return img
    }
}

// MARK: - Build sheet

struct ExpansionOffer {
    let fromSize: Int
    let toSize: Int
    let costLabel: String
    let canAfford: Bool
}

struct BuildShopView: View {
    var settings: UserSettings
    var expansion: ExpansionOffer? = nil
    var onExpand: () -> Void = {}
    var onSelect: (BuildingType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmExpand = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                // Inventory header
                HStack(spacing: 10) {
                    ForEach(Material.allCases) { m in
                        MaterialChip(material: m, count: settings.count(m))
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(BuildingType.allCases, id: \.self) { type in
                        BuildCard(type: type, settings: settings) {
                            Haptics.tap()
                            onSelect(type)
                            dismiss()
                        }
                    }
                }
                .padding(16)

                // Map expansion lives here, at the end of the catalogue
                if let exp = expansion {
                    Button {
                        confirmExpand = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                                .foregroundStyle(exp.canAfford ? Color.green : Color.secondary)
                                .frame(width: 46, height: 46)
                                .background((exp.canAfford ? Color.green : Color.secondary).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(S.map.expand))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(exp.fromSize)×\(exp.fromSize) → \(exp.toSize)×\(exp.toSize) za \(exp.costLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(!exp.canAfford)
                    .opacity(exp.canAfford ? 1 : 0.55)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .confirmationDialog(L(S.map.expandQuestion), isPresented: $confirmExpand, titleVisibility: .visible) {
                        Button(L(S.map.expandFor, exp.costLabel)) {
                            onExpand()
                            dismiss()
                        }
                        Button(L(S.common.cancel), role: .cancel) {}
                    } message: {
                        Text(L(S.map.expandNote))
                    }
                }
            }
            .navigationTitle(L(S.misc.buildBuilding))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
        }
    }
}

// MARK: - Card

private struct BuildCard: View {
    let type: BuildingType
    let settings: UserSettings
    let onBuild: () -> Void

    private var affordable: Bool { settings.canAfford(type.cost) }

    var body: some View {
        Button(action: { if affordable { onBuild() } }) {
            VStack(spacing: 8) {
                Image(uiImage: BuildingPreview.image(for: type))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 96)
                    .saturation(affordable ? 1 : 0.25)
                    .opacity(affordable ? 1 : 0.55)

                Text(type.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    costPart(.wood,  type.cost.wood)
                    costPart(.brick, type.cost.brick)
                    costPart(.steel, type.cost.steel)
                }
                .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(affordable ? Color.orange.opacity(0.35) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }

    @ViewBuilder
    private func costPart(_ m: Material, _ n: Int) -> some View {
        if n > 0 {
            let enough = settings.count(m) >= n
            HStack(spacing: 2) {
                Image(systemName: m.symbolName)
                    .foregroundStyle(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b))
                Text("\(n)")
                    .fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(enough ? Color.primary : Color.red)
            }
        }
    }
}

// MARK: - Material chip (shared HUD element)

struct MaterialChip: View {
    let material: Material
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: material.symbolName)
                .font(.caption)
                .foregroundStyle(Color(red: material.tint.r, green: material.tint.g, blue: material.tint.b))
            Text("\(count)")
                .font(.caption.bold()).monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(material.displayName): \(count)")
        .resourceInfo(icon: material.symbolName,
                      tint: Color(red: material.tint.r, green: material.tint.g, blue: material.tint.b),
                      material.displayName, material.infoText)
    }
}

extension Material {
    /// Long-press explanation shown on the HUD chip.
    var infoText: String {
        switch self {
        case .wood:
            L(S.map.woodInfo)
        case .brick:
            L(S.map.brickInfo)
        case .steel:
            L(S.map.steelInfo)
        }
    }
}

// MARK: - Day close payout card

struct PayoutView: View {
    let payout: Payout
    let completedCount: Int
    var onBuild: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
                .padding(.top, 28)

            Text(L(S.map.dayClosedTitle))
                .font(.system(.title2, design: .rounded).bold())

            VStack(spacing: 10) {
                if payout.brick > 0 { payoutRow(.brick, payout.brick) }
                if payout.steel > 0 { payoutRow(.steel, payout.steel) }
                if payout.brick == 0 && payout.steel == 0 {
                    Text(L(S.map.woodAlready))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            Button {
                dismiss()
                onBuild()
            } label: {
                Label(L(S.misc.buildBuilding), systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.20), .orange],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)

            Button(L(S.common.close)) { dismiss() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .presentationDetents([.height(400)])
    }

    private func payoutRow(_ m: Material, _ n: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: m.symbolName)
                .foregroundStyle(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b))
            Text("+\(n) \(m.displayName.lowercased())")
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}
