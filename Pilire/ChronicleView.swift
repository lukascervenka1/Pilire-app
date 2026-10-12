import SwiftUI
import SwiftData

// MARK: - Kronika — searchable history of days, tasks and buildings

struct ChronicleView: View {
    @Query(sort: \DayRecord.date, order: .reverse) private var records: [DayRecord]
    @Query(sort: \Building.builtDate)              private var buildings: [Building]
    @Query(sort: \PlacedDecoration.placedDate)     private var decorations: [PlacedDecoration]
    @Query(sort: \OwnedAnimal.boughtDate)          private var animals: [OwnedAnimal]
    @Query(sort: \Habit.createdDate)               private var habits: [Habit]
    @Query                                         private var settingsList: [UserSettings]

    @State private var search = ""
    @State private var selectedRecord: DayRecord?
    @State private var showAchievements = false

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    // Badges sit above the history: the Kronika should open on
                    // how far you've come, not on a wall of dates. Hidden while
                    // searching, when the only thing that matters is the hits.
                    if search.isEmpty {
                        AchievementsCard(progress: achievements) { showAchievements = true }
                            .padding(.top, 4)
                    }

                    if grouped.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? L(S.chronicle.emptyTitle) : L(S.chronicle.noResults),
                            systemImage: search.isEmpty ? "book.closed" : "magnifyingglass",
                            description: Text(search.isEmpty
                                ? L(S.chronicle.emptyBody)
                                : L(S.chronicle.tryAnother))
                        )
                        .padding(.top, 24)
                    }

                    ForEach(grouped, id: \.month) { group in
                        Section {
                            VStack(spacing: 10) {
                                ForEach(group.days, id: \.persistentModelID) { rec in
                                    Button { selectedRecord = rec } label: {
                                        ChronicleCard(record: rec)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            monthHeader(group.month, count: group.days.count)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.creamGradient.ignoresSafeArea())
            .navigationTitle(L(S.tabs.chronicle))
            .searchable(text: $search, prompt: L(S.chronicle.searchPrompt))
        }
        .sheet(item: $selectedRecord) { rec in
            if let b = rec.buildings.first {
                CalendarBuildingSheet(record: rec, building: b)
            } else {
                CalendarDaySheet(record: rec)
            }
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView(progress: achievements)
        }
    }

    private var achievements: [AchievementProgress] {
        Achievements.progress(
            Achievements.stats(records: records, buildings: buildings,
                               decorations: decorations, animals: animals,
                               habits: habits, settings: settingsList.first),
            seen: Set(settingsList.first?.seenAchievements ?? [])
        )
    }

    private func monthHeader(_ d: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(monthTitle(d))
                .font(.system(.title3, design: .rounded).bold())
            Text(S.chronicle.days(count))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.panel, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 6)
        .background(Theme.creamTop.opacity(0.92))
    }

    // MARK: - Grouping & filtering

    private var filtered: [DayRecord] {
        // Days planned ahead aren't history yet, so they stay out of the chronicle.
        let today = cal.startOfDay(for: .now)
        let nonEmpty = records.filter {
            (!$0.pillars.isEmpty || !$0.buildings.isEmpty) && cal.startOfDay(for: $0.date) <= today
        }
        guard !search.isEmpty else { return nonEmpty }
        return nonEmpty.filter { rec in
            rec.pillars.contains { $0.text.localizedStandardContains(search) }
        }
    }

    private var grouped: [(month: Date, days: [DayRecord])] {
        let dict = Dictionary(grouping: filtered) { rec in
            cal.date(from: cal.dateComponents([.year, .month], from: rec.date)) ?? rec.date
        }
        return dict.keys.sorted(by: >).map { (month: $0, days: dict[$0] ?? []) }
    }

    private func monthTitle(_ d: Date) -> String {
        d.formatted(.dateTime.month(.wide).year()
            .locale(Language.shared.current.locale)).capitalized
    }
}

// MARK: - Card

private struct ChronicleCard: View {
    let record: DayRecord

    private var total: Int { record.pillars.count }
    private var done: Int { record.completedCount }
    private var ratio: Double { total == 0 ? 0 : Double(done) / Double(total) }
    private var isFull: Bool { total > 0 && done == total }

    var body: some View {
        HStack(spacing: 14) {
            dateBlock

            VStack(alignment: .leading, spacing: 6) {
                Text(summaryText)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    progressBadge
                    if !record.buildings.isEmpty {
                        buildingChip
                    }
                    if record.pillars.contains(where: { $0.isHabit && $0.isCompleted }) {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Theme.creamLabel.opacity(0.6))
        }
        .padding(12)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(isFull ? DayCell.fullColor : (done > 0 ? Color.orange : Color.primary.opacity(0.12)))
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 2)
        }
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(record.date, format: .dateTime.day().locale(Language.shared.current.locale))
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
            Text(record.date, format: .dateTime.weekday(.abbreviated).locale(Language.shared.current.locale))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
        }
        .frame(width: 42)
    }

    private var progressBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: isFull ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption2)
                .foregroundStyle(isFull ? DayCell.fullColor : (done > 0 ? .orange : .secondary))
            Text("\(done)/\(total)")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.creamLabel)
        }
    }

    private var buildingChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.58, green: 0.42, blue: 0.25))
            Text("\(record.buildings.count)")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(red: 0.58, green: 0.42, blue: 0.25))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(red: 0.58, green: 0.42, blue: 0.25).opacity(0.12), in: Capsule())
    }

    private var summaryText: String {
        let texts = record.pillars.sorted { $0.order < $1.order }.map(\.text)
        return texts.isEmpty ? L(S.chronicle.noPillars) : texts.joined(separator: " · ")
    }
}
