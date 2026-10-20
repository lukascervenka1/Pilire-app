import SceneKit

/// A reservation for one reachable bowl, independent of SwiftData and its lifetime.
struct AnimalBowlDestination {
    let id: ObjectIdentifier
    let entrance: AnimalCell
    let standingWorld: SCNVector3
    let yaw: Float
    let isValid: () -> Bool
    let updateProgress: (Double) -> Void
    let consume: () -> Bool
}

enum DogFeedingMotion {
    static let eatClip = "companion_eat"
    static let fedClip = "companion_fed"
    static let eatDuration: TimeInterval = 6.4
    static let fedDuration: TimeInterval = 2.8
    /// Granules disappear during actual muzzle contact, before the head rises.
    static let biteTimes: [TimeInterval] = [1.20, 1.70, 2.20, 2.70, 3.20, 3.70, 4.20, 4.70, 5.20]

    static func muzzleReach(for kind: AnimalKind) -> Float { kind == .husky ? 0.30 : 0.28 }
}
