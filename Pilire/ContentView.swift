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
    @State private var doghouseToFeed: PlacedDecoration?
    @State private var doghouseToRename: PlacedDecoration?
    @State private var kennelName = ""
    @State private var tappedAnimal: TappedAnimal?
    private let tutorial = Tutorial.shared

    struct TappedAnimal: Identifiable {
        let id = UUID()
        let node: AnimalNode
    }

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
                .onChange(of: tab) { _, newTab in
                    scene.setRendering(active: newTab == 0)
                    // Coming back to the map: re-read the clock so fires and
                    // bedtime match real time without restarting the app.
                    if newTab == 0 { scene.refreshTimeOfDay() }
                }
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
                    // Greenery snaps to the closest of 5 anchors (centre + corners)
                    scene.placingUsesAnchors = item.canUseCornerAnchor
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
            settings.registerActiveDay()
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
            }
        }
        .confirmationDialog(
            L(S.town.removeQuestion, decoToRemove?.type.displayName.lowercased() ?? ""),
            isPresented: Binding(get: { decoToRemove != nil },
                                 set: { if !$0 { decoToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button(L(S.town.removeRefund, (decoToRemove?.type.cost ?? 0) / 2), role: .destructive) {
                removeDecoration()
            }
            Button(L(S.common.cancel), role: .cancel) {}
        } message: {
            Text(L(S.town.dragToMove))
        }
        .confirmationDialog(
            tappedAnimal?.node.associatedAnimal?.displayName ?? L(S.town.animal),
            isPresented: Binding(get: { tappedAnimal != nil },
                                 set: { if !$0 { tappedAnimal = nil } }),
            titleVisibility: .visible
        ) {
            if let t = tappedAnimal {
                if t.node.isSleeping {
                    Button(L(S.town.wakeUp)) { t.node.wake(); tappedAnimal = nil }
                } else if t.node.hasKennel {
                    Button(L(S.town.sendToKennel)) { t.node.sendToKennel(); tappedAnimal = nil }
                }
                Button(L(S.town.tuckAway)) {
                    if let a = t.node.associatedAnimal { animalToTuck = a }
                    tappedAnimal = nil
                }
            }
            Button(L(S.common.cancel), role: .cancel) {}
        } message: {
            Text(L(S.town.carryHint))
        }
        .confirmationDialog(
            L(S.town.doghouse),
            isPresented: Binding(get: { doghouseToFeed != nil },
                                 set: { if !$0 { doghouseToFeed = nil } }),
            titleVisibility: .visible
        ) {
            if doghouseToFeed?.hasFood == true {
                Button(L(S.town.bowlFull)) {}.disabled(true)
            } else {
                Button(L(S.town.fillBowl, DecorationItem.dogFoodPrice)) { fillDogBowl() }
            }
            Button(L(S.town.nameKennel)) {
                kennelName = doghouseToFeed?.label ?? ""
                doghouseToRename = doghouseToFeed
                doghouseToFeed = nil
            }
            Button(L(S.town.removeKennel), role: .destructive) {
                if let dec = doghouseToFeed,
                   let node = scene.decorationNodes.first(where: { $0.associatedDecoration === dec }) {
                    doghouseToFeed = nil
                    decoToRemove = node
                }
            }
            Button(L(S.common.cancel), role: .cancel) {}
        } message: {
            Text(doghouseToFeed?.hasFood == true
                 ? L(S.town.bowlFullNote)
                 : L(S.town.kennelNote))
        }
        .alert(L(S.town.kennelNameTitle), isPresented: Binding(
            get: { doghouseToRename != nil },
            set: { if !$0 { doghouseToRename = nil } })
        ) {
            TextField(L(S.town.kennelNamePlaceholder), text: $kennelName)
            Button(L(S.common.save)) { saveKennelName() }
            Button(L(S.common.cancel), role: .cancel) { doghouseToRename = nil }
        } message: {
            Text(L(S.town.kennelNameNote))
        }
        .confirmationDialog(
            L(S.town.tuckQuestion, animalToTuck?.kind.displayName.lowercased() ?? ""),
            isPresented: Binding(get: { animalToTuck != nil },
                                 set: { if !$0 { animalToTuck = nil } }),
            titleVisibility: .visible
        ) {
            Button(L(S.town.tuckAway)) { tuckAnimal() }
            Button(L(S.common.cancel), role: .cancel) {}
        } message: {
            Text(L(S.town.tuckNote))
        }
    }

    private func saveKennelName() {
        guard let dec = doghouseToRename else { return }
        doghouseToRename = nil
        dec.label = kennelName.trimmingCharacters(in: .whitespacesAndNewlines)
        ctx.saveChanges()
        scene.decorationNodes.first { $0.associatedDecoration === dec }?.setKennelName(dec.label)
        Haptics.success()
    }

    private func fillDogBowl() {
        guard let dec = doghouseToFeed else { return }
        doghouseToFeed = nil
        guard settings.coinBalance >= DecorationItem.dogFoodPrice else { Haptics.warning(); return }
        settings.coinBalance -= DecorationItem.dogFoodPrice
        dec.hasFood = true
        ctx.saveChanges()
        scene.decorationNodes.first { $0.associatedDecoration === dec }?.setBowlFilled(true)
        Haptics.success()
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
        .accessibilityLabel(L(S.misc.coinsLabel, settings.coinBalance))
        .resourceInfo(icon: "seal.fill", tint: .yellow, L(S.common.coins),
                      L(S.town.coinsInfo))
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
        .accessibilityLabel(L(S.misc.momentumLabel, Int(settings.momentum)))
        .resourceInfo(icon: "leaf.fill", tint: .green, L(S.town.momentum),
                      L(S.town.momentumInfo))
    }

    private var shopButton: some View {
        Button { showShop = true } label: {
            Image(systemName: "storefront.fill")
                .font(.caption)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(S.shop.title))
    }

    private func loginRewardToast(_ n: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "seal.fill").foregroundStyle(.yellow)
            Text(L(S.town.visitReward, n))
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
                Text(L(S.town.tapToBuild, b.displayName)).font(.subheadline)
            } else if placingItem == .road {
                Image(systemName: "hand.draw.fill")
                Text(L(S.town.dragPath, DecorationItem.road.cost))
                    .font(.subheadline)
            } else if let item = placingItem, item.canUseCornerAnchor {
                Image(systemName: "leaf.fill")
                Text(L(S.town.tapToPlaceCorner, item.displayName))
                    .font(.subheadline)
            } else {
                Text(L(S.town.tapToPlace, placingItem?.displayName ?? "")).font(.subheadline)
            }
            Spacer()
            Button(placingItem == .road ? L(S.common.done) : L(S.common.cancel)) {
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
        scene.placingUsesAnchors = false
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
        if c.coins > 0 { return "\(c.coins) \(L(S.common.coins).lowercased())" }
        var parts: [String] = []
        if c.cost.wood > 0  { parts.append("\(c.cost.wood) \(Material.wood.displayName.lowercased())") }
        if c.cost.brick > 0 { parts.append("\(c.cost.brick) \(Material.brick.displayName.lowercased())") }
        if c.cost.steel > 0 { parts.append("\(c.cost.steel) \(Material.steel.displayName.lowercased())") }
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
            // Tapping the doghouse offers food instead of removal.
            if node.type == .doghouse, let dec = node.associatedDecoration {
                doghouseToFeed = dec
                return
            }
            decoToRemove = node
        }

        // A pet finished the bowl — clear it.
        scene.onBowlEmptied = {
            for d in decorations where d.type == .doghouse && d.hasFood {
                d.hasFood = false
                scene.decorationNodes.first { $0.associatedDecoration === d }?.setBowlFilled(false)
            }
            ctx.saveChanges()
        }

        scene.onAnimalTapped = { node in
            guard !scene.isPlacementMode else { return }
            tappedAnimal = TappedAnimal(node: node)
        }

        scene.onTileTapped = { col, row in
            guard (0..<scene.cols).contains(col), (0..<scene.rows).contains(row) else { return }

            // Building placement (Phase 1 economy)
            if let type = placingBuilding {
                let fp = type.footprint
                guard scene.cellsFree(col: col, row: row, w: fp.w, l: fp.l) else { Haptics.warning(); return }
                guard settings.pay(type.cost) else { Haptics.warning(); return }
                // A tree on a shared corner never blocks building — it makes way
                // and half its price comes back.
                clearCornerGreenery(under: type, col: col, row: row)
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

        // Small greenery: snapped either to a tile centre or a shared tile corner.
        scene.onAnchorTapped = { anchor in
            guard let item = placingItem else { return }
            // Pool items (fruit trees, bushes) roll their look once, on placement.
            let variant = Int.random(in: 0..<item.variantCount)

            // Try the tapped anchor first, then the next closest free one — so
            // tapping right beside the fire still gets the bench in nicely.
            var candidates: [TownScene.Anchor] = [anchor]
            if let g = scene.lastAnchorPoint {
                candidates += scene.anchorsByDistance(to: g)
            }

            for candidate in candidates {
                switch candidate {
                case let .corner(cx, cy):
                    guard scene.cornerFree(cx: cx, cy: cy) else { continue }
                    let dec = PlacedDecoration(type: item, gridX: cx, gridY: cy,
                                               isCornerAnchor: true, variant: variant)
                    ctx.insert(dec)
                    let node = scene.addDecoration(type: item, gridX: cx, gridY: cy,
                                                   isCornerAnchor: true, variant: variant)
                    node.associatedDecoration = dec
                case let .tile(col, row):
                    guard (0..<scene.cols).contains(col), (0..<scene.rows).contains(row),
                          scene.cellsFree(col: col, row: row) else { continue }
                    let dec = PlacedDecoration(type: item, gridX: col, gridY: row, variant: variant)
                    ctx.insert(dec)
                    let node = scene.addDecoration(type: item, gridX: col, gridY: row, variant: variant)
                    node.associatedDecoration = dec
                }
                Haptics.tap()
                endPlacement()
                return
            }
            Haptics.warning()   // everything nearby is taken
        }

        scene.onPaintCell = { col, row in
            paintRoadCell(col, row)
        }

        syncBuildings()
        syncDecorations()
        syncAnimals()
    }

    /// Remove corner greenery standing where a building is about to go up,
    /// refunding half the price so the player never loses out.
    private func clearCornerGreenery(under type: BuildingType, col: Int, row: Int) {
        let fp = type.footprint
        var doomed: [DecorationNode] = []
        for dc in 0..<fp.w {
            for dr in 0..<fp.l {
                // Neighbouring cells share corners, so skip anything already listed.
                for node in scene.cornerDecorations(around: col + dc, row: row + dr)
                where !doomed.contains(where: { $0 === node }) {
                    doomed.append(node)
                }
            }
        }
        for node in doomed {
            settings.coinBalance += node.type.cost / 2
            if let dec = node.associatedDecoration { ctx.delete(dec) }
            scene.removeDecoration(node)
        }
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
            if d.isCornerAnchor {
                guard scene.cornerFree(cx: d.gridX, cy: d.gridY) else { continue }
                let node = scene.addDecoration(type: d.type, gridX: d.gridX, gridY: d.gridY,
                                               rotation: d.rotation, isCornerAnchor: true,
                                               variant: d.variant)
                node.associatedDecoration = d
                continue
            }
            let fp = d.type.footprint
            guard scene.cellsFree(col: d.gridX, row: d.gridY, w: fp.w, l: fp.l) else { continue }
            let node = scene.addDecoration(type: d.type, gridX: d.gridX, gridY: d.gridY,
                                           rotation: d.rotation, variant: d.variant)
            node.associatedDecoration = d
            if d.type == .doghouse {
                node.setBowlFilled(d.hasFood)
                node.setKennelName(d.label)
            }
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
