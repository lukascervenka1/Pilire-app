import SwiftUI

// MARK: - Root wrapper: splash → app

struct RootView: View {
    @State private var showSplash = true
    @State private var language = Language.shared

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            // First launch: pick a language before anything else happens.
            if !language.hasChosen {
                LanguagePickerView { picked in
                    withAnimation(.easeOut(duration: 0.3)) { language.choose(picked) }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        // Dates, calendars and number formats follow the chosen language, and
        // the id forces a clean redraw when it changes.
        .environment(\.locale, language.current.locale)
        .id(language.current)
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

            // Palette
            let goldTop = Color(red: 0.98, green: 0.84, blue: 0.45)
            let goldL   = Color(red: 0.91, green: 0.74, blue: 0.34)
            let goldR   = Color(red: 0.77, green: 0.60, blue: 0.24)
            let marbT   = Color(red: 0.99, green: 0.97, blue: 0.92)
            let marbL   = Color(red: 0.93, green: 0.90, blue: 0.83)
            let marbR   = Color(red: 0.79, green: 0.75, blue: 0.67)

            /// One isometric box. `ty` is the centre of its TOP diamond; the box
            /// then extends downward by `h`. Boxes stack by putting a child's
            /// `ty` at `parent.ty - childHeight`, so everything sits cleanly.
            func box(_ cxx: CGFloat, _ ty: CGFloat, w: CGFloat, d: CGFloat, h: CGFloat,
                     top: Color, left: Color, right: Color, flutes: Bool = false) {
                let hw = w / 2, hd = d / 2
                let N = CGPoint(x: cxx, y: ty - hd)
                let E = CGPoint(x: cxx + hw, y: ty)
                let S = CGPoint(x: cxx, y: ty + hd)
                let W = CGPoint(x: cxx - hw, y: ty)

                var lf = Path()          // front-left face
                lf.move(to: W); lf.addLine(to: S)
                lf.addLine(to: CGPoint(x: S.x, y: S.y + h))
                lf.addLine(to: CGPoint(x: W.x, y: W.y + h)); lf.closeSubpath()
                ctx.fill(lf, with: .color(left))

                var rf = Path()          // front-right face
                rf.move(to: S); rf.addLine(to: E)
                rf.addLine(to: CGPoint(x: E.x, y: E.y + h))
                rf.addLine(to: CGPoint(x: S.x, y: S.y + h)); rf.closeSubpath()
                ctx.fill(rf, with: .color(right))

                if flutes {              // subtle vertical grooves on the shaft
                    for f in [0.34, 0.68] as [CGFloat] {
                        let a = CGPoint(x: W.x + (S.x - W.x) * f, y: W.y + (S.y - W.y) * f)
                        var g = Path(); g.move(to: a); g.addLine(to: CGPoint(x: a.x, y: a.y + h))
                        ctx.stroke(g, with: .color(.black.opacity(0.06)), lineWidth: 1.1)
                        let b = CGPoint(x: S.x + (E.x - S.x) * f, y: S.y + (E.y - S.y) * f)
                        var g2 = Path(); g2.move(to: b); g2.addLine(to: CGPoint(x: b.x, y: b.y + h))
                        ctx.stroke(g2, with: .color(.black.opacity(0.06)), lineWidth: 1.1)
                    }
                }

                var tp = Path()          // top diamond
                tp.move(to: N); tp.addLine(to: E); tp.addLine(to: S); tp.addLine(to: W); tp.closeSubpath()
                ctx.fill(tp, with: .color(top))
            }

            // Heights
            let h1: CGFloat = 22, h2: CGFloat = 18, hBase: CGFloat = 10
            let hShaft: CGFloat = 92, hCap: CGFloat = 11, hFin: CGFloat = 14

            // Vertical stack (top-diamond centres), bottom step anchored low.
            let ty1 = size.height * 0.74          // bottom pedestal step
            let ty2 = ty1 - h2                     // upper pedestal step
            let tyBase = ty2 - hBase               // marble base plate
            let tyShaft = tyBase - hShaft          // column shaft
            let tyCap = tyShaft - hCap             // marble capital
            let tyFin = tyCap - hFin               // golden finial

            // Draw bottom → top so higher pieces sit in front.
            box(cx, ty1, w: 140, d: 50, h: h1, top: goldTop, left: goldL, right: goldR)
            box(cx, ty2, w: 104, d: 38, h: h2, top: goldTop, left: goldL, right: goldR)
            box(cx, tyBase, w: 64, d: 24, h: hBase, top: marbT, left: marbL, right: marbR)
            box(cx, tyShaft, w: 40, d: 16, h: hShaft, top: marbT, left: marbL, right: marbR, flutes: true)
            box(cx, tyCap, w: 50, d: 20, h: hCap, top: marbT, left: marbL, right: marbR)
            box(cx, tyFin, w: 24, d: 10, h: hFin, top: goldTop, left: goldL, right: goldR)
        }
    }
}

// MARK: - Motivational quotes

enum SplashQuotes {
    static var all: [String] { S.quotes.all }

    static func random() -> String {
        all.randomElement() ?? all[0]
    }
}
