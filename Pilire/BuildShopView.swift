import SwiftUI
import SceneKit

// MARK: - Offscreen 3D preview renderer (cached per building type)

@MainActor
enum BuildingPreview {
    private static var cache: [BuildingType: UIImage] = [:]
    private static var stableHorseReady = false

    /// Refresh the initially synchronous thumbnail once the bundled horse is loaded.
    static func loadStableImage(completion: @escaping (UIImage) -> Void) {
        // A thumbnail on disk is only ever written once the horse is in it.
        if !stableHorseReady, let saved = PreviewDiskCache.load("building-stables") {
            cache[.stables] = saved
            stableHorseReady = true
        }
        if stableHorseReady {
            completion(image(for: .stables))
            return
        }
        AnimalModelLoader.loadRig(.horse) { _, _ in
            if !stableHorseReady {
                cache.removeValue(forKey: .stables)
                stableHorseReady = true
            }
            completion(image(for: .stables))
        }
    }

    static func image(for type: BuildingType) -> UIImage {
        if let img = cache[type] { return img }
        let key = "building-\(type.rawValue)"
        if let saved = PreviewDiskCache.load(key) {
            cache[type] = saved
            if type == .stables { stableHorseReady = true }
            return saved
        }

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let model = BuildingFactory.node(for: type)
        let (minB, maxB) = model.boundingBox
        let h = CGFloat(maxB.y - minB.y)
        let w = CGFloat(maxB.x - minB.x)
        let depth = CGFloat(maxB.z - minB.z)
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
        // Include depth projected by the preview's yaw, especially for two-cell buildings.
        let projectedWidth = w * cos(CGFloat.pi / 5) + depth * sin(CGFloat.pi / 5)
        cam.orthographicScale = Double(max(0.75, h * 0.62, projectedWidth * 0.55))
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
        // The stables are drawn first without their horse; only the finished
        // picture is worth keeping.
        if type != .stables || stableHorseReady { PreviewDiskCache.save(img, key) }
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
    var onSelectDecoration: (DecorationItem) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmExpand = false
    @State private var shortage: CatalogShortageTarget?
    @State private var category: BuildCategory = .all

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var minimumCardWidth: CGFloat = 156
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 290 : minimumCardWidth), spacing: 12)]
    }
    private let event = SeasonalEvent.current()

    /// One card in the catalogue: a building (paid in materials) or a
    /// decoration (paid in coins).
    private enum Entry: Hashable {
        case building(BuildingType)
        case decoration(DecorationItem)
    }

    private var entries: [Entry] {
        let buildings = BuildingType.allCases.filter { $0.isForSale() }
        let decorations = DecorationItem.allCases.filter { $0.isForSale() }
        switch category {
        case .all:
            return buildings.map(Entry.building) + decorations.map(Entry.decoration)
        case .decorations:
            return decorations.map(Entry.decoration)
        case .seasonal:
            return buildings.filter { $0.event != nil }.map(Entry.building)
                 + decorations.filter { $0.event != nil }.map(Entry.decoration)
        default:
            return buildings.filter { $0.category == category }.map(Entry.building)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 0).id("catalogueTop")
                        if dynamicTypeSize >= .xxLarge { CatalogWallet(settings: settings) }
                        if category == .all || category == .seasonal {
                            if let event {
                                CatalogSeasonBanner(event: event, expanded: category == .seasonal) {
                                    selectCategory(.seasonal)
                                }
                            } else if category == .seasonal {
                                seasonEmptyState
                            }
                        }
                        if !entries.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Text(category == .all ? L(S.build.catalogueTitle) : category.title)
                                    .font(.system(.title3, design: .rounded).bold())
                                    .accessibilityAddTraits(.isHeader)
                                Spacer()
                                Text("\(entries.count)")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.creamLabel)
                                    .accessibilityLabel(L(S.build.itemCount, entries.count))
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(entries, id: \.self) { entry in
                                    switch entry {
                                    case .building(let type):
                                        BuildCard(type: type, settings: settings, onUnavailable: {
                                            Haptics.tap(); shortage = .building(type)
                                        }) {
                                            Haptics.tap(); onSelect(type); dismiss()
                                        }
                                    case .decoration(let item):
                                        DecorationCard(item: item, settings: settings, onUnavailable: {
                                            Haptics.tap(); shortage = .decoration(item)
                                        }) {
                                            Haptics.tap(); onSelectDecoration(item); dismiss()
                                        }
                                    }
                                }
                            }
                        }
                        if category == .all, let exp = expansion { expansionRow(exp) }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 20).padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: category) { _, _ in scroll.scrollTo("catalogueTop", anchor: .top) }
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 12) {
                        if dynamicTypeSize < .xxLarge { CatalogWallet(settings: settings) }
                        categoryChips
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.creamTop)
                }
            }
            .background(Theme.creamGradient)
            .navigationTitle(L(S.build.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.creamTop, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .tint(Theme.creamLabel).accessibilityLabel(L(S.common.close))
                }
            }
        }
        .sheet(item: $shortage) { target in
            CatalogShortageSheet(target: target, settings: settings)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
    }

    private func selectCategory(_ value: BuildCategory) {
        Haptics.tap()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { category = value }
    }

    @ViewBuilder private var categoryChips: some View {
        if dynamicTypeSize.isAccessibilitySize {
            categoryMenu
        } else {
            HStack(spacing: 8) {
                ScrollViewReader { tabs in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BuildCategory.allCases) { c in
                                Button { selectCategory(c) } label: {
                                    Label(c.title, systemImage: c.symbolName)
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 14).frame(minHeight: 44)
                                        .foregroundStyle(category == c ? Color.white : Theme.creamLabel)
                                        .background(category == c ? CatalogStyle.ink : Color.white.opacity(0.65), in: Capsule())
                                }
                                .buttonStyle(CatalogPressStyle()).id(c)
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                            }
                        }
                    }
                    .onAppear { tabs.scrollTo(category, anchor: .center) }
                    .onChange(of: category) { _, value in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { tabs.scrollTo(value, anchor: .center) }
                    }
                }
                categoryMenu
            }
        }
    }

    private var categoryMenu: some View {
        Menu {
            Picker(L(S.build.categories), selection: $category) {
                ForEach(BuildCategory.allCases) { c in
                    Label(c.title, systemImage: c.symbolName).tag(c)
                }
            }
        } label: {
            HStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(category.title).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, dynamicTypeSize.isAccessibilitySize ? 14 : 0)
            .foregroundStyle(CatalogStyle.ink)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
        }
        .accessibilityLabel(L(S.build.categories))
        .accessibilityValue(category.title)
    }

    private var seasonEmptyState: some View {
        let next = SeasonalEvent.upcoming()
        let style = Date.FormatStyle.dateTime.day().month(.wide).locale(Language.shared.current.locale)
        return VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "calendar").font(.largeTitle).foregroundStyle(Theme.creamLabel)
            Text(L(S.build.seasonNone)).font(.headline)
            Text(L(S.build.seasonNext, next.event.title, next.start.formatted(style)))
                .foregroundStyle(Theme.creamLabel)
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func expansionRow(_ exp: ExpansionOffer) -> some View {
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
                    Text(L(S.build.expandRow,
                           "\(exp.fromSize)×\(exp.fromSize) → \(exp.toSize)×\(exp.toSize)", exp.costLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .disabled(!exp.canAfford)
        .opacity(exp.canAfford ? 1 : 0.55)
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

// MARK: - Decoration card (same shape as a building card, priced in coins)

private struct DecorationCard: View {
    let item: DecorationItem
    let settings: UserSettings
    let onUnavailable: () -> Void
    let onBuy: () -> Void
    private var affordable: Bool { settings.coinBalance >= item.cost }

    var body: some View {
        Button(action: { if affordable { onBuy() } else { onUnavailable() } }) {
            CatalogProductCard(name: item.displayName, subtitle: L(S.shop.decorations),
                               image: DecorationPreview.image(for: item), event: item.event,
                               affordable: affordable, action: L(S.build.place),
                               unavailable: L(S.build.needCoins)) {
                CatalogPrice(symbol: "seal.fill", color: CatalogStyle.coin, amount: item.cost,
                             enough: affordable, label: L(S.common.coins))
            }
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityHint(affordable ? "" : L(S.build.shortageHint))
        .accessibilityElement(children: .combine)
    }
}

struct CoinChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "seal.fill").font(.caption).foregroundStyle(.yellow)
            Text("\(count)")
                .font(.caption.bold()).monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(S.common.coins)): \(count)")
    }
}

