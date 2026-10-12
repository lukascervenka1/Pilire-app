import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @State private var morningHour = 8
    @State private var eveningHour = 20
    @State private var notificationsEnabled = false
    @AppStorage("mapFollowsFinger")    private var mapFollowsFinger = true
    @AppStorage("notifHabitsEnabled")  private var notifHabits = true
    @AppStorage("notifTasksEnabled")   private var notifTasks = true
    @AppStorage("hasSeenOnboarding")   private var hasSeenOnboarding = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var resetDone = false
    @State private var language = Language.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: Binding(
                        get: { language.current },
                        set: { language.choose($0) })
                    ) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text("\(lang.flag)  \(lang.nativeName)").tag(lang)
                        }
                    } label: {
                        Label(L(S.settings.language), systemImage: "globe")
                    }
                } header: {
                    Text(L(S.settings.languageSection))
                }

                Section(L(S.settings.remindersSection)) {
                    Toggle(L(S.settings.remindersToggle), isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, on in
                            if on {
                                NotificationManager.requestPermission()
                                NotificationManager.scheduleDailyReminders(
                                    morningHour: morningHour, eveningHour: eveningHour
                                )
                            } else {
                                UNUserNotificationCenter.current()
                                    .removePendingNotificationRequests(withIdentifiers: ["morning", "evening"])
                            }
                        }

                    if notificationsEnabled {
                        HStack {
                            Text(L(S.settings.morningNudge))
                            Spacer()
                            Stepper("\(morningHour):00", value: $morningHour, in: 5...11)
                                .onChange(of: morningHour) { _, v in
                                    NotificationManager.scheduleDailyReminders(morningHour: v, eveningHour: eveningHour)
                                }
                        }

                        HStack {
                            Text(L(S.settings.eveningNudge))
                            Spacer()
                            Stepper("\(eveningHour):00", value: $eveningHour, in: 16...23)
                                .onChange(of: eveningHour) { _, v in
                                    NotificationManager.scheduleDailyReminders(morningHour: morningHour, eveningHour: v)
                                }
                        }
                    }
                }

                Section {
                    Toggle(isOn: $notifHabits) {
                        Label(L(S.settings.habits), systemImage: "repeat")
                    }
                    .tint(.indigo)
                    .onChange(of: notifHabits) { _, on in
                        if !on { NotificationManager.removePending(prefix: "habit-") }
                        // when re-enabled, reminders re-plan on the next visit to Pilíře
                    }

                    Toggle(isOn: $notifTasks) {
                        Label(L(S.settings.timedTasks), systemImage: "clock")
                    }
                    .tint(.orange)
                    .onChange(of: notifTasks) { _, on in
                        if !on { NotificationManager.removePending(prefix: "pillar-") }
                    }
                } header: {
                    Text(L(S.settings.gentleSection))
                } footer: {
                    Text(L(S.settings.gentleFooter))
                }

                Section {
                    Toggle(isOn: $mapFollowsFinger) {
                        Label(L(S.settings.mapFollowsFinger), systemImage: "hand.draw")
                    }
                    .tint(.orange)
                } header: {
                    Text(L(S.settings.mapSection))
                } footer: {
                    Text(L(S.settings.mapFooter))
                }

                Section(L(S.settings.appSection)) {
                    LabeledContent(L(S.settings.version), value: "1.0")
                }

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label(L(S.settings.deleteAll), systemImage: "trash")
                    }
                } footer: {
                    Text(resetDone ? L(S.settings.deleteDoneFooter) : L(S.settings.deleteFooter))
                }
            }
            .navigationTitle(L(S.settings.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.done)) { dismiss() }
                }
            }
            .confirmationDialog(L(S.settings.deleteAllQuestion),
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L(S.settings.deleteEverything), role: .destructive) { resetEverything() }
                Button(L(S.common.cancel), role: .cancel) {}
            } message: {
                Text(L(S.settings.deleteMessage))
            }
        }
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async {
                    notificationsEnabled = s.authorizationStatus == .authorized
                }
            }
        }
    }

    /// Full wipe: SwiftData store, preference flags, tutorial state and every
    /// pending notification — leaves the app as if freshly installed.
    private func resetEverything() {
        try? ctx.delete(model: DayRecord.self)
        try? ctx.delete(model: Building.self)
        try? ctx.delete(model: PlacedDecoration.self)
        try? ctx.delete(model: OwnedAnimal.self)
        try? ctx.delete(model: Habit.self)
        try? ctx.delete(model: UserSettings.self)
        // ContentView stays alive behind this sheet. Leave it a valid singleton
        // immediately instead of forcing a restart before rewards work again.
        ctx.insert(UserSettings())
        ctx.saveChanges()

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let d = UserDefaults.standard
        for key in ["hasSeenOnboarding", "tutorialStep", "tutorialDone",
                    "devModeEnabled", "notifHabitsEnabled", "notifTasksEnabled",
                    "achievementsSeeded", "cachedMapSize"] {
            d.removeObject(forKey: key)
        }

        hasSeenOnboarding = false
        Haptics.success()
        resetDone = true
    }
}
