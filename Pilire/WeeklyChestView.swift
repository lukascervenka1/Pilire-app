import SwiftUI

struct WeeklyChestCard: View {
    let week: WeeklyChestProgress.Week
    let availableCount: Int
    let rangeLabel: String
    let isBusy: Bool
    let onOpen: () -> Void

    private var canOpen: Bool { availableCount > 0 }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                Text(L(S.calendar.weeklyReward))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.creamLabel)
                Text(L(S.calendar.chestTitle))
                    .font(.system(.title3, design: .rounded).bold())
                Text(rangeLabel)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
            }
            HStack(spacing: 5) {
                ForEach(week.days) { day in
                    VStack(spacing: 7) {
                        Text(day.date, format: .dateTime.weekday(.abbreviated)
                            .locale(Language.shared.current.locale))
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Image(systemName: day.isComplete ? "checkmark" : day.isFuture ? "circle" :
                                day.date == week.today ? "sun.max" : "minus")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(day.isComplete ? Theme.calendarGreen : Theme.creamLabel)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(day.isComplete ? Theme.calendarSage : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        if day.date == week.today {
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(Theme.accentBottom.opacity(0.65), lineWidth: 1.5)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)
                        .locale(Language.shared.current.locale)))
                    .accessibilityValue(day.isComplete ? L(S.calendar.dayComplete) :
                        day.isFuture ? L(S.calendar.dayAhead) :
                        day.date == week.today ? L(S.calendar.dayToday) : L(S.calendar.dayMissed))
                }
            }
            WeeklyChestArtwork()
                .frame(height: 150)
                .padding(.vertical, -8)
            VStack(spacing: 6) {
                Text(canOpen ? L(S.calendar.chestReady) :
                     week.isClaimed ? L(S.calendar.chestClaimed) :
                     L(S.calendar.weekProgress, week.completedCount))
                    .font(.system(.subheadline, design: .rounded).bold())
                Text(canOpen ? L(S.calendar.readyQuestion) :
                     week.isClaimed ? L(S.calendar.claimedHint) :
                     week.hasMissedDay ? L(S.calendar.missedHint) : L(S.calendar.chestRule))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if availableCount > 1 {
                    Text(L(S.calendar.moreChests, availableCount - 1))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.creamLabel)
                }
            }
            .multilineTextAlignment(.center)

            if canOpen {
                Button(action: onOpen) {
                    Text(L(S.calendar.openChest))
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Theme.chestButtonLabel)
                        .background(Theme.accentGradient,
                                    in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }
}

struct WeeklyChestReveal: View {
    let receipt: WeeklyChestReceipt
    let onContinue: () -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var rewardFocused: Bool
    @State private var phase: ChestRevealPhase = .closed
    @State private var saveFailed = false

    private var isRevealed: Bool { phase == .revealed }
    private var rarityColor: Color {
        guard phase.rawValue >= ChestRevealPhase.opened.rawValue else { return Theme.creamLabel }
        switch receipt.reward.rarity {
        case .common: return Theme.creamLabel
        case .rare: return Theme.chestRare
        case .epic: return Theme.chestGold
        }
    }
    private var rewardHint: String {
        switch receipt.reward.rarity {
        case .common: return L(S.calendar.commonHint)
        case .rare: return L(S.calendar.rareHint)
        case .epic: return L(S.calendar.epicHint)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(L(S.calendar.weeklyReward))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.creamLabel)
                        Text(L(S.calendar.chestTitle))
                            .font(.system(.title, design: .rounded).bold())
                    }
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [
                                rarityColor.opacity(phase.rawValue >= ChestRevealPhase.opened.rawValue ? 0.22 : 0.06),
                                .clear
                            ], center: .center, startRadius: 5, endRadius: 130))
                            .frame(width: 260, height: 260)
                        WeeklyChestSceneView(phase: phase, rarity: receipt.reward.rarity,
                                             reduceMotion: reduceMotion)
                            .frame(height: 245)
                    }
                    .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(isRevealed ? receipt.reward.rarity.title : L(S.calendar.sevenSteps))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(rarityColor)
                        Text(isRevealed ? receipt.reward.label : L(S.calendar.openingChest))
                            .font(.system(.title2, design: .rounded).bold())
                            .multilineTextAlignment(.center)
                        Text(isRevealed ? rewardHint : L(S.calendar.readyQuestion))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.creamLabel)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 115)
                    .accessibilityElement(children: .combine)
                    .accessibilityFocused($rewardFocused)
                    if saveFailed {
                        Text(L(S.calendar.rewardSaveError))
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        saveFailed = !onContinue()
                    } label: {
                        Text(L(S.calendar.continueReward))
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(Theme.chestButtonLabel)
                            .background(Theme.accentGradient,
                                        in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isRevealed)
                    .opacity(isRevealed ? 1 : 0)
                    .accessibilityHidden(!isRevealed)
                }
                .padding(28)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(Theme.creamGradient.ignoresSafeArea())
        .interactiveDismissDisabled()
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await reveal()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced && !isRevealed { finish() }
        }
    }

    @MainActor
    private func reveal() async {
        if reduceMotion {
            if !isRevealed { SoundManager.shared.play(.chest); finish() }
            return
        }
        do {
            if phase == .closed {
                phase = .stirring
                Haptics.tap()
            }
            if phase == .stirring {
                try await Task.sleep(for: .milliseconds(700))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.35)) { phase = .glowing }
            }
            if phase == .glowing {
                try await Task.sleep(for: .milliseconds(650))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.5)) { phase = .opened }
                Haptics.pickup()
                SoundManager.shared.play(.chest)
            }
            if phase == .opened {
                try await Task.sleep(for: .milliseconds(850))
                try Task.checkCancellation()
                withAnimation(.easeOut(duration: 0.25)) { finish() }
            }
        } catch {
            // Scene changes cancel the wait. Resume the same saved result on return.
        }
    }

    @MainActor
    private func finish() {
        guard !isRevealed else { return }
        phase = .revealed
        switch receipt.reward.rarity {
        case .common: Haptics.tap()
        case .rare: Haptics.success()
        case .epic: Haptics.drop(); Haptics.success()
        }
        rewardFocused = true
    }
}
