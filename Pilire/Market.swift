import Foundation

// MARK: - Market
//
// Trade with the town, never with other players (there is no server). Prices
// follow the coin values the game already uses (wood 10, brick 20, steel 40);
// selling pays back a generous share, more once the town has a market hall.
// Each day brings one deal and a few requests from a travelling trader. They
// are seeded by the date like the weather, so they hold for the whole day and
// relaunching the app can't reroll them.

enum Market {

    // MARK: Prices

    static let sellShare = 0.65
    static let sellShareWithMarketHall = 0.75

    static func baseValue(_ m: Material) -> Int { m.coinPrice }

    static func buyPrice(_ m: Material, on day: Date = .now) -> Int {
        let deal = deal(on: day)
        guard deal.material == m, deal.kind == .cheaperBuy else { return baseValue(m) }
        return Int((Double(baseValue(m)) * 0.8).rounded())
    }

    static func sellPrice(_ m: Material, hasMarketHall: Bool, on day: Date = .now) -> Int {
        var share = hasMarketHall ? sellShareWithMarketHall : sellShare
        let deal = deal(on: day)
        if deal.material == m, deal.kind == .betterSell { share += 0.15 }
        return max(1, Int((Double(baseValue(m)) * share).rounded(.down)))
    }

    /// How many of `from` buy one `to` through the market.
    static func swapCost(from: Material, to: Material, hasMarketHall: Bool, on day: Date = .now) -> Int {
        let need = Double(buyPrice(to, on: day)) / Double(sellPrice(from, hasMarketHall: hasMarketHall, on: day))
        return max(1, Int(need.rounded(.up)))
    }

    // MARK: Deal of the day

    struct Deal: Equatable {
        enum Kind { case cheaperBuy, betterSell }
        let kind: Kind
        let material: Material
    }

    static func deal(on day: Date = .now) -> Deal {
        var rng = DayRandom(day: day, salt: 1)
        let material = Material.allCases[Int(rng.next() % 3)]
        return Deal(kind: rng.next() % 2 == 0 ? .cheaperBuy : .betterSell, material: material)
    }

    // MARK: Trader

    enum Payment: Equatable {
        case material(Material, Int)
        case coins(Int)
    }

    struct Offer: Identifiable, Equatable {
        let id: String
        /// What the player hands over, and what they get for it.
        let give: Payment
        let get: Payment
        let story: T

        static func == (a: Offer, b: Offer) -> Bool { a.id == b.id }
    }

    static func offers(on day: Date = .now, hasMarketHall: Bool) -> [Offer] {
        var rng = DayRandom(day: day, salt: 7)
        let count = hasMarketHall ? 3 : 2
        var made: [Offer] = []
        var styles = [0, 1, 2]
        // Each request is about a different material, so one can't be used to
        // buy cheaply from the trader and sell straight back to him.
        var materials = Material.allCases
        for i in 0..<count {
            // A visit contains different kinds of requests, rather than three
            // differently worded copies of the same transaction.
            let style = styles.remove(at: Int(rng.next() % UInt64(styles.count)))
            let want = materials.remove(at: Int(rng.next() % UInt64(materials.count)))
            let n = smallAmount(of: want, &rng)
            let give: Payment, get: Payment
            let stories: [T]
            switch style {
            case 0:   // they need a material and pay well in coins
                give = .material(want, n)
                get = .coins(roundToFive(Double(baseValue(want) * n) * 1.5))
                stories = S.market.storiesForCoins
            case 1:   // a swap, clearly in the player's favour
                let other = Material.allCases.filter { $0 != want }[Int(rng.next() % 2)]
                let worth = Double(baseValue(want) * n) * 1.7
                give = .material(want, n)
                get = .material(other, max(1, Int((worth / Double(baseValue(other))).rounded())))
                stories = S.market.storiesSwap
            default:  // a pile they want gone, cheap
                give = .coins(roundToFive(Double(baseValue(want) * n) * 0.6))
                get = .material(want, n)
                stories = S.market.storiesSurplus
            }
            made.append(Offer(id: "\(dayKey(day))-\(i)", give: give, get: get,
                              story: stories[storyIndex(on: day, style: style, count: stories.count)]))
        }
        return made
    }

    /// Walks each pool in a scrambled but fixed order: a stride coprime with
    /// the pool size visits every story once before any comes back, and never
    /// shows the same one two days running. Amounts and materials stay seeded.
    static let storyStride = 5

    static func storyIndex(on day: Date, style: Int, count: Int) -> Int {
        let ordinal = Calendar.current.ordinality(of: .day, in: .era,
                                                 for: Calendar.current.startOfDay(for: day)) ?? 0
        return (ordinal * storyStride + style * 4) % count
    }

