import SwiftUI

enum CatalogShortageTarget: Identifiable {
    case building(BuildingType)
    case decoration(DecorationItem)
    case animal(AnimalKind)

    var id: String {
        switch self {
        case .building(let type): "building-\(type.rawValue)"
        case .decoration(let item): "decoration-\(item.rawValue)"
        case .animal(let kind): "animal-\(kind.rawValue)"
        }
    }

    @MainActor var name: String {
        switch self {
        case .building(let type): type.displayName
        case .decoration(let item): item.displayName
        case .animal(let kind): kind.displayName
        }
    }

    @MainActor var title: String {
        switch self {
        case .building: L(S.build.needMaterials)
        case .decoration, .animal: L(S.build.needCoins)
        }
    }

    /// Read balances each time so the explanation also updates after a reward.
    @MainActor func missing(in settings: UserSettings) -> [CatalogMissingResource] {
        switch self {
        case .building(let type):
            let cost = type.cost
            return [(Material.wood, cost.wood), (.brick, cost.brick), (.steel, cost.steel)].compactMap { material, required in
                let available = settings.count(material)
                guard available < required else { return nil }
                return CatalogMissingResource(id: material.rawValue, name: material.displayName,
                    symbol: material.symbolName,
                    color: Color(red: material.tint.r, green: material.tint.g, blue: material.tint.b),
                    available: available, required: required)
            }
        case .decoration(let item):
            return Self.coins(item.cost, in: settings)
        case .animal(let kind):
            return Self.coins(kind.cost, in: settings)
        }
    }

    @MainActor private static func coins(_ cost: Int, in settings: UserSettings) -> [CatalogMissingResource] {
        guard settings.coinBalance < cost else { return [] }
        return [CatalogMissingResource(id: "coins", name: L(S.common.coins), symbol: "seal.fill",
            color: CatalogStyle.coin, available: settings.coinBalance, required: cost)]
    }
}

struct CatalogMissingResource: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let color: Color
    let available: Int
    let required: Int
    var deficit: Int { max(0, required - available) }
}

struct CatalogShortageSheet: View {
    let target: CatalogShortageTarget
    let settings: UserSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 24)).foregroundStyle(CatalogStyle.shortage)
                    .frame(width: 52, height: 52)
                    .background(CatalogStyle.shortage.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(target.title).font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(CatalogStyle.ink).accessibilityAddTraits(.isHeader)
                    Text(L(S.build.shortageFor, target.name))
                        .font(.subheadline).foregroundStyle(Theme.creamLabel)
                }
                let resources = target.missing(in: settings)
                if resources.isEmpty {
                    Text(L(S.build.shortageReady)).foregroundStyle(CatalogStyle.ink)
                } else {
                    VStack(spacing: 10) {
                        ForEach(resources) { resource in
                            resourceRow(resource)
                        }
                    }
                }
            }
            .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { dismiss() } label: {
                Text(L(S.info.understood)).font(.system(.headline, design: .rounded))
                    .foregroundStyle(CatalogStyle.ink)
                    .frame(maxWidth: .infinity).frame(minHeight: 50)
                    .background(Theme.creamBottom, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(CatalogPressStyle())
            .padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 560).frame(maxWidth: .infinity).background(Theme.creamTop)
        }
        .background(Theme.creamTop)
        .presentationBackground(Theme.creamTop)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
        .presentationDetents(dynamicTypeSize >= .xxLarge ? [.large] :
            [.height(CGFloat(300 + 74 * max(1, target.missing(in: settings).count))), .large])
    }

    private func resourceRow(_ resource: CatalogMissingResource) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: resource.symbol).font(.system(size: 20)).foregroundStyle(resource.color)
                .frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(resource.name).foregroundStyle(CatalogStyle.ink)
                        Spacer(minLength: 12)
                        Text(L(S.build.missingAmount, resource.deficit)).foregroundStyle(CatalogStyle.shortage)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.name).foregroundStyle(CatalogStyle.ink)
                        Text(L(S.build.missingAmount, resource.deficit)).foregroundStyle(CatalogStyle.shortage)
                    }
                }
                .font(.system(.subheadline, design: .rounded).bold()).fixedSize(horizontal: false, vertical: true)
                Text(L(S.build.availableOf, resource.available, resource.required))
                    .font(.caption).foregroundStyle(Theme.creamLabel)
            }
        }
        .monospacedDigit().padding(14)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
