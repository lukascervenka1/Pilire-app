import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    @Query(sort: \Building.builtDate)              private var buildings:    [Building]
    @Query(sort: \DayRecord.date, order: .reverse) private var dayRecords:   [DayRecord]
    @Query(sort: \PlacedDecoration.placedDate)     private var decorations:  [PlacedDecoration]
    @Query(sort: \OwnedAnimal.boughtDate)          private var animals:      [OwnedAnimal]
    @Query(sort: \Habit.createdDate)               private var habits:       [Habit]
    @Query                                         private var settingsAll:  [UserSettings]

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("achievementsSeeded") private var achievementsSeeded = false

    @State private var tab         = 0
    @State private var scene       = TownScene()
    @State private var sceneReady  = false
    @State private var tappedBuilding: TappedBuilding?
    @State private var showInventory = false
    @State private var showBuild   = false
    @State private var placingItem: DecorationItem?
    @State private var placingBuilding: BuildingType?
    /// Set when the piece being placed comes out of the inventory: it lands for
    /// free and keeps its record (and with it its history and name).
    @State private var placingStoredBuilding: Building?
    @State private var placingStoredDecoration: PlacedDecoration?
    @State private var storedToast = false
    /// The tab bar sits on the bottom safe area, so it rides up with the
    /// keyboard and lands right on top of the field you're typing into. It
    /// steps aside while the keyboard is out.
    @State private var keyboardVisible = false
    @State private var payout: PayoutPresentation?
    @State private var loginToast: Int?
    @State private var showOnboarding = false
    @State private var showReleaseNotes = false
    @State private var decoToRemove: DecorationNode?
    @State private var animalToTuck: OwnedAnimal?
    @State private var doghouseToFeed: PlacedDecoration?
    @State private var feedingSaveError = false
    @State private var doghouseToRename: PlacedDecoration?
    @State private var kennelName = ""
    @State private var tappedAnimal: TappedAnimal?
    @State private var unlockQueue: [Achievement] = []
    @State private var dailyRefreshID = UUID()
    @State private var bootstrappedSettings: UserSettings?
    private let tutorial = Tutorial.shared

    struct TappedAnimal: Identifiable {
        let id = UUID()
        let node: AnimalNode
    }

    /// Returns the stored settings, or a transient fallback for the brief first
    /// frame before `ensureSettings()` inserts the real one. Never mutates the
    /// context during view rendering (that ran on every body evaluation before).
    private var settings: UserSettings {
        settingsAll.first ?? bootstrappedSettings ?? UserSettings()
    }

    /// Creates the singleton settings row once — called from a lifecycle
    /// callback (`.onAppear`), not from a computed property read during `body`.
    @discardableResult
    private func ensureSettings() -> UserSettings {
        if let stored = settingsAll.first {
            bootstrappedSettings = stored
            return stored
        }
        if let bootstrappedSettings { return bootstrappedSettings }
        let created = UserSettings()
        ctx.insert(created)
        bootstrappedSettings = created
        ctx.saveChanges()
        return created
    }

    var body: some View {
        TabView(selection: $tab) {
            mapView
                .toolbar(.hidden, for: .tabBar)
                .tag(0)
                .onChange(of: tab) { _, newTab in
                    scene.setRendering(active: scenePhase == .active && newTab == 0)
                    // Coming back to the map: re-read the clock so fires and
                    // bedtime match real time without restarting the app.
                    if newTab == 0 { scene.refreshTimeOfDay() }
                }
            DailyView(settings: settings,
                      onDayCompleted: dayCompleted,
                      onPillarCompleted: checkAchievements)
                .id(dailyRefreshID)
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
            if !keyboardVisible {
                GameTabBar(selection: $tab, pulseBuild: tutorial.current == .build) {
                    tab = 0
                    showBuild = true
                }
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardVisible = false }
        }
        .overlay(alignment: .bottom) {
            if let step = tutorial.current, !keyboardVisible {
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
        // After an update: once badges have had their moment.
        .overlay {
            if showReleaseNotes, unlockQueue.isEmpty, !showOnboarding {
                ReleaseNotesOverlay {
                    ReleaseNotes.markSeen()
                    withAnimation(.easeOut(duration: 0.2)) { showReleaseNotes = false }
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if let next = unlockQueue.first {
                AchievementUnlockedOverlay(achievement: next) {
                    withAnimation(.easeOut(duration: 0.25)) { _ = unlockQueue.removeFirst() }
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $tappedBuilding) { tb in
            BuildingDetailSheet(
                node: tb.node,
                dayRecord: tb.dayRecord,
                onRotate: { scene.tryRotate(tb.node) },
                onStore: { store(tb.node) }
            )
        }
        .sheet(isPresented: $showInventory) {
            InventoryView(
                buildings: buildings.filter(\.isStored),
                decorations: decorations.filter(\.isStored),
                animals: animals.filter(\.isTucked),
                onPlaceBuilding: { b in
                    placingStoredBuilding = b
                    placingBuilding = b.type
                    scene.isPlacementMode = true
                    tab = 0
                },
                onPlaceDecoration: { d in
                    // Roads paint by dragging and use up stored tiles first.
                    if d.type != .road { placingStoredDecoration = d }
                    beginPlacement(d.type)
                },
                onSellBuilding: sell,
                onSellDecoration: sell,
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
                },
                onRenameAnimal: { ctx.saveChanges() }
            ) {
                ShopView(
                    settings: settings,
                    onPurchase: { item in
                        showInventory = false
                        beginPlacement(item)
                    },
                    onPurchaseAnimal: { kind in
                        // Insert only — syncAnimals owns node creation, so there's
                        // exactly one roaming node per owned animal.
                        ctx.insert(OwnedAnimal(kind: kind))
                        ctx.saveChanges()
                        showInventory = false
                        tab = 0
                    }
                )
            }
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
                },
                onSelectDecoration: { item in beginPlacement(item) },
                onAdoptAnimal: { kind in
                    // Insert only — syncAnimals owns node creation, as with the shop.
                    ctx.insert(OwnedAnimal(kind: kind))
                    ctx.saveChanges()
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
                // A new player meets everything through the tutorial instead.
                ReleaseNotes.markSeen()
                // Now that they've seen what the app is for, the reminder
                // prompt has some context to stand on.
                NotificationManager.requestPermission()
                NotificationManager.scheduleDailyReminders()
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
            activateForCurrentDay()
            // Onboarding waits until a language is picked, so the two full-screen
            // presentations can never collide on a fresh install.
            if !hasSeenOnboarding, Language.shared.hasChosen {
                // Wait for the splash to fade before presenting the tutorial
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { showOnboarding = true }
            } else if ReleaseNotes.shouldShow(hasSeenOnboarding: hasSeenOnboarding) {
                // Same wait as onboarding, so the splash has faded first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                    withAnimation(.easeOut(duration: 0.25)) { showReleaseNotes = true }
                }
            }
            checkAchievements()
        }
        .onChange(of: scenePhase) { _, phase in
            updateAmbience()
            guard phase == .active else { return }
            activateForCurrentDay(refreshDailyView: true)
            scene.refreshTimeOfDay()
        }
        .onChange(of: reduceMotion) { _, _ in scene.refreshWeatherAccessibility() }
        .onChange(of: dimFlashingLights) { _, _ in scene.refreshWeatherAccessibility() }
        // Ambience belongs to the town: it fades in on the map and out elsewhere.
        .onChange(of: tab) { _, _ in updateAmbience() }
        .onChange(of: hasSeenOnboarding) { _, seen in
            guard !seen, Language.shared.hasChosen else { return }
            showOnboarding = true
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
                .onChange(of: buildings)   { _, _ in checkAchievements() }
                .onChange(of: decorations) { _, _ in checkAchievements() }
                .onChange(of: animals)     { _, _ in checkAchievements() }
                .onChange(of: habits)      { _, _ in checkAchievements() }

            VStack {
                // One calm surface keeps every resource readable over clouds,
                // weather and buildings without a row of competing capsules.
                HStack(spacing: 0) {
                    hudValue(icon: "seal.fill", tint: .yellow,
                             count: settings.coinBalance,
                             title: L(S.common.coins), info: L(S.town.coinsInfo))
                    hudDivider
                    ForEach(Material.allCases) { m in
                        hudValue(icon: m.symbolName,
                                 tint: Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b),
                                 count: settings.count(m),
                                 title: m.displayName, info: m.infoText)
                        hudDivider
                    }
                    hudValue(icon: "leaf.fill", tint: .green,
                             count: Int(settings.momentum),
                             title: L(S.town.momentum), info: L(S.town.momentumInfo))
                    hudDivider
                    inventoryButton
                }
                .padding(.horizontal, 7).padding(.vertical, 6)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.62), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
                .padding(.horizontal, 12).padding(.top, 8)

                if let reward = loginToast { loginRewardToast(reward) }
                if storedToast { storedAwayToast }
                if placingItem != nil || placingBuilding != nil { placementBanner }
                Spacer()
            }
        }
        .confirmationDialog(
            decoToRemove?.type.displayName ?? "",
            isPresented: Binding(get: { decoToRemove != nil },
                                 set: { if !$0 { decoToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button(L(S.town.storeAway)) { storeDecoration() }
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
                if t.node.kind.usesDoghouse, !t.node.isSleeping {
                    Button(L(S.town.pet)) { t.node.pet(); tappedAnimal = nil }
                }
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
            Button(L(S.town.storeAway)) {
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
        .alert(L(S.town.doghouse), isPresented: $feedingSaveError) {
            Button(L(S.common.close), role: .cancel) { }
        } message: {
            Text(L(S.town.foodSaveError))
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
        guard !dec.hasFood else { return }
        guard settings.coinBalance >= DecorationItem.dogFoodPrice else { Haptics.warning(); return }
        let previousBalance = settings.coinBalance
        settings.coinBalance -= DecorationItem.dogFoodPrice
        dec.hasFood = true
        do {
            try ctx.save()
        } catch {
            settings.coinBalance = previousBalance
            dec.hasFood = false
            feedingSaveError = true
            Haptics.warning()
            return
        }
        scene.decorationNodes.first { $0.associatedDecoration === dec }?.setBowlFilled(true)
        scene.notifyBowlFilled()
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
        scene.skyColors.map { Color(uiColor: $0) }
    }

    // MARK: - HUD elements

    private func hudValue(icon: String, tint: Color, count: Int,
                          title: String, info: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: count)
            Text("\(count)")
                .fontWeight(.bold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption)
        .frame(minWidth: 44)
        .padding(.horizontal, 5).padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(count)")
        .resourceInfo(icon: icon, tint: tint, title, info)
    }

    private var hudDivider: some View {
        Rectangle()
            .fill(Theme.creamLabel.opacity(0.14))
            .frame(width: 1, height: 18)
    }

    private var inventoryButton: some View {
        Button { showInventory = true } label: {
            Image(systemName: "backpack.fill")
                .font(.caption)
                .foregroundStyle(Theme.creamLabel)
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(S.inventory.title))
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

    private var storedAwayToast: some View {
        Label(L(S.town.storedToast), systemImage: "backpack.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var placementBanner: some View {
        HStack(spacing: 10) {
            if let b = placingBuilding {
                Image(systemName: placingStoredBuilding == nil ? "hammer.fill" : "backpack.fill")
                Text(L(S.town.tapToBuild, b.displayName) + inventorySuffix(placingStoredBuilding != nil))
                    .font(.subheadline)
            } else if placingItem == .road {
                Image(systemName: "hand.draw.fill")
                Text(storedRoads > 0 ? L(S.town.dragPathStored, storedRoads)
                                     : L(S.town.dragPath, DecorationItem.road.cost))
                    .font(.subheadline)
            } else if let item = placingItem, item.canUseCornerAnchor {
                Image(systemName: placingStoredDecoration == nil ? "leaf.fill" : "backpack.fill")
                Text(L(S.town.tapToPlaceCorner, item.displayName) + inventorySuffix(placingStoredDecoration != nil))
                    .font(.subheadline)
            } else {
                Text(L(S.town.tapToPlace, placingItem?.displayName ?? "")
                     + inventorySuffix(placingStoredDecoration != nil))
                    .font(.subheadline)
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

    private func inventorySuffix(_ fromInventory: Bool) -> String {
        fromInventory ? " · " + L(S.town.fromInventory) : ""
    }

    private var storedRoads: Int {
        decorations.filter { $0.type == .road && $0.isStored }.count
    }

    /// Start placing a decoration — bought, or taken out of the inventory when
    /// `placingStoredDecoration` is already set.
    private func beginPlacement(_ item: DecorationItem) {
        placingItem = item
        scene.isPlacementMode = true
        scene.isRoadPaintMode = (item == .road)   // roads paint by dragging
        // Greenery snaps to the closest of 5 anchors (centre + corners)
        scene.placingUsesAnchors = item.canUseCornerAnchor
        tab = 0
    }

    private func endPlacement() {
        placingItem = nil
        placingBuilding = nil
        placingStoredBuilding = nil
        placingStoredDecoration = nil
        scene.isPlacementMode = false
        scene.isRoadPaintMode = false
        scene.placingUsesAnchors = false
    }

    /// One road tile painted (drag or tap). Charges coins per tile and keeps
    /// the paint mode running so long paths cost one gesture, not many taps.
    private func paintRoadCell(_ col: Int, _ row: Int) {
        guard placingItem == .road else { return }
        guard scene.cellsFree(col: col, row: row) else { return }
        let dec: PlacedDecoration
        if let stored = decorations.first(where: { $0.type == .road && $0.isStored }) {
            // Tiles you tidied away go down first, for free.
            stored.isStored = false
            stored.isCornerAnchor = false
            stored.gridX = col
            stored.gridY = row
            dec = stored
        } else {
            guard settings.coinBalance >= DecorationItem.road.cost else {
                Haptics.warning()
                return
            }
            settings.coinBalance -= DecorationItem.road.cost
            dec = PlacedDecoration(type: .road, gridX: col, gridY: row)
            ctx.insert(dec)
        }
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
        if c.coins > 0 { return S.coinsCount(c.coins) }
        var parts: [String] = []
        if c.cost.wood > 0  { parts.append(Material.wood.amount(c.cost.wood)) }
        if c.cost.brick > 0 { parts.append(Material.brick.amount(c.cost.brick)) }
        if c.cost.steel > 0 { parts.append(Material.steel.amount(c.cost.steel)) }
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

    private func updateAmbience() {
        let active = scenePhase == .active && tab == 0
        scene.setRendering(active: active)
        SoundManager.shared.setListening(active)
    }

    private func configureScene() {
        guard !sceneReady else { return }
        sceneReady = true

        scene.onAtmosphereChanged = { SoundManager.shared.setAtmosphere(scene.atmosphere) }
        SoundManager.shared.setAtmosphere(scene.atmosphere)
        SoundManager.shared.setZoom(orthographicScale: scene.cameraZoom)
        updateAmbience()

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
        scene.onBowlEmptied = { decoration in
            guard decoration.hasFood else { return false }
            decoration.hasFood = false
            do {
                try ctx.save()
                return true
            } catch {
                decoration.hasFood = true
                feedingSaveError = true
                return false
            }
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
                guard let b = takeBuilding(type) else { Haptics.warning(); return }
                // A tree on a shared corner never blocks building — it makes way
                // into the inventory.
                clearCornerGreenery(under: type, col: col, row: row)
                b.gridX = col
                b.gridY = row
                b.rotation = 0
                let node = scene.addBuilding(type: type, gridX: col, gridY: row, animated: true,
                                             style: BuildingStyle(roof: b.roofColorIndex, facade: b.facadeIndex))
                node.associatedBuilding = b
                endPlacement()
                ctx.saveChanges()
                Haptics.success()
                SoundManager.shared.play(.build)
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
            guard let dec = takeDecoration(item, variant: 0) else { Haptics.warning(); return }
            dec.isCornerAnchor = false
            dec.gridX = col
            dec.gridY = row
            dec.rotation = 0
            let node = scene.addDecoration(type: item, gridX: col, gridY: row, variant: dec.variant)
            node.associatedDecoration = dec
            restoreDetails(of: dec, on: node)
            endPlacement()
            ctx.saveChanges()
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
                    guard let dec = takeDecoration(item, variant: variant) else { Haptics.warning(); return }
                    dec.isCornerAnchor = true
                    dec.gridX = cx
                    dec.gridY = cy
                    let node = scene.addDecoration(type: item, gridX: cx, gridY: cy,
                                                   isCornerAnchor: true, variant: dec.variant)
                    node.associatedDecoration = dec
                case let .tile(col, row):
                    guard (0..<scene.cols).contains(col), (0..<scene.rows).contains(row),
                          scene.cellsFree(col: col, row: row) else { continue }
                    guard let dec = takeDecoration(item, variant: variant) else { Haptics.warning(); return }
                    dec.isCornerAnchor = false
                    dec.gridX = col
                    dec.gridY = row
                    let node = scene.addDecoration(type: item, gridX: col, gridY: row, variant: dec.variant)
                    node.associatedDecoration = dec
                }
                ctx.saveChanges()
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
        // Hand the whole populated scene to Metal now, so the first drag isn't
        // the thing that compiles its shaders.
        scene.scheduleWarmUp()
    }

    /// Corner greenery standing where a building is about to go up moves into
    /// the inventory, so the player never loses it.
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
            node.associatedDecoration?.isStored = true
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
        // Queries can also shrink (full reset). Keep SceneKit in lockstep with
        // SwiftData instead of only ever adding nodes.
        for node in scene.buildingNodes
        where node.associatedBuilding?.isStored ?? true
            || !buildings.contains(where: { $0 === node.associatedBuilding }) {
            scene.removeBuilding(node)
        }
        for b in buildings where !b.isStored {
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
        for node in scene.decorationNodes
        where node.associatedDecoration?.isStored ?? true
            || !decorations.contains(where: { $0 === node.associatedDecoration }) {
            scene.removeDecoration(node)
        }
        for d in decorations where !d.isStored {
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

    // MARK: - Inventory: putting away, taking out, selling

    /// The record for a building being placed: the stored one when it comes out
    /// of the inventory (free), otherwise a freshly bought one.
    private func takeBuilding(_ type: BuildingType) -> Building? {
        if let stored = placingStoredBuilding {
            stored.isStored = false
            return stored
        }
        guard settings.pay(type.cost) else { return nil }
        let b = Building(type: type, gridX: 0, gridY: 0)
        if let today = todayRecord() { b.dayRecord = today }
        ctx.insert(b)
        withAnimation { Tutorial.shared.advance(from: .build) }
        return b
    }

    private func takeDecoration(_ item: DecorationItem, variant: Int) -> PlacedDecoration? {
        if let stored = placingStoredDecoration {
            stored.isStored = false
            return stored
        }
        guard settings.coinBalance >= item.cost else { return nil }
        settings.coinBalance -= item.cost
        let dec = PlacedDecoration(type: item, gridX: 0, gridY: 0, variant: variant)
        ctx.insert(dec)
        return dec
    }

    /// A doghouse back from the inventory keeps its name and its bowl.
    private func restoreDetails(of dec: PlacedDecoration, on node: DecorationNode) {
        guard dec.type == .doghouse else { return }
        node.setBowlFilled(dec.hasFood)
        node.setKennelName(dec.label)
    }

    private func store(_ node: BuildingNode) {
        node.associatedBuilding?.isStored = true
        scene.removeBuilding(node)
        finishStoring()
    }

    private func storeDecoration() {
        guard let node = decoToRemove else { return }
        decoToRemove = nil
        node.associatedDecoration?.isStored = true
        scene.removeDecoration(node)
        finishStoring()
    }

    private func finishStoring() {
        ctx.saveChanges()
        Haptics.drop()
        withAnimation(.spring(response: 0.35)) { storedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { storedToast = false }
        }
    }

    private func sell(_ b: Building) {
        let c = b.type.cost
        settings.add(.wood,  c.wood / 2)
        settings.add(.brick, c.brick / 2)
        settings.add(.steel, c.steel / 2)
        ctx.delete(b)
        ctx.saveChanges()
    }

    private func sell(_ d: PlacedDecoration) {
        settings.coinBalance += d.type.cost / 2
        ctx.delete(d)
        ctx.saveChanges()
    }

    // MARK: - Day completion → payout (no auto-building anymore)

    private func dayCompleted(_ record: DayRecord) {
        let count = record.completedCount
        guard count > 0 else { return }

        let p = settings.processDayClose(completedPillars: count, totalPillars: record.pillars.count)
        Haptics.success()
        payout = PayoutPresentation(payout: p, completedCount: count)
        checkAchievements()
    }

    // MARK: - Odznaky

    /// Recomputes the badges from the real data and queues anything newly
    /// earned for a celebration. Cheap enough to call on every meaningful
    /// action: one pass over the day records and a few counts.
    private func checkAchievements() {
        guard let store = settingsAll.first else { return }

        let stats = Achievements.stats(records: dayRecords, buildings: buildings,
                                       decorations: decorations, animals: animals,
                                       habits: habits, settings: store)
        let unlocked = Achievements.unlockedIDs(stats)

        // First run after badges shipped: quietly adopt whatever the player has
        // already earned. Fifteen popups in a row would be a punishment, and the
        // Kronika shows them all anyway. A new player has nothing unlocked at
        // this point, so their very first badge still gets its moment.
        guard achievementsSeeded else {
            store.seenAchievements = Array(unlocked)
            achievementsSeeded = true
            ctx.saveChanges()
            return
        }

        let seen = Set(store.seenAchievements)
        let fresh = Achievements.all.filter { unlocked.contains($0.id) && !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }

        store.seenAchievements.append(contentsOf: fresh.map(\.id))
        ctx.saveChanges()
        Haptics.success()
        unlockQueue.append(contentsOf: fresh)
    }

    /// Re-run all date-bound state whenever the process becomes active. iOS can
    /// keep the same view hierarchy alive across midnight, so `onAppear` alone
    /// is not a reliable boundary for a daily app.
    private func activateForCurrentDay(refreshDailyView: Bool = false) {
        let store = ensureSettings()
        store.registerActiveDay()
        if let reward = store.claimLoginRewardIfNeeded() {
            withAnimation(.spring(response: 0.35)) { loginToast = reward }
            SoundManager.shared.play(.coin)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { loginToast = nil }
            }
        }
        ctx.saveChanges()
        if refreshDailyView { dailyRefreshID = UUID() }
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
