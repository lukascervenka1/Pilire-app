// Separate simulator bundle with an in-memory wallet. No player data is read.
import SwiftUI
import SwiftData
@testable import Pilire

@MainActor @Observable final class MarketCheck {
    let container: ModelContainer
    let settings: UserSettings
    var textSize: DynamicTypeSize = .large
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var section: MarketSection = .requests
    init() {
        Language.shared.choose(.cs)
        UserDefaults.standard.removeObject(forKey: "marketClaimedOffers")
        container = try! ModelContainer(for: UserSettings.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        settings = UserSettings(); settings.coinBalance = 240
        settings.woodCount = 12; settings.brickCount = 1; settings.steelCount = 0
        container.mainContext.insert(settings)
        if ProcessInfo.processInfo.arguments.contains("--large-text") { textSize = .accessibility5 }
        if ProcessInfo.processInfo.arguments.contains("--small") { width = 375 }
        if ProcessInfo.processInfo.arguments.contains("--landscape") { width = 812; height = 375 }
        if ProcessInfo.processInfo.arguments.contains("--supplies") { section = .supplies }
        if ProcessInfo.processInfo.arguments.contains("--settled") {
            for offer in Market.offers(hasMarketHall: true) {
                Market.receive(offer.give, settings)
                precondition(Market.accept(offer, settings))
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--english") { Language.shared.choose(.en) }
    }
    func capture() async {
        try? await Task.sleep(for: .seconds(1.2))
        try! MerchantPortrait.image.pngData()!.write(to: URL.documentsDirectory.appending(path: "matej.png"))
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: \.isKeyWindow) {
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let options = ProcessInfo.processInfo.arguments.dropFirst().joined(separator: "-").replacingOccurrences(of: "--", with: "")
            let name = options.isEmpty ? "market" : options
            try! image.pngData()!.write(to: URL.documentsDirectory.appending(path: name + ".png"))

            // Render the same native view at useful review sizes. These windows
            // belong only to this separate preview app.
            let variants: [(String, CGSize, DynamicTypeSize, MarketSection)] = [
                ("small", CGSize(width: 375, height: 812), .large, .requests),
                ("supplies", CGSize(width: 375, height: 1400), .large, .supplies),
                ("large-text", CGSize(width: 375, height: 1600), .accessibility5, .requests),
                ("landscape", CGSize(width: 812, height: 375), .large, .supplies),
                ("tablet", CGSize(width: 834, height: 1194), .large, .requests),
            ]
            for (file, size, type, section) in variants {
                let content = MarketView(settings: settings, hasMarketHall: true, initialSection: section)
                    .modelContainer(container).environment(\.dynamicTypeSize, type).preferredColorScheme(.light)
                let host = UIHostingController(rootView: content)
                let reviewWindow = UIWindow(windowScene: scene)
                reviewWindow.frame = CGRect(origin: .zero, size: size)
                reviewWindow.rootViewController = host
                reviewWindow.makeKeyAndVisible()
                host.view.frame = reviewWindow.bounds
                host.view.setNeedsLayout(); host.view.layoutIfNeeded()
                try? await Task.sleep(for: .milliseconds(350))
                let capture = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                try! capture.pngData()!.write(to: URL.documentsDirectory.appending(path: file + ".png"))
                reviewWindow.isHidden = true
            }
            window.makeKeyAndVisible()
        }
    }
}

@main struct MarketPreviewApp: App {
    @State private var check = MarketCheck()
    var body: some Scene {
        WindowGroup {
            MarketView(settings: check.settings, hasMarketHall: true, initialSection: check.section)
                .modelContainer(check.container)
                .environment(\.dynamicTypeSize, check.textSize)
                .frame(width: check.width, height: check.height)
                .frame(maxWidth: .infinity)
                .background(Theme.creamTop)
                .preferredColorScheme(.light)
                .task { await check.capture() }
        }
    }
}
