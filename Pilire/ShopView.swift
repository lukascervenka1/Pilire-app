import SwiftUI
import SwiftData

struct ShopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    var settings: UserSettings
    var onPurchase: (DecorationItem) -> Void
    var onPurchaseAnimal: (AnimalKind) -> Void = { _ in }
    var tuckedAnimals: [OwnedAnimal] = []
    var onReleaseAnimal: (OwnedAnimal) -> Void = { _ in }
    var onDeleteAnimal: (OwnedAnimal) -> Void = { _ in }

    @State private var purchased: DecorationItem?
    @State private var animalToDelete: OwnedAnimal?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Tvůj zůstatek")
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "seal.fill").foregroundStyle(.yellow)
                            Text("\(settings.coinBalance)")
                                .fontWeight(.bold).monospacedDigit()
                        }
                    }
                }

                Section("Směnárna") {
                    ForEach(Material.allCases) { m in
                        HStack(spacing: 14) {
                            Image(systemName: m.symbolName)
                                .font(.title3)
                                .foregroundStyle(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b))
                                .frame(width: 42, height: 42)
                                .background(Color(red: m.tint.r, green: m.tint.g, blue: m.tint.b).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("1× \(m.displayName)").fontWeight(.semibold)
                                Text("Máš: \(settings.count(m))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                guard settings.coinBalance >= m.coinPrice else { return }
                                settings.coinBalance -= m.coinPrice
                                settings.add(m, 1)
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(settings.coinBalance >= m.coinPrice ? .yellow : .secondary)
                                    Text("\(m.coinPrice)").fontWeight(.bold).monospacedDigit()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(settings.coinBalance >= m.coinPrice ? Color.orange : Color.secondary.opacity(0.2))
                                .foregroundStyle(settings.coinBalance >= m.coinPrice ? Color.white : Color.secondary)
                                .clipShape(Capsule())
                                .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .disabled(settings.coinBalance < m.coinPrice)
                        }
                    }
                }

                Section("Dekorace") {
                    ForEach(DecorationItem.allCases, id: \.self) { item in
                        ShopRow(item: item, canAfford: settings.coinBalance >= item.cost) {
                            buy(item)
                        }
                    }
                }

                Section {
                    ForEach(AnimalKind.allCases) { kind in
                        AnimalShopRow(kind: kind, canAfford: settings.coinBalance >= kind.cost) {
                            buyAnimal(kind)
                        }
                    }
                } header: {
                    Text("Zoo")
                } footer: {
                    Text("Zvíře se po koupi nastěhuje na mapu a začne se procházet. Chodí po loukách i cestách, obchází domy a rádo si žije po svém. Na mapě ho dotykem probudíš, podržením uklidíš do boudy.")
                }

                if !tuckedAnimals.isEmpty {
                    Section {
                        ForEach(tuckedAnimals) { animal in
                            DoghouseRow(
                                animal: animal,
                                onRelease: { onReleaseAnimal(animal); Haptics.tap() },
                                onDelete: { animalToDelete = animal },
                                onNameChange: { ctx.saveChanges() }
                            )
                        }
                    } header: {
                        Text("Bouda")
                    } footer: {
                        Text("Zvířata, která teď odpočívají. Dej jim jméno, pusť je zpět na mapu, nebo se s nimi rozluč.")
                    }
                }

                Section {
                    Text("Po nákupu ťukni na dlaždici kde chceš dekoraci umístit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Obchod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .confirmationDialog(
                "Rozloučit se s \(animalToDelete?.displayName ?? "")?",
                isPresented: Binding(get: { animalToDelete != nil },
                                     set: { if !$0 { animalToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Rozloučit se", role: .destructive) {
                    if let a = animalToDelete { onDeleteAnimal(a) }
                    animalToDelete = nil
                }
                Button("Zrušit", role: .cancel) {}
            } message: {
                Text("Zvíře nadobro opustí tvé městečko. Tohle nejde vzít zpět.")
            }
        }
    }

    private func buy(_ item: DecorationItem) {
        guard settings.coinBalance >= item.cost else { return }
        // Roads are paid per painted tile while dragging on the map,
        // everything else is charged right here.
        if item != .road {
            settings.coinBalance -= item.cost
        }
        Haptics.success()
        onPurchase(item)
        dismiss()
    }

    private func buyAnimal(_ kind: AnimalKind) {
        guard settings.coinBalance >= kind.cost else { return }
        settings.coinBalance -= kind.cost
        Haptics.success()
        onPurchaseAnimal(kind)
        dismiss()
    }
}

struct DoghouseRow: View {
    @Bindable var animal: OwnedAnimal
    let onRelease: () -> Void
    let onDelete: () -> Void
    let onNameChange: () -> Void

    @FocusState private var naming: Bool

    private var tintColor: Color {
        Color(red: animal.kind.tint.r, green: animal.kind.tint.g, blue: animal.kind.tint.b)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: animal.kind.symbolName)
                .font(.title3)
                .foregroundStyle(tintColor)
                .frame(width: 42, height: 42)
                .background(tintColor.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            VStack(alignment: .leading, spacing: 1) {
                TextField(animal.kind.displayName, text: $animal.name)
                    .focused($naming)
                    .fontWeight(.semibold)
                    .submitLabel(.done)
                    .onSubmit { onNameChange() }
                Text(animal.kind.displayName).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: onRelease) {
                Text("Pustit ven").fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                    .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rozloučit se se zvířetem")
        }
        .onChange(of: naming) { _, focused in
            if !focused { onNameChange() }   // save when the field loses focus
        }
    }
}

struct AnimalShopRow: View {
    let kind: AnimalKind
    let canAfford: Bool
    let onBuy: () -> Void

    private var tintColor: Color {
        Color(red: kind.tint.r, green: kind.tint.g, blue: kind.tint.b)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbolName)
                .font(.title3)
                .foregroundStyle(tintColor)
                .frame(width: 42, height: 42)
                .background(tintColor.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).fontWeight(.semibold)
                Text(kind.shopDescription).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onBuy) {
                HStack(spacing: 4) {
                    Image(systemName: "seal.fill")
                        .font(.caption)
                        .foregroundStyle(canAfford ? .yellow : .secondary)
                    Text("\(kind.cost)").fontWeight(.bold).monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(canAfford ? Color.orange : Color.secondary.opacity(0.2))
                .foregroundStyle(canAfford ? Color.white : Color.secondary)
                .clipShape(Capsule())
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }
}

struct ShopRow: View {
    let item: DecorationItem
    let canAfford: Bool
    let onBuy: () -> Void

    private var tintColor: Color {
        Color(red: item.tint.r, green: item.tint.g, blue: item.tint.b)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbolName)
                .font(.title3)
                .foregroundStyle(tintColor)
                .frame(width: 42, height: 42)
                .background(tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).fontWeight(.semibold)
                Text(item.description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onBuy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "seal.fill")
                        .font(.caption)
                        .foregroundStyle(canAfford ? .yellow : .secondary)
                    Text("\(item.cost)").fontWeight(.bold).monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(canAfford ? Color.orange : Color.secondary.opacity(0.2))
                .foregroundStyle(canAfford ? Color.white : Color.secondary)
                .clipShape(Capsule())
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)
        }
    }
}
