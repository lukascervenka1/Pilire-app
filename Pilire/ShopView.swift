import SwiftUI
import SwiftData
import SceneKit

// MARK: - Offscreen 3D preview renderer (cached per decoration)

/// Shows the real model in the shop rather than a stand-in symbol, so what you
/// buy is exactly what you saw. Rendered once per item and cached.
@MainActor
enum DecorationPreview {
    private static var cache: [DecorationItem: UIImage] = [:]

    static func image(for item: DecorationItem) -> UIImage {
        if let img = cache[item] { return img }

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let model = DecorationFactory.node(for: item)
        // Centre on the bounding sphere: it never crops, whatever the shape.
        let (centre, radius) = model.boundingSphere
        model.position = SCNVector3(-centre.x, -centre.y, -centre.z)
        scene.rootNode.addChildNode(model)

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
        amb.intensity = 640
        amb.color = UIColor(red: 0.85, green: 0.90, blue: 0.96, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Exactly the map's camera rig, so an icon looks like the piece does in
        // the town rather than something viewed from an odd angle.
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(radius * 1.05)
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 12)
        let rig = SCNNode()
        rig.eulerAngles = SCNVector3(-0.62, Float.pi / 4, 0)
        rig.addChildNode(camNode)
        scene.rootNode.addChildNode(rig)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camNode
        let img = renderer.snapshot(atTime: 0,
                                    with: CGSize(width: 240, height: 240),
                                    antialiasingMode: .multisampling4X)
        cache[item] = img
        return img
    }
}

// MARK: - Animal thumbnails (rendered from the real rigged models)

@MainActor
enum AnimalPreview {
    private static var cache: [AnimalKind: UIImage] = [:]

    static func image(for kind: AnimalKind) async -> UIImage? {
        if let img = cache[kind] { return img }

        // The glTF loads asynchronously, so the row shows a symbol until it lands.
        let visual: SCNNode = await withCheckedContinuation { cont in
            AnimalModelLoader.loadRig(kind) { node, _ in cont.resume(returning: node) }
        }

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // Models arrive normalised (feet on y = 0, ~0.7 tiles long), so frame
        // them by hand — a skinned mesh's bounding box can't be trusted.
        visual.position.y -= 0.22
        scene.rootNode.addChildNode(visual)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 900
        sun.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.8, -0.7, 0)
        scene.rootNode.addChildNode(sunNode)

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 680
        amb.color = UIColor(red: 0.86, green: 0.90, blue: 0.96, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Same isometric rig as the map and the decoration icons.
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = 0.46
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 12)
        let rig = SCNNode()
        rig.eulerAngles = SCNVector3(-0.45, Float.pi / 4, 0)
        rig.addChildNode(camNode)
        scene.rootNode.addChildNode(rig)

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camNode
        let img = renderer.snapshot(atTime: 0,
                                    with: CGSize(width: 240, height: 240),
                                    antialiasingMode: .multisampling4X)
        cache[kind] = img
        return img
    }
}

struct AnimalThumb: View {
    let kind: AnimalKind
    let tint: Color
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(1)
            } else {
                Image(systemName: kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 48, height: 48)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.rowRadius))
        .task { image = await AnimalPreview.image(for: kind) }
    }
}

