import SwiftUI
import SwiftData

struct CalendarView: View {
    @Query(sort: \DayRecord.date) private var records: [DayRecord]
    @Query private var settingsList: [UserSettings]
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @State private var displayMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedRecord: DayRecord?
    @State private var claimedChest: WeeklyChestReceipt?
    @State private var rewardSaveError = false
    @State private var isClaiming = false
    @State private var now = Date.now

    private let cal: Calendar = {
        var c = Calendar.current
        c.locale = Language.shared.current.locale
        // Monday first, like the reward week; the device region may say Sunday.
        c.firstWeekday = WeeklyChestClaims.weekStartsOn
        return c
    }()

    private var rewardCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = settingsList.first.map {
            WeeklyChestClaims.firstWeekday(in: $0, legacyCalendar: cal)
        } ?? cal.firstWeekday
        return calendar
    }

    private var weeklyProgress: WeeklyChestProgress {
        WeeklyChestProgress(activities: records.map { .init(date: $0.date, completedCount: $0.completedCount) },
                            claimedKeys: settingsList.first?.claimedWeekKeys ?? [],
                            calendar: rewardCalendar, now: now)
    }

    var body: some View {
        let progress = weeklyProgress
        let week = progress.claimableWeeks.first ?? progress.currentWeek
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    WeeklyChestCard(week: week, availableCount: progress.claimableWeeks.count,
                                    rangeLabel: weekRangeLabel(from: week.start),
                                    isBusy: isClaiming, onOpen: claimChest)
                    monthHeader
                    calendarCard
                    statsRow
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
        .fullScreenCover(item: $claimedChest) { receipt in
            WeeklyChestReveal(receipt: receipt) { acknowledge(receipt) }
        }
        .alert(L(S.calendar.chestTitle), isPresented: $rewardSaveError) {
            Button(L(S.common.close), role: .cancel) { }
        } message: {
            Text(L(S.calendar.rewardSaveError))
        }
        .task(id: settingsList.first?.persistentModelID) { refreshCalendar() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCalendar() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
    }

    // MARK: - Month header

    private var monthHeader: some View {
        VStack(spacing: 2) {
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
            if !cal.isDate(displayMonth, equalTo: now, toGranularity: .month) {
                Button(L(S.calendar.today)) {
                    withAnimation(.snappy(duration: 0.25)) {
                        displayMonth = cal.dateInterval(of: .month, for: now)?.start ?? now
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accentBottom)
                .frame(minHeight: 44)
            }
        }
        .padding(.top, 8)
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
        .accessibilityLabel(symbol == "chevron.left" ? L(S.calendar.previousMonth) : L(S.calendar.nextMonth))
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
                    .font(.system(.caption2, design: .rounded))
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
        .padding(10)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
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
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    let rec = byDay[cal.startOfDay(for: date)]
                    Button {
                        selectedRecord = rec
                    } label: {
                        DayCell(date: date, record: rec, isToday: cal.isDate(date, inSameDayAs: now))
                    }
                    .buttonStyle(.plain)
                    .disabled(rec == nil)
                    .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()
                        .locale(Language.shared.current.locale)))
                    .accessibilityValue(rec.map { L(S.calendar.doneOf, $0.completedCount, $0.pillars.count) } ?? L(S.calendar.legendNothing))
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    // MARK: - Weekly chest

    private func refreshCalendar() {
        now = .now
        guard let settings = settingsList.first else { return }
        do {
            try WeeklyChestClaims.preserveWeekPolicy(in: settings, legacyCalendar: cal, context: ctx)
            if claimedChest == nil { claimedChest = try WeeklyChestClaims.pending(in: settings) }
        } catch {
            rewardSaveError = true
        }
    }

    private func claimChest() {
        guard !isClaiming, claimedChest == nil, let settings = settingsList.first else { return }
        isClaiming = true
        defer { isClaiming = false }
        do {
            claimedChest = try WeeklyChestClaims.claim(in: settings, records: records,
                                                       calendar: rewardCalendar, now: .now, context: ctx)
        } catch {
            rewardSaveError = true
            Haptics.warning()
        }
    }

    private func acknowledge(_ receipt: WeeklyChestReceipt) -> Bool {
        guard let settings = settingsList.first else { return false }
        do {
            try WeeklyChestClaims.acknowledge(receipt, in: settings, context: ctx)
            claimedChest = nil
            return true
        } catch {
            return false
        }
    }

    private func weekRangeLabel(from start: Date) -> String {
        let calendar = rewardCalendar
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateIntervalFormatter()
        formatter.locale = Language.shared.current.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = calendar.component(.year, from: start) == calendar.component(.year, from: end) ? "dMMM" : "yMMMd"
        return formatter.string(from: start, to: end)
    }

    // MARK: - Legend

    private var legendRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                legendSquare(fill: DayCell.fullFill, label: L(S.calendar.legendAllDone))
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
    @ScaledMetric(relativeTo: .subheadline) private var cellHeight: CGFloat = 46

    static let fullColor = Theme.calendarGreen
    static let fullFill = Theme.calendarSage

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
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            HStack(spacing: 3) {
                if isFull {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Self.fullColor)
                }
                if let rec = record {
                    if !rec.buildings.isEmpty {
                        Circle()
                            .fill(Color(red: 0.58, green: 0.42, blue: 0.25))
                            .frame(width: 4, height: 4)
                    }
                    if rec.pillars.contains(where: { $0.isHabit && $0.isCompleted }) {
                        Circle()
                            .fill(Color.indigo)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .background(cellFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isToday ? Color.orange : Color.clear, lineWidth: 2)
        )
    }

    private var numberColor: Color {
        if isFull { return Self.fullColor }
        if isFuture { return Color.primary.opacity(0.30) }
        return .primary
    }

    private var cellFill: Color {
        guard let r = ratio else { return Color.primary.opacity(record == nil ? 0.03 : 0.05) }
        if r == 1 { return Self.fullFill }
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
