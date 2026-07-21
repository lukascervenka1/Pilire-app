import SwiftUI

// MARK: - Random task pool („Nevím, dej mi task")

struct PoolTask: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let category: PoolCategory
}

enum PoolCategory: String, CaseIterable {
    case body     = "Tělo"
    case space    = "Prostor"
    case people   = "Vztahy"
    case mind     = "Mysl"
    case joy      = "Radost"
    case selfCare = "Péče o sebe"

    var symbolName: String {
        switch self {
        case .body:     "figure.walk"
        case .space:    "house.fill"
        case .people:   "heart.fill"
        case .mind:     "brain.head.profile"
        case .joy:      "sparkles"
        case .selfCare: "drop.fill"
        }
    }

    var tint: Color {
        switch self {
        case .body:     Color(red: 0.36, green: 0.62, blue: 0.44)
        case .space:    Color(red: 0.64, green: 0.50, blue: 0.34)
        case .people:   Color(red: 0.88, green: 0.45, blue: 0.50)
        case .mind:     Color(red: 0.44, green: 0.52, blue: 0.72)
        case .joy:      Color(red: 0.92, green: 0.68, blue: 0.25)
        case .selfCare: Color(red: 0.40, green: 0.66, blue: 0.78)
        }
    }
}

enum PoolTasks {
    static let all: [PoolTask] = [
        // Tělo / pohyb
        PoolTask(text: "Jít na 20minutovou procházku", category: .body),
        PoolTask(text: "Protáhnout se 10 minut", category: .body),
        PoolTask(text: "Vypít sklenici vody hned teď", category: .body),
        PoolTask(text: "Jít spát o 30 minut dřív", category: .body),
        PoolTask(text: "Ujet libovolnou trasu na kole", category: .body),
        PoolTask(text: "Udělat 10 dřepů nebo kliků", category: .body),
        // Prostor / domácnost
        PoolTask(text: "Uklidit jednu poličku nebo šuplík", category: .space),
        PoolTask(text: "Umýt nádobí", category: .space),
        PoolTask(text: "Vynést odpadky", category: .space),
        PoolTask(text: "Ustlat postel", category: .space),
        PoolTask(text: "Vyvětrat pokoj", category: .space),
        PoolTask(text: "Vytřídit hromádku papírů či pošty", category: .space),
        PoolTask(text: "Zalít kytky", category: .space),
        PoolTask(text: "Opravit jednu maličkost, kterou odkládáš", category: .space),
        // Vztahy
        PoolTask(text: "Zavolat rodičům", category: .people),
        PoolTask(text: "Napsat kamarádovi „myslím na tebe“", category: .people),
        PoolTask(text: "Naplánovat setkání s někým", category: .people),
        PoolTask(text: "Vyvenčit psa nebo jít ven se zvířetem", category: .people),
        PoolTask(text: "Udělat drobnost pro partnera/partnerku", category: .people),
        // Mysl / klid
        PoolTask(text: "Přečíst si kapitolu knihy", category: .mind),
        PoolTask(text: "Strávit 10 minut v tichu bez telefonu", category: .mind),
        PoolTask(text: "Napsat 3 věci, za které jsi dnes vděčný", category: .mind),
        PoolTask(text: "Jít bez cíle ven na hodinu", category: .mind),
        PoolTask(text: "Dojít do parku a chvíli tam pobýt", category: .mind),
        // Radost / hravost
        PoolTask(text: "Pustit si oblíbenou hudbu a jen ji poslouchat", category: .joy),
        PoolTask(text: "Uvařit si oblíbené jídlo", category: .joy),
        PoolTask(text: "Udělat si čas na koníček bez pocitu viny", category: .joy),
        PoolTask(text: "Zahrát si hru nebo epizodu seriálu naplno, bez multitaskingu", category: .joy),
        // Péče o sebe
        PoolTask(text: "Dát si pořádnou sprchu, v klidu a bez spěchu", category: .selfCare),
        PoolTask(text: "Naplánovat večeři na zítra", category: .selfCare),
    ]

    /// Draw 3 tasks from 3 different categories.
    static func draw3(excluding texts: Set<String> = []) -> [PoolTask] {
        let available = all.filter { !texts.contains($0.text) }
        let byCategory = Dictionary(grouping: available, by: \.category)
        let cats = byCategory.keys.shuffled().prefix(3)
        return cats.compactMap { byCategory[$0]?.randomElement() }
    }
}

// MARK: - Picker sheet

struct PoolPickerView: View {
    var existingTexts: Set<String>
    var onPick: (PoolTask) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var offer: [PoolTask] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Vyber si jeden. Za splnění vylosovaného tasku dostaneš bonusovou odměnu.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24).padding(.top, 8)

                    ForEach(offer) { task in
                        Button {
                            Haptics.tap()
                            onPick(task)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: task.category.symbolName)
                                    .font(.title3)
                                    .foregroundStyle(task.category.tint)
                                    .frame(width: 42, height: 42)
                                    .background(task.category.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rowRadius))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.category.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(task.category.tint)
                                    Text(task.text)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            .padding(14)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    Button {
                        withAnimation { offer = PoolTasks.draw3(excluding: existingTexts) }
                    } label: {
                        Label("Vylosovat jiné", systemImage: "dice")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Dej mi task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Zavřít") { dismiss() } }
            }
            .onAppear { offer = PoolTasks.draw3(excluding: existingTexts) }
        }
        .presentationDetents([.medium, .large])
    }
}
