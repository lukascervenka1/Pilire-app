import Foundation
import SwiftData

/// The reveal can be resumed after leaving the app, without rolling another reward.
struct WeeklyChestReceipt: Codable, Identifiable {
    let weekKey: String
    let weekStart: Date
    let reward: ChestReward
    var id: String { weekKey }
}

@MainActor
enum WeeklyChestClaims {
    /// Reward weeks run Monday to Sunday, as weeks are counted in Czechia and
    /// Slovakia and as the habit day picker already reads, whatever the device
    /// region says. Weeks claimed under an older Sunday-first policy still
    /// count: `WeeklyChestProgress` treats any week overlapping a claimed one
    /// as rewarded, so switching never pays the same days out twice.
    static let weekStartsOn = 2

    static func firstWeekday(in settings: UserSettings, legacyCalendar: Calendar) -> Int {
        weekStartsOn
    }

    static func pending(in settings: UserSettings) throws -> WeeklyChestReceipt? {
        guard let data = settings.pendingWeeklyChestData else { return nil }
        return try JSONDecoder().decode(WeeklyChestReceipt.self, from: data)
    }

    static func preserveWeekPolicy(in settings: UserSettings, legacyCalendar: Calendar,
                                   context: ModelContext) throws {
        guard settings.weeklyChestFirstWeekday != weekStartsOn else { return }
        let previous = settings.weeklyChestFirstWeekday
        settings.weeklyChestFirstWeekday = firstWeekday(in: settings, legacyCalendar: legacyCalendar)
        do {
            try context.save()
        } catch {
            settings.weeklyChestFirstWeekday = previous
            throw error
        }
    }

    static func claim(in settings: UserSettings, records: [DayRecord], calendar: Calendar,
                      now: Date, context: ModelContext) throws -> WeeklyChestReceipt? {
        if let pending = try pending(in: settings) { return pending }
        var calendar = calendar
        calendar.firstWeekday = firstWeekday(in: settings, legacyCalendar: calendar)
        let progress = WeeklyChestProgress(
            activities: records.map { .init(date: $0.date, completedCount: $0.completedCount) },
            claimedKeys: settings.claimedWeekKeys, calendar: calendar, now: now)
        guard let week = progress.claimableWeeks.first else { return nil }

        let oldKeys = settings.claimedWeekKeys
        let oldBalances = (settings.coinBalance, settings.woodCount, settings.brickCount, settings.steelCount)
        let oldPolicy = settings.weeklyChestFirstWeekday
        do {
            guard let reward = settings.claimWeeklyChest(weekKey: week.key) else { return nil }
            let receipt = WeeklyChestReceipt(weekKey: week.key, weekStart: week.start, reward: reward)
            settings.pendingWeeklyChestData = try JSONEncoder().encode(receipt)
            settings.weeklyChestFirstWeekday = calendar.firstWeekday
            try context.save()
            return receipt
        } catch {
            // Restore only this operation. Other edits in the shared context are preserved.
            settings.claimedWeekKeys = oldKeys
            settings.coinBalance = oldBalances.0
            settings.woodCount = oldBalances.1
            settings.brickCount = oldBalances.2
            settings.steelCount = oldBalances.3
            settings.weeklyChestFirstWeekday = oldPolicy
            settings.pendingWeeklyChestData = nil
            throw error
        }
    }

    static func acknowledge(_ receipt: WeeklyChestReceipt, in settings: UserSettings,
                            context: ModelContext) throws {
        guard try pending(in: settings)?.id == receipt.id else { return }
        let previous = settings.pendingWeeklyChestData
        settings.pendingWeeklyChestData = nil
        do {
            try context.save()
        } catch {
            settings.pendingWeeklyChestData = previous
            throw error
        }
    }
}
