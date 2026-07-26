import SwiftUI

// MARK: - Interactive tutorial — walks the player through the first loop
// (write a task → complete it → close the day → build something)

enum TutorialStep: Int {
    case addTask = 0, completeTask, build
}

@MainActor
@Observable
final class Tutorial {
    static let shared = Tutorial()

    /// -1 = inactive/finished, 0…3 = current step
    private(set) var step: Int

    private init() {
        step = UserDefaults.standard.object(forKey: "tutorialStep") as? Int ?? -1
    }

    private func set(_ v: Int) {
        step = v
        UserDefaults.standard.set(v, forKey: "tutorialStep")
    }

    /// Kick off after onboarding.
    func start() {
        guard !UserDefaults.standard.bool(forKey: "tutorialDone") else { return }
        set(TutorialStep.addTask.rawValue)
    }

    /// Advance when the player actually performs the expected action.
    func advance(from expected: TutorialStep) {
        guard step == expected.rawValue else { return }
        if expected == .build {
            finish()
        } else {
            set(step + 1)
        }
    }

    func skip() { finish() }

    private func finish() {
        set(-1)
        UserDefaults.standard.set(true, forKey: "tutorialDone")
        Haptics.success()
    }

    var isActive: Bool { step >= 0 }
    var current: TutorialStep? { TutorialStep(rawValue: step) }
}

// MARK: - Banner shown above the tab bar

struct TutorialBanner: View {
    let step: TutorialStep
    let currentTab: Int
    var onGoToTasks: () -> Void
    var onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [Color(red: 0.98, green: 0.64, blue: 0.22),
                                            Color(red: 0.93, green: 0.52, blue: 0.16)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(i <= step.rawValue ? Color.orange : Color.secondary.opacity(0.25))
                            .frame(width: i == step.rawValue ? 18 : 7, height: 5)
                    }
                    Spacer()
                    Button {
                        onSkip()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                Text(text)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if step == .addTask && currentTab != 1 {
                    Button(action: onGoToTasks) {
                        Text(L(S.tutorial.openPillars))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.panel)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var icon: String {
        switch step {
        case .addTask:      "square.and.pencil"
        case .completeTask: "checkmark.circle"
        case .build:        "hammer.fill"
        }
    }

    private var text: String {
        switch step {
        case .addTask:
            L(S.tutorial.step1)
        case .completeTask:
            L(S.tutorial.step2)
        case .build:
            L(S.tutorial.step3)
        }
    }
}
