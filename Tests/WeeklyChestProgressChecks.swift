import Foundation

@main
struct WeeklyChestProgressChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        calendar.firstWeekday = 2
        func date(_ month: Int, _ day: Int, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }
        func activities(from start: Date) -> [WeeklyChestProgress.Activity] {
            (0..<7).map { .init(date: calendar.date(byAdding: .day, value: $0, to: start)!, completedCount: 1) }
        }
        func progress(_ activities: [WeeklyChestProgress.Activity], now: Date,
                      claimed: [String] = [], cal: Calendar? = nil) -> WeeklyChestProgress {
            WeeklyChestProgress(activities: activities, claimedKeys: claimed,
                                calendar: cal ?? calendar, now: now)
        }
        let complete = activities(from: date(10, 5))
        precondition(progress(complete, now: date(10, 16)).claimableWeeks.map(\.key) == ["2026-10-05"])
        precondition(progress(Array(complete.dropLast()), now: date(10, 16)).claimableWeeks.isEmpty)
        precondition(progress(complete, now: date(10, 16), claimed: ["2026-10-05"]).claimableWeeks.isEmpty)
        precondition(progress(complete, now: date(10, 16), claimed: ["2026-10-04"]).claimableWeeks.isEmpty)
        precondition(progress(complete, now: date(10, 11), claimed: ["2026-10-05"]).currentWeek.isClaimed)
        precondition(progress(activities(from: date(10, 12)), now: date(10, 16)).claimableWeeks.isEmpty)
        var duplicated = complete
        duplicated.insert(.init(date: complete[0].date, completedCount: 0), at: 0)
        precondition(progress(duplicated, now: date(10, 16)).claimableWeeks.count == 1)
        for start in [date(3, 23), date(10, 19)] {
            let days = activities(from: start)
            precondition(progress(days, now: days.last!.date).claimableWeeks.count == 1)
        }
        precondition(progress(activities(from: date(12, 28)), now: date(1, 3, year: 2027))
            .claimableWeeks.first?.key == "2026-12-28")
        for locale in ["cs", "sk", "en"] {
            var localized = calendar
            localized.locale = Locale(identifier: locale)
            localized.firstWeekday = 2 // persisted reward policy, applied after locale
            precondition(progress(complete, now: date(10, 16), cal: localized)
                .claimableWeeks.map(\.key) == ["2026-10-05"])
        }
        let emptyMonday = progress([], now: date(10, 12)).currentWeek
        precondition(!emptyMonday.hasMissedDay)
        precondition(progress([], now: date(10, 13)).currentWeek.hasMissedDay)
        print("PASS: complete, missing, claimed, future, duplicate, DST, year boundary, language and missed-day cases")
    }
}
