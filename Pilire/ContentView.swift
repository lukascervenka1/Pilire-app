import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Building.builtDate)              private var buildings:    [Building]
    @Query(sort: \DayRecord.date, order: .reverse) private var dayRecords:   [DayRecord]
    @Query(sort: \PlacedDecoration.placedDate)     private var decorations:  [PlacedDecoration]
    @Query(sort: \OwnedAnimal.boughtDate)          private var animals:      [OwnedAnimal]
    @Query                                         private var settingsAll:  [UserSettings]

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("devModeEnabled")    private var devModeEnabled    = false

    @State private var tab         = 0
    @State private var scene       = TownScene()
    @State private var sceneReady  = false
    @State private var tappedBuilding: TappedBuilding?
    @State private var showShop    = false
    @State private var showBuild   = false
    @State private var placingItem: DecorationItem?
    @State private var placingBuilding: BuildingType?
    @State private var payout: PayoutPresentation?
    @State private var loginToast: Int?
    @State private var showOnboarding = false
    @State private var decoToRemove: DecorationNode?
    @State private var animalToTuck: OwnedAnimal?
    private let tutorial = Tutorial.shared

    /// Returns the stored settings, or a transient fallback for the brief first
    /// frame before `ensureSettings()` inserts the real one. Never mutates the
    /// context during view rendering (that ran on every body evaluation before).
    private var settings: UserSettings {
        settingsAll.first ?? UserSettings()
    }

    /// Creates the singleton settings row once — called from a lifecycle
    /// callback (`.onAppear`), not from a computed property read during `body`.
    private func ensureSettings() {
        guard settingsAll.isEmpty else { return }
        ctx.insert(UserSettings())
        ctx.saveChanges()
    }

    var body: some View {
        TabView(selection: $tab) {
            mapView
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
                .onChange(of: tab) { _, newTab in scene.setRendering(active: newTab == 0) }
            DailyView(settings: settings, onDayCompleted: dayCompleted)
                .toolbar(.hidden, for: .tabBar)
                .tag(1)
            CalendarView()
                .toolbar(.hidden, for: .tabBar)
                .tag(2)
            ChronicleView()
                .toolbar(.hidden, for: .tabBar)
                .tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GameTabBar(selection: $tab, pulseBuild: tutorial.current == .build) {
                tab = 0
                showBuild = true
            }
        }
        .overlay(alignment: .bottom) {
            if let step = tutorial.current {
                TutorialBanner(
                    step: step,
                    currentTab: tab,
                    onGoToTasks: { tab = 1 },
                    onSkip: { withAnimation { Tutorial.shared.skip() } }
                )
                .padding(.bottom, 92)
                .animation(.spring(response: 0.4), value: tutorial.step)
            }
        }
        .sheet(item: $tappedBuilding) { tb in
            BuildingDetailSheet(
                node: tb.node,
                dayRecord: tb.dayRecord,
                onRotate: { scene.tryRotate(tb.node) },
                onDemolish: { demolish(tb.node) }
            )
        }
        .sheet(isPresented: $showShop) {
            ShopView(
                settings: settings,
                onPurchase: { item in
                    placingItem = item
                    scene.isPlacementMode = true
                    scene.isRoadPaintMode = (item == .road)   // roads paint by dragging
                    tab = 0
                },
                onPurchaseAnimal: { kind in
                    // Insert only — syncAnimals owns node creation, so there's
                    // exactly one roaming node per owned animal.
                    ctx.insert(OwnedAnimal(kind: kind))
                    ctx.saveChanges()
                    tab = 0
                },
                tuckedAnimals: animals.filter(\.isTucked),
                onReleaseAnimal: { animal in
                    animal.isTucked = false
                    ctx.saveChanges()
                    syncAnimals()
                },
                onDeleteAnimal: { animal in
                    if let node = scene.animalNodes.first(where: { $0.associatedAnimal === animal }) {
                        scene.removeAnimal(node)
                    }
                    ctx.delete(animal)
                    ctx.saveChanges()
                }
            )
        }
        .sheet(isPresented: $showBuild) {
            BuildShopView(
                settings: settings,
                expansion: settings.mapTier < 3 ? ExpansionOffer(
                    fromSize: scene.cols,
                    toSize: scene.cols + 4,
                    costLabel: expansionCostLabel,
                    canAfford: canAffordExpansion
                ) : nil,
                onExpand: { expandMap() },
                onSelect: { type in
                    placingBuilding = type
                    scene.isPlacementMode = true
                    tab = 0
                }
            )
        }
        .sheet(item: $payout) { p in
            PayoutView(payout: p.payout, completedCount: p.completedCount) {
                tab = 0
                showBuild = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
                Tutorial.shared.start()
                // Welcome gift: material for the first building and enough coins
                // for a few trees and a stretch of road.
                if Tutorial.shared.isActive {
                    settings.add(.wood, 12)
                    settings.add(.brick, 4)
                    settings.coinBalance += 300
                }
            }
        }
        .onAppear {
            ensureSettings()   // create the settings row here, not during body render
            if !hasSeenOnboarding {
                // Wait for the splash to fade before presenting the tutorial
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { showOnboarding = true }
            }
            settings.reconcileMomentum()
            if let reward = settings.claimLoginRewardIfNeeded() {
                withAnimation(.spring(response: 0.35)) { loginToast = reward }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation { loginToast = nil }
                }
            }
        }
    }

    // MARK: - Map tab

    private var mapView: some View {
        ZStack {
            TownSceneView(scene: scene)
                .background(
                    LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                )
                .ignoresSafeArea()
                .onAppear(perform: configureScene)
                .onChange(of: buildings)   { _, _ in syncBuildings() }
                .onChange(of: decorations) { _, _ in syncDecorations() }
                .onChange(of: animals)     { _, _ in syncAnimals() }

            VStack {
                // Top HUD — everything on one line. Uses .regularMaterial (not
                // glass): tighter, cheaper over the live 3D scene, and it adapts
                // to light/dark automatically.
                HStack(spacing: 6) {
                    coinBadge
                    ForEach(Material.allCases) { m in
                        MaterialChip(material: m, count: settings.count(m))
                    }
                    Spacer(minLength: 4)
                    momentumBadge
                    shopButton
                }
                .padding(.horizontal, 12).padding(.top, 8)

                if let reward = loginToast { loginRewardToast(reward) }
                if placingItem != nil || placingBuilding != nil { placementBanner }
                Spacer()

                #if DEBUG
                if devModeEnabled { devPanel }
                #endif
            }
        }
        .confirmationDialog(
            "Odstranit \(decoToRemove?.type.displayName.lowercased() ?? "")?",
            isPresented: Binding(get: { decoToRemove != nil },
                                 set: { if !$0 { decoToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Odstranit (+\((decoToRemove?.type.cost ?? 0) / 2) mincí zpět)", role: .destructive) {
                removeDecoration()
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Přesunout ji můžeš i podržením a tažením.")
        }
        .confirmationDialog(
            "Uklidit \(animalToTuck?.kind.displayName.lowercased() ?? "") do boudy?",
            isPresented: Binding(get: { animalToTuck != nil },
                                 set: { if !$0 { animalToTuck = nil } }),
            titleVisibility: .visible
        ) {
            Button("Uklidit do boudy") { tuckAnimal() }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Odpočine si v boudě. Kdykoli ho zase pustíš ven z obchodu, ze sekce Bouda.")
        }
    }

    private func tuckAnimal() {
        guard let animal = animalToTuck else { return }
        animalToTuck = nil
        animal.isTucked = true
        ctx.saveChanges()
        Haptics.tap()
        syncAnimals()
    }

    /// Sky gradient driven by real time of day and today's weather.
    private var skyColors: [Color] {
        if scene.weather == .fog {
            return [Color(red: 0.80, green: 0.84, blue: 0.84),
                    Color(red: 0.87, green: 0.90, blue: 0.88)]
        }
        let base: [Color]
        switch scene.daylight {
        case .dawn:
            base = [Color(red: 0.78, green: 0.72, blue: 0.86),
                    Color(red: 0.96, green: 0.80, blue: 0.72),
                    Color(red: 0.98, green: 0.90, blue: 0.80)]
        case .day:
            base = [Color(red: 0.66, green: 0.83, blue: 0.93),
                    Color(red: 0.82, green: 0.91, blue: 0.90),
                    Color(red: 0.93, green: 0.95, blue: 0.88)]
        case .dusk:
            base = [Color(red: 0.46, green: 0.42, blue: 0.66),
                    Color(red: 0.90, green: 0.62, blue: 0.48),
                    Color(red: 0.97, green: 0.82, blue: 0.62)]
        case .night:
            base = [Color(red: 0.10, green: 0.13, blue: 0.26),
                    Color(red: 0.16, green: 0.22, blue: 0.38),
                    Color(red: 0.24, green: 0.32, blue: 0.44)]
        }
        if scene.weather == .rain {
            return base.map { $0.opacity(0.85) }
        }
        return base
    }

    // MARK: - HUD elements

    private var coinBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "seal.fill").foregroundStyle(.yellow)
                .symbolEffect(.bounce, value: settings.coinBalance)
            Text("\(settings.coinBalance)")
                .fontWeight(.bold).monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mince: \(settings.coinBalance)")
        .resourceInfo(icon: "seal.fill", tint: .yellow, "Mince",
                      "Dostaneš je za první otevření aplikace v den. Utratíš je v obchodě za dekorace, směnu materiálu a rozšíření mapy.")
    }

    private var momentumBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill").foregroundStyle(.green)
                .symbolEffect(.bounce, value: Int(settings.momentum))
            Text("\(Int(settings.momentum))")
                .fontWeight(.bold).monospacedDigit()
        }
        .font(.caption)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Momentum: \(Int(settings.momentum)) ze sta")
        .resourceInfo(icon: "leaf.fill", tint: .green, "Momentum",
                      "Roste o 12 za každý uzavřený den a pomalu klesá, když vynecháš. Násobí odměny z pilířů až na dvojnásobek a nikdy tě netrestá.")
    }

    private var shopButton: some View {
        Button { showShop = true } label: {
            Image(systemName: "storefront.fill")
                .font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Obchod")
    }

    private func loginRewardToast(_ n: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "seal.fill").foregroundStyle(.yellow)
            Text("+\(n) za dnešní návštěvu")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var placementBanner: some View {
        HStack(spacing: 10) {
            if let b = placingBuilding {
                Image(systemName: "hammer.fill")
                Text("Ťukni kam postavit: \(b.displayName)").font(.subheadline)
            } else if placingItem == .road {
                Image(systemName: "hand.draw.fill")
                Text("Táhni prstem a stav cestu (\(DecorationItem.road.cost) mincí za políčko)")
                    .font(.subheadline)
            } else {
                Text("Ťukni kam umístit: \(placingItem?.displayName ?? "")").font(.subheadline)
            }
            Spacer()
            Button(placingItem == .road ? "Hotovo" : "Zrušit") {
                endPlacement()
            }
            .font(.subheadline.bold())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.orange.opacity(0.92), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.top, 4)
    }

    private func endPlacement() {
        placingItem = nil
        placingBuilding = nil
        scene.isPlacementMode = false
        scene.isRoadPaintMode = false
    }

    /// One road tile painted (drag or tap). Charges coins per tile and keeps
    /// the paint mode running so long paths cost one gesture, not many taps.
    private func paintRoadCell(_ col: Int, _ row: Int) {
        guard placingItem == .road else { return }
        guard scene.cellsFree(col: col, row: row) else { return }
        guard settings.coinBalance >= DecorationItem.road.cost else {
            Haptics.warning()
            return
        }
        settings.coinBalance -= DecorationItem.road.cost
        let dec = PlacedDecoration(type: .road, gridX: col, gridY: row)
        ctx.insert(dec)
        let node = scene.addDecoration(type: .road, gridX: col, gridY: row)
        node.associatedDecoration = dec
        Haptics.tap()
    }

    // MARK: - Expansion

    private var canAffordExpansion: Bool {
        let c = expansionCost
        return c.coins > 0 ? settings.coinBalance >= c.coins : settings.canAfford(c.cost)
    }

    private var expansionCost: (coins: Int, cost: MaterialCost) {
        switch settings.mapTier {
        case 0:  (300, MaterialCost())
        case 1:  (0, MaterialCost(wood: 20, brick: 15))
        default: (0, MaterialCost(wood: 30, brick: 25, steel: 10))
        }
    }

    private var expansionCostLabel: String {
        let c = expansionCost
        if c.coins > 0 { return "\(c.coins) mincí" }
        var parts: [String] = []
        if c.cost.wood > 0  { parts.append("\(c.cost.wood) dřeva") }
        if c.cost.brick > 0 { parts.append("\(c.cost.brick) cihel") }
        if c.cost.steel > 0 { parts.append("\(c.cost.steel) oceli") }
        return parts.joined(separator: ", ")
    }

    private func expandMap() {
        let c = expansionCost
        if c.coins > 0 {
            guard settings.coinBalance >= c.coins else { Haptics.warning(); return }
            settings.coinBalance -= c.coins
        } else {
            guard settings.pay(c.cost) else { Haptics.warning(); return }
        }
        let shift = 2
        for b in buildings   { b.gridX += shift; b.gridY += shift }
        for d in decorations { d.gridX += shift; d.gridY += shift }
        settings.mapTier += 1
        scene.expand(toCols: TownScene.mapSize(forTier: settings.mapTier))
    }

    // MARK: - Scene setup

    private func configureScene() {
        guard !sceneReady else { return }
        sceneReady = true

        scene.setMapSize(TownScene.mapSize(forTier: settings.mapTier))

        scene.onBuildingTapped = { node in
            guard !scene.isPlacementMode else { return }
            tappedBuilding = TappedBuilding(node: node, dayRecord: node.associatedBuilding?.dayRecord)
        }

        scene.onDecorationTapped = { node in
            guard !scene.isPlacementMode else { return }
            decoToRemove = node
        }

        scene.onAnimalHeld = { node in
            guard !scene.isPlacementMode else { return }
            if let animal = node.associatedAnimal { animalToTuck = animal }
        }

        scene.onTileTapped = { col, row in
            guard (0..<scene.cols).contains(col), (0..<scene.rows).contains(row) else { return }

            // Building placement (Phase 1 economy)
            if let type = placingBuilding {
                let fp = type.footprint
                guard scene.cellsFree(col: col, row: row, w: fp.w, l: fp.l) else { Haptics.warning(); return }
                guard settings.pay(type.cost) else { Haptics.warning(); return }
                let b = Building(type: type, gridX: col, gridY: row)
                if let today = todayRecord() { b.dayRecord = today }
                ctx.insert(b)
                let node = scene.addBuilding(type: type, gridX: col, gridY: row, animated: true)
                node.associatedBuilding = b
                placingBuilding = nil
                scene.isPlacementMode = false
                Haptics.success()
                withAnimation { Tutorial.shared.advance(from: .build) }
                return
            }

            // Roads paint per tile and stay in placement mode for long paths
            if placingItem == .road {
                paintRoadCell(col, row)
                return
            }

            // Decoration placement (footprint-aware — pond spans 2 cells)
            guard let item = placingItem else { return }
            let fp = item.footprint
            guard scene.cellsFree(col: col, row: row, w: fp.w, l: fp.l) else { Haptics.warning(); return }
            let dec = PlacedDecoration(type: item, gridX: col, gridY: row)
            ctx.insert(dec)
            let node = scene.addDecoration(type: item, gridX: col, gridY: row)
            node.associatedDecoration = dec
            placingItem = nil
            scene.isPlacementMode = false
        }

        scene.onPaintCell = { col, row in
            paintRoadCell(col, row)
        }

        syncBuildings()
        syncDecorations()
        syncAnimals()
    }

    private func syncAnimals() {
        // Remove nodes whose animal was tucked away or deleted.
        for node in scene.animalNodes {
            let stillActive = animals.contains { $0 === node.associatedAnimal && !$0.isTucked }
            if !stillActive { scene.removeAnimal(node) }
        }
        // Spawn a node for every active animal that doesn't have one yet.
        for a in animals where !a.isTucked {
            guard !scene.animalNodes.contains(where: { $0.associatedAnimal === a }) else { continue }
            let node = scene.addAnimal(kind: a.kind)
            node.associatedAnimal = a
        }
    }

    private func todayRecord() -> DayRecord? {
        dayRecords.first { Calendar.current.isDate($0.date, inSameDayAs: .now) }
    }

    private func syncBuildings() {
        for b in buildings {
            guard !scene.buildingNodes.contains(where: { $0.associatedBuilding === b }) else { continue }
            // Legacy data: relocate a building that no longer fits (out of
            // bounds, or a footprint that grew, like the tavern's beer garden).
            // Relocation resets rotation so the rectangular search is valid.
            let fp = b.type.footprint
            let offsets = BuildingNode.occupiedOffsets(footprint: fp, steps: b.rotation)
            if !scene.canPlace(offsets: offsets, at: b.gridX, row: b.gridY) {
                b.rotation = 0
                let cell = scene.nextFreeCell(w: fp.w, l: fp.l)
                b.gridX = cell.col
                b.gridY = cell.row
            }
            let node = scene.addBuilding(type: b.type, gridX: b.gridX, gridY: b.gridY,
                                         isComplete: b.isComplete, rotation: b.rotation,
                                         style: BuildingStyle(roof: b.roofColorIndex, facade: b.facadeIndex))
            node.associatedBuilding = b
        }
    }

    private func syncDecorations() {
        for d in decorations {
            guard !scene.decorationNodes.contains(where: { $0.associatedDecoration === d }) else { continue }
            let fp = d.type.footprint
            guard scene.cellsFree(col: d.gridX, row: d.gridY, w: fp.w, l: fp.l) else { continue }
            let node = scene.addDecoration(type: d.type, gridX: d.gridX, gridY: d.gridY, rotation: d.rotation)
            node.associatedDecoration = d
        }
    }

    // MARK: - Removal (buildings & decorations)

    private func removeDecoration() {
        guard let node = decoToRemove else { return }
        decoToRemove = nil
        settings.coinBalance += node.type.cost / 2
        if let model = node.associatedDecoration { ctx.delete(model) }
        scene.removeDecoration(node)
        Haptics.drop()
    }

    private func demolish(_ node: BuildingNode) {
        if let b = node.associatedBuilding {
            let c = node.type.cost
            settings.add(.wood,  c.wood / 2)
            settings.add(.brick, c.brick / 2)
            settings.add(.steel, c.steel / 2)
            ctx.delete(b)
        }
        scene.removeBuilding(node)
        Haptics.drop()
    }

    // MARK: - Day completion → payout (no auto-building anymore)

    private func dayCompleted(_ record: DayRecord) {
        let count = record.completedCount
        guard count > 0 else { return }

        let p = settings.processDayClose(completedPillars: count, totalPillars: record.pillars.count)
        Haptics.success()
        payout = PayoutPresentation(payout: p, completedCount: count)
    }


    // MARK: - DEBUG dev panel

    #if DEBUG
    @State private var devTypeIdx = 0
    private let devTypes = BuildingType.allCases

    private var devPanel: some View {
        HStack(spacing: 10) {
            Button {
                settings.coinBalance += 999
                settings.add(.wood, 99); settings.add(.brick, 99); settings.add(.steel, 99)
            } label: {
                Label("+zdroje", systemImage: "wand.and.stars")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            Button {
                let type = devTypes[devTypeIdx % devTypes.count]
                devTypeIdx += 1
                let cell = scene.nextFreeCell(w: type.footprint.w, l: type.footprint.l)
                let b = Building(type: type, gridX: cell.col, gridY: cell.row)
                ctx.insert(b)
                let node = scene.addBuilding(type: type, gridX: cell.col, gridY: cell.row, animated: true)
                node.associatedBuilding = b
            } label: {
                Text("+\(devTypes[devTypeIdx % devTypes.count].displayName)")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
        }
        .padding(.bottom, 6)
    }
    #endif
}

struct TappedBuilding: Identifiable {
    let id = UUID()
    let node: BuildingNode
    let dayRecord: DayRecord?
}

struct PayoutPresentation: Identifiable {
    let id = UUID()
    let payout: Payout
    let completedCount: Int
}
