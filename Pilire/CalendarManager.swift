import EventKit

/// Write-only bridge to the user's Apple Calendar (EventKit).
/// We only ever create events — the app never reads calendar content.
@MainActor
enum CalendarManager {
    private static let store = EKEventStore()

    /// Adds a 1-hour event. Returns the event identifier on success.
    static func addEvent(title: String, start: Date, notes: String? = nil) async -> String? {
        do {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            guard granted else { return nil }

            let event = EKEvent(eventStore: store)
            event.title     = title
            event.startDate = start
            event.endDate   = start.addingTimeInterval(3600)
            event.notes     = notes
            event.calendar  = store.defaultCalendarForNewEvents
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    // MARK: - Apple Reminders (Připomínky) — recurring habit reminders

    private static let ekWeekdays: [EKWeekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    /// Creates or updates a recurring reminder for a habit.
    /// Returns the reminder identifier on success.
    static func syncHabitReminder(_ habit: Habit) async -> String? {
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { return nil }

            let reminder: EKReminder
            if let id = habit.remindersID,
               let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
                reminder = existing
                reminder.recurrenceRules?.forEach { reminder.removeRecurrenceRule($0) }
                reminder.alarms?.forEach { reminder.removeAlarm($0) }
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = store.defaultCalendarForNewReminders()
            }

            reminder.title = habit.text
            reminder.notes = L(S.notifications.habitNote)

            // First due occurrence: today (or the next scheduled day) at the habit time
            let mins = habit.reminderMinutes ?? 9 * 60
            let cal = Calendar.current
            var firstDay = cal.startOfDay(for: .now)
            for offset in 0..<7 {
                if let d = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)),
                   habit.weekdayIndices.isEmpty || habit.weekdayIndices.contains(Habit.weekdayIndex(of: d)) {
                    firstDay = d
                    break
                }
            }
            var comps = cal.dateComponents([.year, .month, .day], from: firstDay)
            comps.hour = mins / 60
            comps.minute = mins % 60
            reminder.dueDateComponents = comps

            // Recurrence: daily, or weekly on the chosen days
            if habit.weekdayIndices.isEmpty {
                reminder.addRecurrenceRule(EKRecurrenceRule(
                    recurrenceWith: .daily, interval: 1, end: nil))
            } else {
                let days = habit.weekdayIndices.map {
                    EKRecurrenceDayOfWeek(ekWeekdays[$0])
                }
                reminder.addRecurrenceRule(EKRecurrenceRule(
                    recurrenceWith: .weekly, interval: 1,
                    daysOfTheWeek: days, daysOfTheMonth: nil,
                    monthsOfTheYear: nil, weeksOfTheYear: nil,
                    daysOfTheYear: nil, setPositions: nil, end: nil))
            }
            reminder.addAlarm(EKAlarm(relativeOffset: 0))

            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Removes an exported habit reminder.
    static func removeHabitReminder(id: String) async {
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted,
                  let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
            try store.remove(reminder, commit: true)
        } catch { }
    }
}
