import SwiftUI

// MARK: - Onboarding flow (first launch)

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0
    private let pages = OnboardPage.all

    var body: some View {
        ZStack {
            // Soft app-branded backdrop
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.96, blue: 0.93),
                         Color(red: 0.90, green: 0.93, blue: 0.86)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip
                HStack {
                    Spacer()
                    if page < pages.count - 1 {
                        Button("Přeskočit") { finish() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 24)
                    }
                }
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                        OnboardPageView(page: p)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4), value: page)

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? pages[page].accent : Color.secondary.opacity(0.25))
                            .frame(width: i == page ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35), value: page)
                    }
                }
                .padding(.bottom, 24)

                // CTA
                Button {
                    if page < pages.count - 1 {
                        Haptics.tap()
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                } label: {
                    Text(page < pages.count - 1 ? "Pokračovat" : "Pojďme na to")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [pages[page].accent, pages[page].accent.opacity(0.82)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
                        )
                        .foregroundStyle(.white)
                        .shadow(color: pages[page].accent.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }

    private func finish() {
        Haptics.success()
        onFinish()
    }
}

// MARK: - Single page

private struct OnboardPageView: View {
    let page: OnboardPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Illustration with soft glow
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [page.accent.opacity(0.22), .clear],
                                       center: .center, startRadius: 10, endRadius: 150)
                    )
                    .frame(width: 300, height: 300)

                page.illustration
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
            }
            .frame(height: 300)

            Spacer()

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
            }
            .offset(y: appeared ? 0 : 16)
            .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.08)) {
                appeared = true
            }
        }
    }
}

// MARK: - Page model

private struct OnboardPage {
    let title: String
    let subtitle: String
    let accent: Color
    let illustration: AnyView

    static let all: [OnboardPage] = [
        OnboardPage(
            title: "Vítej v Pilířích",
            subtitle: "Každé ráno si zapiš 3 až 5 nejdůležitějších úkolů dne, svoje pilíře. Žádný nekonečný seznam, jen to, na čem ti opravdu záleží.",
            accent: Color(red: 0.91, green: 0.49, blue: 0.24),
            illustration: AnyView(ChecklistIllustration())
        ),
        OnboardPage(
            title: "Plň a sbírej",
            subtitle: "Za splněné pilíře dostáváš materiál, dřevo, cihly a ocel. Momentum ti odměny násobí a nikdy tě netrestá. Roste, když jsi aktivní, a po pauze klesá jen pomalu.",
            accent: Color(red: 0.94, green: 0.72, blue: 0.18),
            illustration: AnyView(CoinsIllustration())
        ),
        OnboardPage(
            title: "Postav své město",
            subtitle: "Za nasbíraný materiál postavíš budovu podle vlastního výběru, kam chceš. Podrž a táhni, když ji chceš přesunout, dvojklikem ji otočíš.",
            accent: Color(red: 0.36, green: 0.55, blue: 0.35),
            illustration: AnyView(IsoHouseIllustration())
        ),
        OnboardPage(
            title: "Zkrášli ho",
            subtitle: "Za nasbírané mince nakoupíš stromy, cesty a fontány. Ať tvoje město roste spolu s tebou.",
            accent: Color(red: 0.33, green: 0.56, blue: 0.72),
            illustration: AnyView(DecorIllustration())
        ),
    ]
}

// MARK: - Illustrations (flat, matching game art)

