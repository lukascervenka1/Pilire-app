import SwiftUI

/// The day's progress as the app-icon monument under construction —
/// Monument Valley style: a floating grass island, golden pedestal, and one
/// marble block per completed task. A full day earns the golden finial.
/// Geometry matches the icon: consistent 2:1 isometric, soft pastel shading.
struct PillarProgressView: View {
    let total: Int      // tasks today (slots)
    let done: Int       // completed tasks (placed blocks)

    private var slots: Int { min(max(total, 1), 5) }
    private var filled: Int { min(done, slots) }
    private var isComplete: Bool { total > 0 && done >= total }

    // Element sizes (width, faceHeight); depth is always width/2
    private let islandW: CGFloat = 70
    private let islandH: CGFloat = 11
    private let blockW: CGFloat = 32
    private let blockH: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            // Top-diamond center chain, bottom-up (nesting is width-independent)
            let ycGrass = H - islandW / 4 - islandH - 4
            let ycPed = ycGrass - 10
            let ycBlock: (Int) -> CGFloat = { i in ycPed - blockH * CGFloat(i + 1) }
            let ycFinial = ycBlock(slots - 1) - 6

            ZStack(alignment: .topLeading) {
                // Grass base (a piece of the town)
                slab(w: islandW, h: islandH,
                     top: Color(red: 0.58, green: 0.74, blue: 0.44),
                     left: Color(red: 0.58, green: 0.47, blue: 0.38),
                     right: Color(red: 0.47, green: 0.38, blue: 0.30))
                    .offset(x: (W - islandW) / 2, y: ycGrass - islandW / 4)

                // Golden pedestal — one chunky tier
                goldSlab(w: 50, h: 10)
                    .offset(x: (W - 50) / 2, y: ycPed - 12.5)

                // Column blocks
                ForEach(0..<slots, id: \.self) { i in
                    let y = ycBlock(i) - blockW / 4
                    if i < filled {
                        marbleSlab(w: blockW, h: blockH)
                            .offset(x: (W - blockW) / 2, y: y)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    } else {
                        slabOutline(w: blockW, h: blockH)
                            .offset(x: (W - blockW) / 2, y: y)
                    }
                }

                // Golden cap for a complete day
                if isComplete {
                    goldSlab(w: 18, h: 6)
                        .offset(x: (W - 18) / 2, y: ycFinial - 4.5)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: filled)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: slots)
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: isComplete)
    }

    // MARK: - Palette shortcuts (matches the app icon)

    private func goldSlab(w: CGFloat, h: CGFloat) -> some View {
        slab(w: w, h: h,
             top: Color(red: 0.97, green: 0.83, blue: 0.44),
             left: Color(red: 0.91, green: 0.75, blue: 0.36),
             right: Color(red: 0.80, green: 0.63, blue: 0.27))
    }

    private func marbleSlab(w: CGFloat, h: CGFloat) -> some View {
        slab(w: w, h: h,
             top: Color(red: 0.99, green: 0.97, blue: 0.92),
             left: Color(red: 0.94, green: 0.91, blue: 0.85),
             right: Color(red: 0.85, green: 0.81, blue: 0.74))
    }

    // MARK: - Iso primitives (2:1, symmetric)

    private func slab(w: CGFloat, h: CGFloat, top: Color, left: Color, right: Color) -> some View {
        Canvas { ctx, _ in
            let hw = w / 2, hd = w / 4

            var lf = Path()
            lf.move(to: CGPoint(x: 0, y: hd))
            lf.addLine(to: CGPoint(x: hw, y: hd * 2))
            lf.addLine(to: CGPoint(x: hw, y: hd * 2 + h))
            lf.addLine(to: CGPoint(x: 0, y: hd + h))
            lf.closeSubpath()
            ctx.fill(lf, with: .color(left))

            var rf = Path()
            rf.move(to: CGPoint(x: hw, y: hd * 2))
            rf.addLine(to: CGPoint(x: w, y: hd))
            rf.addLine(to: CGPoint(x: w, y: hd + h))
            rf.addLine(to: CGPoint(x: hw, y: hd * 2 + h))
            rf.closeSubpath()
            ctx.fill(rf, with: .color(right))

            var tp = Path()
            tp.move(to: CGPoint(x: hw, y: 0))
            tp.addLine(to: CGPoint(x: w, y: hd))
            tp.addLine(to: CGPoint(x: hw, y: hd * 2))
            tp.addLine(to: CGPoint(x: 0, y: hd))
            tp.closeSubpath()
            ctx.fill(tp, with: .color(top))
        }
        .frame(width: w, height: w / 2 + h)
    }

    private func slabOutline(w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, _ in
            let hw = w / 2, hd = w / 4
            var p = Path()
            p.move(to: CGPoint(x: hw, y: 0))
            p.addLine(to: CGPoint(x: w, y: hd))
            p.addLine(to: CGPoint(x: w, y: hd + h))
            p.addLine(to: CGPoint(x: hw, y: hd * 2 + h))
            p.addLine(to: CGPoint(x: 0, y: hd + h))
            p.addLine(to: CGPoint(x: 0, y: hd))
            p.closeSubpath()
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.32)),
                       style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
        }
        .frame(width: w, height: w / 2 + h)
    }
}