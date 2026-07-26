import SwiftUI

// MARK: - Language

/// The app picks its own language rather than following the system, because the
/// player chooses it on first launch and can change it in Settings.
enum AppLanguage: String, CaseIterable, Identifiable {
    case cs, sk, en
    var id: String { rawValue }

    /// Shown in its own language, the way language pickers should be.
    var nativeName: String {
        switch self {
        case .cs: "Čeština"
        case .sk: "Slovenčina"
        case .en: "English"
        }
    }

    var flag: String {
        switch self {
        case .cs: "🇨🇿"
        case .sk: "🇸🇰"
        case .en: "🇬🇧"
        }
    }

    /// Drives date formatting and anything else that reads the environment.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Best guess from the phone's settings, used to preselect on first launch.
    static var systemSuggestion: AppLanguage {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        return AppLanguage(rawValue: String(code)) ?? .en
    }
}

/// Holds the chosen language. Views read `current`, so switching redraws the app.
@MainActor
@Observable
final class Language {
    static let shared = Language()

    private static let key = "appLanguage"
    private static let chosenKey = "appLanguageChosen"

    var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    /// False until the player has picked a language, which is what shows the
    /// picker on first launch.
    var hasChosen: Bool {
        didSet { UserDefaults.standard.set(hasChosen, forKey: Self.chosenKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        current = stored.flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage.systemSuggestion
        hasChosen = UserDefaults.standard.bool(forKey: Self.chosenKey)
    }

    func choose(_ language: AppLanguage) {
        current = language
        hasChosen = true
    }
}

// MARK: - Strings

/// One phrase in every language the app ships. Written as a struct with three
/// required fields on purpose: a missing translation is a compile error, never
/// a Czech sentence leaking into the English build.
struct T {
    let cs: String
    let sk: String
    let en: String

    func callAsFunction() -> String { resolved }

    var resolved: String {
        switch Language.shared.current {
        case .cs: cs
        case .sk: sk
        case .en: en
        }
    }
}

/// Shorthand so call sites stay readable: `Text(L(S.daily.title))`.
@MainActor
func L(_ phrase: T) -> String { phrase.resolved }

/// Same for phrases that take a value, e.g. counts and names.
@MainActor
func L(_ phrase: T, _ args: CVarArg...) -> String {
    String(format: phrase.resolved, arguments: args)
}

// MARK: - First-launch picker

struct LanguagePickerView: View {
    var onPick: (AppLanguage) -> Void

    var body: some View {
        ZStack {
            Theme.creamGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                PillarLogoView()
                    .frame(width: 120, height: 130)

                VStack(spacing: 6) {
                    Text("Pilíře")
                        .font(.system(size: 34, design: .rounded).bold())
                        .foregroundStyle(Color(red: 0.30, green: 0.27, blue: 0.22))
                    // Deliberately in all three languages: at this point we
                    // don't know which one the player reads.
                    Text("Vyber jazyk · Vyber jazyk · Choose your language")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.creamLabel)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            onPick(language)
                        } label: {
                            HStack(spacing: 14) {
                                Text(language.flag).font(.title2)
                                Text(language.nativeName)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundStyle(Theme.creamLabel.opacity(0.6))
                            }
                            .padding(.horizontal, 18).padding(.vertical, 16)
                            .background(Color.white.opacity(0.8),
                                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(language.nativeName)
                    }
                }
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
        }
    }
}
