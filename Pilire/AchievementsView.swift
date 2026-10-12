import SwiftUI
import SwiftData

// MARK: - Kronika summary card
//
// Sits above the day list, so the Kronika opens on "here's how far you've come"
// rather than a wall of dates. Works in the empty state too — a brand-new
// player still sees what there is to aim for.

struct AchievementsCard: View {
    let progress: [AchievementProgress]
    let onOpen: () -> Void

    private var earned: [AchievementProgress] { progress.filter(\.isUnlocked) }

    /// Earned badges first (rarest first, so the best one leads), then whatever
    /// is closest to unlocking — the row always has something to show.
    private var showcase: [AchievementProgress] {
        let done = earned.sorted { rank($0.achievement.tier) > rank($1.achievement.tier) }
        let next = progress.filter { !$0.isUnlocked }.sorted { $0.fraction > $1.fraction }
        return Array((done + next).prefix(5))
    }

    private func rank(_ t: AchievementTier) -> Int {
        switch t {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .legendary: 3
        }
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(L(S.achievements.title))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text("\(earned.count)/\(progress.count)")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .monospacedDigit()
                        .foregroundStyle(Theme.accentBottom)
                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Theme.creamLabel.opacity(0.6))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: geo.size.width * overallFraction)
                    }
                }
                .frame(height: 6)

                // Spread across the full width rather than clumping left with a
                // gap on the end — five badges always fill the row.
                HStack(spacing: 0) {
                    ForEach(showcase) { item in
                        AchievementBadge(progress: item, size: 46)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(S.achievements.cardLabel, earned.count, progress.count))
    }

    private var overallFraction: Double {
        guard !progress.isEmpty else { return 0 }
        return Double(earned.count) / Double(progress.count)
    }
}

// MARK: - Full grid

struct AchievementsView: View {
    let progress: [AchievementProgress]
    @Environment(\.dismiss) private var dismiss
    @State private var selected: AchievementProgress?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var earnedCount: Int { progress.filter(\.isUnlocked).count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary

                    ForEach(AchievementGroup.allCases) { group in
                        let items = progress.filter { $0.achievement.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text(L(group.title))
                                        .font(.system(.headline, design: .rounded))
                                    Text("\(items.filter(\.isUnlocked).count)/\(items.count)")
                                        .font(.system(.caption, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Theme.creamLabel)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.panel, in: Capsule())
                                }

                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(items) { item in
                                        Button { selected = item } label: {
                                            gridCell(item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.creamGradient.ignoresSafeArea())
            .navigationTitle(L(S.achievements.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(S.common.done)) { dismiss() }
                }
            }
        }
        .sheet(item: $selected) { item in
            AchievementDetailSheet(progress: item)
        }
    }

    private var summary: some View {
        VStack(spacing: 6) {
            Text(L(S.achievements.summary, earnedCount, progress.count))
                .font(.system(.title3, design: .rounded).bold())
            Text(L(S.achievements.subtitle))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func gridCell(_ item: AchievementProgress) -> some View {
        VStack(spacing: 6) {
            AchievementBadge(progress: item, size: 60)
            Text(L(item.achievement.title))
                .font(.system(size: 10, design: .rounded).weight(.medium))
                .foregroundStyle(item.isUnlocked ? .primary : Theme.creamLabel)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 26, alignment: .top)
        }
        // Every cell takes its whole column, so the badge centres on the column
        // instead of on its own caption — long titles were nudging them around.
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One badge, up close

struct AchievementDetailSheet: View {
    let progress: AchievementProgress
    @Environment(\.dismiss) private var dismiss

    private var tier: AchievementTier { progress.achievement.tier }

    var body: some View {
        VStack(spacing: 16) {
            AchievementBadge(progress: progress, size: 120)
                .padding(.top, 28)

            VStack(spacing: 6) {
                Text(L(progress.achievement.title))
                    .font(.system(.title3, design: .rounded).bold())
                Text(L(tier.title))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(tier.ink)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(tier.ink.opacity(0.12), in: Capsule())
            }

            Text(L(progress.achievement.detail))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            if progress.isUnlocked {
                VStack(spacing: 4) {
                    Label(L(S.achievements.earned), systemImage: "checkmark.circle.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(tier.ink)
                    // What you actually got to, so an earned badge can be traced
                    // back to the thing that earned it.
                    Text(L(S.achievements.reached, progress.value))
                        .font(.system(.caption, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.creamLabel)
                }
            } else {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(tier.gradient)
                                .frame(width: geo.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 8)
                    Text("\(progress.value) / \(progress.achievement.target)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.creamLabel)
                }
                .padding(.horizontal, 44)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.creamGradient.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - "You earned a badge" celebration

struct AchievementUnlockedOverlay: View {
    let achievement: Achievement
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var tier: AchievementTier { achievement.tier }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(tier.colors[0].opacity(0.18))
                        .frame(width: 150, height: 150)
                        .scaleEffect(shown ? 1 : 0.5)
                    AchievementBadge(
                        progress: AchievementProgress(achievement: achievement,
                                                      value: achievement.target),
                        size: 104)
                        .scaleEffect(shown ? 1 : 0.4)
                        .rotationEffect(.degrees(shown ? 0 : -14))
                }

                VStack(spacing: 6) {
                    Text(L(S.achievements.unlocked))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(tier.colors[0])
                    Text(L(achievement.title))
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(L(achievement.detail))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(shown ? 1 : 0)

                Button(action: onDismiss) {
                    Text(L(S.calendar.nice))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(tier.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .opacity(shown ? 1 : 0)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(Color(red: 0.20, green: 0.17, blue: 0.13),
                        in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .scaleEffect(shown ? 1 : 0.85)
            .padding(.horizontal, 40)
        }
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(S.achievements.unlockedLabel, L(achievement.title)))
    }
}
