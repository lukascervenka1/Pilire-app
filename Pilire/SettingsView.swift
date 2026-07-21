import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @State private var morningHour = 8
    @State private var eveningHour = 20
    @State private var notificationsEnabled = false
    @AppStorage("devModeEnabled")      private var devModeEnabled = false
    @AppStorage("mapFollowsFinger")    private var mapFollowsFinger = true
    @AppStorage("notifHabitsEnabled")  private var notifHabits = true
    @AppStorage("notifTasksEnabled")   private var notifTasks = true
    @AppStorage("hasSeenOnboarding")   private var hasSeenOnboarding = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var resetDone = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Připomínky") {
                    Toggle("Zapnout připomínky", isOn: $notificationsEnabled)
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
                            Text("Ranní výzva")
                            Spacer()
                            Stepper("\(morningHour):00", value: $morningHour, in: 5...11)
                                .onChange(of: morningHour) { _, v in
                                    NotificationManager.scheduleDailyReminders(morningHour: v, eveningHour: eveningHour)
                                }
                        }

                        HStack {
                            Text("Večerní připomínka")
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
                        Label("Návyky", systemImage: "repeat")
                    }
                    .tint(.indigo)
                    .onChange(of: notifHabits) { _, on in
                        if !on { NotificationManager.removePending(prefix: "habit-") }
                        // when re-enabled, reminders re-plan on the next visit to Pilíře
                    }

                    Toggle(isOn: $notifTasks) {
                        Label("Časované úkoly", systemImage: "clock")
                    }
                    .tint(.orange)
                    .onChange(of: notifTasks) { _, on in
                        if !on { NotificationManager.removePending(prefix: "pillar-") }
                    }
                } header: {
                    Text("Jemné připomínky")
                } footer: {
                    Text("Jedna tichá zpráva v čas návyku nebo úkolu, žádné výčitky ani opakování. Splněný návyk už ten den nepípne.")
                }

                Section {
                    Toggle(isOn: $mapFollowsFinger) {
                        Label("Mapa sleduje prst", systemImage: "hand.draw")
                    }
                    .tint(.orange)
                } header: {
                    Text("Ovládání mapy")
                } footer: {
                    Text("Zapnuto: mapa se posouvá s prstem, jako fotka. Vypnuto: kamera letí směrem tažení.")
                }

                Section("Aplikace") {
                    LabeledContent("Verze", value: "1.0 MVP")
                    LabeledContent("Platforma", value: "iOS 26+")
                }

                #if DEBUG
                Section {
                    Toggle(isOn: $devModeEnabled) {
                        Label("God mode", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("Vývojář")
                } footer: {
                    Text("Zobrazí na mapě panel s neomezenými zdroji a okamžitým stavěním. Vypni, když chceš appku zažít jako běžný uživatel.")
                }
                #endif

                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Smazat všechna data", systemImage: "trash")
                    }
                } footer: {
                    Text(resetDone
                         ? "Hotovo. Ukonči aplikaci (odsuň ji nahoru) a spusť znovu, načte se jako úplně nová."
                         : "Smaže město, pilíře, návyky, mince i materiál a vrátí appku do stavu po instalaci. Nevratné.")
                }
            }
            .navigationTitle("Nastavení")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hotovo") { dismiss() }
                }
            }
            .confirmationDialog("Smazat všechna data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Smazat vše", role: .destructive) { resetEverything() }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Přijdeš o celé město, historii i návyky. Tohle nejde vzít zpět.")
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
        ctx.saveChanges()

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        let d = UserDefaults.standard
        for key in ["hasSeenOnboarding", "tutorialStep", "tutorialDone",
                    "devModeEnabled", "notifHabitsEnabled", "notifTasksEnabled"] {
            d.removeObject(forKey: key)
        }

        hasSeenOnboarding = false
        Haptics.success()
        resetDone = true
    }
}
