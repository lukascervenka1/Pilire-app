import SwiftUI

// MARK: - Root wrapper: splash → app

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // App ships Czech-first for now; proper String Catalog localization
        // (CZ/SK/EN) comes later — this keeps dates & calendars Czech everywhere.
        .environment(\.locale, Locale(identifier: "cs"))
        // The whole app uses one warm, light look. Lock to light mode so the
        // branded cream/pastel design stays consistent regardless of the phone's
        // system appearance.
        .preferredColorScheme(.light)
        .onAppear {
            NotificationManager.requestPermission()
            NotificationManager.scheduleDailyReminders()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
            }
        }
    }
}

// MARK: - Splash screen — pillar logo on a golden pedestal + daily quote

struct SplashView: View {
    @State private var appeared = false
    @State private var quoteShown = false
    private let quote = SplashQuotes.random()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.97, green: 0.95, blue: 0.90),
                         Color(red: 0.91, green: 0.93, blue: 0.86)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    // Golden glow
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color(red: 0.95, green: 0.80, blue: 0.40).opacity(0.35),
                                                    .clear],
                                           center: .center, startRadius: 20, endRadius: 160)
                        )
                        .frame(width: 320, height: 320)
                        .scaleEffect(appeared ? 1 : 0.6)

                    PillarLogoView()
                        .frame(width: 200, height: 210)
                        .scaleEffect(appeared ? 1 : 0.75)
                        .opacity(appeared ? 1 : 0)
                }

                Text("Pilíře")
                    .font(.system(size: 42, design: .rounded).bold())
                    .foregroundStyle(Color(red: 0.30, green: 0.27, blue: 0.22))
                    .padding(.top, 4)
                    .opacity(appeared ? 1 : 0)

                Text(quote)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Color(red: 0.48, green: 0.44, blue: 0.38))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
                    .padding(.top, 14)
                    .opacity(quoteShown ? 1 : 0)
                    .offset(y: quoteShown ? 0 : 8)

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { quoteShown = true }
        }
    }
}

// MARK: - Logo: low-poly pillar on a golden pedestal (matches game art)

struct PillarLogoView: View {
    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let baseY = size.height * 0.88

            // Palette
            let goldTop  = Color(red: 0.97, green: 0.83, blue: 0.44)
            let goldL    = Color(red: 0.90, green: 0.73, blue: 0.33)
            let goldR    = Color(red: 0.76, green: 0.59, blue: 0.24)
            let marbleL  = Color(red: 0.94, green: 0.91, blue: 0.84)
            let marbleR  = Color(red: 0.80, green: 0.76, blue: 0.68)
            let marbleT  = Color(red: 0.98, green: 0.96, blue: 0.91)

            /// Isometric slab: top diamond + left/right faces.
            func slab(cxx: CGFloat, y: CGFloat, w: CGFloat, d: CGFloat, h: CGFloat,
                      top: Color, left: Color, right: Color) {
                let halfW = w / 2, halfD = d / 2
                var lf = Path()
                lf.move(to: CGPoint(x: cxx - halfW, y: y - halfD * 0))
                lf.addLine(to: CGPoint(x: cxx, y: y + halfD))
                lf.addLine(to: CGPoint(x: cxx, y: y + halfD + h))
                lf.addLine(to: CGPoint(x: cxx - halfW, y: y + h))
                lf.closeSubpath()
                ctx.fill(lf, with: .color(left))

                var rf = Path()
                rf.move(to: CGPoint(x: cxx, y: y + halfD))
                rf.addLine(to: CGPoint(x: cxx + halfW, y: y))
                rf.addLine(to: CGPoint(x: cxx + halfW, y: y + h))
                rf.addLine(to: CGPoint(x: cxx, y: y + halfD + h))
                rf.closeSubpath()
                ctx.fill(rf, with: .color(right))

                var tp = Path()
                tp.move(to: CGPoint(x: cxx, y: y - halfD))
                tp.addLine(to: CGPoint(x: cxx + halfW, y: y))
                tp.addLine(to: CGPoint(x: cxx, y: y + halfD))
                tp.addLine(to: CGPoint(x: cxx - halfW, y: y))
                tp.closeSubpath()
                ctx.fill(tp, with: .color(top))
            }

            // Golden pedestal — two stacked slabs
            slab(cxx: cx, y: baseY - 20, w: 130, d: 46, h: 20,
                 top: goldTop, left: goldL, right: goldR)
            slab(cxx: cx, y: baseY - 38, w: 96, d: 34, h: 16,
                 top: goldTop, left: goldL, right: goldR)

            // Column shaft — lit / shadow halves
            let shaftW: CGFloat = 40
            let shaftH: CGFloat = 96
            let shaftTop = baseY - 40 - shaftH
            var shaftL = Path()
            shaftL.addRect(CGRect(x: cx - shaftW/2, y: shaftTop, width: shaftW/2, height: shaftH))
            ctx.fill(shaftL, with: .color(marbleL))
            var shaftR = Path()
            shaftR.addRect(CGRect(x: cx, y: shaftTop, width: shaftW/2, height: shaftH))
            ctx.fill(shaftR, with: .color(marbleR))

            // Flutes (subtle vertical grooves)
            for i in 1..<4 {
                let x = cx - shaftW/2 + CGFloat(i) * shaftW/4
                var line = Path()
                line.addRect(CGRect(x: x - 0.6, y: shaftTop + 3, width: 1.2, height: shaftH - 6))
                ctx.fill(line, with: .color(.black.opacity(0.05)))
            }

            // Base ring & capital (marble slabs)
            slab(cxx: cx, y: baseY - 44, w: 58, d: 20, h: 8,
                 top: marbleT, left: marbleL, right: marbleR)
            slab(cxx: cx, y: shaftTop - 4, w: 58, d: 20, h: 9,
                 top: marbleT, left: marbleL, right: marbleR)

            // Golden finial on top
            slab(cxx: cx, y: shaftTop - 16, w: 26, d: 10, h: 6,
                 top: goldTop, left: goldL, right: goldR)
        }
    }
}

// MARK: - Motivational quotes

enum SplashQuotes {
    static let all: [String] = [
        "Malé kroky staví velká města.",
        "Dnešek je nový kámen v základech.",
        "Nemusíš všechno. Stačí něco.",
        "Každý splněný úkol je cihla k lepšímu dni.",
        "Pomalu se taky dojde daleko.",
        "Tvoje město roste s tebou.",
        "I odpočinek je pilíř.",
        "Začni tím nejmenším.",
        "Dnes stačí jeden dobrý krok.",
        "Silné základy se staví každý den.",
        "Co uděláš dnes, zůstane stát.",
        "Není třeba spěchat, jen nepřestat.",
        "I šedý den může položit zlatý kámen.",
        "Buď na sebe hodný, stavíš celý svět.",
        "Jeden pilíř stačí, aby den stál.",
        "Velké katedrály začínaly jedním kamenem.",
        "Včerejšek je postaven. Dnešek čeká.",
        "Města nerostou přes noc. Ty taky ne, a to je v pořádku.",
    ]

    static func random() -> String {
        all.randomElement() ?? all[0]
    }
}
