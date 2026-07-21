import UIKit

/// Lightweight haptic helper — pre-warmed generators for snappy feedback.
enum Haptics {
    private static let light  = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid  = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func tap()     { light.impactOccurred() }
    static func pickup()  { medium.impactOccurred() }
    static func drop()    { rigid.impactOccurred() }
    static func success() { notify.notificationOccurred(.success) }
    static func warning() { notify.notificationOccurred(.warning) }
}
