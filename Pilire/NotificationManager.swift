import UserNotifications

struct NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func scheduleDailyReminders(morningHour: Int = 8, eveningHour: Int = 20) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning", "evening"])

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            schedule(id: "morning", hour: morningHour, minute: 0,
                     title: "Jaké budou tvoje dnešní pilíře? 🏗",
                     body: "Nastav si 1–5 cílů a postav budovu.")
            schedule(id: "evening", hour: eveningHour, minute: 0,
                     title: "Nezapomněl jsi uzavřít den? 🌙",
                     body: "Odškrtni splněné pilíře a uzavři den.")
        }
    }

    // MARK: - User preferences (default: on)

    static var habitRemindersEnabled: Bool {
        UserDefaults.standard.object(forKey: "notifHabitsEnabled") as? Bool ?? true
    }
    static var taskRemindersEnabled: Bool {
        UserDefaults.standard.object(forKey: "notifTasksEnabled") as? Bool ?? true
    }

    /// Remove pending notifications whose identifier starts with a prefix.
    static func removePending(prefix: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Habit reminders (gentle, Duolingo-like but never pushy)

    private static let gentleBodies = [
        "Žádný spěch, klidně až se to bude hodit.",
        "Malý krok stačí. Město roste s tebou.",
        "Jen jemné připomenutí, nic víc.",
        "Klidně jen minutku. I ta se počítá.",
        "Zkus to, až budeš mít chvilku.",
    ]

    /// Re-plans one-shot habit reminders for the next 7 days.
    /// Skips today's reminder when the habit is already done — no pointless pings.
    static func syncHabitReminders(habits: [Habit], completedTodayTexts: Set<String>) {
        struct Planned {
            let id: String
            let title: String
            let body: String
            let comps: DateComponents
        }

        var planned: [Planned] = []
        if habitRemindersEnabled {
            let cal = Calendar.current
            let now = Date.now
            for habit in habits where habit.isActive {
                guard let mins = habit.reminderMinutes else { continue }
                let key = habit.createdDate.timeIntervalSince1970
                for offset in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                          habit.isScheduled(on: day),
                          let fire = cal.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: day),
                          fire > now
                    else { continue }
                    if offset == 0 && completedTodayTexts.contains(habit.text) { continue }

                    planned.append(Planned(
                        id: "habit-\(key)-\(offset)",
                        title: "🌿 \(habit.text)",
                        body: gentleBodies[(habit.text.count + offset) % gentleBodies.count],
                        comps: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    ))
                }
            }
        }

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let old = reqs.map(\.identifier).filter { $0.hasPrefix("habit-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for p in planned {
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body  = p.body
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: p.comps, repeats: false)
                center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - Per-pillar reminders (scheduled tasks)

    static func schedulePillarReminder(id: UUID, text: String, date: Date) {
        guard taskRemindersEnabled, date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(text)"
        content.body  = "Naplánovaný pilíř, máš na něj čas?"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "pillar-\(id.uuidString)",
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelPillarReminder(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["pillar-\(id.uuidString)"])
    }

    private static func schedule(id: String, hour: Int, minute: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
