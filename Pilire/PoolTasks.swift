import SwiftUI

// MARK: - Random task pool („Nevím, dej mi task")

struct PoolTask: Identifiable, Equatable {
    let id = UUID()
    let phrase: T
    let category: PoolCategory

    /// The wording in the player's language. Once picked it's copied into the
    /// pillar as plain text, so it keeps whatever language it was added in.
    @MainActor
    var text: String { phrase.resolved }

    static func == (a: PoolTask, b: PoolTask) -> Bool { a.id == b.id }
}

enum PoolCategory: String, CaseIterable {
    case body     = "Tělo"
    case space    = "Prostor"
    case people   = "Vztahy"
    case mind     = "Mysl"
    case joy      = "Radost"
    case selfCare = "Péče o sebe"

    @MainActor
    var displayName: String {
        switch self {
        case .body:     L(T(cs: "Tělo", sk: "Telo", en: "Body"))
        case .space:    L(T(cs: "Prostor", sk: "Priestor", en: "Space"))
        case .people:   L(T(cs: "Vztahy", sk: "Vzťahy", en: "People"))
        case .mind:     L(T(cs: "Mysl", sk: "Myseľ", en: "Mind"))
        case .joy:      L(T(cs: "Radost", sk: "Radosť", en: "Joy"))
        case .selfCare: L(T(cs: "Péče o sebe", sk: "Starostlivosť o seba", en: "Self-care"))
        }
    }

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
        PoolTask(phrase: T(cs: "Jít na 20minutovou procházku", sk: "Ísť na 20-minútovú prechádzku", en: "Go for a 20 minute walk"), category: .body),
        PoolTask(phrase: T(cs: "Protáhnout se 10 minut", sk: "Ponaťahovať sa 10 minút", en: "Stretch for 10 minutes"), category: .body),
        PoolTask(phrase: T(cs: "Vypít sklenici vody hned teď", sk: "Vypiť pohár vody hneď teraz", en: "Drink a glass of water right now"), category: .body),
        PoolTask(phrase: T(cs: "Jít spát o 30 minut dřív", sk: "Ísť spať o 30 minút skôr", en: "Go to bed 30 minutes earlier"), category: .body),
        PoolTask(phrase: T(cs: "Ujet libovolnou trasu na kole", sk: "Prejsť ľubovoľnú trasu na bicykli", en: "Ride your bike anywhere"), category: .body),
        PoolTask(phrase: T(cs: "Udělat 10 dřepů nebo kliků", sk: "Urobiť 10 drepov alebo klikov", en: "Do 10 squats or push-ups"), category: .body),
        PoolTask(phrase: T(cs: "Uklidit jednu poličku nebo šuplík", sk: "Upratať jednu poličku alebo šuplík", en: "Tidy one shelf or drawer"), category: .space),
        PoolTask(phrase: T(cs: "Umýt nádobí", sk: "Umyť riad", en: "Do the dishes"), category: .space),
        PoolTask(phrase: T(cs: "Vynést odpadky", sk: "Vyniesť odpadky", en: "Take out the rubbish"), category: .space),
        PoolTask(phrase: T(cs: "Ustlat postel", sk: "Ustlať posteľ", en: "Make the bed"), category: .space),
        PoolTask(phrase: T(cs: "Vyvětrat pokoj", sk: "Vyvetrať izbu", en: "Air out the room"), category: .space),
        PoolTask(phrase: T(cs: "Vytřídit hromádku papírů či pošty", sk: "Vytriediť kôpku papierov či pošty", en: "Sort that pile of paper or post"), category: .space),
        PoolTask(phrase: T(cs: "Zalít kytky", sk: "Poliať kvety", en: "Water the plants"), category: .space),
        PoolTask(phrase: T(cs: "Opravit jednu maličkost, kterou odkládáš", sk: "Opraviť jednu maličkosť, ktorú odkladáš", en: "Fix one small thing you keep putting off"), category: .space),
        PoolTask(phrase: T(cs: "Zavolat rodičům", sk: "Zavolať rodičom", en: "Call your parents"), category: .people),
        PoolTask(phrase: T(cs: "Napsat kamarádovi „myslím na tebe“", sk: "Napísať kamarátovi „myslím na teba“", en: "Text a friend „thinking of you“"), category: .people),
        PoolTask(phrase: T(cs: "Naplánovat setkání s někým", sk: "Naplánovať stretnutie s niekým", en: "Make plans to see someone"), category: .people),
        PoolTask(phrase: T(cs: "Vyvenčit psa nebo jít ven se zvířetem", sk: "Vyvenčiť psa alebo ísť von so zvieraťom", en: "Walk the dog or get outside with a pet"), category: .people),
        PoolTask(phrase: T(cs: "Udělat drobnost pro partnera/partnerku", sk: "Urobiť drobnosť pre partnera/partnerku", en: "Do a small thing for your partner"), category: .people),
        PoolTask(phrase: T(cs: "Přečíst si kapitolu knihy", sk: "Prečítať si kapitolu knihy", en: "Read a chapter of a book"), category: .mind),
        PoolTask(phrase: T(cs: "Strávit 10 minut v tichu bez telefonu", sk: "Stráviť 10 minút v tichu bez telefónu", en: "Spend 10 quiet minutes without your phone"), category: .mind),
        PoolTask(phrase: T(cs: "Napsat 3 věci, za které jsi dnes vděčný", sk: "Napísať 3 veci, za ktoré si dnes vďačný", en: "Write down three things you're grateful for"), category: .mind),
        PoolTask(phrase: T(cs: "Jít bez cíle ven na hodinu", sk: "Ísť bez cieľa von na hodinu", en: "Head outside for an hour with no plan"), category: .mind),
        PoolTask(phrase: T(cs: "Dojít do parku a chvíli tam pobýt", sk: "Dôjsť do parku a chvíľu tam pobudnúť", en: "Walk to a park and stay a while"), category: .mind),
        PoolTask(phrase: T(cs: "Pustit si oblíbenou hudbu a jen ji poslouchat", sk: "Pustiť si obľúbenú hudbu a len ju počúvať", en: "Put on music you love and just listen"), category: .joy),
        PoolTask(phrase: T(cs: "Uvařit si oblíbené jídlo", sk: "Uvariť si obľúbené jedlo", en: "Cook something you love"), category: .joy),
        PoolTask(phrase: T(cs: "Udělat si čas na koníček bez pocitu viny", sk: "Urobiť si čas na koníček bez pocitu viny", en: "Make guilt-free time for a hobby"), category: .joy),
        PoolTask(phrase: T(cs: "Zahrát si hru nebo epizodu seriálu naplno, bez multitaskingu", sk: "Zahrať si hru alebo epizódu seriálu naplno, bez multitaskingu", en: "Play a game or watch an episode properly, no multitasking"), category: .joy),
        PoolTask(phrase: T(cs: "Dát si pořádnou sprchu, v klidu a bez spěchu", sk: "Dať si poriadnu sprchu, v pokoji a bez zhonu", en: "Take a proper unhurried shower"), category: .selfCare),
        PoolTask(phrase: T(cs: "Naplánovat večeři na zítra", sk: "Naplánovať večeru na zajtra", en: "Plan tomorrow's dinner"), category: .selfCare),
    ]

    /// Draw 3 tasks from 3 different categories.
    @MainActor
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
                    Text(L(S.pool.intro))
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
                                    Text(task.category.displayName)
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
                        Label(L(S.pool.reroll), systemImage: "dice")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(L(S.pool.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L(S.common.close)) { dismiss() } }
            }
            .onAppear { offer = PoolTasks.draw3(excluding: existingTexts) }
        }
        .presentationDetents([.medium, .large])
    }
}