struct ShopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    var settings: UserSettings
    var onPurchase: (DecorationItem) -> Void
    var onPurchaseAnimal: (AnimalKind) -> Void = { _ in }
    var tuckedAnimals: [OwnedAnimal] = []
    var onReleaseAnimal: (OwnedAnimal) -> Void = { _ in }
    var onDeleteAnimal: (OwnedAnimal) -> Void = { _ in }

    @State private var purchased: DecorationItem?
    @State private var animalToDelete: OwnedAnimal?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(L(S.shop.balance))
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "seal.fill").foregroundStyle(.yellow)
                            Text("\(settings.coinBalance)")
                                .fontWeight(.bold).monospacedDigit()
                        }
                    }
                }

                Section(L(S.shop.exchange)) {
                    ForEach(Material.allCases) { m in
                        HStack(spacing: 14) {
                            Image(systemName: m.symbolName)
                                .font(.title3)
                                .foregroundStyle(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b))
                                .frame(width: 42, height: 42)
                                .background(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("1× \(m.displayName)").fontWeight(.semibold)
                                Text(L(S.shop.youHave, settings.count(m))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                guard settings.coinBalance >= m.coinPrice else { return }
                                settings.coinBalance -= m.coinPrice
                                settings.add(m, 1)
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(settings.coinBalance >= m.coinPrice ? .yellow : .secondary)
                                    Text("\(m.coinPrice)").fontWeight(.bold).monospacedDigit()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(settings.coinBalance >= m.coinPrice ? Color.orange : Color.secondary.opacity(0.2))
                                .foregroundStyle(settings.coinBalance >= m.coinPrice ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                                .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .disabled(settings.coinBalance < m.coinPrice)
                        }
                    }
                }

                Section(L(S.shop.decorations)) {
                    ForEach(DecorationItem.allCases, id: \.self) { item in
                        ShopRow(item: item, canAfford: settings.coinBalance >= item.cost) {
                            buy(item)
                        }
                    }
                }

                Section {
                    ForEach(AnimalKind.allCases) { kind in
                        AnimalShopRow(kind: kind, canAfford: settings.coinBalance >= kind.cost) {
                            buyAnimal(kind)
                        }
                    }
                } header: {
                    Text(L(S.shop.zoo))
                } footer: {
                    Text(L(S.shop.zooFooter))
                }

                if !tuckedAnimals.isEmpty {
                    Section {
                        ForEach(tuckedAnimals) { animal in
                            DoghouseRow(
                                animal: animal,
                                onRelease: { onReleaseAnimal(animal); Haptics.tap() },
                                onDelete: { animalToDelete = animal },
                                onNameChange: { ctx.saveChanges() }
                            )
                        }
                    } header: {
                        Text(L(S.shop.resting))
                    } footer: {
                        Text(L(S.shop.restingFooter))
                    }
                }

                Section {
                    Text(L(S.shop.placeHint))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L(S.shop.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.close)) { dismiss() }
                }
            }
            .confirmationDialog(
                L(S.shop.sayGoodbyeTo, animalToDelete?.displayName ?? ""),
                isPresented: Binding(get: { animalToDelete != nil },
                                     set: { if !$0 { animalToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button(L(S.shop.sayGoodbye), role: .destructive) {
                    if let a = animalToDelete { onDeleteAnimal(a) }
                    animalToDelete = nil
                }
                Button(L(S.common.cancel), role: .cancel) {}
            } message: {
                Text(L(S.shop.goodbyeNote))
            }
        }
    }

    private func buy(_ item: DecorationItem) {
        guard settings.coinBalance >= item.cost else { return }
        // Roads are paid per painted tile while dragging on the map,
        // everything else is charged right here.
        if item != .road {
            settings.coinBalance -= item.cost
        }
        Haptics.success()
        onPurchase(item)
        dismiss()
    }

    private func buyAnimal(_ kind: AnimalKind) {
        guard settings.coinBalance >= kind.cost else { return }
        settings.coinBalance -= kind.cost
        Haptics.success()
        onPurchaseAnimal(kind)
        dismiss()
    }
}

struct DoghouseRow: View {
    @Bindable var animal: OwnedAnimal
    let onRelease: () -> Void
    let onDelete: () -> Void
    let onNameChange: () -> Void

    @FocusState private var naming: Bool

    private var tintColor: Color {
        Color(red: animal.kind.tint.r, green: animal.kind.tint.g, blue: animal.kind.tint.b)
    }

    var body: some View {
        HStack(spacing: 12) {
            AnimalThumb(kind: animal.kind, tint: tintColor)

            VStack(alignment: .leading, spacing: 1) {
                TextField(animal.kind.displayName, text: $animal.name)
                    .focused($naming)
                    .fontWeight(.semibold)
                    .submitLabel(.done)
                    .onSubmit { onNameChange() }
                Text(animal.kind.displayName).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: onRelease) {
                Text(L(S.shop.letOut)).fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(S.shop.goodbyeLabel))
        }
        .onChange(of: naming) { _, focused in
            if !focused { onNameChange() }   // save when the field loses focus
        }
    }
}

struct AnimalShopRow: View {
    let kind: AnimalKind
    let canAfford: Bool
    let onBuy: () -> Void

    private var tintColor: Color {
        Color(red: kind.tint.r, green: kind.tint.g, blue: kind.tint.b)
    }

    var body: some View {
        HStack(spacing: 14) {
            AnimalThumb(kind: kind, tint: tintColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).fontWeight(.semibold)
                Text(kind.shopDescription).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onBuy) {
                HStack(spacing: 4) {
                    Image(systemName: "seal.fill")
                        .font(.caption)
                        .foregroundStyle(canAfford ? .yellow : .secondary)
                    Text("\(kind.cost)").fontWeight(.bold).monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(canAfford ? Color.orange : Color.secondary.opacity(0.2))
                .foregroundStyle(canAfford ? Color.white : Color.secondary)
                .clipShape(Capsule())
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }
}

struct ShopRow: View {
    let item: DecorationItem
    let canAfford: Bool
    let onBuy: () -> Void

    private var tintColor: Color {
        Color(red: item.tint.r, green: item.tint.g, blue: item.tint.b)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: DecorationPreview.image(for: item))
                .resizable()
                .scaledToFit()
                .padding(2)
                .frame(width: 48, height: 48)
                .background(tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).fontWeight(.semibold)
                Text(item.description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onBuy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "seal.fill")
                        .font(.caption)
                        .foregroundStyle(canAfford ? .yellow : .secondary)
                    Text("\(item.cost)").fontWeight(.bold).monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(canAfford ? Color.orange : Color.secondary.opacity(0.2))
                .foregroundStyle(canAfford ? Color.white : Color.secondary)
                .clipShape(Capsule())
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }
}
