import Foundation
import SwiftData

@main
struct WeeklyChestClaimsChecks {
    static func main() throws {
        let url = URL(fileURLWithPath: "/private/tmp/pilire-weekly-claims-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let schema = Schema([DayRecord.self, Building.self, UserSettings.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        context.autosaveEnabled = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.firstWeekday = 2
        let sundayLegacy = UserSettings()
        sundayLegacy.claimedWeekKeys = ["2026-10-04"]
        precondition(WeeklyChestClaims.firstWeekday(in: sundayLegacy, legacyCalendar: calendar) == 2)
        func date(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        func insertWeek(_ start: Date) {
            for offset in 0..<7 {
                let record = DayRecord(date: calendar.date(byAdding: .day, value: offset, to: start)!)
                var pillar = Pillar(text: "Splněný pilíř", order: 0)
                pillar.isCompleted = true
                record.pillars = [pillar]
                context.insert(record)
            }
        }
        let settings = UserSettings()
        settings.coinBalance = 100
        context.insert(settings)
        insertWeek(date(9, 28))
        try WeeklyChestClaims.preserveWeekPolicy(in: settings, legacyCalendar: calendar, context: context)
        precondition(settings.weeklyChestFirstWeekday == 2)
        let records = try context.fetch(FetchDescriptor<DayRecord>())
        let first = try WeeklyChestClaims.claim(in: settings, records: records, calendar: calendar,
                                               now: date(10, 4), context: context)!
        let balances = (settings.coinBalance, settings.brickCount, settings.steelCount)
        let repeated = try WeeklyChestClaims.claim(in: settings, records: records, calendar: calendar,
                                                  now: date(10, 4), context: context)!
        precondition(first.reward.id == repeated.reward.id && settings.coinBalance == balances.0)

        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let reopenedContext = reopened.mainContext
        reopenedContext.autosaveEnabled = false
        let reloaded = try reopenedContext.fetch(FetchDescriptor<UserSettings>()).first!
        let resumed = try WeeklyChestClaims.pending(in: reloaded)!
        precondition(resumed.reward.id == first.reward.id)
        precondition(reloaded.coinBalance == balances.0 && reloaded.brickCount == balances.1 && reloaded.steelCount == balances.2)
        try WeeklyChestClaims.acknowledge(resumed, in: reloaded, context: reopenedContext)
        let afterAcknowledgement = try WeeklyChestClaims.pending(in: reloaded)
        precondition(afterAcknowledgement == nil)
        let noSecondClaim = try WeeklyChestClaims.claim(in: reloaded,
            records: reopenedContext.fetch(FetchDescriptor<DayRecord>()), calendar: calendar,
            now: date(10, 4), context: reopenedContext)
        precondition(noSecondClaim == nil)

        // A separate eligible week exercises an actual persistent-store write rejection.
        for offset in 0..<7 {
            let record = DayRecord(date: calendar.date(byAdding: .day, value: offset, to: date(10, 5))!)
            var pillar = Pillar(text: "Další týden", order: 0)
            pillar.isCompleted = true
            record.pillars = [pillar]
            reopenedContext.insert(record)
        }
        try reopenedContext.save()
        let readOnly = try ModelContainer(for: schema, configurations:
            ModelConfiguration(schema: schema, url: url, allowsSave: false))
        let readContext = readOnly.mainContext
        readContext.autosaveEnabled = false
        let readSettings = try readContext.fetch(FetchDescriptor<UserSettings>()).first!
        let beforeKeys = readSettings.claimedWeekKeys
        let beforeCoins = readSettings.coinBalance
        var didFail = false
        do {
            _ = try WeeklyChestClaims.claim(in: readSettings,
                records: readContext.fetch(FetchDescriptor<DayRecord>()), calendar: calendar,
                now: date(10, 16), context: readContext)
        } catch { didFail = true }
        precondition(didFail)
        precondition(readSettings.coinBalance == beforeCoins && readSettings.claimedWeekKeys == beforeKeys)
        precondition(readSettings.pendingWeeklyChestData == nil)
        print("PASS: single claim, saved reveal, reopen, acknowledge, repeat prevention and failed-save restoration")
    }
}