// MARK: - Card

private struct BuildCard: View {
    let type: BuildingType
    let settings: UserSettings
    let onUnavailable: () -> Void
    let onBuild: () -> Void
    @State private var loadedPreview: UIImage?
    private var affordable: Bool { settings.canAfford(type.cost) }

    var body: some View {
        Button(action: { if affordable { onBuild() } else { onUnavailable() } }) {
            CatalogProductCard(name: type.displayName,
                               subtitle: "\(type.footprint.w) × \(type.footprint.l) · \(type.category.title)",
                               image: loadedPreview ?? BuildingPreview.image(for: type), event: type.event,
                               affordable: affordable, action: L(S.build.build),
                               unavailable: L(S.build.needMaterials)) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { costs }
                    VStack(alignment: .leading, spacing: 5) { costs }
                }
            }
        }
        .buttonStyle(CatalogPressStyle())
        .accessibilityHint(affordable ? "" : L(S.build.shortageHint))
        .accessibilityElement(children: .combine)
        .onAppear {
            guard type == .stables else { return }
            BuildingPreview.loadStableImage { loadedPreview = $0 }
        }
    }

    @ViewBuilder private var costs: some View {
        costPart(.wood, type.cost.wood)
        costPart(.brick, type.cost.brick)
        costPart(.steel, type.cost.steel)
    }

    @ViewBuilder private func costPart(_ m: Material, _ n: Int) -> some View {
        if n > 0 {
            CatalogPrice(symbol: m.symbolName, color: Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b),
                         amount: n, enough: settings.count(m) >= n, label: m.displayName)
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
            Text("+" + m.amount(n))
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}
