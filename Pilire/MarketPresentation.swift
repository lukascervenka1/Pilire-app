import SwiftUI

enum MarketStyle {
    static let green = Color(red: 0.24, green: 0.36, blue: 0.27)
    static let sage = Color(red: 0.85, green: 0.89, blue: 0.78)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let edge = Color(red: 0.77, green: 0.74, blue: 0.64)
    /// The accent's text colour on a light tint, for the quieter buy buttons.
    static let accentInk = Color(red: 0.55, green: 0.29, blue: 0.05)
}

extension S.market {
    static let merchantName = T(cs: "Matěj", sk: "Matej", en: "Matěj")
    static let merchantRole = T(cs: "Potulný kupec", sk: "Potulný kupec", en: "Travelling merchant")
    static let requests = T(cs: "Dnešní prosby", sk: "Dnešné prosby", en: "Today's requests")
    static let requestsTab = T(cs: "Prosby", sk: "Prosby", en: "Requests")
    static let suppliesTab = T(cs: "Suroviny", sk: "Suroviny", en: "Supplies")
    static let marketTabs = T(cs: "Co na tržišti hledáš", sk: "Čo na trhovisku hľadáš", en: "Market sections")
    static let nextVisit = T(cs: "Nové prosby zase zítra", sk: "Nové prosby opäť zajtra", en: "Fresh requests tomorrow")
    static let missing = T(cs: "Chybí ti ještě %@", sk: "Chýba ti ešte %@", en: "You still need %@")
    static let settled = T(cs: "Domluveno", sk: "Dohodnuté", en: "Settled")
    static let tradeThanks = T(cs: "To se mi hodí. Díky za obchod!", sk: "To sa mi hodí. Vďaka za obchod!", en: "Just what I needed. Thanks for the trade!")
    static let allDone = T(cs: "Dnes jsme si pomohli. Zítra se zase stavím s něčím novým.", sk: "Dnes sme si pomohli. Zajtra sa opäť zastavím s niečím novým.", en: "We helped each other today. I'll stop by tomorrow with something new.")
    static let quantityLabel = T(cs: "Množství", sk: "Množstvo", en: "Quantity")
    static let swapAction = T(cs: "Vyměnit", sk: "Vymeniť", en: "Swap")
    static let greetings: [T] = [
        T(cs: "Z cest vezu pár zásob. Třeba si dnes navzájem pomůžeme.", sk: "Z ciest veziem pár zásob. Možno si dnes navzájom pomôžeme.", en: "I've brought a few supplies from my travels. Perhaps we can help each other today."),
        T(cs: "Vozík mám plný a v zápisníku pár proseb. Mrkneš na ně?", sk: "Vozík mám plný a v zápisníku pár prosieb. Pozrieš sa na ne?", en: "A full handcart and a few requests in my notebook. Care to take a look?"),
        T(cs: "Zase rád vidím tvoje městečko. Podívej, co dnes vezu.", sk: "Opäť rád vidím tvoje mestečko. Pozri, čo dnes veziem.", en: "It's good to see your little town again. Have a look at what I've brought."),
        T(cs: "Na cestách se vždycky něco najde. A někomu jinému to zrovna chybí.", sk: "Na cestách sa vždy niečo nájde. A niekomu inému to práve chýba.", en: "I always find something on the road. Often just what someone else is missing."),
    ]
}

extension Material {
    var color: Color { Color(red: tint.r, green: tint.g, blue: tint.b) }
}

/// Matěj, his greeting and the deal of the day, in one card.
struct MerchantWelcomeCard: View {
    let day: Date
    let allCompleted: Bool
    let hasMarketHall: Bool
    @Environment(\.dynamicTypeSize) private var textSize

    private var greeting: String {
        let ordinal = Calendar.current.ordinality(of: .day, in: .era,
                                                 for: Calendar.current.startOfDay(for: day)) ?? 0
        return L(allCompleted ? S.market.allDone : S.market.greetings[ordinal % S.market.greetings.count])
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(S.market.merchantName))
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(CatalogStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(L(S.market.merchantRole))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(MarketStyle.green)
            }
            Text(greeting)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CatalogStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deal: some View {
        let deal = Market.deal(on: day)
        let material = deal.material
        let detail = deal.kind == .cheaperBuy
            ? L(S.market.dealCheaper, material.displayName.lowercased(),
                Market.buyPrice(material, on: day), Market.baseValue(material))
            : L(S.market.dealBetterSell, material.displayName.lowercased(),
                Market.sellPrice(material, hasMarketHall: hasMarketHall, on: day))
        return HStack(spacing: 12) {
            AppIcon(material.symbolName)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.75), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(S.market.dealHeader))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(MarketStyle.green)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CatalogStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if textSize.isAccessibilitySize {
                introduction
            } else {
                HStack(alignment: .center, spacing: 0) {
                    introduction.frame(maxWidth: .infinity, alignment: .leading)
                    Image(uiImage: MerchantPortrait.image).resizable().scaledToFit()
                        .frame(width: textSize >= .xxLarge ? 112 : 150, height: 180)
                        .padding(.trailing, -8).accessibilityHidden(true)
                }
            }
            Rectangle().fill(MarketStyle.green.opacity(0.14)).frame(height: 1)
            deal
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [MarketStyle.sage, Theme.creamBottom],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(.white.opacity(0.65), lineWidth: 1) }
    }
}

/// An amount with its icon, set inline rather than in a box of its own.
struct MarketToken: View {
    let payment: Market.Payment
    var tone: Color = CatalogStyle.ink

    var body: some View {
        HStack(spacing: 5) {
            Group {
                switch payment {
                case .coins: AppIcon(ResourceIcon.coin)
                case .material(let m, _): AppIcon(m.symbolName)
                }
            }
            .font(.system(size: 15)).accessibilityHidden(true)
            Text(Market.text(payment)).foregroundStyle(tone)
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .monospacedDigit()
        .fixedSize()
    }
}

/// One paper panel with hairline-separated rows, like a page of the ledger.
struct PaperPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle().fill(MarketStyle.edge.opacity(0.35)).frame(height: 1)
                            .padding(.leading, 16)
                    }
                    row
                }
            }
        }
        .background(MarketStyle.paper, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(MarketStyle.edge.opacity(0.4), lineWidth: 1)
        }
    }
}

/// Compact capsule actions. One filled accent for the deal itself, a light
/// tint for buying and an outline for selling, so a list never shouts.
struct CapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, tinted, outline }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).bold())
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(kind == .primary ? Theme.chestButtonLabel
                             : kind == .tinted ? MarketStyle.accentInk : CatalogStyle.ink)
            .background {
                switch kind {
                case .primary: Capsule().fill(Theme.accentGradient)
                case .tinted: Capsule().fill(Theme.accentTop.opacity(0.18))
                case .outline: Capsule().strokeBorder(MarketStyle.edge.opacity(0.8), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
    }
}
