import SwiftUI
import SwiftData

enum MarketSection: CaseIterable { case requests, supplies }

/// Matěj's visit and the permanent supplies counter share a wallet, but each
/// has its own space. A day's requests remain still while the player reads.
struct MarketView: View {
    let settings: UserSettings
    let hasMarketHall: Bool

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: MarketSection
    @State private var quantity = 1
    @State private var swapFrom: Material = .brick
    @State private var swapTo: Material = .steel
    @State private var marketDay = Calendar.current.startOfDay(for: Date.now)
    @State private var claimedIDs = Set<String>()

    init(settings: UserSettings, hasMarketHall: Bool, initialSection: MarketSection = .requests) {
        self.settings = settings
        self.hasMarketHall = hasMarketHall
        _section = State(initialValue: initialSection)
    }

    private var offers: [Market.Offer] { Market.offers(on: marketDay, hasMarketHall: hasMarketHall) }
    private var completed: Int { offers.filter { claimedIDs.contains($0.id) }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CatalogWallet(settings: settings)
                    MerchantWelcomeCard(day: marketDay, allCompleted: completed == offers.count,
                                        hasMarketHall: hasMarketHall)
                    sectionPicker
                    if section == .requests {
                        traderSection
                    } else {
                        tradeSection
                        swapSection
                        Label(L(hasMarketHall ? S.market.hallActive : S.market.hallBonus), systemImage: "storefront")
                            .font(.system(.footnote, design: .rounded)).foregroundStyle(Theme.creamLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Theme.creamGradient)
            .navigationTitle(L(S.market.title))
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
        .onAppear { refreshDay() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDay() } }
        .onChange(of: hasMarketHall) { _, _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refreshDay() }
    }

    private func refreshDay() {
        marketDay = Calendar.current.startOfDay(for: .now)
        claimedIDs = Set(offers.filter { Market.isClaimed($0) }.map(\.id))
        Market.markSeen(on: marketDay)
    }

    /// If midnight arrives between drawing a price and tapping it, show the new
    /// day first. Never execute yesterday's price under today's label.
    private func canTradeToday() -> Bool {
        guard Market.dayKey(marketDay) == Market.dayKey(.now) else { refreshDay(); return false }
        return true
    }

    private func traded() {
        ctx.saveChanges()
        claimedIDs = Set(offers.filter { Market.isClaimed($0) }.map(\.id))
        SoundManager.shared.play(.coin)
        Haptics.success()
    }

    /// A quiet segmented control: the selected page lifts onto white.
    private var sectionPicker: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            ForEach(MarketSection.allCases, id: \.self) { item in
                let on = section == item
                Button {
                    section = item
                    Haptics.tap()
                } label: {
                    Text(L(item == .requests ? S.market.requestsTab : S.market.suppliesTab))
                        .font(.system(.subheadline, design: .rounded).weight(on ? .bold : .medium))
                        .foregroundStyle(on ? CatalogStyle.ink : Theme.creamLabel)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if on {
                                Capsule().fill(.white)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(CatalogPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(MarketStyle.edge.opacity(0.22), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L(S.market.marketTabs))
    }

    // MARK: Matěj's requests

    private var traderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(L(S.market.requests))
            PaperPanel {
                ForEach(offers) { offer in offerRow(offer) }
            }
            Label(L(S.market.nextVisit), systemImage: "sun.horizon")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
                .frame(maxWidth: .infinity).padding(.top, 4)
        }
    }

    private func shortfall(for payment: Market.Payment) -> Market.Payment? {
        switch payment {
        case .coins(let n): settings.coinBalance < n ? .coins(n - settings.coinBalance) : nil
        case .material(let m, let n): settings.count(m) < n ? .material(m, n - settings.count(m)) : nil
        }
    }

    private func offerRow(_ offer: Market.Offer) -> some View {
        let claimed = claimedIDs.contains(offer.id)
        let missing = shortfall(for: offer.give)
        return VStack(alignment: .leading, spacing: 12) {
            Text(claimed ? L(S.market.tradeThanks) : quoted(L(offer.story, Market.text(offer.give), Market.text(offer.get))))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(claimed ? Theme.creamLabel : CatalogStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    exchange(offer, short: missing != nil && !claimed)
                    Spacer(minLength: 4)
                    offerAction(offer, claimed: claimed, missing: missing)
                }
                VStack(alignment: .leading, spacing: 10) {
                    exchange(offer, short: missing != nil && !claimed)
                    offerAction(offer, claimed: claimed, missing: missing)
                }
            }
            .opacity(claimed ? 0.6 : 1)
        }
        .padding(16)
    }

    /// Matěj's words, in the quotation marks of the chosen language.
    private func quoted(_ text: String) -> String {
        Language.shared.current == .en ? "“\(text)”" : "„\(text)“"
    }

    private func exchange(_ offer: Market.Offer, short: Bool) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            MarketToken(payment: offer.give, tone: short ? CatalogStyle.shortageAmount : CatalogStyle.ink)
            Image(systemName: "arrow.right").font(.caption.weight(.bold))
                .foregroundStyle(Theme.creamLabel).accessibilityHidden(true)
            MarketToken(payment: offer.get, tone: MarketStyle.green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(L(S.market.youGive)) \(Market.text(offer.give)), \(L(S.market.youGet)) \(Market.text(offer.get))")
    }

    @ViewBuilder
    private func offerAction(_ offer: Market.Offer, claimed: Bool, missing: Market.Payment?) -> some View {
        if claimed {
            Label(L(S.market.settled), systemImage: "checkmark.circle.fill")
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(MarketStyle.green)
                .fixedSize()
        } else if let missing {
            Text(L(S.market.missing, Market.text(missing)))
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(CatalogStyle.shortage)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button(L(S.market.accept)) {
                guard canTradeToday() else { return }
                if Market.accept(offer, settings) { traded() } else { refreshDay(); Haptics.warning() }
            }
            .buttonStyle(CapsuleButtonStyle(kind: .primary))
            .fixedSize()
        }
    }

