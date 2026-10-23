import SwiftUI

// MARK: - What's new
//
// Shown once, the first time someone opens a version that has notes. A fresh
// install never sees it (onboarding and the tutorial cover that), and a version
// without notes simply shows nothing. Every release's notes stay in Settings,
// newest first.

struct ReleaseNote: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: T
    /// Says where to find it, not only what it is: most of these live behind a
    /// gesture nobody would stumble on.
    let detail: T
}

struct Release: Identifiable {
    let version: String
    let items: [ReleaseNote]
    var id: String { version }
}

enum ReleaseNotes {
    /// Newest first. Add a release at the top with the same version string as
    /// MARKETING_VERSION; a version missing here shows no popup.
    static let releases: [Release] = [
        Release(version: "1.1.0", items: [
        ReleaseNote(symbol: "speaker.wave.2.fill", tint: Color(red: 0.30, green: 0.58, blue: 0.45),
                    title: S.whatsNew.soundTitle, detail: S.whatsNew.soundDetail),
        ReleaseNote(symbol: "cloud.bolt.rain.fill", tint: Color(red: 0.36, green: 0.44, blue: 0.62),
                    title: S.whatsNew.stormTitle, detail: S.whatsNew.stormDetail),
        ReleaseNote(symbol: "cup.and.saucer.fill", tint: Color(red: 0.62, green: 0.42, blue: 0.30),
                    title: S.whatsNew.cafeTitle, detail: S.whatsNew.cafeDetail),
        ReleaseNote(symbol: "chevron.down.circle", tint: .indigo,
                    title: S.whatsNew.foldTitle, detail: S.whatsNew.foldDetail),
        ReleaseNote(symbol: "wrench.and.screwdriver", tint: Theme.accentBottom,
                    title: S.whatsNew.fixesTitle, detail: S.whatsNew.fixesDetail),
        ]),
        Release(version: "1.0.2", items: [
        ReleaseNote(symbol: "calendar.badge.clock", tint: .orange,
                    title: S.whatsNew.planTitle, detail: S.whatsNew.planDetail),
        ReleaseNote(symbol: "arrow.up.arrow.down", tint: Theme.accentBottom,
                    title: S.whatsNew.tidyTitle, detail: S.whatsNew.tidyDetail),
        ReleaseNote(symbol: "clock", tint: .indigo,
                    title: S.whatsNew.habitsTitle, detail: S.whatsNew.habitsDetail),
        ReleaseNote(symbol: "dog.fill", tint: Color(red: 0.80, green: 0.50, blue: 0.20),
                    title: S.whatsNew.dogsTitle, detail: S.whatsNew.dogsDetail),
        ReleaseNote(symbol: "calendar", tint: Color(red: 0.85, green: 0.62, blue: 0.15),
                    title: S.whatsNew.weekTitle, detail: S.whatsNew.weekDetail),
        ]),
        Release(version: "1.0.1", items: [
        ReleaseNote(symbol: "pawprint.fill", tint: Color(red: 0.58, green: 0.42, blue: 0.25),
                    title: S.whatsNew.zooTitle, detail: S.whatsNew.zooDetail),
        ReleaseNote(symbol: "shippingbox.fill", tint: Color(red: 0.85, green: 0.62, blue: 0.15),
                    title: S.whatsNew.chestTitle, detail: S.whatsNew.chestDetail),
        ]),
    ]

    /// The notes for the version that's running, if it has any.
    static var current: Release? { releases.first { $0.version == appVersion } }

    private static let seenKey = "releaseNotesSeenVersion"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// True once per version, only for someone who already knew the app.
    static func shouldShow(hasSeenOnboarding: Bool) -> Bool {
        guard hasSeenOnboarding, let current, !current.items.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: seenKey) != current.version
    }

    static func markSeen() {
        UserDefaults.standard.set(appVersion, forKey: seenKey)
    }
}

// MARK: - Card

/// The list of notes on a cream card; shared by the overlay and the Settings sheet.
struct ReleaseNotesCard: View {
    /// One release after an update; every release when opened from Settings.
    var releases: [Release]
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                if releases.count == 1, let only = releases.first {
                    Text(L(S.whatsNew.kicker, only.version))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.accentBottom)
                        .textCase(.uppercase)
                }
                Text(L(S.whatsNew.title))
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(CatalogStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                  ForEach(releases) { release in
                    if releases.count > 1 {
                        Text(L(S.whatsNew.versionHeader, release.version))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.accentBottom)
                            .textCase(.uppercase)
                            .padding(.top, release.id == releases.first?.id ? 0 : 10)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(release.items) { note in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: note.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(note.tint)
                                .frame(width: 42, height: 42)
                                .background(note.tint.opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L(note.title))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(CatalogStyle.ink)
                                Text(L(note.detail))
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Theme.creamLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                  }
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(action: onContinue) {
                Text(L(S.whatsNew.continueButton))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient(colors: [Theme.accentTop, Theme.accentBottom],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

/// Shown over the town after an update.
struct ReleaseNotesOverlay: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            ReleaseNotesCard(releases: ReleaseNotes.current.map { [$0] } ?? [], onContinue: onDismiss)
                .frame(maxWidth: 380, maxHeight: 640)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
                .padding(.horizontal, 20)
                .padding(.vertical, 60)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85)) {
                shown = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }
}

/// The same notes, reopened from Settings.
struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ReleaseNotesCard(releases: ReleaseNotes.releases) { dismiss() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.panel.ignoresSafeArea())
            .presentationDetents([.large])
    }
}
