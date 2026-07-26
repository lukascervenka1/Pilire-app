import SwiftUI
import SwiftData

// MARK: - Habit — a recurring pillar that adds itself to the day

@Model
final class Habit {
    var text: String
    var weekdayIndices: [Int]   // 0 = Po … 6 = Ne; empty = every day
    var isActive: Bool = true
    var createdDate: Date = Date.now
    var reminderMinutes: Int? = nil   // minutes from midnight; nil = no reminder
    var remindersID: String? = nil    // EKReminder id, when exported to Apple Reminders

    init(text: String, weekdayIndices: [Int] = [], reminderMinutes: Int? = nil) {
        self.text = text
        self.weekdayIndices = weekdayIndices
        self.reminderMinutes = reminderMinutes
    }

    var reminderLabel: String? {
        guard let m = reminderMinutes else { return nil }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    static func minutes(from date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 8) * 60 + (c.minute ?? 0)
    }

    static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    /// Mon-first weekday index (0–6) for a date.
    static func weekdayIndex(of date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7
    }

    func isScheduled(on date: Date) -> Bool {
        guard isActive else { return false }
        return weekdayIndices.isEmpty || weekdayIndices.contains(Self.weekdayIndex(of: date))
    }

    @MainActor
    var daysSummary: String {
        guard !weekdayIndices.isEmpty else { return L(S.habits.everyDay) }
        return weekdayIndices.sorted().map { Habit.dayLabels[$0] }.joined(separator: " ")
    }

    @MainActor
    static var dayLabels: [String] { S.habits.dayLabels }
}

// MARK: - Habits management sheet

