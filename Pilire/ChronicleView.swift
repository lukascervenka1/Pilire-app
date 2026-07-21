import SwiftUI
import SwiftData

// MARK: - Kronika — searchable history of days, tasks and buildings

struct ChronicleView: View {
    @Query(sort: \DayRecord.date, order: .reverse) private var records: [DayRecord]
    @State private var search = ""
    @State private var selectedRecord: DayRecord?

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            Group {
                if grouped.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Zatím prázdno" : "Nic nenalezeno",
                        systemImage: search.isEmpty ? "book.closed" : "magnifyingglass",
                        description: Text(search.isEmpty
                            ? "Sem se zapíše každý uzavřený den. Uvidíš, co jsi splnil a co jsi za to postavil."
                            : "Zkus jiný výraz.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
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
                }
            }
            .navigationTitle("Kronika")
            .searchable(text: $search, prompt: "Hledat v tascích")
        }
        .sheet(item: $selectedRecord) { rec in
            if let b = rec.buildings.first {
                CalendarBuildingSheet(record: rec, building: b)
            } else {
                CalendarDaySheet(record: rec)
            }
        }
    }

    private func monthHeader(_ d: Date, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(monthTitle(d))
                .font(.system(.title3, design: .rounded).bold())
            Text("\(count) \(count == 1 ? "den" : (count >= 2 && count <= 4 ? "dny" : "dnů"))")
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
        let nonEmpty = records.filter { !$0.pillars.isEmpty || !$0.buildings.isEmpty }
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
            .locale(Locale(identifier: "cs"))).capitalized
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
            Text(record.date, format: .dateTime.day().locale(Locale(identifier: "cs")))
                .font(.system(.title2, design: .rounded).bold())
                .monospacedDigit()
            Text(record.date, format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "cs")))
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
        return texts.isEmpty ? "Bez pilířů" : texts.joined(separator: " · ")
    }
}
