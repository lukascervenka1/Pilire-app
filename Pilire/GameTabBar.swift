import SwiftUI

/// Custom bottom bar styled to match the game — warm cream panel, orange pill
/// on the active tab, and a raised hammer button in the middle for building.
struct GameTabBar: View {
    @Binding var selection: Int
    var pulseBuild: Bool = false
    var onBuild: () -> Void
    @State private var pulsing = false
    @State private var hammerBounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let left:  [(icon: String, label: String, tag: Int)] = [
        ("map.fill",  L(S.tabs.town),  0),
        ("checklist", L(S.tabs.pillars), 1),
    ]
    private let right: [(icon: String, label: String, tag: Int)] = [
        ("calendar",         L(S.tabs.calendar), 2),
        ("book.closed.fill", L(S.tabs.chronicle),  3),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(left,  id: \.tag) { tabButton($0) }
            buildButton
            ForEach(right, id: \.tag) { tabButton($0) }
        }
        .padding(6)
        // Hit-absorbing backing: glass is translucent and does not block taps,
        // so without a solid layer a tap in the gaps between tab buttons falls
        // through to the "Uzavřít den" button that sits behind the bar.
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Color.black.opacity(0.001))
        )
        // Liquid Glass — floats over the 3D city and adapts to light/dark.
        .glassEffect(in: .rect(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Tab item

    private func tabButton(_ item: (icon: String, label: String, tag: Int)) -> some View {
        Button {
            guard selection != item.tag else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = item.tag
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selection == item.tag ? Color.white : Theme.creamLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if selection == item.tag {
                    RoundedRectangle(cornerRadius: Theme.rowRadius)
                        .fill(Theme.accentGradient)
                        .shadow(color: Color.orange.opacity(0.35), radius: 6, y: 3)
                        .matchedGeometryEffect(id: "activeTab", in: ns)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Raised hammer (build / expand)

    private var buildButton: some View {
        Button {
            Haptics.tap()
            hammerBounce += 1          // triggers a purpose-built SF Symbol bounce
            onBuild()
        } label: {
            ZStack {
                // Tutorial affordance. With reduce motion on, we show a steady
                // ring instead of an expanding pulse.
                if pulseBuild {
                    Circle()
                        .stroke(Color.orange, lineWidth: 3)
                        .frame(width: 46, height: 46)
                        .scaleEffect(reduceMotion ? 1.12 : (pulsing ? 1.45 : 1))
                        .opacity(reduceMotion ? 0.6 : (pulsing ? 0 : 0.9))
                }
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: Color.orange.opacity(0.40), radius: 7, y: 3)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
                Image(systemName: "hammer.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: hammerBounce)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(S.misc.buildBuilding))
        .onChange(of: pulseBuild, initial: true) { _, on in
            guard !reduceMotion else { pulsing = false; return }
            if on {
                pulsing = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            } else {
                pulsing = false
            }
        }
    }

    @Namespace private var ns
}