    // MARK: The permanent counter

    private var tradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    header(L(S.market.tradeHeader))
                    Spacer(minLength: 12)
                    quantityPicker.frame(maxWidth: 170)
                }
                VStack(alignment: .leading, spacing: 10) {
                    header(L(S.market.tradeHeader))
                    quantityPicker
                }
            }
            PaperPanel {
                ForEach(Material.allCases) { materialRow($0) }
            }
        }
    }

    private var quantityPicker: some View {
        Picker(L(S.market.quantityLabel), selection: $quantity) {
            ForEach([1, 5, 10], id: \.self) { Text("×\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func materialRow(_ material: Material) -> some View {
        let buy = Market.buyPrice(material, on: marketDay) * quantity
        let sell = Market.sellPrice(material, hasMarketHall: hasMarketHall, on: marketDay) * quantity
        let canBuy = settings.coinBalance >= buy
        let canSell = settings.count(material) >= quantity
        let name = HStack(spacing: 12) {
            AppIcon(material.symbolName).font(.system(size: 26))
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(material.displayName).font(.system(.headline, design: .rounded))
                    .foregroundStyle(CatalogStyle.ink)
                Text(L(S.market.youHave, settings.count(material)))
                    .font(.system(.caption, design: .rounded)).foregroundStyle(Theme.creamLabel)
                    .monospacedDigit()
            }
        }
        let actions = (textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
            priceButton(L(S.market.buyFor, buy), kind: .tinted, enabled: canBuy) {
                guard canTradeToday(), settings.coinBalance >= buy else { return }
                settings.coinBalance -= buy; settings.add(material, quantity); traded()
            }
            priceButton(L(S.market.sellFor, sell), kind: .outline, enabled: canSell) {
                guard canTradeToday(), settings.count(material) >= quantity else { return }
                settings.add(material, -quantity); settings.coinBalance += sell; traded()
            }
        }
        // One layout per device, not per row: prices differ in width, and rows
        // that wrap independently (or jump when the quantity changes) look loose.
        return Group {
            if sizeClass == .regular && !textSize.isAccessibilitySize {
                HStack(spacing: 8) { name; Spacer(minLength: 0); actions }
            } else {
                // Under the name, the buttons line up with its text, not the icon.
                VStack(alignment: .leading, spacing: 10) { name; actions.padding(.leading, 48) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func priceButton(_ title: String, kind: CapsuleButtonStyle.Kind, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                AppIcon(ResourceIcon.coin).font(.system(size: 12))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(CapsuleButtonStyle(kind: kind))
        .fixedSize()
        .disabled(!enabled)
    }

    private var swapSection: some View {
        let cost = Market.swapCost(from: swapFrom, to: swapTo, hasMarketHall: hasMarketHall, on: marketDay) * quantity
        let can = swapFrom != swapTo && settings.count(swapFrom) >= cost
        return VStack(alignment: .leading, spacing: 12) {
            header(L(S.market.swapHeader))
            PaperPanel {
                materialPicker(L(S.market.swapFrom), selection: $swapFrom)
                materialPicker(L(S.market.swapTo), selection: $swapTo)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        swapSummary(cost: cost, short: !can)
                        Spacer(minLength: 4)
                        swapButton(cost: cost, enabled: can)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        swapSummary(cost: cost, short: !can)
                        swapButton(cost: cost, enabled: can)
                    }
                }
                .padding(16)
            }
        }
        .onChange(of: swapFrom) { _, new in if new == swapTo { swapTo = Material.allCases.first { $0 != new }! } }
        .onChange(of: swapTo) { _, new in if new == swapFrom { swapFrom = Material.allCases.first { $0 != new }! } }
    }

    private func swapSummary(cost: Int, short: Bool) -> some View {
        HStack(spacing: 8) {
            MarketToken(payment: .material(swapFrom, cost), tone: short ? CatalogStyle.shortageAmount : CatalogStyle.ink)
            Image(systemName: "arrow.right").font(.caption.weight(.bold))
                .foregroundStyle(Theme.creamLabel).accessibilityHidden(true)
            MarketToken(payment: .material(swapTo, quantity), tone: MarketStyle.green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L(S.market.swapButton, swapFrom.amount(cost), swapTo.amount(quantity)))
    }

    private func swapButton(cost: Int, enabled: Bool) -> some View {
        Button(L(S.market.swapAction)) {
            guard canTradeToday(), swapFrom != swapTo, settings.count(swapFrom) >= cost else { return }
            settings.add(swapFrom, -cost); settings.add(swapTo, quantity); traded()
        }
        .buttonStyle(CapsuleButtonStyle(kind: .primary))
        .fixedSize()
        .disabled(!enabled)
    }

    private func materialPicker(_ label: String, selection: Binding<Material>) -> some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(label).font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.creamLabel)
                .frame(minWidth: 44, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(Material.allCases) { material in
                    let on = selection.wrappedValue == material
                    Button { selection.wrappedValue = material } label: {
                        AppIcon(material.symbolName)
                            .font(.system(size: 20))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                Capsule().fill(on ? material.color.opacity(0.14) : .clear)
                                Capsule().strokeBorder(on ? material.color.opacity(0.7) : MarketStyle.edge.opacity(0.6),
                                                       lineWidth: on ? 1.5 : 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(CatalogPressStyle())
                    .accessibilityLabel(material.displayName)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(.title3, design: .rounded).bold())
            .foregroundStyle(CatalogStyle.ink).accessibilityAddTraits(.isHeader)
    }
}
