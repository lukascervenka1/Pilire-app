import SwiftUI
import SwiftData

// MARK: - Odznaky
//
// Badges are *derived*, never stored. Everything they need already lives in the
// day records, buildings, decorations, animals and settings, so the whole list
// is recomputed from the real data. Nothing to migrate, nothing that can drift
// out of sync with reality, and a player who has been going for weeks sees the
// badges they already earned the first time they open the Kronika.
//
// The only thing persisted is *which badges have been seen*, so a new one can
// be celebrated exactly once.

// MARK: - Tiers

enum AchievementTier {
    case bronze, silver, gold, legendary

    /// Fill for an earned badge. Warm metals first, violet for the rare ones —
    /// it reads as "beyond gold" without fighting the cream palette.
    var colors: [Color] {
        switch self {
        case .bronze:
            [Color(red: 0.80, green: 0.57, blue: 0.35), Color(red: 0.60, green: 0.39, blue: 0.21)]
        case .silver:
            [Color(red: 0.79, green: 0.83, blue: 0.88), Color(red: 0.55, green: 0.60, blue: 0.67)]
        case .gold:
            [Color(red: 0.97, green: 0.80, blue: 0.36), Color(red: 0.85, green: 0.59, blue: 0.13)]
        case .legendary:
            [Color(red: 0.62, green: 0.52, blue: 0.88), Color(red: 0.39, green: 0.31, blue: 0.70)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// The darker end, for text and rings on cream.
    var ink: Color { colors[1] }

    var title: T {
        switch self {
        case .bronze:    T(cs: "Bronzový", sk: "Bronzový", en: "Bronze")
        case .silver:    T(cs: "Stříbrný", sk: "Strieborný", en: "Silver")
        case .gold:      T(cs: "Zlatý", sk: "Zlatý", en: "Gold")
        case .legendary: T(cs: "Vzácný", sk: "Vzácny", en: "Rare")
        }
    }
}

// MARK: - Groups

enum AchievementGroup: String, CaseIterable, Identifiable {
    case pillars, days, town, animals, rhythm
    var id: String { rawValue }

    var title: T {
        switch self {
        case .pillars: T(cs: "Pilíře", sk: "Piliere", en: "Pillars")
        case .days:    T(cs: "Dny a série", sk: "Dni a série", en: "Days & streaks")
        case .town:    T(cs: "Město", sk: "Mesto", en: "Your town")
        case .animals: T(cs: "Zvířata", sk: "Zvieratá", en: "Animals")
        case .rhythm:  T(cs: "Rytmus", sk: "Rytmus", en: "Rhythm")
        }
    }
}

// MARK: - One badge

struct Achievement: Identifiable {
    /// Stable key — persisted in `seenAchievements`, so never rename one.
    let id: String
    let group: AchievementGroup
    let tier: AchievementTier
    let symbol: String
    let title: T
    let detail: T
    let target: Int
    /// Which counted thing this badge watches.
    let metric: KeyPath<AchievementStats, Int>
}

/// Everything the catalogue can measure. All plain counts, so a badge is just
/// "this number reached that target" — booleans become 0/1.
struct AchievementStats {
    var completedPillars = 0
    var perfectDays = 0
    var bestDayPillars = 0
    var longestStreak = 0
    var longestPerfectStreak = 0
    var buildings = 0
    var cathedrals = 0
    var castles = 0
    var decorations = 0
    var roads = 0
    var animals = 0
    var habits = 0
    var habitPillars = 0
    var poolPillars = 0
    var chests = 0
    var mapTier = 0
    var momentum = 0
}

struct AchievementProgress: Identifiable {
    let achievement: Achievement
    let value: Int
    /// Earned at some point. Selling the castle from the inventory lowers the
    /// count, but a badge you've had is never taken back.
    var everEarned = false

    var id: String { achievement.id }
    var isUnlocked: Bool { everEarned || value >= achievement.target }
    /// 0…1 — how full the badge is drawn when still locked.
    var fraction: Double {
        guard !isUnlocked else { return 1 }
        guard achievement.target > 0 else { return 0 }
        return min(1, Double(value) / Double(achievement.target))
    }
}

// MARK: - Catalogue

enum Achievements {

    static let all: [Achievement] = [

        // ── Pilíře ────────────────────────────────────────────────────────
        Achievement(
            id: "pillar.first", group: .pillars, tier: .bronze,
            symbol: "checkmark.circle.fill",
            title: T(cs: "První pilíř", sk: "Prvý piliar", en: "First pillar"),
            detail: T(cs: "Splň svůj úplně první pilíř.",
                      sk: "Splň svoj úplne prvý piliar.",
                      en: "Complete your very first pillar."),
            target: 1, metric: \.completedPillars),
        Achievement(
            id: "pillar.10", group: .pillars, tier: .bronze,
            symbol: "list.bullet.clipboard.fill",
            title: T(cs: "Deset hotových", sk: "Desať hotových", en: "Ten done"),
            detail: T(cs: "Splň 10 pilířů.", sk: "Splň 10 pilierov.",
                      en: "Complete 10 pillars."),
            target: 10, metric: \.completedPillars),
        Achievement(
            id: "pillar.50", group: .pillars, tier: .silver,
            symbol: "square.stack.3d.up.fill",
            title: T(cs: "Padesátka", sk: "Päťdesiatka", en: "Fifty"),
            detail: T(cs: "Splň 50 pilířů.", sk: "Splň 50 pilierov.",
                      en: "Complete 50 pillars."),
            target: 50, metric: \.completedPillars),
        Achievement(
            id: "pillar.100", group: .pillars, tier: .gold,
            symbol: "trophy.fill",
            title: T(cs: "Stovka", sk: "Stovka", en: "Hundred"),
            detail: T(cs: "Splň 100 pilířů.", sk: "Splň 100 pilierov.",
                      en: "Complete 100 pillars."),
            target: 100, metric: \.completedPillars),
        Achievement(
            id: "pillar.365", group: .pillars, tier: .legendary,
            symbol: "rosette",
            title: T(cs: "Rok pilířů", sk: "Rok pilierov", en: "A year of pillars"),
            detail: T(cs: "Splň 365 pilířů. Za každý den v roce jeden.",
                      sk: "Splň 365 pilierov. Za každý deň v roku jeden.",
                      en: "Complete 365 pillars. One for every day of the year."),
            target: 365, metric: \.completedPillars),

        // ── Dny a série ───────────────────────────────────────────────────
        Achievement(
            id: "day.perfect", group: .days, tier: .bronze,
            symbol: "checkmark.seal.fill",
            title: T(cs: "Čistý stůl", sk: "Čistý stôl", en: "Clean slate"),
            detail: T(cs: "Splň v jednom dni všechno, co sis dal.",
                      sk: "Splň v jeden deň všetko, čo si si dal.",
                      en: "Finish everything you set for a single day."),
            target: 1, metric: \.perfectDays),
        Achievement(
            id: "day.perfect10", group: .days, tier: .silver,
            symbol: "sparkles",
            title: T(cs: "Deset čistých dnů", sk: "Desať čistých dní",
                     en: "Ten clean days"),
            detail: T(cs: "Deset dnů, kdy jsi splnil úplně všechno.",
                      sk: "Desať dní, keď si splnil úplne všetko.",
                      en: "Ten days where you finished the lot."),
            target: 10, metric: \.perfectDays),
        Achievement(
            id: "day.perfectWeek", group: .days, tier: .gold,
            symbol: "star.fill",
            title: T(cs: "Bezchybný týden", sk: "Bezchybný týždeň",
                     en: "Flawless week"),
            detail: T(cs: "Sedm dnů po sobě, každý splněný do posledního pilíře.",
                      sk: "Sedem dní po sebe, každý splnený do posledného piliera.",
                      en: "Seven days in a row, every one finished to the last pillar."),
            target: 7, metric: \.longestPerfectStreak),
        Achievement(
            id: "day.big", group: .days, tier: .silver,
            symbol: "bolt.fill",
            title: T(cs: "Nabitý den", sk: "Nabitý deň", en: "Packed day"),
            detail: T(cs: "Splň 5 pilířů během jediného dne.",
                      sk: "Splň 5 pilierov počas jediného dňa.",
                      en: "Complete 5 pillars in one day."),
            target: 5, metric: \.bestDayPillars),
        Achievement(
            id: "streak.3", group: .days, tier: .bronze,
            symbol: "flame.fill",
            title: T(cs: "Tři dny v kuse", sk: "Tri dni v kuse",
                     en: "Three days running"),
            detail: T(cs: "Tři dny po sobě aspoň jeden splněný pilíř.",
                      sk: "Tri dni po sebe aspoň jeden splnený piliar.",
                      en: "Three days in a row with at least one pillar done."),
            target: 3, metric: \.longestStreak),
        Achievement(
            id: "streak.7", group: .days, tier: .silver,
            symbol: "flame.fill",
            title: T(cs: "Týden v kuse", sk: "Týždeň v kuse", en: "A week running"),
            detail: T(cs: "Sedm dnů po sobě aspoň jeden splněný pilíř.",
                      sk: "Sedem dní po sebe aspoň jeden splnený piliar.",
                      en: "Seven days in a row with at least one pillar done."),
            target: 7, metric: \.longestStreak),
        Achievement(
            id: "streak.14", group: .days, tier: .gold,
            symbol: "flame.fill",
            title: T(cs: "Čtrnáct dní v kuse", sk: "Štrnásť dní v kuse",
                     en: "Fourteen days running"),
            detail: T(cs: "Dva týdny bez vynechání.",
                      sk: "Dva týždne bez vynechania.",
                      en: "Two weeks without missing one."),
            target: 14, metric: \.longestStreak),
        Achievement(
            id: "streak.30", group: .days, tier: .legendary,
            symbol: "flame.fill",
            title: T(cs: "Měsíc v kuse", sk: "Mesiac v kuse", en: "A month running"),
            detail: T(cs: "Třicet dnů po sobě. To už je zvyk.",
                      sk: "Tridsať dní po sebe. To už je zvyk.",
                      en: "Thirty days in a row. That is a habit now."),
            target: 30, metric: \.longestStreak),
        Achievement(
            id: "streak.100", group: .days, tier: .legendary,
            symbol: "medal.fill",
            title: T(cs: "Sto dní v kuse", sk: "Sto dní v kuse",
                     en: "A hundred days running"),
            detail: T(cs: "Sto dnů po sobě. Klobouk dolů.",
                      sk: "Sto dní po sebe. Klobúk dole.",
                      en: "A hundred days in a row. Hats off."),
            target: 100, metric: \.longestStreak),

        // ── Město ─────────────────────────────────────────────────────────
        Achievement(
            id: "build.first", group: .town, tier: .bronze,
            symbol: "hammer.fill",
            title: T(cs: "První budova", sk: "Prvá budova", en: "First building"),
            detail: T(cs: "Postav na ostrově cokoli.",
                      sk: "Postav na ostrove čokoľvek.",
                      en: "Put anything on the island."),
            target: 1, metric: \.buildings),
        Achievement(
            id: "build.5", group: .town, tier: .bronze,
            symbol: "house.fill",
            title: T(cs: "Vesnička", sk: "Dedinka", en: "A hamlet"),
            detail: T(cs: "Postav 5 budov.", sk: "Postav 5 budov.",
                      en: "Build 5 buildings."),
            target: 5, metric: \.buildings),
        Achievement(
            id: "build.15", group: .town, tier: .silver,
            symbol: "building.2.fill",
            title: T(cs: "Městečko", sk: "Mestečko", en: "A small town"),
            detail: T(cs: "Postav 15 budov.", sk: "Postav 15 budov.",
                      en: "Build 15 buildings."),
            target: 15, metric: \.buildings),
        Achievement(
            id: "build.30", group: .town, tier: .gold,
            symbol: "building.columns.fill",
            title: T(cs: "Město", sk: "Mesto", en: "A city"),
            detail: T(cs: "Postav 30 budov.", sk: "Postav 30 budov.",
                      en: "Build 30 buildings."),
            target: 30, metric: \.buildings),
        Achievement(
            id: "build.cathedral", group: .town, tier: .gold,
            symbol: "star.circle.fill",
            title: T(cs: "Katedrála", sk: "Katedrála", en: "The cathedral"),
            detail: T(cs: "Postav katedrálu. Není zrovna levná.",
                      sk: "Postav katedrálu. Nie je práve lacná.",
                      en: "Build the cathedral. It does not come cheap."),
            target: 1, metric: \.cathedrals),
        Achievement(
            id: "build.castle", group: .town, tier: .legendary,
            symbol: "crown.fill",
            title: T(cs: "Hrad na kopci", sk: "Hrad na kopci",
                     en: "Castle on the hill"),
            detail: T(cs: "Postav hrad, korunu celého ostrova.",
                      sk: "Postav hrad, korunu celého ostrova.",
                      en: "Build the castle, the crown of the island."),
            target: 1, metric: \.castles),
        Achievement(
            id: "deco.first", group: .town, tier: .bronze,
            symbol: "leaf.fill",
            title: T(cs: "První dekorace", sk: "Prvá dekorácia",
                     en: "First decoration"),
            detail: T(cs: "Přidej na mapu první zeleň nebo drobnost.",
                      sk: "Pridaj na mapu prvú zeleň alebo drobnosť.",
                      en: "Add your first bit of greenery or trim."),
            target: 1, metric: \.decorations),
        Achievement(
            id: "deco.10", group: .town, tier: .silver,
            symbol: "tree.fill",
            title: T(cs: "Zahradník", sk: "Záhradník", en: "Gardener"),
            detail: T(cs: "Rozmísti po ostrově 10 dekorací.",
                      sk: "Rozmiestni po ostrove 10 dekorácií.",
                      en: "Place 10 decorations around the island."),
            target: 10, metric: \.decorations),
        Achievement(
            id: "deco.roads10", group: .town, tier: .bronze,
            symbol: "road.lanes",
            title: T(cs: "Cestář", sk: "Cestár", en: "Roadbuilder"),
            detail: T(cs: "Polož 10 dílů cesty.", sk: "Polož 10 dielov cesty.",
                      en: "Lay 10 tiles of path."),
            target: 10, metric: \.roads),
        Achievement(
            id: "map.expanded", group: .town, tier: .silver,
            symbol: "arrow.up.left.and.arrow.down.right",
            title: T(cs: "Expanze", sk: "Expanzia", en: "Room to grow"),
            detail: T(cs: "Rozšiř ostrov o kus další země.",
                      sk: "Rozšír ostrov o kus ďalšej zeme.",
                      en: "Push the island out to more land."),
            target: 1, metric: \.mapTier),

        // ── Zvířata ───────────────────────────────────────────────────────
        Achievement(
            id: "animal.first", group: .animals, tier: .bronze,
            symbol: "pawprint.fill",
            title: T(cs: "První zvíře", sk: "Prvé zviera", en: "First animal"),
            detail: T(cs: "Pořiď si prvního obyvatele se čtyřma nohama.",
                      sk: "Zaobstaraj si prvého obyvateľa so štyrmi nohami.",
                      en: "Get your first four-legged resident."),
            target: 1, metric: \.animals),
        Achievement(
            id: "animal.3", group: .animals, tier: .silver,
            symbol: "pawprint.circle.fill",
            title: T(cs: "Malá zoo", sk: "Malá zoo", en: "Little zoo"),
            detail: T(cs: "Měj na mapě 3 zvířata.",
                      sk: "Maj na mape 3 zvieratá.",
                      en: "Have 3 animals on the map."),
            target: 3, metric: \.animals),
        Achievement(
            id: "animal.6", group: .animals, tier: .gold,
            symbol: "hare.fill",
            title: T(cs: "Velká zoo", sk: "Veľká zoo", en: "Proper zoo"),
            detail: T(cs: "Měj na mapě 6 zvířat.",
                      sk: "Maj na mape 6 zvierat.",
                      en: "Have 6 animals on the map."),
            target: 6, metric: \.animals),

        // ── Rytmus ────────────────────────────────────────────────────────
        Achievement(
            id: "habit.first", group: .rhythm, tier: .bronze,
            symbol: "repeat.circle.fill",
            title: T(cs: "První návyk", sk: "Prvý návyk", en: "First habit"),
            detail: T(cs: "Založ si opakující se pilíř.",
                      sk: "Založ si opakujúci sa piliar.",
                      en: "Set up a recurring pillar."),
            target: 1, metric: \.habits),
        Achievement(
            id: "habit.30", group: .rhythm, tier: .silver,
            symbol: "arrow.triangle.2.circlepath",
            title: T(cs: "Rytmus", sk: "Rytmus", en: "In rhythm"),
            detail: T(cs: "Splň 30 pilířů, které přišly z návyku.",
                      sk: "Splň 30 pilierov, ktoré prišli z návyku.",
                      en: "Complete 30 pillars that came from a habit."),
            target: 30, metric: \.habitPillars),
        Achievement(
            id: "pool.10", group: .rhythm, tier: .silver,
            symbol: "dice.fill",
            title: T(cs: "Zkusím cokoli", sk: "Skúsim čokoľvek",
                     en: "Up for anything"),
            detail: T(cs: "Splň 10 tasků, které ti vylosovala appka.",
                      sk: "Splň 10 úloh, ktoré ti vylosovala appka.",
                      en: "Complete 10 tasks the app rolled for you."),
            target: 10, metric: \.poolPillars),
        Achievement(
            id: "momentum.max", group: .rhythm, tier: .gold,
            symbol: "gauge.high",
            title: T(cs: "Naplno", sk: "Naplno", en: "Full tilt"),
            detail: T(cs: "Vytáhni momentum na maximum.",
                      sk: "Vytiahni momentum na maximum.",
                      en: "Take your momentum all the way up."),
            target: Int(UserSettings.momentumMax), metric: \.momentum),
        Achievement(
            id: "chest.first", group: .rhythm, tier: .bronze,
            symbol: "gift.fill",
            title: T(cs: "První truhla", sk: "Prvá truhlica", en: "First chest"),
            detail: T(cs: "Otevři týdenní truhlu.",
                      sk: "Otvor týždennú truhlicu.",
                      en: "Open a weekly chest."),
            target: 1, metric: \.chests),
        Achievement(
            id: "chest.5", group: .rhythm, tier: .silver,
            symbol: "shippingbox.fill",
            title: T(cs: "Sběratel truhel", sk: "Zberateľ truhlíc",
                     en: "Chest collector"),
            detail: T(cs: "Otevři 5 týdenních truhel.",
                      sk: "Otvor 5 týždenných truhlíc.",
                      en: "Open 5 weekly chests."),
            target: 5, metric: \.chests),
    ]

    // MARK: - Measuring

    static func stats(records: [DayRecord],
                      buildings: [Building],
                      decorations: [PlacedDecoration],
                      animals: [OwnedAnimal],
                      habits: [Habit],
                      settings: UserSettings?) -> AchievementStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var s = AchievementStats()

        // Days planned ahead aren't history yet — they must not count.
        let past = records.filter { cal.startOfDay(for: $0.date) <= today }

        var activeDays: Set<Date> = []
        var perfectDaySet: Set<Date> = []

        for rec in past {
            let done = rec.completedCount
            s.completedPillars += done
            s.bestDayPillars = max(s.bestDayPillars, done)
            s.habitPillars += rec.pillars.filter { $0.isHabit && $0.isCompleted }.count
            s.poolPillars  += rec.pillars.filter { $0.isFromPool && $0.isCompleted }.count

            let day = cal.startOfDay(for: rec.date)
            if done > 0 { activeDays.insert(day) }
            if !rec.pillars.isEmpty && done == rec.pillars.count {
                perfectDaySet.insert(day)
            }
        }

        s.perfectDays = perfectDaySet.count
        s.longestStreak = longestRun(in: activeDays, cal: cal)
        s.longestPerfectStreak = longestRun(in: perfectDaySet, cal: cal)

        s.buildings  = buildings.count
        s.cathedrals = buildings.filter { $0.type == .cathedral }.count
        s.castles    = buildings.filter { $0.type == .castle }.count

        s.decorations = decorations.count
        s.roads       = decorations.filter { $0.type == .road }.count

        s.animals = animals.count
        s.habits  = habits.count

        if let settings {
            s.chests   = settings.claimedWeekKeys.count
            s.mapTier  = settings.mapTier
            s.momentum = Int(settings.momentum)
        }
        return s
    }

    /// Longest run of consecutive calendar days present in the set.
    private static func longestRun(in days: Set<Date>, cal: Calendar) -> Int {
        var longest = 0
        for day in days {
            // Only start counting from the first day of a run, so each run is
            // walked once and the whole thing stays linear.
            guard let before = cal.date(byAdding: .day, value: -1, to: day),
                  !days.contains(cal.startOfDay(for: before))
            else { continue }

            var length = 1
            var cursor = day
            while let next = cal.date(byAdding: .day, value: 1, to: cursor),
                  days.contains(cal.startOfDay(for: next)) {
                length += 1
                cursor = cal.startOfDay(for: next)
            }
            longest = max(longest, length)
        }
        return longest
    }

    static func progress(_ stats: AchievementStats, seen: Set<String> = []) -> [AchievementProgress] {
        all.map {
            AchievementProgress(achievement: $0, value: stats[keyPath: $0.metric],
                                everEarned: seen.contains($0.id))
        }
    }

    static func unlockedIDs(_ stats: AchievementStats) -> Set<String> {
        Set(all.filter { stats[keyPath: $0.metric] >= $0.target }.map(\.id))
    }
}

// MARK: - Badge shape
//
// A pointy-top hexagon: instantly reads as "award" and it is the one shape the
// app doesn't already use for resources, chests or animals.

struct HexagonShape: Shape {
    var cornerRadius: CGFloat = 6

    /// A pointy-top hexagon is exactly √3/2 as wide as it is tall. Frames built
    /// on this ratio hold the shape with no slack, so a row of badges is evenly
    /// spaced and every one sits dead centre in its cell.
    static let aspect: CGFloat = 0.8660254   // √3 / 2

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // Largest hexagon that still fits, measured against both edges — the
        // shape then fills a correctly proportioned frame completely.
        let radius = min(rect.height / 2, rect.width / (2 * Self.aspect))
        let corners = (0..<6).map { i -> CGPoint in
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            return CGPoint(x: centre.x + radius * cos(angle),
                           y: centre.y + radius * sin(angle))
        }

        var path = Path()
        let start = CGPoint(x: (corners[5].x + corners[0].x) / 2,
                            y: (corners[5].y + corners[0].y) / 2)
        path.move(to: start)
        for i in 0..<6 {
            path.addArc(tangent1End: corners[i],
                        tangent2End: corners[(i + 1) % 6],
                        radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Badge

struct AchievementBadge: View {
    let progress: AchievementProgress
    var size: CGFloat = 64

    private var tier: AchievementTier { progress.achievement.tier }

    var body: some View {
        ZStack {
            if progress.isUnlocked {
                HexagonShape(cornerRadius: size * 0.09)
                    .fill(tier.gradient)
                    .shadow(color: tier.ink.opacity(0.35), radius: size * 0.08, y: size * 0.045)
                HexagonShape(cornerRadius: size * 0.07)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
                    .padding(size * 0.09)
                Image(systemName: progress.achievement.symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: tier.ink.opacity(0.4), radius: 1, y: 1)
            } else {
                HexagonShape(cornerRadius: size * 0.09)
                    .fill(Color.primary.opacity(0.055))
                // The badge fills up from the bottom as you get closer — a
                // locked badge should still show that it's moving.
                HexagonShape(cornerRadius: size * 0.09)
                    .fill(tier.gradient)
                    .opacity(0.30)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size * progress.fraction)
                    }
                HexagonShape(cornerRadius: size * 0.09)
                    .stroke(Theme.creamLabel.opacity(0.22), lineWidth: 1)
                Image(systemName: progress.achievement.symbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(Theme.creamLabel.opacity(0.45))
            }
        }
        // Exactly the hexagon's own proportions: no slack inside the frame, so
        // `size` means the same thing everywhere the badge is used.
        .frame(width: size * HexagonShape.aspect, height: size)
        .accessibilityElement()
        .accessibilityLabel(L(progress.achievement.title))
        .accessibilityValue(progress.isUnlocked
                            ? L(S.achievements.earned)
                            : "\(progress.value)/\(progress.achievement.target)")
    }
}
