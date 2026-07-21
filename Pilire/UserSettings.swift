import Foundation
import SwiftData

@Model
final class UserSettings {
    // Coins — daily login reward, cosmetics, exchange
    var coinBalance: Int
    var lastLoginRewardDate: Date?

    // Materials — main building resource
    var woodCount: Int  = 0
    var brickCount: Int = 0
    var steelCount: Int = 0

    // Momentum 0–100 — soft streak: grows on active days, decays slowly, never punishes
    var momentum: Double = 0
    var momentumDate: Date?        // last day decay was reconciled

    // Map expansion tier: 0 = 12×12, 1 = 16×16, 2 = 20×20, 3 = 24×24
    var mapTier: Int = 0

    // Weekly chest — keys ("yyyy-MM-dd" of week start) of already claimed weeks
    var claimedWeekKeys: [String] = []

    // Legacy (kept for store compatibility; UI no longer shows it)
    var currentStreak: Int
    var lastCompletedDate: Date?

    init() {
        self.coinBalance = 0
        self.currentStreak = 0
        self.lastCompletedDate = nil
    }

    // MARK: - Materials

    func count(_ m: Material) -> Int {
        switch m {
        case .wood:  woodCount
        case .brick: brickCount
        case .steel: steelCount
        }
    }

    func add(_ m: Material, _ n: Int) {
        switch m {
        case .wood:  woodCount  += n
        case .brick: brickCount += n
        case .steel: steelCount += n
        }
    }

    func canAfford(_ cost: MaterialCost) -> Bool {
        woodCount >= cost.wood && brickCount >= cost.brick && steelCount >= cost.steel
    }

    @discardableResult
    func pay(_ cost: MaterialCost) -> Bool {
        guard canAfford(cost) else { return false }
        woodCount  -= cost.wood
        brickCount -= cost.brick
        steelCount -= cost.steel
        return true
    }

    // MARK: - Momentum

    var momentumMultiplier: Double { 1 + momentum / 100 }   // 1.0 ... 2.0

    /// Decay −6 for every fully missed day. Call on app open; safe to call repeatedly.
    func reconcileMomentum(now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        defer { momentumDate = today }
        guard let lastDone = lastCompletedDate else { return }

        let sinceDone = cal.dateComponents([.day], from: cal.startOfDay(for: lastDone), to: today).day ?? 0
        let missedTotal = max(0, sinceDone - 1)   // days strictly between last activity and today
        let alreadyCounted: Int
        if let md = momentumDate {
            let sinceAtLastCheck = cal.dateComponents([.day], from: cal.startOfDay(for: lastDone),
                                                      to: cal.startOfDay(for: md)).day ?? 0
            alreadyCounted = max(0, sinceAtLastCheck - 1)
        } else {
            alreadyCounted = 0
        }
        let newMissed = max(0, missedTotal - alreadyCounted)
        if newMissed > 0 {
            momentum = max(0, momentum - 6 * Double(newMissed))
        }
    }

    // MARK: - Rewards

    /// +20 coins, once per calendar day. Returns the amount when claimed.
    func claimLoginRewardIfNeeded(now: Date = .now) -> Int? {
        let today = Calendar.current.startOfDay(for: now)
        if let last = lastLoginRewardDate, Calendar.current.isDate(last, inSameDayAs: today) {
            return nil
        }
        lastLoginRewardDate = today
        coinBalance += 20
        return 20
    }

    /// Weekly chest: a surprise reward for a week where every day has a pillar done.
    /// Rolls a random reward (Duolingo-style mystery loot).
    static func rollChestReward() -> ChestReward {
        switch Double.random(in: 0..<1) {
        case ..<0.50:   // běžná: hrst mincí
            return ChestReward(rarity: .common,
                               coins: [30, 40, 50].randomElement()!)
        case ..<0.82:   // vzácnější: mince + cihly
            return ChestReward(rarity: .rare,
                               coins: [50, 60].randomElement()!,
                               brick: Int.random(in: 2...4))
        default:        // vzácná: velká hromada + ocel
            return ChestReward(rarity: .epic,
                               coins: [80, 100].randomElement()!,
                               steel: Int.random(in: 1...3))
        }
    }

    /// Rolls a random reward and credits it. Repeatable — used for the weekly
    /// chest and for the god-mode test button.
    @discardableResult
    func grantRandomChest() -> ChestReward {
        let reward = Self.rollChestReward()
        coinBalance += reward.coins
        woodCount   += reward.wood
        brickCount  += reward.brick
        steelCount  += reward.steel
        return reward
    }

    /// Claims the chest for the given week. Returns the rolled reward, nil when already claimed.
    func claimWeeklyChest(weekKey: String) -> ChestReward? {
        guard !claimedWeekKeys.contains(weekKey) else { return nil }
        claimedWeekKeys.append(weekKey)
        return grantRandomChest()
    }

    /// Okamžitá odměna za splněný task: dřevo (pool tasky +50 %).
    @discardableResult
    func awardTaskWood(isFromPool: Bool) -> Int {
        reconcileMomentum()
        let base = isFromPool ? 3.0 : 2.0
        let amount = Int((base * momentumMultiplier).rounded())
        woodCount += amount
        return amount
    }

    /// Uzavření dne: cihly/ocel podle počtu splněných + momentum +12.
    func processDayClose(completedPillars: Int, totalPillars: Int) -> Payout {
        reconcileMomentum()
        var payout = Payout()
        let mult = momentumMultiplier

        if completedPillars >= 2 { payout.brick = Int((3 * mult).rounded()) }
        if completedPillars >= 4 { payout.steel = Int((2 * mult).rounded()) }
        if completedPillars == totalPillars && totalPillars > 0 { payout.steel += 1 }

        brickCount += payout.brick
        steelCount += payout.steel

        let before = momentum
        momentum = min(100, momentum + 12)
        payout.momentumGained = momentum - before

        // Legacy streak upkeep (data only)
        updateStreak()
        return payout
    }

    private func updateStreak() {
        let today = Calendar.current.startOfDay(for: .now)
        if let last = lastCompletedDate {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
            if Calendar.current.isDate(last, inSameDayAs: yesterday) {
                currentStreak += 1
            } else if Calendar.current.isDate(last, inSameDayAs: today) {
                // already closed today
            } else {
                currentStreak = 1
            }
        } else {
            currentStreak = 1
        }
        lastCompletedDate = today
    }
}

// MARK: - Weekly chest reward

struct ChestReward: Identifiable {
    enum Rarity {
        case common, rare, epic
        var title: String {
            switch self {
            case .common: "Truhla"
            case .rare:   "Vzácná truhla"
            case .epic:   "Zlatá truhla"
            }
        }
    }

    let id = UUID()
    var rarity: Rarity = .common
    var coins: Int = 0
    var wood: Int = 0
    var brick: Int = 0
    var steel: Int = 0

    /// Human-readable reward line, e.g. "60 mincí + 3 cihly".
    var label: String {
        var parts: [String] = []
        if coins > 0 { parts.append("\(coins) mincí") }
        if wood  > 0 { parts.append("\(wood) dřeva") }
        if brick > 0 { parts.append("\(brick) cihel") }
        if steel > 0 { parts.append("\(steel) oceli") }
        return parts.joined(separator: " + ")
    }
}

// MARK: - Day close payout

struct Payout: Identifiable {
    let id = UUID()
    var brick: Int = 0
    var steel: Int = 0
    var momentumGained: Double = 0
}
