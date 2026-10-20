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
    var momentumDate: Date?        // last day the app was opened (active day)

    // Map expansion tier: 0 = 12×12, 1 = 16×16, 2 = 20×20, 3 = 24×24
    var mapTier: Int = 0

    // Weekly chest — keys ("yyyy-MM-dd" of week start) of already claimed weeks
    var claimedWeekKeys: [String] = []
    /// Optional additions allow existing stores to migrate without resetting reward history.
    var weeklyChestFirstWeekday: Int? = nil
    var pendingWeeklyChestData: Data? = nil

    // Badges the player has already been shown, by stable id. Which badges are
    // *earned* is derived from the real data every time, so this list only
    // decides what still deserves a celebration.
    var seenAchievements: [String] = []

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

    /// Momentum is a small, bounded "how regularly do you show up" meter:
    /// +1 each day the app is opened, −1 per missed day, capped low so it never
    /// balloons into a silly number.
    static let momentumMax: Double = 30
    static let momentumDecayPerMissedDay: Double = 1

    /// Gentle reward multiplier: 1.0× at zero, up to 1.6× at the cap.
    var momentumMultiplier: Double { 1 + momentum / 50 }

    /// Call once when the app opens. Adds +1 for today (first open of the day)
    /// and subtracts for any days that were skipped since the last visit.
    func registerActiveDay(now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        if let last = momentumDate {
            // Already counted today? Nothing to do.
            if cal.isDate(last, inSameDayAs: today) { return }
            let gap = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: today).day ?? 0
            let missed = max(0, gap - 1)   // full days with no visit in between
            momentum -= Double(missed) * Self.momentumDecayPerMissedDay
        }
        momentum += 1
        momentum = min(Self.momentumMax, max(0, momentum))
        momentumDate = today
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
        let base = isFromPool ? 3.0 : 2.0
        let amount = Int((base * momentumMultiplier).rounded())
        woodCount += amount
        return amount
    }

    /// Uzavření dne: cihly/ocel podle počtu splněných. Momentum se řídí jen tím,
    /// jak pravidelně appku otevíráš (viz registerActiveDay), ne uzavřením dne.
    func processDayClose(completedPillars: Int, totalPillars: Int) -> Payout {
        var payout = Payout()
        let mult = momentumMultiplier

        if completedPillars >= 2 { payout.brick = Int((3 * mult).rounded()) }
        if completedPillars >= 4 { payout.steel = Int((2 * mult).rounded()) }
        if completedPillars == totalPillars && totalPillars > 0 { payout.steel += 1 }

        brickCount += payout.brick
        steelCount += payout.steel

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

struct ChestReward: Identifiable, Codable {
    enum Rarity: String, Codable {
        case common, rare, epic
        var title: String {
            switch self {
            case .common: L(S.calendar.commonReward)
            case .rare:   L(S.calendar.rareReward)
            case .epic:   L(S.calendar.epicReward)
            }
        }
    }

    let id: UUID
    var rarity: Rarity = .common
    var coins: Int = 0
    var wood: Int = 0
    var brick: Int = 0
    var steel: Int = 0

    init(id: UUID = UUID(), rarity: Rarity = .common, coins: Int = 0,
         wood: Int = 0, brick: Int = 0, steel: Int = 0) {
        self.id = id
        self.rarity = rarity
        self.coins = coins
        self.wood = wood
        self.brick = brick
        self.steel = steel
    }

    /// Human-readable reward line, e.g. "60 mincí + 3 cihly".
    var label: String {
        var parts: [String] = []
        if coins > 0 { parts.append(S.coinsCount(coins)) }
        if wood  > 0 { parts.append(Material.wood.amount(wood)) }
        if brick > 0 { parts.append(Material.brick.amount(brick)) }
        if steel > 0 { parts.append(Material.steel.amount(steel)) }
        return parts.joined(separator: " + ")
    }
}

// MARK: - Day close payout

struct Payout: Identifiable {
    let id = UUID()
    var brick: Int = 0
    var steel: Int = 0
}