/// Isometric flat-shaded house drawn with Paths — mirrors the in-game asset style.
private struct IsoHouseIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height * 0.62
            let tw: CGFloat = 130   // tile width
            let th: CGFloat = 65
            let bh: CGFloat = 62    // wall height
            let rh: CGFloat = 30    // roof rise

            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + x, y: cy - y) }

            // Ground tile
            var ground = Path()
            ground.move(to: P(0, -th/2 - 8))
            ground.addLine(to: P(tw/2 + 14, -8))
            ground.addLine(to: P(0, th/2 - 8))
            ground.addLine(to: P(-tw/2 - 14, -8))
            ground.closeSubpath()
            ctx.fill(ground, with: .color(Color(red: 0.42, green: 0.58, blue: 0.33)))

            let body = Color(red: 0.863, green: 0.769, blue: 0.627)
            let roof = Color(red: 0.776, green: 0.420, blue: 0.306)

            // Right wall (shadow)
            var rw = Path()
            rw.move(to: P(0, bh - th/2)); rw.addLine(to: P(tw/2, bh))
            rw.addLine(to: P(tw/2, 0));   rw.addLine(to: P(0, -th/2))
            rw.closeSubpath()
            ctx.fill(rw, with: .color(body.opacity(1).shade(0.64)))

            // Left wall (lit)
            var lw = Path()
            lw.move(to: P(-tw/2, bh)); lw.addLine(to: P(0, bh - th/2))
            lw.addLine(to: P(0, -th/2)); lw.addLine(to: P(-tw/2, 0))
            lw.closeSubpath()
            ctx.fill(lw, with: .color(body.shade(0.84)))

            // Roof slopes
            let rH = bh + rh
            var rs = Path()
            rs.move(to: P(0, bh - th/2)); rs.addLine(to: P(tw/2, bh))
            rs.addLine(to: P(tw/4, rH));   rs.addLine(to: P(0, rH - th/4))
            rs.closeSubpath()
            ctx.fill(rs, with: .color(roof.shade(0.72)))

            var ls = Path()
            ls.move(to: P(-tw/2, bh));     ls.addLine(to: P(0, bh - th/2))
            ls.addLine(to: P(0, rH - th/4)); ls.addLine(to: P(-tw/4, rH))
            ls.closeSubpath()
            ctx.fill(ls, with: .color(roof.shade(0.96)))

            var ridge = Path()
            ridge.move(to: P(0, rH + th/4)); ridge.addLine(to: P(tw/4, rH))
            ridge.addLine(to: P(0, rH - th/4)); ridge.addLine(to: P(-tw/4, rH))
            ridge.closeSubpath()
            ctx.fill(ridge, with: .color(roof.shade(1.08)))

            // Window (right face) + door (left face)
            var win = Path()
            let wx: CGFloat = tw * 0.26, wy: CGFloat = bh * 0.45
            win.move(to: P(wx - 9, wy)); win.addLine(to: P(wx + 9, wy + 9))
            win.addLine(to: P(wx + 9, wy - 9)); win.addLine(to: P(wx - 9, wy - 18))
            win.closeSubpath()
            ctx.fill(win, with: .color(Color(red: 0.93, green: 0.85, blue: 0.61)))

            var door = Path()
            let dx: CGFloat = -tw * 0.24
            door.move(to: P(dx - 8, 24)); door.addLine(to: P(dx + 8, 32))
            door.addLine(to: P(dx + 8, 4)); door.addLine(to: P(dx - 8, -4))
            door.closeSubpath()
            ctx.fill(door, with: .color(Color(red: 0.353, green: 0.275, blue: 0.212)))
        }
        .frame(width: 260, height: 240)
    }
}

private struct ChecklistIllustration: View {
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    Image(systemName: i < 2 ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(i < 2 ? Color(red: 0.36, green: 0.65, blue: 0.36) : .secondary)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: CGFloat(120 - i * 24), height: 10)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            }
        }
        .frame(width: 230)
    }
}

private struct CoinsIllustration: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.25),
                                                Color(red: 0.93, green: 0.65, blue: 0.13)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
                    .offset(x: CGFloat(i - 1) * 44, y: CGFloat(abs(i - 1)) * 26)
                    .zIndex(i == 1 ? 1 : 0)
            }
            Text("×2")
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(red: 0.91, green: 0.49, blue: 0.24), in: Capsule())
                .offset(x: 62, y: -52)
        }
    }
}

private struct DecorIllustration: View {
    var body: some View {
        HStack(spacing: 26) {
            symbolTile("tree.fill",  Color(red: 0.36, green: 0.60, blue: 0.34))
            symbolTile("drop.fill",  Color(red: 0.36, green: 0.62, blue: 0.80))
                .offset(y: -22)
            symbolTile("road.lanes", Color(red: 0.64, green: 0.55, blue: 0.42))
        }
    }

    private func symbolTile(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 76, height: 76)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
    }
}

// MARK: - Color shade helper (SwiftUI)

private extension Color {
    func shade(_ f: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), opacity: a)
    }
}
