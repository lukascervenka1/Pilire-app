import Foundation
import SwiftData

/// Fixed time of day and weather for App Store screenshots, passed as launch
/// arguments: `-screenshotHour 14 -screenshotWeather sunny`. Debug builds only;
/// a Release build always follows the real clock and the seeded weather.
enum ScreenshotMode {
    static var hour: Int? {
        #if DEBUG
        // Launch arguments arrive as strings.
        UserDefaults.standard.string(forKey: "screenshotHour").flatMap { Int($0) }
        #else
        nil
        #endif
    }

    static var weather: TownWeather? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "screenshotWeather") {
        case "sunny": .sunny
        case "rain": .rain
        case "fog": .fog
        case "storm": .storm
        default: nil
        }
        #else
        nil
        #endif
    }

    /// `-screenshotZoom 24` opens the map pulled further back than a pinch
    /// allows, to frame the whole island for the store's lead image.
    static var zoom: Double? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "screenshotZoom").flatMap { Double($0) }
        #else
        nil
        #endif
    }

    /// The hour the town should light itself for.
    static func currentHour(at date: Date = .now) -> Int {
        hour ?? Calendar.current.component(.hour, from: date)
    }

    /// `-screenshotSeed cs|sk|en` replaces the day history with this month's
    /// worth of believable days in that language, so the calendar, chronicle
    /// and today's list look lived-in. Destructive — simulator copies only.
    static func seedIfRequested(_ container: ModelContainer) {
        #if DEBUG
        guard let code = UserDefaults.standard.string(forKey: "screenshotSeed"),
              let lang = AppLanguage(rawValue: code) else { return }
        let ctx = container.mainContext
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let t = SeedTexts(lang)

        for old in (try? ctx.fetch(FetchDescriptor<DayRecord>())) ?? [] { ctx.delete(old) }
        for old in (try? ctx.fetch(FetchDescriptor<Habit>())) ?? [] { ctx.delete(old) }

        let walk = Habit(text: t.walk, reminderMinutes: 7 * 60 + 30)
        let read = Habit(text: t.read, reminderMinutes: 21 * 60)
        for h in [walk, read] {
            h.createdDate = cal.date(byAdding: .month, value: -1, to: today) ?? today
            ctx.insert(h)
        }

        func pillar(_ text: String, _ order: Int, done: Bool, habit: Bool = false, at hour: Int? = nil) -> Pillar {
            var p = Pillar(text: text, order: order, isHabit: habit,
                           scheduledAt: hour.flatMap { cal.date(bySettingHour: $0, minute: 0, second: 0, of: today) })
            p.isCompleted = done
            p.woodAwarded = done ? 2 : 0
            return p
        }

        // Past days of this month: every one closed, the reading habit skipped
        // now and then, one weekend left out, last week complete for the chest.
        let monthStart = cal.dateInterval(of: .month, for: today)?.start ?? today
        let partial: Set<Int> = [6, 9, 13]
        let skipped: Set<Int> = [3]
        var pastDays: [DayRecord] = []
        var day = monthStart, n = 0
        while day < today {
            let dom = cal.component(.day, from: day)
            if !skipped.contains(dom) {
                let rec = DayRecord(date: day)
                var ps = [pillar(t.walk, 0, done: true, habit: true),
                          pillar(t.read, 1, done: !partial.contains(dom), habit: true)]
                for k in 0..<(1 + n % 3) {
                    ps.append(pillar(t.pool[(n * 2 + k) % t.pool.count], ps.count, done: true))
                }
                rec.pillars = ps
                rec.isCompleted = true
                ctx.insert(rec)
                pastDays.append(rec)
            }
            n += 1
            day = cal.date(byAdding: .day, value: 1, to: day) ?? today
        }

        let now = DayRecord(date: today)
        now.pillars = [pillar(t.walk, 0, done: true, habit: true),
                       pillar(t.mail, 1, done: true),
                       pillar(t.call, 2, done: true),
                       pillar(t.gym, 3, done: false, at: 18),
                       pillar(t.read, 4, done: false, habit: true)]
        ctx.insert(now)

        // Hang a few of the town's buildings on those days for the calendar dots.
        let built = ((try? ctx.fetch(FetchDescriptor<Building>(sortBy: [SortDescriptor(\.builtDate, order: .reverse)]))) ?? [])
            .filter { !$0.isStored }
        for (b, rec) in zip(built.prefix(7), stride(from: 0, to: pastDays.count, by: 2).map { pastDays[$0] }) {
            b.dayRecord = rec
            b.builtDate = cal.date(byAdding: .hour, value: 17, to: rec.date) ?? rec.date
        }

        if let settings = try? ctx.fetch(FetchDescriptor<UserSettings>()).first {
            settings.claimedWeekKeys = []
        }
        try? ctx.save()
        #endif
    }
}

#if DEBUG
private struct SeedTexts {
    let walk, read, mail, call, gym: String
    let pool: [String]

    init(_ lang: AppLanguage) {
        switch lang {
        case .cs:
            walk = "Ranní procházka"; read = "Přečíst 10 stránek"; mail = "Odpovědět na e-maily"
            call = "Zavolat babičce"; gym = "30 minut cvičení"
            pool = ["Uvařit večeři", "Uklidit pracovní stůl", "Zaplatit nájem", "Napsat Petrovi",
                    "Vyprat prádlo", "Naplánovat víkend", "Zalít květiny", "Nakoupit zeleninu",
                    "Objednat se k zubaři", "Protáhnout se po práci"]
        case .sk:
            walk = "Ranná prechádzka"; read = "Prečítať 10 strán"; mail = "Odpovedať na e-maily"
            call = "Zavolať babke"; gym = "30 minút cvičenia"
            pool = ["Uvariť večeru", "Upratať pracovný stôl", "Zaplatiť nájom", "Napísať Petrovi",
                    "Oprať bielizeň", "Naplánovať víkend", "Poliať kvety", "Nakúpiť zeleninu",
                    "Objednať sa k zubárovi", "Ponaťahovať sa po práci"]
        case .en:
            walk = "Morning walk"; read = "Read 10 pages"; mail = "Reply to emails"
            call = "Call grandma"; gym = "30 minutes of exercise"
            pool = ["Cook dinner", "Tidy up the desk", "Pay the rent", "Text Peter",
                    "Do the laundry", "Plan the weekend", "Water the plants", "Buy vegetables",
                    "Book a dentist appointment", "Stretch after work"]
        }
    }
}
#endif
