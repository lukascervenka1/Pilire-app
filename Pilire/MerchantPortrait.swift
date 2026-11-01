import UIKit

/// Original 3D character authored in Art/Merchant/matej.blend, flat-shaded and
/// lit like the town, rendered on a path with softly fading meadow edges.
/// A compiled image keeps the market lightweight and its appearance consistent.
@MainActor
enum MerchantPortrait {
    static let image = UIImage(resource: .merchantMatej)
}
