import SwiftUI

// MARK: - Inventář
//
// Everything you own but haven't got standing on the map: buildings and
// decorations you tidied away, seasonal pieces kept for next year, and pets
// resting off the map. Putting something back is free; selling it returns half
// the price. The shop is reached from here.

enum InventoryFilter: String, CaseIterable, Identifiable {
    case all, buildings, decorations, animals, seasonal
    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .all:         L(S.inventory.filterAll)
        case .buildings:   L(S.inventory.filterBuildings)
        case .decorations: L(S.inventory.filterDecorations)
        case .animals:     L(S.inventory.filterAnimals)
        case .seasonal:    L(S.inventory.filterSeasonal)
        }
    }
}

/// Identical pieces stacked into one card.
private struct InventoryStack: Identifiable {
    enum Kind: Hashable {
        case building(BuildingType)
        case decoration(DecorationItem)
    }
    let kind: Kind
    let count: Int
    var id: Kind { kind }

    var event: SeasonalEvent? {
        switch kind {
        case .building(let t):   t.event
        case .decoration(let d): d.event
        }
    }

    @MainActor var name: String {
        switch kind {
        case .building(let t):   t.displayName
        case .decoration(let d): d.displayName
        }
    }

    /// Half the price, the way it's paid back.
    @MainActor var refundLabel: String {
        switch kind {
        case .building(let t):
            let c = t.cost
            return [(Material.wood, c.wood / 2), (.brick, c.brick / 2), (.steel, c.steel / 2)]
                .filter { $0.1 > 0 }
                .map { $0.0.amount($0.1) }
                .joined(separator: ", ")
        case .decoration(let d):
            return S.coinsCount(d.cost / 2)
        }
    }
}

struct InventoryView<Shop: View>: View {
    let buildings: [Building]
    let decorations: [PlacedDecoration]
    let animals: [OwnedAnimal]
    var onPlaceBuilding: (Building) -> Void
    var onPlaceDecoration: (PlacedDecoration) -> Void
    var onSellBuilding: (Building) -> Void
    var onSellDecoration: (PlacedDecoration) -> Void
    var onReleaseAnimal: (OwnedAnimal) -> Void
    var onDeleteAnimal: (OwnedAnimal) -> Void
    var onRenameAnimal: () -> Void
    @ViewBuilder var shop: () -> Shop

    @Environment(\.dismiss) private var dismiss
    @State private var filter: InventoryFilter = .all
    @State private var selected: InventoryStack?
    @State private var animalToDelete: OwnedAnimal?
    @State private var showShop = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var stacks: [InventoryStack] {
        let b = Dictionary(grouping: buildings, by: \.type)
            .map { InventoryStack(kind: .building($0.key), count: $0.value.count) }
            .sorted { (BuildingType.allCases.firstIndex(of: $0.buildingType!) ?? 0)
                    < (BuildingType.allCases.firstIndex(of: $1.buildingType!) ?? 0) }
        let d = Dictionary(grouping: decorations, by: \.type)
            .map { InventoryStack(kind: .decoration($0.key), count: $0.value.count) }
            .sorted { (DecorationItem.allCases.firstIndex(of: $0.decorationItem!) ?? 0)
                    < (DecorationItem.allCases.firstIndex(of: $1.decorationItem!) ?? 0) }
        switch filter {
        case .all:         return b + d
        case .buildings:   return b
        case .decorations: return d
        case .animals:     return []
        case .seasonal:    return (b + d).filter { $0.event != nil }
        }
    }

    private var showsAnimals: Bool {
        (filter == .all || filter == .animals) && !animals.isEmpty
    }

    private var isCompletelyEmpty: Bool {
        buildings.isEmpty && decorations.isEmpty && animals.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L(S.inventory.freeToPlace))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.creamLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    filterChips