    private static func smallAmount(of m: Material, _ rng: inout DayRandom) -> Int {
        switch m {
        case .wood:  4 + Int(rng.next() % 5)   // 4–8
        case .brick: 2 + Int(rng.next() % 3)   // 2–4
        case .steel: 1 + Int(rng.next() % 2)   // 1–2
        }
    }

    private static func roundToFive(_ v: Double) -> Int { max(5, Int((v / 5).rounded()) * 5) }

    // MARK: Claimed offers (per device, per day)

    private static let claimedKey = "marketClaimedOffers"
    private static let seenKey = "marketSeenDay"

    static func isClaimed(_ offer: Offer) -> Bool {
        (UserDefaults.standard.stringArray(forKey: claimedKey) ?? []).contains(offer.id)
    }

    static func markClaimed(_ offer: Offer, on day: Date = .now) {
        let today = dayKey(day)
        var ids = (UserDefaults.standard.stringArray(forKey: claimedKey) ?? []).filter { $0.hasPrefix(today) }
        ids.append(offer.id)
        UserDefaults.standard.set(ids, forKey: claimedKey)
    }

    /// The trader's dot on the map shows until the market is opened that day.
    static var hasUnseenOffers: Bool {
        UserDefaults.standard.string(forKey: seenKey) != dayKey(.now)
    }

    static func markSeen(on day: Date = .now) { UserDefaults.standard.set(dayKey(day), forKey: seenKey) }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: Trading

    static func canPay(_ p: Payment, _ settings: UserSettings) -> Bool {
        switch p {
        case .material(let m, let n): settings.count(m) >= n
        case .coins(let n):           settings.coinBalance >= n
        }
    }

    static func pay(_ p: Payment, _ settings: UserSettings) {
        switch p {
        case .material(let m, let n): settings.add(m, -n)
        case .coins(let n):           settings.coinBalance -= n
        }
    }

    static func receive(_ p: Payment, _ settings: UserSettings) {
        switch p {
        case .material(let m, let n): settings.add(m, n)
        case .coins(let n):           settings.coinBalance += n
        }
    }

    @discardableResult
    static func accept(_ offer: Offer, _ settings: UserSettings, on day: Date = .now) -> Bool {
        guard offer.id.hasPrefix(dayKey(day) + "-"),
              !isClaimed(offer), canPay(offer.give, settings) else { return false }
        pay(offer.give, settings)
        receive(offer.get, settings)
        markClaimed(offer, on: day)
        return true
    }

    /// Coins needed to buy exactly what's missing for `cost`, or nil if nothing is.
    static func topUpPrice(for cost: MaterialCost, _ settings: UserSettings) -> Int? {
        let missing = [(Material.wood, cost.wood), (.brick, cost.brick), (.steel, cost.steel)]
            .map { ($0, max(0, $1 - settings.count($0))) }
        let total = missing.reduce(0) { $0 + $1.1 * buyPrice($1.0) }
        return total > 0 ? total : nil
    }

    static func topUp(for cost: MaterialCost, _ settings: UserSettings) -> Bool {
        guard let price = topUpPrice(for: cost, settings), settings.coinBalance >= price else { return false }
        for (m, need) in [(Material.wood, cost.wood), (.brick, cost.brick), (.steel, cost.steel)] {
            settings.add(m, max(0, need - settings.count(m)))
        }
        settings.coinBalance -= price
        return true
    }

    // MARK: Wording

    @MainActor
    static func text(_ p: Payment) -> String {
        switch p {
        case .material(let m, let n): m.amount(n)
        case .coins(let n):           coins(n)
        }
    }

    @MainActor
    static func coins(_ n: Int) -> String {
        switch Language.shared.current {
        case .cs: n == 1 ? "1 mince" : (2...4).contains(n) ? "\(n) mince" : "\(n) mincí"
        case .sk: n == 1 ? "1 minca" : (2...4).contains(n) ? "\(n) mince" : "\(n) mincí"
        case .en: n == 1 ? "1 coin" : "\(n) coins"
        }
    }
}

/// A small deterministic generator seeded by the calendar day (splitmix64,
/// the same mix the weather uses), so a day's market is stable.
private struct DayRandom {
    private var state: UInt64

    init(day: Date, salt: UInt64) {
        let cal = Calendar.current
        let d = UInt64(cal.ordinality(of: .day, in: .year, for: day) ?? 0)
        let y = UInt64(cal.component(.year, from: day))
        state = d &* 7919 &+ y &* 104_729 &+ salt &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
