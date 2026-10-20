import SwiftUI
import SwiftData

// MARK: - Pilíře design system
//
// Single source of truth for brand colors (light / "night cream" dark),
// corner-radius rhythm and small shared helpers.

enum Theme {

    // MARK: Corner radius rhythm (2 values + capsules)
    /// Cards, sheets, banners, large surfaces.
    static let cardRadius: CGFloat = 20
    /// Rows, buttons, chips, small tiles.
    static let rowRadius: CGFloat = 12

    // MARK: Brand "cream" — the app is locked to one warm, light look.

    /// Top of the brand background gradient.
    static let creamTop = Color(red: 0.97, green: 0.95, blue: 0.90)   // parchment

    /// Bottom of the brand background gradient.
    static let creamBottom = Color(red: 0.91, green: 0.93, blue: 0.86)

    /// Solid surface used by the floating tab bar / raised panels.
    static let panel = Color(red: 0.97, green: 0.95, blue: 0.89)

    /// Warm secondary label used on the cream surfaces.
    static let creamLabel = Color(red: 0.45, green: 0.40, blue: 0.33)

    /// Hairline/edge stroke.
    static let hairline = Color(white: 1, opacity: 0.65)

    /// The brand background as a ready-to-use gradient.
    static var creamGradient: LinearGradient {
        LinearGradient(colors: [creamTop, creamBottom], startPoint: .top, endPoint: .bottom)
    }

    // Warm accent shared across the app (unchanged in dark mode)
    static let accentTop = Color(red: 0.98, green: 0.64, blue: 0.22)
    static let accentBottom = Color(red: 0.93, green: 0.52, blue: 0.16)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom)
    }

    // Calendar and its wooden weekly chest.
    static let calendarSage = Color(red: 0.74, green: 0.85, blue: 0.73)
    static let calendarGreen = Color(red: 0.14, green: 0.27, blue: 0.18)
    static let chestButtonLabel = Color(red: 0.22, green: 0.16, blue: 0.08)
    static let chestRare = Color(red: 0.20, green: 0.40, blue: 0.56)
    static let chestGold = Color(red: 0.48, green: 0.34, blue: 0.09)
}

// MARK: - Resource info (long-press a HUD chip → small bottom sheet)

struct ResourceInfoModifier: ViewModifier {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.35) {
                Haptics.tap()
                show = true
            }
            .sheet(isPresented: $show) {
                VStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 34))
                        .foregroundStyle(tint)
                        .frame(width: 72, height: 72)
                        .background(tint.opacity(0.12), in: Circle())
                        .padding(.top, 24)

                    Text(title)
                        .font(.system(.title3, design: .rounded).bold())

                    Text(message)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)

                    Button {
                        show = false
                    } label: {
                        Text(L(S.info.understood))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Theme.accentGradient,
                                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                    Spacer(minLength: 12)
                }
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .accessibilityHint(L(S.info.holdHint))
    }
}

extension View {
    /// Long-press explanation of a game resource, shown as a small sheet.
    func resourceInfo(icon: String, tint: Color, _ title: String, _ message: String) -> some View {
        modifier(ResourceInfoModifier(icon: icon, tint: tint, title: title, message: message))
    }
}

// MARK: - Safe SwiftData saves

extension ModelContext {
    /// Persists pending changes, surfacing failures loudly in DEBUG instead of
    /// swallowing them with `try?`.
    func saveChanges(_ context: StaticString = #function) {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            #if DEBUG
            assertionFailure("SwiftData save failed in \(context): \(error)")
            #else
            print("SwiftData save failed in \(context): \(error)")
            #endif
        }
    }
}
