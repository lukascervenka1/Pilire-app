import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \DayRecord.date) private var records: [DayRecord]
    @Query private var settingsList: [UserSettings]
    @Environment(\.modelContext) private var ctx
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayMonth = Calendar.current.startOfDay(for: .now)
    @State private var selectedRecord: DayRecord?
    @State private var claimedReward: ChestReward?
    @State private var pulse: CGFloat = 1

    private let cal: Calendar = {
        var c = Calendar.current
        c.locale = Language.shared.current.locale
        return c
    }()

    private static let weekKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthHeader
                    statsRow
                    calendarCard
                    chestBanner
                    legendRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.creamGradient.ignoresSafeArea())
            .navigationTitle(L(S.calendar.title))
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedRecord) { rec in
            if let b = rec.buildings.first {
                CalendarBuildingSheet(record: rec, building: b)
            } else {
                CalendarDaySheet(record: rec)
            }
        }
        .overlay {
            if let reward = claimedReward {
                ChestRewardOverlay(reward: reward) {
                    withAnimation(.easeOut(duration: 0.25)) { claimedReward = nil }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        HStack {
            monthButton("chevron.left") { shiftMonth(-1) }
            Spacer()
            Text(displayMonth, format: .dateTime.month(.wide).year().locale(Language.shared.current.locale))
                .font(.system(.headline, design: .rounded))
                .textCase(nil)
                .contentTransition(.numericText())
            Spacer()
            monthButton("chevron.right") { shiftMonth(1) }
        }
    }

    private func monthButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accentBottom)
                .frame(width: 44, height: 44)
                .background(Theme.panel, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Month stats

    private var statsRow: some View {
        let s = monthStats
        return HStack(spacing: 10) {
            statChip(value: s.active, label: L(S.calendar.activeDays), symbol: "flame.fill", tint: .orange)
            statChip(value: s.full, label: L(S.calendar.allDone), symbol: "checkmark.seal.fill", tint: .green)
            statChip(value: s.buildings, label: s.buildings == 1 ? L(S.calendar.building) : L(S.calendar.buildings), symbol: "house.fill", tint: Color(red: 0.58, green: 0.42, blue: 0.25))
        }
    }

    private func statChip(value: Int, label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
    }

    private var monthStats: (active: Int, full: Int, buildings: Int) {
        let monthRecords = records.filter { cal.isDate($0.date, equalTo: displayMonth, toGranularity: .month) }
        let active = monthRecords.filter { $0.completedCount > 0 }.count
        let full = monthRecords.filter { !$0.pillars.isEmpty && $0.completedCount == $0.pillars.count }.count
        let buildings = monthRecords.reduce(0) { $0 + $1.buildings.count }
        return (active, full, buildings)
    }

    // MARK: - Grid

    private var calendarCard: some View {
        VStack(spacing: 8) {
            weekdayRow
            calendarGrid
        }
        .padding(12)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(shortWeekdays, id: \.self) { d in
                Text(d)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.creamLabel)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        // Index-based IDs: the leading/trailing padding cells are all `nil`, so
        // `id: \.self` would repeat nil and give SwiftUI duplicate IDs.
        let byDay = recordsByDay
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    let rec = byDay[cal.startOfDay(for: date)]
                    DayCell(date: date, record: rec, isToday: cal.isDateInToday(date))
                        .onTapGesture { if let r = rec { selectedRecord = r } }
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    // MARK: - Weekly chest

    /// All weeks that are fully done (a pillar every day) and not yet claimed,
    /// oldest first.
    private var claimableWeeks: [(key: String, start: Date)] {
        guard let settings = settingsList.first else { return [] }
        let today = cal.startOfDay(for: .now)
        let byDay = recordsByDay
        let weekStarts = Set(records.compactMap { rec -> Date? in
            cal.dateInterval(of: .weekOfYear, for: rec.date).map { cal.startOfDay(for: $0.start) }
        })
        return weekStarts.compactMap { start -> (key: String, start: Date)? in
            guard start <= today else { return nil }
            let key = Self.weekKeyFormatter.string(from: start)
            guard !settings.claimedWeekKeys.contains(key) else { return nil }
            let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            let allDone = days.allSatisfy { (byDay[cal.startOfDay(for: $0)]?.completedCount ?? 0) > 0 }
            return allDone ? (key, start) : nil
        }
        .sorted { $0.start < $1.start }
    }

    /// Days of the current week that already have a pillar done (0…7).
    private var currentWeekProgress: Int {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
        let start = cal.startOfDay(for: interval.start)
        let today = cal.startOfDay(for: .now)
        let byDay = recordsByDay
        return (0..<7)
            .compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { $0 <= today }
            .filter { (byDay[cal.startOfDay(for: $0)]?.completedCount ?? 0) > 0 }
            .count
    }

    private func claimChest(key: String) {
        guard let settings = settingsList.first,
              let reward = settings.claimWeeklyChest(weekKey: key)
        else { return }
        ctx.saveChanges()
        Haptics.success()
        withAnimation(.spring(duration: 0.4)) {
            claimedReward = reward
        }
    }

    @ViewBuilder
    private var chestBanner: some View {
        let ready = claimableWeeks.count
        Button {
            if let first = claimableWeeks.first { claimChest(key: first.key) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(ready > 0 ? AnyShapeStyle(Theme.accentGradient)
                                        : AnyShapeStyle(Color.primary.opacity(0.10)))
                        .frame(width: 44, height: 44)
                    Image(systemName: "gift.fill")
                        .font(.title3)
                        .foregroundStyle(ready > 0 ? .white : Theme.creamLabel)
                        .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1.1)),
                                      isActive: ready > 0 && !reduceMotion)
                }
                .scaleEffect(ready > 0 && !reduceMotion ? pulse : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ready > 0
                         ? (ready == 1 ? L(S.calendar.chestReady) : L(S.calendar.chestReadyMany, ready))
                         : L(S.calendar.chestTitle))
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(ready > 0 ? Theme.accentBottom : .primary)
                    Text(bannerSubtitle(ready: ready))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.creamLabel)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if ready > 0 {
                    Text(L(S.calendar.open))
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.accentGradient, in: Capsule())
                }
            }
            .padding(12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(ready > 0 ? Theme.accentBottom.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(ready == 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                pulse = 1.08
            }
        }
    }

    private func bannerSubtitle(ready: Int) -> String {
        if ready > 1 { return L(S.calendar.chestHintMany) }
        if ready == 1 { return L(S.calendar.chestHintOne) }
        return L(S.calendar.chestHintProgress, currentWeekProgress)
    }

    // MARK: - Legend

    private var legendRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                legendSquare(fill: DayCell.fullColor, label: L(S.calendar.legendAllDone))
                legendSquare(fill: Color.orange.opacity(0.30), label: L(S.calendar.legendPartly))
                legendSquare(fill: Color.primary.opacity(0.05), label: L(S.calendar.legendNothing))
            }
            HStack(spacing: 14) {
                legendDot(color: Color(red: 0.58, green: 0.42, blue: 0.25), label: L(S.calendar.legendBuilding))
                legendDot(color: .indigo, label: L(S.calendar.legendHabit))
            }
        }
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Theme.creamLabel)
        .padding(.top, 2)
    }

    private func legendSquare(fill: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 12, height: 12)
            Text(label)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Helpers

    private var shortWeekdays: [String] {
        let syms = cal.shortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private func daysInMonth() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: displayMonth),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: displayMonth))
        else { return [] }

        let weekday = cal.component(.weekday, from: firstDay)
        let offset  = (weekday - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)

        for d in range {
            days.append(cal.date(byAdding: .day, value: d - 1, to: firstDay))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    /// Records keyed by day. The grid and the weekly-chest check look up dozens
    /// of dates per redraw; scanning the whole history for each one got slower
    /// every month the player kept going.
    private var recordsByDay: [Date: DayRecord] {
        Dictionary(records.map { (cal.startOfDay(for: $0.date), $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: displayMonth) {
            displayMonth = d
        }
    }
}

// MARK: - Day cell

struct DayCell: View {
    let date: Date
    let record: DayRecord?
    let isToday: Bool

    /// Soft Duolingo-like green for fully completed days.
    static let fullColor = Color(red: 0.42, green: 0.72, blue: 0.44)

    private var cal: Calendar { .current }

    private var ratio: Double? {
        guard let rec = record, !rec.pillars.isEmpty else { return nil }
        return Double(rec.completedCount) / Double(rec.pillars.count)
    }

    private var isFull: Bool { ratio == 1 }
    private var isFuture: Bool { date > cal.startOfDay(for: .now) && !isToday }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(cal.component(.day, from: date))")
                .font(.system(.subheadline, design: .rounded).weight(isToday || isFull ? .bold : .medium))
                .foregroundStyle(numberColor)

            HStack(spacing: 3) {
                if let rec = record {
                    if !rec.buildings.isEmpty {
                        Circle()
                            .fill(isFull ? Color.white : Color(red: 0.58, green: 0.42, blue: 0.25))
                            .frame(width: 4, height: 4)
                    }
                    if rec.pillars.contains(where: { $0.isHabit && $0.isCompleted }) {
                        Circle()
                            .fill(isFull ? Color.white.opacity(0.7) : Color.indigo)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(cellFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isToday ? Color.orange : Color.clear, lineWidth: 2)
        )
    }

    private var numberColor: Color {
        if isFull { return .white }
        if isFuture { return Color.primary.opacity(0.30) }
        return .primary
    }

    private var cellFill: Color {
        guard let r = ratio else { return Color.primary.opacity(record == nil ? 0.03 : 0.05) }
        if r == 1 { return Self.fullColor }
        if r > 0  { return Color.orange.opacity(0.14 + 0.22 * r) }
        return Color.primary.opacity(0.05)
    }
}

// MARK: - Detail sheets

struct CalendarBuildingSheet: View {
    let record: DayRecord
    let building: Building
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(accentColor.opacity(0.12)).frame(width: 110, height: 110)
                        Text(building.type.emoji).font(.system(size: 52))
                    }.padding(.top, 16)

                    VStack(spacing: 4) {
                        Text(building.type.displayName).font(.title2.bold())
                        Text(record.date, format: Date.FormatStyle(date: .long))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    Divider()

                    if !record.pillars.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L(S.calendar.dayPillars)).font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(record.pillars.sorted(by: { $0.order < $1.order })) { p in
                                HStack(spacing: 10) {
                                    Image(systemName: p.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(p.isCompleted ? Color.green : Color.secondary)
                                    Text(p.text)
                                }
                            }
                        }.padding(.horizontal)
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal)
            }
            .navigationTitle(building.type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
        }
    }

    private var accentColor: Color {
        let c = building.type.skColorRGB
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

struct CalendarDaySheet: View {
    let record: DayRecord
    @Environment(\.dismiss) private var dismiss

    private var doneCount: Int { record.completedCount }
    private var totalCount: Int { record.pillars.count }
    private var ratio: Double {
        totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    progressRing
                        .padding(.top, 16)

                    Text(headline)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.creamLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if record.pillars.contains(where: { $0.isHabit && $0.isCompleted }) {
                        Label(L(S.calendar.habitDone), systemImage: "repeat")
                            .font(.system(.caption, design: .rounded).bold())
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.indigo.opacity(0.10), in: Capsule())
                    }

                    if !record.pillars.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L(S.calendar.dayPillars))
                                .font(.system(.headline, design: .rounded))
                            ForEach(record.pillars.sorted(by: { $0.order < $1.order })) { p in
                                HStack(spacing: 10) {
                                    Image(systemName: p.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(p.isCompleted ? DayCell.fullColor : Color.secondary)
                                    Text(p.text)
                                        .foregroundStyle(p.isCompleted ? Color.primary : Color.secondary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 24)
                }
            }
            .background(Theme.creamGradient.ignoresSafeArea())
            .navigationTitle(record.date.formatted(Date.FormatStyle(date: .long)
                .locale(Language.shared.current.locale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(ratio == 1 ? DayCell.fullColor : Color.orange,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(doneCount)/\(totalCount)")
                    .font(.system(.title2, design: .rounded).bold())
                Text(L(S.calendar.pillarsLabel))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
            }
        }
        .frame(width: 110, height: 110)
        .accessibilityLabel(L(S.calendar.doneOf, doneCount, totalCount))
    }

    private var headline: String {
        if totalCount == 0 { return L(S.calendar.noPillarsDay) }
        if ratio == 1 { return L(S.calendar.perfectDay) }
        if ratio > 0 { return L(S.calendar.partialDay) }
        return L(S.calendar.emptyDay)
    }
}

// MARK: - Chest reward reveal

struct ChestRewardOverlay: View {
    let reward: ChestReward
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var rarityColor: Color {
        switch reward.rarity {
        case .common: return Theme.accentBottom
        case .rare:   return Color(red: 0.36, green: 0.62, blue: 0.86)
        case .epic:   return Color(red: 0.86, green: 0.66, blue: 0.20)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(rarityColor.opacity(0.18))
                        .frame(width: 150, height: 150)
                    Circle()
                        .fill(rarityColor.opacity(0.28))
                        .frame(width: 110, height: 110)
                        .scaleEffect(shown ? 1 : 0.4)
                    Image(systemName: "gift.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(rarityColor)
                        .scaleEffect(shown ? 1 : 0.3)
                        .rotationEffect(.degrees(shown ? 0 : -12))
                        .symbolEffect(.bounce, value: shown)
                }

                VStack(spacing: 6) {
                    Text(reward.rarity.title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(rarityColor)
                    Text(reward.label)
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .opacity(shown ? 1 : 0)

                Button(action: onDismiss) {
                    Text(L(S.calendar.nice))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(rarityColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .opacity(shown ? 1 : 0)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color(red: 0.20, green: 0.17, blue: 0.13), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .scaleEffect(shown ? 1 : 0.85)
            .padding(.horizontal, 40)
        }
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(S.calendar.gotReward, reward.rarity.title, reward.label))
    }
}

