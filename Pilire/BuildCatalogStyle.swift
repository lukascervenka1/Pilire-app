import SwiftUI

/// Warm catalogue surfaces, matching the town's cream interface.
enum CatalogStyle {
    static let ink = Color(red: 0.28, green: 0.32, blue: 0.27)
    static let coin = Color(red: 0.65, green: 0.43, blue: 0.10)
    static let shortage = Color(red: 0.66, green: 0.26, blue: 0.18)
    static let shortageAmount = Color(red: 0.76, green: 0.18, blue: 0.15)
    static let eventTop = Color(red: 0.23, green: 0.22, blue: 0.32)
    static let eventBottom = Color(red: 0.34, green: 0.27, blue: 0.36)
    static let eventAccent = Color(red: 1.0, green: 0.77, blue: 0.43)
}

struct CatalogPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct CatalogWallet: View {
    let settings: UserSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize >= .xxLarge ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            balance("seal.fill", color: CatalogStyle.coin, count: settings.coinBalance, label: L(S.common.coins))
            ForEach(Material.allCases) { material in
                balance(material.symbolName,
                        color: Color(red: material.tint.r, green: material.tint.g, blue: material.tint.b),
                        count: settings.count(material), label: material.displayName)
                    .resourceInfo(icon: material.symbolName,
                                  tint: Color(red: material.tint.r, green: material.tint.g, blue: material.tint.b),
                                  material.displayName, material.infoText)
            }
        }
        .padding(12)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.rowRadius))
    }

    private func balance(_ symbol: String, color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(count.formatted(.number.locale(Language.shared.current.locale)))
                .monospacedDigit().foregroundStyle(CatalogStyle.ink)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(count)")
    }
}

struct CatalogSeasonBanner: View {
    let event: SeasonalEvent
    let expanded: Bool
    let onExplore: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var art: some View {
        ZStack {
            Circle().fill(CatalogStyle.eventAccent.opacity(0.10)).frame(width: 122, height: 122)
            Image(systemName: event.symbolName)
                .font(.title2).foregroundStyle(CatalogStyle.eventAccent)
                .offset(x: 47, y: -53)
            Image(uiImage: BuildingPreview.image(for: event == .halloween ? .hauntedHouse : .gingerbreadHouse))
                .resizable().scaledToFit().frame(width: 144, height: 150)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
        }
        .frame(width: 132, height: 156).accessibilityHidden(true)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(S.build.collection))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(CatalogStyle.eventAccent)
            Text(event.title)
                .font(.system(.title, design: .rounded).bold()).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(L(S.build.until, event.lastDay().formatted(.dateTime.day().month(.wide).locale(Language.shared.current.locale))))
                .font(.subheadline).foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                text
            } else {
                HStack(spacing: 0) { text.frame(maxWidth: .infinity, alignment: .leading); art }
            }
            if expanded {
                Label(L(S.build.seasonKeep), systemImage: "checkmark.seal")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(action: onExplore) {
                    HStack(spacing: 8) {
                        Text(L(S.build.explore))
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(CatalogStyle.eventAccent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CatalogPressStyle())
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [CatalogStyle.eventTop, CatalogStyle.eventBottom], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct CatalogPrice: View {
    let symbol: String
    let color: Color
    let amount: Int
    let enough: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text("\(amount)").monospacedDigit().fontWeight(enough ? .semibold : .bold)
                .foregroundStyle(enough ? CatalogStyle.ink : CatalogStyle.shortageAmount)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(enough ? Color.clear : CatalogStyle.shortageAmount.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .font(.system(.caption, design: .rounded)).fixedSize()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label): \(amount)")
        .accessibilityValue(enough ? "" : L(S.build.insufficient))
    }
}

struct CatalogProductCard<Price: View>: View {
    let name: String
    let subtitle: String
    let image: UIImage?
    var placeholder = "pawprint.fill"     // shown while an async thumbnail renders
    var subtitleLines: Int? = nil         // reserve room so a row of cards lines up
    let event: SeasonalEvent?
    let affordable: Bool
    let action: String
    let unavailable: String
    @ViewBuilder var price: () -> Price

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(event == nil ? Theme.creamBottom.opacity(0.55) : CatalogStyle.eventAccent.opacity(0.20))
                Group {
                    if let image {
                        Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                    } else {
                        Image(systemName: placeholder).font(.largeTitle).foregroundStyle(Theme.creamLabel.opacity(0.5))
                    }
                }
                .padding(8).frame(maxWidth: .infinity).frame(height: 126)
                .accessibilityHidden(true)
                if let event {
                    Image(systemName: event.symbolName)
                        .font(.caption).foregroundStyle(CatalogStyle.ink)
                        .padding(7).background(.white.opacity(0.85), in: Circle()).padding(6)
                        .accessibilityLabel(event.title)
                }
            }
            .frame(height: 126)
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(CatalogStyle.ink).lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle).font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.creamLabel)
                    .lineLimit(subtitleLines ?? 10, reservesSpace: subtitleLines != nil)
                    .fixedSize(horizontal: false, vertical: true)
                price().frame(minHeight: 28, alignment: .leading)
                Divider().overlay(Theme.creamLabel.opacity(0.08))
                HStack(spacing: 4) {
                    Text(affordable ? action : unavailable)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: affordable ? "arrow.up.right" : "info.circle")
                        .accessibilityHidden(true)
                }
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(affordable ? CatalogStyle.ink : CatalogStyle.shortage)
                .padding(.horizontal, 8).frame(minHeight: 36)
                .background(affordable ? Color.clear : CatalogStyle.shortage.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 9))
                .padding(.top, 3)
            }
            .padding(.horizontal, 3).padding(.top, 12).padding(.bottom, 6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(affordable ? Theme.creamLabel.opacity(0.09) : CatalogStyle.shortage.opacity(0.20), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
