import SwiftUI

/// The game's own resource artwork, rendered in Blender in the town's low-poly
/// style by Tools/author_resource_icons.py.
enum ResourceIcon {
    static let coin = "ResourceCoin"
    static let leaf = "ResourceLeaf"
    fileprivate static let prefix = "Resource"
}

/// Draws resource artwork where an SF Symbol used to be, or the symbol itself
/// for any other name. The artwork takes its size from the surrounding font,
/// exactly like a symbol, so it follows Dynamic Type and existing `.font` calls.
struct AppIcon: View {
    let name: String
    init(_ name: String) { self.name = name }

    var body: some View {
        if name.hasPrefix(ResourceIcon.prefix) {
            Image(systemName: "square.fill").hidden()
                .overlay {
                    Image(name).resizable().interpolation(.high).scaledToFit()
                        .scaleEffect(1.18)
                }
                .accessibilityHidden(true)
        } else {
            Image(systemName: name)
        }
    }
}
