import SwiftUI
import SwiftData

struct DailyView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DayRecord.date, order: .reverse) private var records: [DayRecord]
    @Query(sort: \Habit.createdDate) private var habits: [Habit]
    @State private var today: DayRecord?
    @State private var newText = ""
    @State private var lastEarned: Int?
    @State private var showSettings = false
    @State private var showPool = false
    @State private var showHabits = false
    @State private var editHabit: Habit?
    @State private var withTime = false
    @State private var newTime = Self.nextFullHour()
    @State private var timeEdit: TimeEdit?
    @State private var pillarEdit: PillarEdit?
    @FocusState private var focusedInput: PillarInput?

    private enum PillarInput: Hashable { case today, tomorrow }

    struct TimeEdit: Identifiable {
        let id: UUID          // pillar id
        var date: Date
    }

    struct PillarEdit: Identifiable {
        let id: UUID          // pillar id
        var text: String
    }

    static func nextFullHour() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: .now)!
        return cal.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    var settings: UserSettings
    var onDayCompleted: ((DayRecord) -> Void)?
    /// Ticking a pillar can earn a badge, and the celebration lives at the tab
    /// container so it can cover any screen.
    var onPillarCompleted: (() -> Void)?

    /// Generous cap so you can jot down a lot of tasks without it becoming endless.
    private let maxPillars = 20

    @State private var newTomorrowText = ""
    /// Observed so the list makes room when the tutorial banner appears.
    @State private var tutorial = Tutorial.shared

    var body: some View {
        NavigationStack {
            if let day = today {
                List {
                    progressSection(day)
                    pillarsSection(day)
                    if !day.isCompleted, !carryOverItems.isEmpty {
                        carryOverSection(day)
                    }
                    if day.pillars.count < maxPillars && !day.isCompleted {
                        addSection(day)
                    }
                    habitsSection(day)
                    // Once the day is closed there's nowhere left to put a
                    // thought — so let it land on tomorrow instead.
                    if day.isCompleted || !tomorrowPillars.isEmpty {
                        tomorrowSection
                    }
                    if !day.pillars.isEmpty {
                        closeDaySection(day)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                // Scrollable bottom margin so the last row (close the day) always
                // clears the floating tab bar and can be pulled into view. While
                // the tutorial banner is up it needs to clear that too, otherwise
                // the banner sits on top of the button.
                .contentMargins(.bottom, focusedInput == nil ? (tutorial.current == nil ? 96 : 220) : 24,
                                for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.creamGradient.ignoresSafeArea())
                .navigationTitle(L(S.daily.title))
                .toolbar {
                    streakItem; habitsItem; settingsItem
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(L(S.common.done)) { focusedInput = nil }
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showHabits, onDismiss: {
                    fillHabits(into: day)
                    syncHabitReminders(day)
                }) {
                    HabitsView()
                }
                .sheet(item: $editHabit, onDismiss: {
                    fillHabits(into: day)
                    syncHabitReminders(day)
                }) { habit in
                    HabitEditSheet(habit: habit)
                }
                .sheet(isPresented: $showPool) {
                    PoolPickerView(existingTexts: Set(day.pillars.map(\.text))) { task in
                        day.pillars.append(Pillar(text: task.text, order: day.pillars.count, isFromPool: true))
                    }
                }
                .sheet(item: $timeEdit) { edit in
                    TimeEditSheet(date: edit.date) { picked in
                        setTime(picked, forID: edit.id, in: day)
                    }
                }
                .sheet(item: $pillarEdit) { edit in
                    PillarEditSheet(text: edit.text) { newText in
                        updatePillarText(id: edit.id, to: newText, in: day)
                    }
                }
                .overlay(alignment: .top) { coinToast }
            } else {
                ProgressView().navigationTitle(L(S.daily.title))
            }
        }
        .onAppear(perform: ensureToday)
    }

    // MARK: - Sections

    private func progressSection(_ day: DayRecord) -> some View {
        let frac = day.pillars.isEmpty ? 0 : Double(day.completedCount) / Double(day.pillars.count)
        return Section {
            HStack(spacing: 22) {
                PillarProgressView(total: day.pillars.count, done: day.completedCount)
                    .frame(width: 84, height: 148)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(day.completedCount)/\(day.pillars.count)")
                        .font(.system(size: 36, design: .rounded).bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: day.completedCount)
                    Text(motivation(frac: frac, count: day.pillars.count))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.creamLabel)
                    Text(day.date, style: .date)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }
    }

    private func motivation(frac: Double, count: Int) -> String {
        switch frac {
        case 1 where count > 0: L(S.daily.doneAll)
        case 0.5...:            L(S.daily.halfWay)
        case 0.001...:          L(S.daily.started)
        default: count == 0 ? L(S.daily.empty) : L(S.daily.waiting)
        }
    }

    private func pillarsSection(_ day: DayRecord) -> some View {
        Section {
            if day.pillars.isEmpty {
                Text(L(S.daily.noPillars))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(day.pillars.sorted(by: { $0.order < $1.order })) { p in
                PillarRow(pillar: p) { toggle(id: p.id, in: day) }
                    .swipeActions(edge: .leading) {
                        Button {
                            pillarEdit = PillarEdit(id: p.id, text: p.text)
                        } label: {
                            Label(L(S.common.edit), systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            pillarEdit = PillarEdit(id: p.id, text: p.text)
                        } label: {
                            Label(L(S.daily.editText), systemImage: "pencil")
                        }
                        if !p.isHabit && !habits.contains(where: { $0.text == p.text }) {
                            Button {
                                makeHabit(from: p.text)
                            } label: {
                                Label(L(S.daily.makeHabit), systemImage: "repeat")
                            }
                        }
                        Button {
                            timeEdit = TimeEdit(id: p.id, date: p.scheduledAt ?? Self.nextFullHour())
                        } label: {
                            Label(p.scheduledAt == nil ? L(S.daily.scheduleTime) : L(S.daily.changeTime),
                                  systemImage: "clock")
                        }
                        Button {
                            addToCalendar(p, in: day)
                        } label: {
                            Label(p.calendarEventID == nil ? L(S.daily.addToCalendar) : L(S.daily.addToCalendarAgain),
                                  systemImage: "calendar.badge.plus")
                        }
                        if p.scheduledAt != nil {
                            Button(role: .destructive) {
                                clearTime(id: p.id, in: day)
                            } label: {
                                Label(L(S.daily.clearTime), systemImage: "clock.badge.xmark")
                            }
                        }
                    }
            }
            .onDelete { remove($0, from: day) }
        } header: {
            Text(L(S.daily.blocksHeader))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.creamLabel)
                .textCase(nil)
        }
    }

    private func addSection(_ day: DayRecord) -> some View {
        Section {
            HStack {
                TextField(L(S.daily.addPlaceholder), text: $newText)
                    .focused($focusedInput, equals: .today)
                    .background(KeyboardFieldVisibility(isFocused: focusedInput == .today))
                    .accessibilityIdentifier("pillar.today.input")
                    .submitLabel(.done)
                    .onSubmit { add(to: day) }
                Button {
                    withAnimation { withTime.toggle() }
                } label: {
                    Image(systemName: withTime ? "clock.fill" : "clock")
                        .foregroundStyle(withTime ? .orange : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(withTime ? L(S.daily.cancelPillarTime) : L(S.daily.schedulePillarTime))
                if !newText.isEmpty {
                    Button { add(to: day) } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.orange)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L(S.daily.addPillar))
                }
            }
            if withTime {
                DatePicker(L(S.habits.atWhatTime), selection: $newTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
            }

            // Quick suggestions from recent days
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { text in
                            Button {
                                Haptics.tap()
                                day.pillars.append(Pillar(text: text, order: day.pillars.count))
                                Tutorial.shared.advance(from: .addTask)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath").font(.caption2)
                                    Text(text).lineLimit(1)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.orange.opacity(0.10), in: Capsule())
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    makeHabit(from: text)
                                } label: {
                                    Label(L(S.daily.makeHabit), systemImage: "repeat")
                                }
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            Button {
                showPool = true
            } label: {
                Label(L(S.daily.giveMeTask), systemImage: "dice.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
        }
    }

    /// Permanent overview of all regular habits — tap to edit.
    private func habitsSection(_ day: DayRecord) -> some View {
        Section {
            if habits.isEmpty {
                Button {
                    showHabits = true
                } label: {
                    Label(L(S.daily.firstHabit), systemImage: "repeat")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            } else {
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
                                    if !habit.isActive {
                                        Text(L(S.misc.paused))
                                    } else if habit.isScheduled(on: day.date) {
                                        Text(L(S.misc.todayMark))
                                            .foregroundStyle(.indigo)
                                    }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text(L(S.daily.habitsHeader))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.creamLabel)
                    .textCase(nil)
                Spacer()
                if !habits.isEmpty {
                    Button {
                        showHabits = true
                    } label: {
                        Label(L(S.common.add), systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .textCase(nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            if !habits.isEmpty {
                Text(L(S.daily.habitsFooter))
            }
        }
    }

    /// Up to 3 recent unique pillar texts not already in today's list.
    private var suggestions: [String] {
        guard let day = today else { return [] }
        var excluded = Set(day.pillars.map(\.text))
        habits.forEach { excluded.insert($0.text) }
        var seen = Set<String>()
        var out: [String] = []
        for rec in records where rec !== day {
            for p in rec.pillars.sorted(by: { $0.order < $1.order }) {
                let t = p.text
                guard !t.isEmpty, !excluded.contains(t), !seen.contains(t) else { continue }
                seen.insert(t)
                out.append(t)
                if out.count == 3 { return out }
            }
        }
        return out
    }

    // MARK: - Close button

    // MARK: - Close day (scrolls with the list — never covers other content)

    private func closeDaySection(_ day: DayRecord) -> some View {
        Section {
            VStack(spacing: 8) {
                HoldToCloseButton(isCompleted: day.isCompleted) { close(day) }
                if !day.isCompleted {
                    Text(L(S.daily.holdHint))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func close(_ day: DayRecord) {
        day.isCompleted = true
        onDayCompleted?(day)
    }

    // MARK: - Toolbar / toast

    @ToolbarContentBuilder
    private var streakItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if settings.momentum > 0 {
                Label("\(Int(settings.momentum))", systemImage: "leaf.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
        }
    }

    @ToolbarContentBuilder
    private var habitsItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showHabits = true } label: {
                Image(systemName: "repeat")
            }
            .accessibilityLabel(L(S.daily.habitsHeader))
        }
    }

    @ToolbarContentBuilder
    private var settingsItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(L(S.settings.title))
        }
    }

    @ViewBuilder
    private var coinToast: some View {
        if let earned = lastEarned {
            HStack(spacing: 5) {
                Text(earned >= 0 ? "+\(earned)" : "\(earned)")
                    .font(.subheadline.bold()).monospacedDigit()
                Image(systemName: Material.wood.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(earned >= 0
                        ? Color(red: 0.45, green: 0.80, blue: 0.45)
                        : Color(red: 0.85, green: 0.75, blue: 0.65))
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(
                (earned >= 0
                    ? Color(red: 0.45, green: 0.35, blue: 0.24)
                    : Color(red: 0.45, green: 0.42, blue: 0.40)).opacity(0.94),
                in: Capsule())
            .foregroundStyle(.white)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 4)
        }
    }

    // MARK: - Logic

    private func ensureToday() {
        let start = Calendar.current.startOfDay(for: .now)
        if let existing = records.first(where: { Calendar.current.isDate($0.date, inSameDayAs: start) }) {
            today = existing
        } else {
            let rec = DayRecord(date: start)
            ctx.insert(rec)
            today = rec
        }
        if let day = today {
            fillHabits(into: day)
            syncHabitReminders(day)
        }
    }

    /// Turn an existing task text into a recurring habit and open the editor
    /// so the user can pick days and a reminder right away.
    private func makeHabit(from text: String) {
        guard !habits.contains(where: { $0.text == text }) else { return }
        let habit = Habit(text: text)
        ctx.insert(habit)
        ctx.saveChanges()
        Haptics.success()
        editHabit = habit
    }

    /// Plan gentle habit notifications for the coming week; a habit finished
    /// today won't ping again today.
    private func syncHabitReminders(_ day: DayRecord) {
        let done = Set(day.pillars.filter(\.isCompleted).map(\.text))
        NotificationManager.syncHabitReminders(habits: habits, completedTodayTexts: done)
    }

    // MARK: - Planning tomorrow

    private var tomorrowDate: Date {
        Calendar.current.date(byAdding: .day, value: 1,
                              to: Calendar.current.startOfDay(for: .now))!
    }

    private var tomorrowRecord: DayRecord? {
        records.first { Calendar.current.isDate($0.date, inSameDayAs: tomorrowDate) }
    }

    private var tomorrowPillars: [Pillar] {
        (tomorrowRecord?.pillars ?? []).sorted { $0.order < $1.order }
    }

    @ViewBuilder
    private var tomorrowSection: some View {
        Section {
            ForEach(tomorrowPillars) { p in
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars")
                        .foregroundStyle(.indigo.opacity(0.7))
                    Text(p.text)
                        .font(.system(.subheadline, design: .rounded))
                    Spacer(minLength: 0)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { removeFromTomorrow(p.id) } label: {
                        Label(L(S.common.delete), systemImage: "trash")
                    }
                }
            }

            if tomorrowPillars.count < maxPillars {
                HStack {
                    TextField(L(S.daily.tomorrowPlaceholder), text: $newTomorrowText)
                        .focused($focusedInput, equals: .tomorrow)
                        .background(KeyboardFieldVisibility(isFocused: focusedInput == .tomorrow))
                        .accessibilityIdentifier("pillar.tomorrow.input")
                        .submitLabel(.done)
                        .onSubmit { addToTomorrow() }
                    if !newTomorrowText.isEmpty {
                        Button { addToTomorrow() } label: {
                            Image(systemName: "plus.circle.fill").foregroundStyle(.indigo)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(S.daily.addPillarTomorrow))
                    }
                }
            }
        } header: {
            Text(L(S.daily.tomorrowHeader))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.creamLabel)
                .textCase(nil)
        } footer: {
            Text(L(S.daily.tomorrowFooter))
        }
    }

    private func addToTomorrow() {
        let text = newTomorrowText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Create tomorrow's record only once something is actually planned.
        let record: DayRecord
        if let existing = tomorrowRecord {
            record = existing
        } else {
            record = DayRecord(date: tomorrowDate)
            ctx.insert(record)
        }
        record.pillars.append(Pillar(text: text, order: record.pillars.count))
        newTomorrowText = ""
        ctx.saveChanges()
        Haptics.tap()
    }

    private func removeFromTomorrow(_ id: UUID) {
        guard let record = tomorrowRecord else { return }
        record.pillars.removeAll { $0.id == id }
        ctx.saveChanges()
        Haptics.drop()
    }

    // MARK: - Carry over unfinished pillars

    struct CarryItem: Identifiable {
        let record: DayRecord
        let pillar: Pillar
        var id: UUID { pillar.id }
    }

    /// Unfinished, non-habit pillars from earlier days — offered to bring forward.
    private var carryOverItems: [CarryItem] {
        guard let today, !today.isCompleted else { return [] }
        let todayStart = Calendar.current.startOfDay(for: today.date)
        var items: [CarryItem] = []
        for rec in records where Calendar.current.startOfDay(for: rec.date) < todayStart {
            for p in rec.pillars where !p.isCompleted && !p.isHabit {
                items.append(CarryItem(record: rec, pillar: p))
            }
        }
        return items
    }

    @ViewBuilder
    private func carryOverSection(_ day: DayRecord) -> some View {
        let items = carryOverItems
        Section {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.uturn.down.circle")
                        .foregroundStyle(Theme.accentBottom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.pillar.text)
                            .font(.system(.subheadline, design: .rounded))
                        Text(item.record.date, format: Date.FormatStyle(date: .abbreviated)
                            .locale(Language.shared.current.locale))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button(L(S.daily.carry)) { carryOver(item) }
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(Theme.accentBottom)
                        .buttonStyle(.plain)
                        .disabled(day.pillars.count >= maxPillars)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button(role: .destructive) { deleteCarryOver(item) } label: {
                        Label(L(S.common.delete), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteCarryOver(item) } label: {
                        Label(L(S.common.delete), systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Text(L(S.daily.carryHeader))
                Spacer()
                if items.count > 1 {
                    Button(L(S.daily.carryAll)) { for i in items { carryOver(i) } }
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accentBottom)
                        .textCase(nil)
                }
            }
        } footer: {
            Text(L(S.daily.carryFooter))
        }
    }

    /// Move an unfinished pillar from its old day into today (fresh attempt).
    private func carryOver(_ item: CarryItem) {
        guard let day = today, !day.isCompleted, day.pillars.count < maxPillars else {
            Haptics.warning(); return
        }
        item.record.pillars.removeAll { $0.id == item.pillar.id }
        day.pillars.append(Pillar(text: item.pillar.text,
                                  order: day.pillars.count,
                                  isFromPool: item.pillar.isFromPool))
        ctx.saveChanges()
        Haptics.tap()
    }

    /// Delete an old unfinished pillar for good (drops it from its day).
    private func deleteCarryOver(_ item: CarryItem) {
        item.record.pillars.removeAll { $0.id == item.pillar.id }
        ctx.saveChanges()
        Haptics.drop()
    }

    /// Add today's scheduled habits as pillars (idempotent).
    private func fillHabits(into day: DayRecord) {
        guard !day.isCompleted else { return }
        let existing = Set(day.pillars.map(\.text))
        for habit in habits where habit.isScheduled(on: day.date) {
            guard !existing.contains(habit.text), day.pillars.count < maxPillars else { continue }
            day.pillars.append(Pillar(text: habit.text, order: day.pillars.count, isHabit: true))
        }
    }

    private func add(to day: DayRecord) {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let scheduled = withTime ? todayAt(newTime) : nil
        let pillar = Pillar(text: t, order: day.pillars.count, scheduledAt: scheduled)
        day.pillars.append(pillar)
        if let scheduled {
            NotificationManager.schedulePillarReminder(id: pillar.id, text: t, date: scheduled)
        }
        newText = ""
        withTime = false
        newTime = Self.nextFullHour()
        Tutorial.shared.advance(from: .addTask)
    }

    /// Combine today's date with the picked hour/minute.
    private func todayAt(_ time: Date) -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: .now) ?? time
    }

    private func setTime(_ date: Date, forID id: UUID, in day: DayRecord) {
        guard let i = day.pillars.firstIndex(where: { $0.id == id }) else { return }
        let scheduled = todayAt(date)
        day.pillars[i].scheduledAt = scheduled
        NotificationManager.cancelPillarReminder(id: id)
        NotificationManager.schedulePillarReminder(id: id, text: day.pillars[i].text, date: scheduled)
        Haptics.tap()
    }

    private func clearTime(id: UUID, in day: DayRecord) {
        guard let i = day.pillars.firstIndex(where: { $0.id == id }) else { return }
        day.pillars[i].scheduledAt = nil
        NotificationManager.cancelPillarReminder(id: id)
    }

    private func updatePillarText(id: UUID, to text: String, in day: DayRecord) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = day.pillars.firstIndex(where: { $0.id == id }) else { return }
        day.pillars[i].text = trimmed
        // Keep any scheduled reminder in sync with the new wording.
        if let when = day.pillars[i].scheduledAt {
            NotificationManager.cancelPillarReminder(id: id)
            NotificationManager.schedulePillarReminder(id: id, text: trimmed, date: when)
        }
        ctx.saveChanges()
        Haptics.tap()
    }

    private func addToCalendar(_ pillar: Pillar, in day: DayRecord) {
        let start = pillar.scheduledAt ?? Self.nextFullHour()
        Task { @MainActor in
            if let eventID = await CalendarManager.addEvent(
                title: pillar.text,
                start: start,
                notes: L(S.daily.calendarNote)
            ) {
                if let i = day.pillars.firstIndex(where: { $0.id == pillar.id }) {
                    day.pillars[i].calendarEventID = eventID
                }
                Haptics.success()
            } else {
                Haptics.warning()
            }
        }
    }

    private func toggle(id: UUID, in day: DayRecord) {
        guard !day.isCompleted else { return }   // closed day is read-only
        guard let i = day.pillars.firstIndex(where: { $0.id == id }) else { return }
        let wasCompleted = day.pillars[i].isCompleted
        day.pillars[i].isCompleted.toggle()

        if !wasCompleted {
            // Completing: award wood (pool tasks earn +50 %), remember the amount
            Haptics.tap()
            NotificationManager.cancelPillarReminder(id: id)   // done → no reminder needed
            let earned = settings.awardTaskWood(isFromPool: day.pillars[i].isFromPool)
            day.pillars[i].woodAwarded = earned
            showEarnedToast(earned)
            Tutorial.shared.advance(from: .completeTask)
            onPillarCompleted?()
        } else {
            // Un-completing: take the exact reward back (no free-wood loop)
            let refund = day.pillars[i].woodAwarded
            if refund > 0 {
                settings.woodCount = max(0, settings.woodCount - refund)
                day.pillars[i].woodAwarded = 0
                showEarnedToast(-refund)
            }
        }

        // Habit state changed → today's gentle reminder may need (un)scheduling
        if day.pillars[i].isHabit {
            syncHabitReminders(day)
        }
    }

    private func showEarnedToast(_ amount: Int) {
        withAnimation(.spring(response: 0.3)) { lastEarned = amount }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { lastEarned = nil }
        }
    }

    private func remove(_ offsets: IndexSet, from day: DayRecord) {
        let sorted = day.pillars.sorted(by: { $0.order < $1.order })
        for i in offsets {
            NotificationManager.cancelPillarReminder(id: sorted[i].id)
            // Deleting a completed pillar returns its reward too
            if sorted[i].woodAwarded > 0 {
                settings.woodCount = max(0, settings.woodCount - sorted[i].woodAwarded)
            }
            day.pillars.removeAll { $0.id == sorted[i].id }
        }
    }

}

struct PillarRow: View {
    let pillar: Pillar
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Juicy check medallion — pops with a spring when the block lands
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(pillar.isCompleted ? 0 : 0.4), lineWidth: 2)
                if pillar.isCompleted {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.35, green: 0.75, blue: 0.40),
                                     Color(red: 0.22, green: 0.62, blue: 0.32)],
                            startPoint: .top, endPoint: .bottom))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 27, height: 27)
            .scaleEffect(pillar.isCompleted ? 1 : 0.94)
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: pillar.isCompleted)

            VStack(alignment: .leading, spacing: 2) {
                Text(pillar.text)
                    .font(.system(.body, design: .rounded))
                    .strikethrough(pillar.isCompleted, color: .secondary)
                    .foregroundStyle(pillar.isCompleted ? Color.secondary : Color.primary)
                if let t = pillar.scheduledAt, !pillar.isCompleted {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(t.formatted(date: .omitted, time: .shortened))
                        if pillar.calendarEventID != nil {
                            Image(systemName: "calendar.badge.checkmark")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                }
            }
            if pillar.isFromPool {
                Image(systemName: "dice.fill")
                    .font(.caption)
                    .foregroundStyle(.indigo.opacity(0.7))
            }
            if pillar.isHabit {
                Image(systemName: "repeat")
                    .font(.caption)
                    .foregroundStyle(.indigo.opacity(0.7))
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Time edit sheet

struct TimeEditSheet: View {
    @State var date: Date
    var onSave: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(L(S.daily.time), selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Text(L(S.daily.timeNote))
                    .font(.caption).foregroundStyle(.secondary)

                Button {
                    onSave(date)
                    dismiss()
                } label: {
                    Text(L(S.common.save))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .navigationTitle(L(S.daily.timeSheetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
        }
        .presentationDetents([.height(360)])
    }
}

// MARK: - Pillar text edit sheet

struct PillarEditSheet: View {
    @State var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField(L(S.daily.pillarText), text: $text, axis: .vertical)
                    .focused($focused)
                    .font(.system(.title3, design: .rounded))
                    .lineLimit(1...4)
                    .padding(14)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                    .submitLabel(.done)
                    .onSubmit { save() }

                Button(action: save) {
                    Text(L(S.common.save))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(trimmed.isEmpty ? Color.secondary.opacity(0.3) : Color.orange,
                                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty)

                Spacer()
            }
            .padding(20)
            .navigationTitle(L(S.daily.editSheetTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
        }
        .presentationDetents([.height(280)])
        .onAppear { focused = true }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

// MARK: - Hold-to-close button

/// Press-and-hold to close the day. A fill sweeps left→right while held so the
/// user can see how much longer to hold; releasing early cancels.
struct HoldToCloseButton: View {
    let isCompleted: Bool
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var didFire = false

    private let holdDuration: Double = 1.1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(isCompleted
                      ? AnyShapeStyle(Color.green.opacity(0.15))
                      : AnyShapeStyle(Theme.accentGradient))

            if !isCompleted {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .fill(Color.white.opacity(0.30))
                        .frame(width: geo.size.width * progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .allowsHitTesting(false)
            }

            Label(labelText,
                  systemImage: isCompleted ? "checkmark.seal.fill" : "flag.checkered")
                .foregroundStyle(isCompleted ? Color.green : Color.white)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .scaleEffect(isHolding ? 0.98 : 1)
        .animation(.easeOut(duration: 0.15), value: isHolding)
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
            fire()
        } onPressingChanged: { pressing in
            if pressing { beginHold() } else { endHold() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isCompleted ? L(S.daily.dayClosed) : L(S.daily.closeDayShort))
        .accessibilityHint(isCompleted ? "" : L(S.daily.closeDay))
        .accessibilityAction { if !isCompleted { fire() } }
    }

    private var labelText: String {
        if isCompleted { return L(S.daily.dayClosed) }
        return isHolding ? L(S.daily.holding) : L(S.daily.closeDay)
    }

    private func beginHold() {
        guard !isHolding, !isCompleted else { return }
        isHolding = true
        didFire = false
        Haptics.tap()
        withAnimation(.linear(duration: holdDuration)) { progress = 1 }
    }

    private func fire() {
        guard !didFire, !isCompleted else { return }
        didFire = true
        isHolding = false
        Haptics.success()
        onClose()
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }

    private func endHold() {
        // If the long press already fired, ignore; otherwise it was an early release.
        guard !didFire else { return }
        isHolding = false
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }
}
