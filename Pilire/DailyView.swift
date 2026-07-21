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

    struct TimeEdit: Identifiable {
        let id: UUID          // pillar id
        var date: Date
    }

    static func nextFullHour() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: .now)!
        return cal.date(bySetting: .minute, value: 0, of: next) ?? next
    }

    var settings: UserSettings
    var onDayCompleted: ((DayRecord) -> Void)?

    var body: some View {
        NavigationStack {
            if let day = today {
                List {
                    progressSection(day)
                    pillarsSection(day)
                    if day.pillars.count < 5 && !day.isCompleted {
                        addSection(day)
                    }
                    habitsSection(day)
                    if !day.pillars.isEmpty {
                        closeDaySection(day)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                // Scrollable bottom margin so the last row (Uzavřít den) always
                // clears the floating tab bar and can be pulled into view.
                .contentMargins(.bottom, 96, for: .scrollContent)
                .background(Theme.creamGradient.ignoresSafeArea())
                .navigationTitle("Dnešní pilíře")
                .toolbar { streakItem; habitsItem; settingsItem }
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
                .overlay(alignment: .top) { coinToast }
            } else {
                ProgressView().navigationTitle("Dnešní pilíře")
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
        case 1 where count > 0: "Pilíř dne máš hotový, dobrá práce."
        case 0.5...:            "Skvěle, už jen pár bloků."
        case 0.001...:          "První blok položen."
        default: count == 0 ? "Polož základy dneška." : "Bloky čekají na položení."
        }
    }

    private func pillarsSection(_ day: DayRecord) -> some View {
        Section {
            if day.pillars.isEmpty {
                Text("Zatím prázdno. Přidej první pilíř níže.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(day.pillars.sorted(by: { $0.order < $1.order })) { p in
                PillarRow(pillar: p) { toggle(id: p.id, in: day) }
                    .contextMenu {
                        if !p.isHabit && !habits.contains(where: { $0.text == p.text }) {
                            Button {
                                makeHabit(from: p.text)
                            } label: {
                                Label("Udělat z toho návyk", systemImage: "repeat")
                            }
                        }
                        Button {
                            timeEdit = TimeEdit(id: p.id, date: p.scheduledAt ?? Self.nextFullHour())
                        } label: {
                            Label(p.scheduledAt == nil ? "Naplánovat čas" : "Změnit čas",
                                  systemImage: "clock")
                        }
                        Button {
                            addToCalendar(p, in: day)
                        } label: {
                            Label(p.calendarEventID == nil ? "Přidat do Apple kalendáře" : "Znovu do kalendáře",
                                  systemImage: "calendar.badge.plus")
                        }
                        if p.scheduledAt != nil {
                            Button(role: .destructive) {
                                clearTime(id: p.id, in: day)
                            } label: {
                                Label("Zrušit čas", systemImage: "clock.badge.xmark")
                            }
                        }
                    }
            }
            .onDelete { remove($0, from: day) }
        } header: {
            Text("Bloky dneška")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.creamLabel)
                .textCase(nil)
        }
    }

    private func addSection(_ day: DayRecord) -> some View {
        Section {
            HStack {
                TextField("Přidat pilíř...", text: $newText)
                    .submitLabel(.done)
                    .onSubmit { add(to: day) }
                Button {
                    withAnimation { withTime.toggle() }
                } label: {
                    Image(systemName: withTime ? "clock.fill" : "clock")
                        .foregroundStyle(withTime ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(withTime ? "Zrušit čas pilíře" : "Naplánovat čas pilíře")
                if !newText.isEmpty {
                    Button { add(to: day) } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Přidat pilíř")
                }
            }
            if withTime {
                DatePicker("V kolik?", selection: $newTime, displayedComponents: .hourAndMinute)
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
                                    Label("Udělat z toho návyk", systemImage: "repeat")
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
                Label("Nevím, dej mi task", systemImage: "dice.fill")
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
                    Label("Vytvořit první návyk", systemImage: "repeat")
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
                                        Text("· pozastaveno")
                                    } else if habit.isScheduled(on: day.date) {
                                        Text("· dnes")
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
                Text("Pravidelné návyky")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.creamLabel)
                    .textCase(nil)
                Spacer()
                if !habits.isEmpty {
                    Button {
                        showHabits = true
                    } label: {
                        Label("Přidat", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .textCase(nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            if !habits.isEmpty {
                Text("Ťukni na návyk pro úpravu dnů, času nebo připomínky.")
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
                    Text("Podrž tlačítko, dokud se nevyplní.")
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
            .accessibilityLabel("Pravidelné návyky")
        }
    }

    @ToolbarContentBuilder
    private var settingsItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Nastavení")
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

    /// Add today's scheduled habits as pillars (idempotent).
    private func fillHabits(into day: DayRecord) {
        guard !day.isCompleted else { return }
        let existing = Set(day.pillars.map(\.text))
        for habit in habits where habit.isScheduled(on: day.date) {
            guard !existing.contains(habit.text), day.pillars.count < 5 else { continue }
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

    private func addToCalendar(_ pillar: Pillar, in day: DayRecord) {
        let start = pillar.scheduledAt ?? Self.nextFullHour()
        Task { @MainActor in
            if let eventID = await CalendarManager.addEvent(
                title: pillar.text,
                start: start,
                notes: "Pilíř dne z aplikace Pilíře"
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
                DatePicker("Čas", selection: $date, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                Text("Na tento čas ti přijde připomínka.")
                    .font(.caption).foregroundStyle(.secondary)

                Button {
                    onSave(date)
                    dismiss()
                } label: {
                    Text("Uložit")
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
            .navigationTitle("Naplánovat čas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Zavřít") { dismiss() } }
            }
        }
        .presentationDetents([.height(360)])
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
        .accessibilityLabel(isCompleted ? "Den uzavřen" : "Uzavřít den")
        .accessibilityHint(isCompleted ? "" : "Podrž pro uzavření dne")
        .accessibilityAction { if !isCompleted { fire() } }
    }

    private var labelText: String {
        if isCompleted { return "Den uzavřen" }
        return isHolding ? "Držte…" : "Podrž pro uzavření dne"
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
