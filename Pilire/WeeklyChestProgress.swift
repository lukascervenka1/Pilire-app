import Foundation

/// Reward periods use their own persisted first weekday, independently of UI language.
struct WeeklyChestProgress {
    struct Activity {
        let date: Date
        let completedCount: Int
    }

    struct Day: Identifiable {
        let date: Date
        let isComplete: Bool
        let isFuture: Bool
        var id: Date { date }
    }

    struct Week: Identifiable {
        let key: String
        let start: Date
        let days: [Day]
        let isClaimed: Bool
        var id: String { key }
        var completedCount: Int { days.filter(\.isComplete).count }
        var isReady: Bool { days.count == 7 && days.allSatisfy { $0.isComplete && !$0.isFuture } }
        var hasMissedDay: Bool { days.contains { !$0.isComplete && !$0.isFuture && $0.date < today } }
        let today: Date
    }

    let currentWeek: Week
    let claimableWeeks: [Week]

    init(activities: [Activity], claimedKeys: [String], calendar: Calendar, now: Date) {
        let today = calendar.startOfDay(for: now)
        let completed = Set(activities.filter { $0.completedCount > 0 }
            .map { calendar.startOfDay(for: $0.date) })
        let claimed = Set(claimedKeys)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let claimedPeriods = claimedKeys.compactMap { key -> DateInterval? in
            guard let start = formatter.date(from: key),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }

        func week(start: Date) -> Week {
            let key = formatter.string(from: start)
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                .map { date in
                    Day(date: date, isComplete: completed.contains(date), isFuture: date > today)
                }
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            // Older versions could claim overlapping weeks after a language change.
            let alreadyRewarded = claimed.contains(key) || claimedPeriods.contains {
                start < $0.end && end > $0.start
            }
            return Week(key: key, start: start, days: days, isClaimed: alreadyRewarded, today: today)
        }

        let currentStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        currentWeek = week(start: calendar.startOfDay(for: currentStart))
        let starts = Set(activities.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start
        })
        claimableWeeks = starts.map { week(start: calendar.startOfDay(for: $0)) }
            .filter { $0.isReady && !$0.isClaimed }
            .sorted { $0.start < $1.start }
    }
}