                    if isCompletelyEmpty {
                        emptyState
                    } else if stacks.isEmpty && !showsAnimals {
                        Text(L(S.inventory.emptyFilter))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.creamLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        if !stacks.isEmpty {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(stacks) { stack in
                                    Button { selected = stack } label: { card(stack) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        if showsAnimals { animalSection }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.creamGradient.ignoresSafeArea())
            .navigationTitle(L(S.inventory.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showShop = true } label: {
                        Label(L(S.shop.title), systemImage: "storefront.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L(S.common.close)) { dismiss() }
                }
            }
            .confirmationDialog(
                selected.map { "\($0.name) ×\($0.count)" } ?? "",
                isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                titleVisibility: .visible,
                presenting: selected
            ) { stack in
                Button(L(S.inventory.placeOnMap)) { place(stack) }
                Button(L(S.inventory.sellFor, stack.refundLabel), role: .destructive) { sell(stack) }
                Button(L(S.common.cancel), role: .cancel) {}
            } message: { _ in
                Text(L(S.inventory.sellNote))
            }
            .confirmationDialog(
                L(S.shop.sayGoodbyeTo, animalToDelete?.displayName ?? ""),
                isPresented: Binding(get: { animalToDelete != nil },
                                     set: { if !$0 { animalToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button(L(S.shop.sayGoodbye), role: .destructive) {
                    if let a = animalToDelete { onDeleteAnimal(a) }
                    animalToDelete = nil
                }
                Button(L(S.common.cancel), role: .cancel) {}
            } message: {
                Text(L(S.shop.goodbyeNote))
            }
        }
        .sheet(isPresented: $showShop) { shop() }
    }

    // MARK: Pieces

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InventoryFilter.allCases) { f in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { filter = f }
                    } label: {
                        Text(f.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(filter == f ? AnyShapeStyle(Theme.accentGradient)
                                                    : AnyShapeStyle(Color.white.opacity(0.75)),
                                        in: Capsule())
                            .foregroundStyle(filter == f ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func card(_ stack: InventoryStack) -> some View {
        VStack(spacing: 6) {
            Image(uiImage: preview(stack))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 84)

            Text(stack.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let event = stack.event {
                Label(event.title, systemImage: event.symbolName)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(red: event.tint.r, green: event.tint.g, blue: event.tint.b))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(alignment: .topTrailing) {
            if stack.count > 1 {
                Text("×\(stack.count)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accentBottom, in: Capsule())
                    .padding(8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L(S.inventory.itemLabel, stack.name, stack.count))
    }

    private func preview(_ stack: InventoryStack) -> UIImage {
        switch stack.kind {
        case .building(let t):   BuildingPreview.image(for: t)
        case .decoration(let d): DecorationPreview.image(for: d)
        }
    }

    private var animalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(S.shop.resting))
                .font(.system(.headline, design: .rounded))
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(animals) { animal in
                    DoghouseRow(
                        animal: animal,
                        onRelease: { onReleaseAnimal(animal); Haptics.tap() },
                        onDelete: { animalToDelete = animal },
                        onNameChange: onRenameAnimal
                    )
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    if animal.id != animals.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            Text(L(S.shop.restingFooter))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "backpack.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentBottom.opacity(0.8))
            Text(L(S.inventory.emptyTitle))
                .font(.system(.title3, design: .rounded).bold())
            Text(L(S.inventory.emptyBody))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.creamLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { showShop = true } label: {
                Label(L(S.shop.title), systemImage: "storefront.fill")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 48)
                    .background(Theme.accentGradient, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
    }

    // MARK: Actions

    private func place(_ stack: InventoryStack) {
        switch stack.kind {
        case .building(let t):
            guard let b = buildings.last(where: { $0.type == t }) else { return }
            onPlaceBuilding(b)
        case .decoration(let d):
            guard let dec = decorations.last(where: { $0.type == d }) else { return }
            onPlaceDecoration(dec)
        }
        Haptics.tap()
        dismiss()
    }

    private func sell(_ stack: InventoryStack) {
        switch stack.kind {
        case .building(let t):
            guard let b = buildings.last(where: { $0.type == t }) else { return }
            onSellBuilding(b)
        case .decoration(let d):
            guard let dec = decorations.last(where: { $0.type == d }) else { return }
            onSellDecoration(dec)
        }
        Haptics.success()
    }
}

private extension InventoryStack {
    var buildingType: BuildingType? {
        if case .building(let t) = kind { return t }
        return nil
    }
    var decorationItem: DecorationItem? {
        if case .decoration(let d) = kind { return d }
        return nil
    }
}