struct HabitsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.createdDate) private var habits: [Habit]

    @State private var newText = ""
    @State private var newDays: Set<Int> = []
    @State private var newReminder = false
    @State private var newTime = Habit.date(fromMinutes: 8 * 60)
    @State private var editHabit: Habit?

    var body: some View {
        NavigationStack {
            List {
                if habits.isEmpty {
                    Section {
                        Text(L(S.habits.intro))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Section(L(S.habits.mine)) {
                        ForEach(habits) { habit in
                            Button {
                                editHabit = habit
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "repeat")
                                        .font(.subheadline)
                                        .foregroundStyle(habit.isActive ? .indigo : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(habit.text)
                                            .foregroundStyle(habit.isActive ? .primary : .secondary)
                                        HStack(spacing: 6) {
                                            Text(habit.daysSummary)
                                            if let t = habit.reminderLabel {
                                                Label(t, systemImage: "bell")
                                            }
                                        }
                                        .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { habit.isActive },
                                        set: { habit.isActive = $0 }
                                    ))
                                    .labelsHidden()
                                    .tint(.indigo)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets {
                                if let id = habits[i].remindersID {
                                    Task { await CalendarManager.removeHabitReminder(id: id) }
                                }
                                ctx.delete(habits[i])
                            }
                            ctx.saveChanges()
                        }
                    }
                }

                Section {
                    TextField(L(S.habits.newPlaceholder), text: $newText)
                        .submitLabel(.done)
                        .onSubmit(add)

                    // Weekday picker — none selected = daily
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            let on = newDays.contains(i)
                            Button {
                                if on { newDays.remove(i) } else { newDays.insert(i) }
                            } label: {
                                Text(Habit.dayLabels[i])
                                    .font(.caption2.bold())
                                    .frame(width: 34, height: 34)
                                    .background(on ? Color.indigo : Color.secondary.opacity(0.12),
                                                in: Circle())
                                    .foregroundStyle(on ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    if newDays.isEmpty {
                        Text(L(S.habits.noDaysNote))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Toggle(isOn: $newReminder) {
                        Label(L(S.habits.remind), systemImage: "bell")
                            .font(.subheadline)
                    }
                    .tint(.indigo)
                    if newReminder {
                        DatePicker(L(S.habits.atWhatTime), selection: $newTime, displayedComponents: .hourAndMinute)
                            .font(.subheadline)
                    }

                    Button(action: add) {
                        Label(L(S.habits.addHabit), systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.indigo)
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text(L(S.habits.newHabit))
                } footer: {
                    Text(L(S.habits.newFooter))
                }
            }
            .navigationTitle(L(S.habits.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.done)) {
                        add()          // don't silently drop a half-typed habit
                        dismiss()
                    }
                }
            }
            .sheet(item: $editHabit) { habit in
                HabitEditSheet(habit: habit)
            }
        }
    }

    private func add() {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        ctx.insert(Habit(text: t, weekdayIndices: Array(newDays),
                         reminderMinutes: newReminder ? Habit.minutes(from: newTime) : nil))
        ctx.saveChanges()
        Haptics.tap()
        newText = ""
        newDays = []
        newReminder = false
    }
}

// MARK: - Habit editing

struct HabitEditSheet: View {
    @Bindable var habit: Habit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DayRecord.date, order: .reverse) private var records: [DayRecord]
    @State private var remindersExportFailed = false

    var body: some View {
        NavigationStack {
            Form {
                historySection
                Section(L(S.habits.habitSection)) {
                    TextField(L(S.habits.name), text: $habit.text)

                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            let on = habit.weekdayIndices.contains(i)
                            Button {
                                if on {
                                    habit.weekdayIndices.removeAll { $0 == i }
                                } else {
                                    habit.weekdayIndices.append(i)
                                }
                            } label: {
                                Text(Habit.dayLabels[i])
                                    .font(.caption2.bold())
                                    .frame(width: 34, height: 34)
                                    .background(on ? Color.indigo : Color.secondary.opacity(0.12),
                                                in: Circle())
                                    .foregroundStyle(on ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    if habit.weekdayIndices.isEmpty {
                        Text(L(S.habits.noDaysNote))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(L(S.habits.reminderSection)) {
                    Toggle(isOn: Binding(
                        get: { habit.reminderMinutes != nil },
                        set: { habit.reminderMinutes = $0 ? 8 * 60 : nil }
                    )) {
                        Label(L(S.habits.remind), systemImage: "bell")
                    }
                    .tint(.indigo)

                    if habit.reminderMinutes != nil {
                        DatePicker(L(S.habits.atWhatTime), selection: Binding(
                            get: { Habit.date(fromMinutes: habit.reminderMinutes ?? 8 * 60) },
                            set: { habit.reminderMinutes = Habit.minutes(from: $0) }
                        ), displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { habit.remindersID != nil },
                        set: { on in
                            if on {
                                Task { @MainActor in
                                    if let id = await CalendarManager.syncHabitReminder(habit) {
                                        habit.remindersID = id
                                        ctx.saveChanges()
                                        Haptics.success()
                                    } else {
                                        remindersExportFailed = true
                                        Haptics.warning()
                                    }
                                }
                            } else {
                                if let id = habit.remindersID {
                                    Task { await CalendarManager.removeHabitReminder(id: id) }
                                }
                                habit.remindersID = nil
                                ctx.saveChanges()
                            }
                        }
                    )) {
                        Label(L(S.habits.remindersApp), systemImage: "checklist")
                    }
                    .tint(.indigo)
                } header: {
                    Text(L(S.misc.integrations))
                } footer: {
                    Text(remindersExportFailed
                         ? L(S.habits.remindersFailed)
                         : L(S.habits.remindersNote))
                }

                Section {
                    Toggle(isOn: $habit.isActive) {
                        Label(L(S.habits.active), systemImage: "repeat")
                    }
                    .tint(.indigo)

                    Button(role: .destructive) {
                        if let id = habit.remindersID {
                            Task { await CalendarManager.removeHabitReminder(id: id) }
                        }
                        ctx.delete(habit)
                        ctx.saveChanges()
                        dismiss()
                    } label: {
                        Label(L(S.habits.deleteHabit), systemImage: "trash")
                    }
                }
            }
            .navigationTitle(L(S.habits.editHabit))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.done)) {
                        ctx.saveChanges()
                        // Push edits (days/time/name) into the exported reminder
                        if habit.remindersID != nil {
                            Task { @MainActor in
                                habit.remindersID = await CalendarManager.syncHabitReminder(habit)
                                ctx.saveChanges()
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Duolingo-style completion history (last 5 weeks)

    private var historySection: some View {
        let days = historyDays()
        let doneCount = days.filter { $0.state == .done }.count
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(Habit.dayLabels[i])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                          spacing: 6) {
                    ForEach(days) { day in
                        ZStack {
                            switch day.state {
                            case .done:
                                Circle().fill(Color.indigo)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            case .missed:
                                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                            case .notScheduled:
                                Circle().fill(Color.secondary.opacity(0.08))
                            case .today:
                                Circle().strokeBorder(Color.indigo, lineWidth: 2)
                            }
                        }
                        .frame(height: 24)
                    }
                }
                Text(L(S.habits.doneInWeeks, doneCount))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L(S.misc.history))
        }
    }

    private enum DayState { case done, missed, notScheduled, today }
    private struct HistoryDay: Identifiable {
        let id: Int
        let state: DayState
    }

    /// Last 5 weeks aligned to Monday, oldest first.
    private func historyDays() -> [HistoryDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekdayIdx = Habit.weekdayIndex(of: today)
        guard let gridEnd = cal.date(byAdding: .day, value: 6 - weekdayIdx, to: today) else { return [] }

        var out: [HistoryDay] = []
        for i in 0..<35 {
            guard let date = cal.date(byAdding: .day, value: i - 34, to: gridEnd) else { continue }
            let isScheduledDay = habit.weekdayIndices.isEmpty
                || habit.weekdayIndices.contains(Habit.weekdayIndex(of: date))
            let state: DayState
            if date > today || !isScheduledDay {
                state = .notScheduled
            } else if completed(on: date) {
                state = .done
            } else if cal.isDate(date, inSameDayAs: today) {
                state = .today
            } else {
                state = .missed
            }
            out.append(HistoryDay(id: i, state: state))
        }
        return out
    }

    private func completed(on date: Date) -> Bool {
        guard let rec = records.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
        else { return false }
        return rec.pillars.contains { $0.text == habit.text && $0.isCompleted }
    }
}
