import Foundation

// MARK: - Every phrase in the app, in every language it ships in
//
// Grouped by screen. Each `T` needs all three languages, so a forgotten
// translation stops the build instead of leaking Czech into English.
// Placeholders use %@ for text and %d for numbers.

enum S {

    // MARK: Common

    enum common {
        static let done = T(cs: "Hotovo", sk: "Hotovo", en: "Done")
        static let cancel = T(cs: "Zrušit", sk: "Zrušiť", en: "Cancel")
        static let close = T(cs: "Zavřít", sk: "Zavrieť", en: "Close")
        static let delete = T(cs: "Smazat", sk: "Zmazať", en: "Delete")
        static let edit = T(cs: "Upravit", sk: "Upraviť", en: "Edit")
        static let save = T(cs: "Uložit", sk: "Uložiť", en: "Save")
        static let add = T(cs: "Přidat", sk: "Pridať", en: "Add")
        static let coins = T(cs: "Mince", sk: "Mince", en: "Coins")
    }

    // MARK: Daily pillars

    enum daily {
        static let title = T(cs: "Dnešní pilíře", sk: "Dnešné piliere", en: "Today's pillars")

        static let doneAll = T(cs: "Pilíř dne máš hotový, dobrá práce.",
                               sk: "Pilier dňa máš hotový, dobrá práca.",
                               en: "Your pillar of the day is standing. Nice work.")
        static let halfWay = T(cs: "Skvěle, už jen pár bloků.", sk: "Skvelé, už len pár blokov.",
                               en: "Great, only a few blocks to go.")
        static let started = T(cs: "První blok položen.", sk: "Prvý blok položený.",
                               en: "First block laid.")
        static let empty = T(cs: "Polož základy dneška.", sk: "Polož základy dneška.",
                             en: "Lay today's foundations.")
        static let waiting = T(cs: "Bloky čekají na položení.", sk: "Bloky čakajú na položenie.",
                               en: "Blocks waiting to be laid.")

        static let blocksHeader = T(cs: "Bloky dneška", sk: "Bloky dneška", en: "Today's blocks")
        static let noPillars = T(cs: "Zatím prázdno. Přidej první pilíř níže.",
                                 sk: "Zatiaľ prázdno. Pridaj prvý pilier nižšie.",
                                 en: "Nothing yet. Add your first pillar below.")
        static let addPlaceholder = T(cs: "Přidat pilíř...", sk: "Pridať pilier...",
                                      en: "Add a pillar...")
        static let addPillar = T(cs: "Přidat pilíř", sk: "Pridať pilier", en: "Add pillar")
        static let editText = T(cs: "Upravit text", sk: "Upraviť text", en: "Edit text")
        static let makeHabit = T(cs: "Udělat z toho návyk", sk: "Urobiť z toho návyk",
                                 en: "Turn into a habit")
        static let scheduleTime = T(cs: "Naplánovat čas", sk: "Naplánovať čas", en: "Schedule a time")
        static let changeTime = T(cs: "Změnit čas", sk: "Zmeniť čas", en: "Change the time")
        static let clearTime = T(cs: "Zrušit čas", sk: "Zrušiť čas", en: "Clear the time")
        static let cancelPillarTime = T(cs: "Zrušit čas pilíře", sk: "Zrušiť čas piliera",
                                        en: "Clear pillar time")
        static let schedulePillarTime = T(cs: "Naplánovat čas pilíře", sk: "Naplánovať čas piliera",
                                          en: "Schedule pillar time")
        static let addToCalendar = T(cs: "Přidat do Apple kalendáře", sk: "Pridať do Apple kalendára",
                                     en: "Add to Apple Calendar")
        static let addToCalendarAgain = T(cs: "Znovu do kalendáře", sk: "Znova do kalendára",
                                          en: "Add to calendar again")
        static let calendarNote = T(cs: "Pilíř dne z aplikace Pilíře",
                                    sk: "Pilier dňa z aplikácie Piliere",
                                    en: "A pillar of the day from Pilíře")

        static let giveMeTask = T(cs: "Nevím, dej mi task", sk: "Neviem, daj mi úlohu",
                                  en: "Not sure, pick one for me")
        static let firstHabit = T(cs: "Vytvořit první návyk", sk: "Vytvoriť prvý návyk",
                                  en: "Create your first habit")

        static let habitsHeader = T(cs: "Pravidelné návyky", sk: "Pravidelné návyky",
                                    en: "Recurring habits")
        static let habitsFooter = T(cs: "Ťukni na návyk pro úpravu dnů, času nebo připomínky.",
                                    sk: "Ťukni na návyk pre úpravu dní, času alebo pripomienky.",
                                    en: "Tap a habit to change its days, time or reminder.")

        static let tomorrowHeader = T(cs: "Plán na zítra", sk: "Plán na zajtra",
                                      en: "Planned for tomorrow")
        static let tomorrowFooter = T(cs: "Ať ráno nemusíš přemýšlet, čím začít.",
                                      sk: "Nech ráno nemusíš premýšľať, čím začať.",
                                      en: "So you won't have to wonder where to start.")
        static let tomorrowPlaceholder = T(cs: "Přidat na zítra...", sk: "Pridať na zajtra...",
                                           en: "Add for tomorrow...")
        static let addPillarTomorrow = T(cs: "Přidat pilíř na zítra", sk: "Pridať pilier na zajtra",
                                         en: "Add pillar for tomorrow")

        static let carryHeader = T(cs: "Nedokončené z dřívějška", sk: "Nedokončené z minula",
                                   en: "Unfinished from before")
        static let carryFooter = T(cs: "Přenes je do dneška a zkus to znovu, nebo je podrž a smaž.",
                                   sk: "Prenes ich do dneška a skús to znova, alebo ich podrž a zmaž.",
                                   en: "Bring one into today and try again, or hold it to delete.")
        static let carry = T(cs: "Přenést", sk: "Preniesť", en: "Bring forward")
        static let carryAll = T(cs: "Přenést vše", sk: "Preniesť všetko", en: "Bring all forward")

        static let closeDay = T(cs: "Podrž pro uzavření dne", sk: "Podrž pre uzavretie dňa",
                                en: "Hold to close the day")
        static let closeDayShort = T(cs: "Uzavřít den", sk: "Uzavrieť deň", en: "Close the day")
        static let dayClosed = T(cs: "Den uzavřen", sk: "Deň uzavretý", en: "Day closed")
        static let holding = T(cs: "Držte…", sk: "Držte…", en: "Holding…")
        static let holdHint = T(cs: "Podrž tlačítko, dokud se nevyplní.",
                                sk: "Podrž tlačidlo, kým sa nevyplní.",
                                en: "Hold the button until it fills up.")

        static let timeSheetTitle = T(cs: "Naplánovat čas", sk: "Naplánovať čas", en: "Schedule a time")
        static let time = T(cs: "Čas", sk: "Čas", en: "Time")
        static let timeNote = T(cs: "Na tento čas ti přijde připomínka.",
                                sk: "Na tento čas ti príde pripomienka.",
                                en: "You'll get a reminder at this time.")
        static let editSheetTitle = T(cs: "Upravit pilíř", sk: "Upraviť pilier", en: "Edit pillar")
        static let pillarText = T(cs: "Text pilíře", sk: "Text piliera", en: "Pillar text")
    }

    // MARK: Tabs

    enum tabs {
        static let town = T(cs: "Město", sk: "Mesto", en: "Town")
        static let pillars = T(cs: "Pilíře", sk: "Piliere", en: "Pillars")
        static let calendar = T(cs: "Kalendář", sk: "Kalendár", en: "Calendar")
        static let chronicle = T(cs: "Kronika", sk: "Kronika", en: "Chronicle")
        static let build = T(cs: "Stavět", sk: "Stavať", en: "Build")
    }

    // MARK: Chronicle

    enum chronicle {
        static let emptyTitle = T(cs: "Zatím prázdno", sk: "Zatiaľ prázdno", en: "Nothing here yet")
        static let emptyBody = T(
            cs: "Sem se zapíše každý uzavřený den. Uvidíš, co jsi splnil a co jsi za to postavil.",
            sk: "Sem sa zapíše každý uzavretý deň. Uvidíš, čo si splnil a čo si za to postavil.",
            en: "Every day you close lands here, along with what you built that day.")
        static let noResults = T(cs: "Nic nenalezeno", sk: "Nič sa nenašlo", en: "No matches")
        static let tryAnother = T(cs: "Zkus jiný výraz.", sk: "Skús iný výraz.",
                                  en: "Try a different word.")
        static let searchPrompt = T(cs: "Hledat v tascích", sk: "Hľadať v úlohách",
                                    en: "Search your tasks")
        static let noPillars = T(cs: "Bez pilířů", sk: "Bez pilierov", en: "No pillars")

        /// Czech and Slovak need three plural forms; English needs two.
        @MainActor
        static func days(_ n: Int) -> String {
            switch Language.shared.current {
            case .cs: n == 1 ? "1 den" : (n >= 2 && n <= 4 ? "\(n) dny" : "\(n) dnů")
            case .sk: n == 1 ? "1 deň" : (n >= 2 && n <= 4 ? "\(n) dni" : "\(n) dní")
            case .en: n == 1 ? "1 day" : "\(n) days"
            }
        }
    }

    // MARK: Onboarding and tutorial

    enum onboarding {
        static let skip = T(cs: "Přeskočit", sk: "Preskočiť", en: "Skip")
        static let next = T(cs: "Pokračovat", sk: "Pokračovať", en: "Continue")
        static let start = T(cs: "Pojďme na to", sk: "Poďme na to", en: "Let's go")

        static let page1Title = T(cs: "Vítej v Pilířích", sk: "Vitaj v Pilieroch",
                                  en: "Welcome to Pilíře")
        static let page1Body = T(
            cs: "Každé ráno si zapiš 3 až 5 nejdůležitějších úkolů dne, svoje pilíře. Žádný nekonečný seznam, jen to, na čem ti opravdu záleží.",
            sk: "Každé ráno si zapíš 3 až 5 najdôležitejších úloh dňa, svoje piliere. Žiadny nekonečný zoznam, len to, na čom ti naozaj záleží.",
            en: "Each morning, write down the three to five things that matter today — your pillars. Not an endless list, just what really counts.")

        static let page2Title = T(cs: "Plň a sbírej", sk: "Plň a zbieraj", en: "Finish and collect")
        static let page2Body = T(
            cs: "Za splněné pilíře dostáváš materiál, dřevo, cihly a ocel. Momentum ti odměny násobí a nikdy tě netrestá. Roste, když jsi aktivní, a po pauze klesá jen pomalu.",
            sk: "Za splnené piliere dostávaš materiál, drevo, tehly a oceľ. Momentum ti odmeny násobí a nikdy ťa netrestá. Rastie, keď si aktívny, a po pauze klesá len pomaly.",
            en: "Finished pillars earn you materials: wood, bricks and steel. Momentum multiplies your rewards and never punishes you — it grows when you show up and slips only slowly when you don't.")

        static let page3Title = T(cs: "Postav své město", sk: "Postav svoje mesto",
                                  en: "Build your town")
        static let page3Body = T(
            cs: "Za nasbíraný materiál postavíš budovu podle vlastního výběru, kam chceš. Podrž a táhni, když ji chceš přesunout, dvojklikem ji otočíš.",
            sk: "Za nazbieraný materiál postavíš budovu podľa vlastného výberu, kam chceš. Podrž a ťahaj, keď ju chceš presunúť, dvojklikom ju otočíš.",
            en: "Spend your materials on whichever building you like, wherever you like. Hold and drag to move it, double tap to turn it.")

        static let page4Title = T(cs: "Zkrášli ho", sk: "Skrášli ho", en: "Make it yours")
        static let page4Body = T(
            cs: "Za nasbírané mince nakoupíš stromy, cesty a fontány. Ať tvoje město roste spolu s tebou.",
            sk: "Za nazbierané mince nakúpiš stromy, cesty a fontány. Nech tvoje mesto rastie spolu s tebou.",
            en: "Coins buy trees, paths and fountains. Let your town grow along with you.")
    }

    enum tutorial {
        static let openPillars = T(cs: "Otevřít Pilíře →", sk: "Otvoriť Piliere →",
                                   en: "Open Pillars →")
        static let step1 = T(
            cs: "Zapiš si svůj první pilíř, cokoli, co dnes dává smysl. Klidně „umýt nádobí“.",
            sk: "Zapíš si svoj prvý pilier, čokoľvek, čo dnes dáva zmysel. Kľudne „umyť riad“.",
            en: "Write your first pillar — anything that makes sense today. Even \"do the dishes\".")
        static let step2 = T(
            cs: "Skvělé! Až to uděláš, odškrtni pilíř ťuknutím. Dostaneš za něj dřevo na stavbu.",
            sk: "Skvelé! Keď to urobíš, odškrtni pilier ťuknutím. Dostaneš zaň drevo na stavbu.",
            en: "Nice. Once it's done, tap the pillar to tick it off — you'll get wood to build with.")
        static let step3 = T(
            cs: "Máš materiál. Ťukni na kladívko uprostřed a postav svůj první baráček.",
            sk: "Máš materiál. Ťukni na kladivko uprostred a postav svoj prvý domček.",
            en: "You've got materials. Tap the hammer in the middle and build your first little house.")
    }

    // MARK: Notifications

    enum notifications {
        static let morningTitle = T(cs: "Jaké budou tvoje dnešní pilíře? 🏗",
                                    sk: "Aké budú tvoje dnešné piliere? 🏗",
                                    en: "What are your pillars today? 🏗")
        static let morningBody = T(cs: "Nastav si 1–5 cílů a postav budovu.",
                                   sk: "Nastav si 1–5 cieľov a postav budovu.",
                                   en: "Set one to five and build something.")
        static let eveningTitle = T(cs: "Nezapomněl jsi uzavřít den? 🌙",
                                    sk: "Nezabudol si uzavrieť deň? 🌙",
                                    en: "Did you close your day? 🌙")
        static let eveningBody = T(cs: "Odškrtni splněné pilíře a uzavři den.",
                                   sk: "Odškrtni splnené piliere a uzavri deň.",
                                   en: "Tick off what you did and close the day.")
        static let pillarDue = T(cs: "Naplánovaný pilíř, máš na něj čas?",
                                 sk: "Naplánovaný pilier, máš naň čas?",
                                 en: "A pillar you planned. Got a moment?")
        static let habitNote = T(cs: "Návyk z aplikace Pilíře", sk: "Návyk z aplikácie Piliere",
                                 en: "A habit from Pilíře")

        @MainActor
        static var gentleLines: [String] {
            switch Language.shared.current {
            case .cs: ["Žádný spěch, klidně až se to bude hodit.",
                       "Malý krok stačí. Město roste s tebou.",
                       "Jen jemné připomenutí, nic víc.",
                       "Klidně jen minutku. I ta se počítá.",
                       "Zkus to, až budeš mít chvilku."]
            case .sk: ["Žiadny zhon, kľudne až sa to bude hodiť.",
                       "Malý krok stačí. Mesto rastie s tebou.",
                       "Len jemné pripomenutie, nič viac.",
                       "Kľudne len minútku. Aj tá sa počíta.",
                       "Skús to, keď budeš mať chvíľku."]
            case .en: ["No rush. Whenever it suits you.",
                       "A small step is enough. Your town grows with you.",
                       "Just a gentle nudge, nothing more.",
                       "Even a minute counts.",
                       "Give it a go when you have a moment."]
            }
        }
    }

    // MARK: Resource info

    enum info {
        static let understood = T(cs: "Rozumím", sk: "Rozumiem", en: "Got it")
        static let holdHint = T(cs: "Podržením zobrazíš vysvětlení.",
                                sk: "Podržaním zobrazíš vysvetlenie.",
                                en: "Hold to see what this is.")
    }

    // MARK: Calendar

    enum calendar {
        static let title = T(cs: "Kalendář", sk: "Kalendár", en: "Calendar")
        static let activeDays = T(cs: "aktivní dny", sk: "aktívne dni", en: "active days")
        static let allDone = T(cs: "vše splněno", sk: "všetko splnené", en: "all done")
        static let building = T(cs: "budova", sk: "budova", en: "building")
        static let buildings = T(cs: "budovy", sk: "budovy", en: "buildings")

        static let chestTitle = T(cs: "Týdenní truhla", sk: "Týždenná truhlica",
                                  en: "Weekly chest")
        static let chestReady = T(cs: "Truhla je připravená!", sk: "Truhlica je pripravená!",
                                  en: "Your chest is ready!")
        static let chestReadyMany = T(cs: "Máš %d truhly!", sk: "Máš %d truhlice!",
                                      en: "You have %d chests!")
        static let open = T(cs: "Otevřít", sk: "Otvoriť", en: "Open")
        static let chestHintMany = T(
            cs: "Klepni a otevři je jednu po druhé. Co v nich je, zjistíš až uvnitř.",
            sk: "Klepni a otvor ich jednu po druhej. Čo v nich je, zistíš až vnútri.",
            en: "Tap to open them one by one. You'll find out what's inside when you do.")
        static let chestHintOne = T(cs: "Klepni a otevři svou týdenní odměnu.",
                                    sk: "Klepni a otvor svoju týždennú odmenu.",
                                    en: "Tap to open your weekly reward.")
        static let chestHintProgress = T(
            cs: "Splň aspoň jeden pilíř každý den v týdnu. Tento týden máš %d/7.",
            sk: "Splň aspoň jeden pilier každý deň v týždni. Tento týždeň máš %d/7.",
            en: "Finish at least one pillar every day this week. You're at %d/7.")
        static let chestOpened = T(cs: "Truhla", sk: "Truhlica", en: "Chest")
        static let chestRare = T(cs: "Vzácná truhla", sk: "Vzácna truhlica", en: "Rare chest")
        static let chestEpic = T(cs: "Zlatá truhla", sk: "Zlatá truhlica", en: "Golden chest")
        static let nice = T(cs: "Super!", sk: "Super!", en: "Lovely!")

        static let legendAllDone = T(cs: "Vše splněno", sk: "Všetko splnené", en: "All done")
        static let legendPartly = T(cs: "Částečně", sk: "Čiastočne", en: "Partly")
        static let legendNothing = T(cs: "Bez záznamu", sk: "Bez záznamu", en: "No record")
        static let legendBuilding = T(cs: "Postavená budova", sk: "Postavená budova",
                                      en: "Something built")
        static let legendHabit = T(cs: "Splněný návyk", sk: "Splnený návyk", en: "Habit done")

        static let dayPillars = T(cs: "Pilíře dne", sk: "Piliere dňa", en: "Pillars of the day")
        static let habitDone = T(cs: "Návyk splněn", sk: "Návyk splnený", en: "Habit done")
        static let pillarsLabel = T(cs: "pilířů", sk: "pilierov", en: "pillars")
        static let noPillarsDay = T(cs: "Tenhle den je bez pilířů.", sk: "Tento deň je bez pilierov.",
                                    en: "No pillars on this day.")
        static let perfectDay = T(cs: "Perfektní den, všechno splněno!",
                                  sk: "Perfektný deň, všetko splnené!",
                                  en: "A perfect day. Everything done!")
        static let partialDay = T(cs: "Dobrá práce, část dne se povedla.",
                                  sk: "Dobrá práca, časť dňa sa podarila.",
                                  en: "Good work, part of the day went well.")
        static let emptyDay = T(cs: "Tenhle den zůstal bez splněných pilířů.",
                                sk: "Tento deň zostal bez splnených pilierov.",
                                en: "No pillars were finished on this day.")
        static let doneOf = T(cs: "Splněno %d z %d pilířů", sk: "Splnené %d z %d pilierov",
                              en: "%d of %d pillars done")
        static let gotReward = T(cs: "%@. Získáno %@.", sk: "%@. Získané %@.",
                                 en: "%@. You got %@.")
    }

    // MARK: Map, shop and buildings

    enum map {
        static let underConstruction = T(cs: "Rozestavěná", sk: "Rozostavaná",
                                         en: "Under construction")
        static let rotate = T(cs: "Otočit", sk: "Otočiť", en: "Rotate")
        static let demolish = T(cs: "Zbourat", sk: "Zbúrať", en: "Demolish")
        static let demolishQuestion = T(cs: "Zbourat budovu?", sk: "Zbúrať budovu?",
                                        en: "Demolish this building?")
        static let refund = T(cs: "Vrátí se ti polovina materiálu (%@).",
                              sk: "Vráti sa ti polovica materiálu (%@).",
                              en: "You'll get half the materials back (%@).")
        static let nothing = T(cs: "nic", sk: "nič", en: "nothing")
        static let moveTip = T(cs: "Tip: podrž prst na budově a táhni pro přesun. Dvojklik ji otočí.",
                               sk: "Tip: podrž prst na budove a ťahaj pre presun. Dvojklik ju otočí.",
                               en: "Tip: hold a building and drag to move it. Double tap turns it.")

        static let expand = T(cs: "Rozšířit město", sk: "Rozšíriť mesto", en: "Expand the town")
        static let expandQuestion = T(cs: "Rozšířit město?", sk: "Rozšíriť mesto?",
                                      en: "Expand the town?")
        static let expandFor = T(cs: "Rozšířit za %@", sk: "Rozšíriť za %@", en: "Expand for %@")
        static let expandNote = T(cs: "Ostrov se zvětší a tvé město zůstane uprostřed.",
                                  sk: "Ostrov sa zväčší a tvoje mesto zostane uprostred.",
                                  en: "The island grows and your town stays in the middle.")

        static let woodInfo = T(
            cs: "Dostaneš ho hned za každý splněný pilíř. Základní materiál, ze kterého stavíš budovy.",
            sk: "Dostaneš ho hneď za každý splnený pilier. Základný materiál, z ktorého staviaš budovy.",
            en: "Earned the moment you finish a pillar. The basic material everything is built from.")
        static let brickInfo = T(
            cs: "Získáš je při uzavření dne, když splníš aspoň 2 pilíře. Potřeba na větší stavby.",
            sk: "Získaš ich pri uzavretí dňa, keď splníš aspoň 2 piliere. Potrebné na väčšie stavby.",
            en: "Earned when you close a day with at least two pillars done. Needed for bigger builds.")
        static let steelInfo = T(
            cs: "Získáš ji při uzavření dne se 4 a více pilíři, bonus za stoprocentní den. Vzácný materiál na ty největší stavby.",
            sk: "Získaš ju pri uzavretí dňa so 4 a viac piliermi, bonus za stopercentný deň. Vzácny materiál na tie najväčšie stavby.",
            en: "Earned by closing a day with four or more pillars, plus a bonus for a perfect day. The rare stuff for the grandest buildings.")

        static let dayClosedTitle = T(cs: "Den uzavřen", sk: "Deň uzavretý", en: "Day closed")
        static let woodAlready = T(cs: "Dřevo za jednotlivé tasky už máš v kapse.",
                                   sk: "Drevo za jednotlivé úlohy už máš vo vrecku.",
                                   en: "The wood for each task is already in your pocket.")
    }

    enum shop {
        static let title = T(cs: "Obchod", sk: "Obchod", en: "Shop")
        static let balance = T(cs: "Tvůj zůstatek", sk: "Tvoj zostatok", en: "Your balance")
        static let exchange = T(cs: "Směnárna", sk: "Zmenáreň", en: "Exchange")
        static let youHave = T(cs: "Máš: %d", sk: "Máš: %d", en: "You have: %d")
        static let decorations = T(cs: "Dekorace", sk: "Dekorácie", en: "Decorations")
        static let zoo = T(cs: "Zoo", sk: "Zoo", en: "Zoo")
        static let zooFooter = T(
            cs: "Zvíře se po koupi nastěhuje na mapu a začne se procházet. Chodí po loukách i cestách, obchází domy a rádo si žije po svém. Ťukni na něj a dá se probudit nebo poslat do boudy, podržením ho přeneseš jinam.",
            sk: "Zviera sa po kúpe nasťahuje na mapu a začne sa prechádzať. Chodí po lúkach aj cestách, obchádza domy a rado si žije po svojom. Ťukni naň a dá sa zobudiť alebo poslať do búdy, podržaním ho prenesieš inam.",
            en: "A pet moves onto the map and starts wandering. It walks the meadows and paths, goes around your buildings and lives its own life. Tap it to wake it or send it to its kennel; hold to carry it somewhere else.")
        static let resting = T(cs: "Na odpočinku", sk: "Na oddychu", en: "Resting")
        static let restingFooter = T(
            cs: "Zvířata, která teď odpočívají mimo mapu. Dej jim jméno, pusť je zpět, nebo se s nimi rozluč.",
            sk: "Zvieratá, ktoré teraz oddychujú mimo mapy. Daj im meno, pusti ich späť, alebo sa s nimi rozlúč.",
            en: "Pets resting off the map. Name them, let them back out, or say goodbye.")
        static let placeHint = T(cs: "Po nákupu ťukni na dlaždici kde chceš dekoraci umístit.",
                                 sk: "Po nákupe ťukni na dlaždicu, kde chceš dekoráciu umiestniť.",
                                 en: "After buying, tap the tile where you want it.")
        static let letOut = T(cs: "Pustit ven", sk: "Pustiť von", en: "Let out")
        static let sayGoodbye = T(cs: "Rozloučit se", sk: "Rozlúčiť sa", en: "Say goodbye")
        static let sayGoodbyeTo = T(cs: "Rozloučit se s %@?", sk: "Rozlúčiť sa s %@?",
                                    en: "Say goodbye to %@?")
        static let goodbyeNote = T(cs: "Zvíře nadobro opustí tvé městečko. Tohle nejde vzít zpět.",
                                   sk: "Zviera navždy opustí tvoje mestečko. Toto sa nedá vziať späť.",
                                   en: "Your pet leaves the town for good. This can't be undone.")
        static let goodbyeLabel = T(cs: "Rozloučit se se zvířetem", sk: "Rozlúčiť sa so zvieraťom",
                                    en: "Say goodbye to this pet")
    }

    // MARK: Map interactions

    enum town {
        static let removeQuestion = T(cs: "Odstranit %@?", sk: "Odstrániť %@?", en: "Remove %@?")
        static let removeRefund = T(cs: "Odstranit (+%d mincí zpět)", sk: "Odstrániť (+%d mincí späť)",
                                    en: "Remove (+%d coins back)")
        static let dragToMove = T(cs: "Přesunout ji můžeš i podržením a tažením.",
                                  sk: "Presunúť ju môžeš aj podržaním a ťahaním.",
                                  en: "You can also hold and drag it somewhere else.")

        static let animal = T(cs: "Zvíře", sk: "Zviera", en: "Pet")
        static let wakeUp = T(cs: "Probudit", sk: "Zobudiť", en: "Wake up")
        static let sendToKennel = T(cs: "Poslat do boudy", sk: "Poslať do búdy",
                                    en: "Send to the kennel")
        static let tuckAway = T(cs: "Uklidit na odpočinek", sk: "Uložiť na oddych",
                                en: "Send off to rest")
        static let tuckQuestion = T(cs: "Uklidit %@ na odpočinek?", sk: "Uložiť %@ na oddych?",
                                    en: "Send %@ off to rest?")
        static let tuckNote = T(
            cs: "Zmizí z mapy a počká v obchodě. Kdykoli ho zase pustíš ven ze sekce Na odpočinku.",
            sk: "Zmizne z mapy a počká v obchode. Kedykoľvek ho zase pustíš von zo sekcie Na oddychu.",
            en: "It leaves the map and waits in the shop. Let it back out any time from Resting.")
        static let carryHint = T(cs: "Podrž na něm prst a můžeš ho přenést jinam po mapě.",
                                 sk: "Podrž na ňom prst a môžeš ho preniesť inam po mape.",
                                 en: "Hold it to carry it somewhere else on the map.")

        static let doghouse = T(cs: "Psí bouda", sk: "Psia búda", en: "Doghouse")
        static let bowlFull = T(cs: "V misce už žrádlo je", sk: "V miske už žrádlo je",
                                en: "The bowl is already full")
        static let fillBowl = T(cs: "Nasypat žrádlo (%d mincí)", sk: "Nasypať žrádlo (%d mincí)",
                                en: "Fill the bowl (%d coins)")
        static let nameKennel = T(cs: "Napsat jméno na boudu", sk: "Napísať meno na búdu",
                                  en: "Put a name on it")
        static let removeKennel = T(cs: "Odstranit boudu", sk: "Odstrániť búdu",
                                    en: "Remove the doghouse")
        static let bowlFullNote = T(cs: "Miska je plná. Za chvíli si pro ni pes přijde.",
                                    sk: "Miska je plná. O chvíľu si po ňu pes príde.",
                                    en: "The bowl is full. Your dog will come for it soon.")
        static let kennelNote = T(cs: "Po setmění tu spí pes. Můžeš mu nasypat do misky.",
                                  sk: "Po zotmení tu spí pes. Môžeš mu nasypať do misky.",
                                  en: "Your dog sleeps here after dark. You can fill the bowl.")
        static let kennelNameTitle = T(cs: "Jméno na boudu", sk: "Meno na búdu", en: "Name the kennel")
        static let kennelNamePlaceholder = T(cs: "Třeba Rex", sk: "Napríklad Rex", en: "Rex, perhaps")
        static let kennelNameNote = T(cs: "Napiš jméno svého psa. Objeví se na cedulce nad boudou.",
                                      sk: "Napíš meno svojho psa. Objaví sa na ceduľke nad búdou.",
                                      en: "Write your dog's name. It goes on the sign above the door.")

        static let coinsInfo = T(
            cs: "Dostaneš je za první otevření aplikace v den. Utratíš je v obchodě za dekorace, směnu materiálu a rozšíření mapy.",
            sk: "Dostaneš ich za prvé otvorenie aplikácie v deň. Minieš ich v obchode za dekorácie, výmenu materiálu a rozšírenie mapy.",
            en: "Earned the first time you open the app each day. Spend them on decorations, materials and a bigger island.")
        static let momentum = T(cs: "Momentum", sk: "Momentum", en: "Momentum")
        static let momentumInfo = T(
            cs: "Roste o 1 za každý den, kdy appku otevřeš, a o 1 klesá za vynechaný den. Násobí odměny z pilířů a nikdy tě netrestá.",
            sk: "Rastie o 1 za každý deň, keď appku otvoríš, a o 1 klesá za vynechaný deň. Násobí odmeny z pilierov a nikdy ťa netrestá.",
            en: "Up one for every day you open the app, down one for every day you miss. It multiplies your rewards and never punishes you.")
        static let visitReward = T(cs: "+%d za dnešní návštěvu", sk: "+%d za dnešnú návštevu",
                                   en: "+%d for stopping by today")

        static let tapToBuild = T(cs: "Ťukni kam postavit: %@", sk: "Ťukni kam postaviť: %@",
                                  en: "Tap where to build: %@")
        static let dragPath = T(cs: "Táhni prstem a stav cestu (%d mincí za políčko)",
                                sk: "Ťahaj prstom a stavaj cestu (%d mincí za políčko)",
                                en: "Drag to lay a path (%d coins per tile)")
        static let tapToPlaceCorner = T(cs: "Ťukni kam umístit: %@. Jde i do rohu mezi políčka.",
                                        sk: "Ťukni kam umiestniť: %@. Ide aj do rohu medzi políčka.",
                                        en: "Tap where to place: %@. Corners between tiles work too.")
        static let tapToPlace = T(cs: "Ťukni kam umístit: %@", sk: "Ťukni kam umiestniť: %@",
                                  en: "Tap where to place: %@")
    }

    // MARK: Habits

    enum habits {
        static let title = T(cs: "Návyky", sk: "Návyky", en: "Habits")
        static let everyDay = T(cs: "Každý den", sk: "Každý deň", en: "Every day")
        static let mine = T(cs: "Moje návyky", sk: "Moje návyky", en: "My habits")
        static let intro = T(
            cs: "Návyk je pilíř, který se každé ráno sám zapíše do tvého dne. Třeba „Protáhnout se“ nebo „Zalít kytky v pondělí“.",
            sk: "Návyk je pilier, ktorý sa každé ráno sám zapíše do tvojho dňa. Napríklad „Ponaťahovať sa“ alebo „Poliať kvety v pondelok“.",
            en: "A habit is a pillar that writes itself into your day each morning. Something like \"Stretch\" or \"Water the plants on Monday\".")
        static let newPlaceholder = T(cs: "Co chceš dělat pravidelně?", sk: "Čo chceš robiť pravidelne?",
                                      en: "What do you want to do regularly?")
        static let noDaysNote = T(cs: "Bez výběru dní se návyk přidává každý den.",
                                  sk: "Bez výberu dní sa návyk pridáva každý deň.",
                                  en: "With no days picked, it's added every day.")
        static let remind = T(cs: "Připomenout", sk: "Pripomenúť", en: "Remind me")
        static let addHabit = T(cs: "Přidat návyk", sk: "Pridať návyk", en: "Add habit")
        static let newHabit = T(cs: "Nový návyk", sk: "Nový návyk", en: "New habit")
        static let newFooter = T(cs: "Aktivní návyky se každé ráno samy objeví mezi pilíři dne.",
                                 sk: "Aktívne návyky sa každé ráno samy objavia medzi piliermi dňa.",
                                 en: "Active habits show up among your pillars each morning.")
        static let habitSection = T(cs: "Návyk", sk: "Návyk", en: "Habit")
        static let name = T(cs: "Název", sk: "Názov", en: "Name")
        static let reminderSection = T(cs: "Připomínka", sk: "Pripomienka", en: "Reminder")
        static let remindersApp = T(cs: "Aplikace Připomínky", sk: "Aplikácia Pripomienky",
                                    en: "Apple Reminders")
        static let remindersFailed = T(
            cs: "Nepodařilo se. Povol Pilířům přístup k Připomínkám v Nastavení systému.",
            sk: "Nepodarilo sa. Povoľ Pilierom prístup k Pripomienkam v Nastaveniach systému.",
            en: "That didn't work. Allow Pilíře to use Reminders in system Settings.")
        static let remindersNote = T(
            cs: "Vytvoří opakovanou připomínku v Apple Připomínkách podle dnů a času návyku.",
            sk: "Vytvorí opakovanú pripomienku v Apple Pripomienkach podľa dní a času návyku.",
            en: "Creates a repeating reminder in Apple Reminders on the habit's days and time.")
        static let active = T(cs: "Aktivní", sk: "Aktívny", en: "Active")
        static let deleteHabit = T(cs: "Smazat návyk", sk: "Zmazať návyk", en: "Delete habit")
        static let editHabit = T(cs: "Upravit návyk", sk: "Upraviť návyk", en: "Edit habit")
        static let atWhatTime = T(cs: "V kolik?", sk: "O koľkej?", en: "At what time?")
        static let doneInWeeks = T(cs: "Splněno %d× za posledních 5 týdnů",
                                   sk: "Splnené %d× za posledných 5 týždňov",
                                   en: "Done %d× in the last 5 weeks")

        @MainActor
        static var dayLabels: [String] {
            switch Language.shared.current {
            case .cs: ["Po", "Út", "St", "Čt", "Pá", "So", "Ne"]
            case .sk: ["Po", "Ut", "St", "Št", "Pi", "So", "Ne"]
            case .en: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            }
        }
    }

    // MARK: Splash quotes

    enum quotes {
        @MainActor
        static var all: [String] {
            switch Language.shared.current {
            case .cs: [
                "Malé kroky staví velká města.",
                "Dnešek je nový kámen v základech.",
                "Nemusíš všechno. Stačí něco.",
                "Každý splněný úkol je cihla k lepšímu dni.",
                "Pomalu se taky dojde daleko.",
                "Tvoje město roste s tebou.",
                "I odpočinek je pilíř.",
                "Začni tím nejmenším.",
                "Dnes stačí jeden dobrý krok.",
                "Silné základy se staví každý den.",
                "Co uděláš dnes, zůstane stát.",
                "Není třeba spěchat, jen nepřestat.",
                "I šedý den může položit zlatý kámen.",
                "Buď na sebe hodný, stavíš celý svět.",
                "Jeden pilíř stačí, aby den stál.",
                "Velké katedrály začínaly jedním kamenem.",
                "Včerejšek je postaven. Dnešek čeká.",
                "Města nerostou přes noc. Ty taky ne, a to je v pořádku."]
            case .sk: [
                "Malé kroky stavajú veľké mestá.",
                "Dnešok je nový kameň v základoch.",
                "Nemusíš všetko. Stačí niečo.",
                "Každá splnená úloha je tehla k lepšiemu dňu.",
                "Pomaly sa tiež dôjde ďaleko.",
                "Tvoje mesto rastie s tebou.",
                "Aj oddych je pilier.",
                "Začni tým najmenším.",
                "Dnes stačí jeden dobrý krok.",
                "Silné základy sa stavajú každý deň.",
                "Čo urobíš dnes, zostane stáť.",
                "Netreba sa ponáhľať, len neprestať.",
                "Aj sivý deň môže položiť zlatý kameň.",
                "Buď na seba dobrý, staviaš celý svet.",
                "Jeden pilier stačí, aby deň stál.",
                "Veľké katedrály začínali jedným kameňom.",
                "Včerajšok je postavený. Dnešok čaká.",
                "Mestá nerastú cez noc. Ty tiež nie, a to je v poriadku."]
            case .en: [
                "Small steps build great towns.",
                "Today is a new stone in the foundations.",
                "You don't have to do everything. Something is enough.",
                "Every finished task is a brick towards a better day.",
                "Slowly still gets you far.",
                "Your town grows with you.",
                "Rest is a pillar too.",
                "Start with the smallest thing.",
                "One good step is enough today.",
                "Strong foundations are laid daily.",
                "What you do today stays standing.",
                "No need to hurry, just don't stop.",
                "Even a grey day can lay a golden stone.",
                "Be kind to yourself. You're building a world.",
                "One pillar is enough to hold up a day.",
                "Great cathedrals started with a single stone.",
                "Yesterday is built. Today is waiting.",
                "Towns don't grow overnight. Neither do you, and that's fine."]
            }
        }
    }

    // MARK: Random task pool

    enum pool {
        static let title = T(cs: "Dej mi task", sk: "Daj mi úlohu", en: "Pick one for me")
        static let intro = T(
            cs: "Vyber si jeden. Za splnění vylosovaného tasku dostaneš bonusovou odměnu.",
            sk: "Vyber si jeden. Za splnenie vylosovanej úlohy dostaneš bonusovú odmenu.",
            en: "Pick one. Finishing a drawn task earns you a bonus reward.")
        static let reroll = T(cs: "Vylosovat jiné", sk: "Vylosovať iné", en: "Draw again")
    }

    // MARK: Leftovers

    enum misc {
        static let paused = T(cs: "· pozastaveno", sk: "· pozastavené", en: "· paused")
        static let todayMark = T(cs: "· dnes", sk: "· dnes", en: "· today")
        static let buildBuilding = T(cs: "Postavit budovu", sk: "Postaviť budovu",
                                     en: "Put up a building")
        static let momentumGain = T(cs: "Momentum +%d", sk: "Momentum +%d", en: "Momentum +%d")
        static let coinsLabel = T(cs: "Mince: %d", sk: "Mince: %d", en: "Coins: %d")
        static let momentumLabel = T(cs: "Momentum: %d", sk: "Momentum: %d", en: "Momentum: %d")
        static let integrations = T(cs: "Integrace", sk: "Integrácie", en: "Integrations")
        static let history = T(cs: "Historie", sk: "História", en: "History")
    }

    // MARK: Settings

    enum settings {
        static let title = T(cs: "Nastavení", sk: "Nastavenia", en: "Settings")

        static let languageSection = T(cs: "Jazyk", sk: "Jazyk", en: "Language")
        static let language = T(cs: "Jazyk aplikace", sk: "Jazyk aplikácie", en: "App language")

        static let remindersSection = T(cs: "Připomínky", sk: "Pripomienky", en: "Reminders")
        static let remindersToggle = T(cs: "Zapnout připomínky", sk: "Zapnúť pripomienky",
                                       en: "Turn on reminders")
        static let morningNudge = T(cs: "Ranní výzva", sk: "Ranná výzva", en: "Morning nudge")
        static let eveningNudge = T(cs: "Večerní připomínka", sk: "Večerná pripomienka",
                                    en: "Evening reminder")

        static let gentleSection = T(cs: "Jemné připomínky", sk: "Jemné pripomienky",
                                     en: "Gentle reminders")
        static let habits = T(cs: "Návyky", sk: "Návyky", en: "Habits")
        static let timedTasks = T(cs: "Časované úkoly", sk: "Časované úlohy", en: "Timed tasks")
        static let gentleFooter = T(
            cs: "Jedna tichá zpráva v čas návyku nebo úkolu, žádné výčitky ani opakování. Splněný návyk už ten den nepípne.",
            sk: "Jedna tichá správa v čase návyku alebo úlohy, žiadne výčitky ani opakovanie. Splnený návyk už v ten deň nepípne.",
            en: "One quiet message when a habit or task is due. No guilt, no repeats. A habit you've done won't ping you again that day.")

        static let mapSection = T(cs: "Ovládání mapy", sk: "Ovládanie mapy", en: "Map controls")
        static let mapFollowsFinger = T(cs: "Mapa sleduje prst", sk: "Mapa sleduje prst",
                                        en: "Map follows your finger")
        static let mapFooter = T(
            cs: "Zapnuto: mapa se posouvá s prstem, jako fotka. Vypnuto: kamera letí směrem tažení.",
            sk: "Zapnuté: mapa sa posúva s prstom, ako fotka. Vypnuté: kamera letí smerom ťahania.",
            en: "On: the map moves with your finger, like a photo. Off: the camera flies the way you drag.")

        static let appSection = T(cs: "Aplikace", sk: "Aplikácia", en: "App")
        static let version = T(cs: "Verze", sk: "Verzia", en: "Version")

        static let deleteAll = T(cs: "Smazat všechna data", sk: "Zmazať všetky dáta",
                                 en: "Delete all data")
        static let deleteAllQuestion = T(cs: "Smazat všechna data?", sk: "Zmazať všetky dáta?",
                                         en: "Delete all data?")
        static let deleteEverything = T(cs: "Smazat vše", sk: "Zmazať všetko", en: "Delete everything")
        static let deleteMessage = T(
            cs: "Přijdeš o celé město, historii i návyky. Tohle nejde vzít zpět.",
            sk: "Prídeš o celé mesto, históriu aj návyky. Toto sa nedá vziať späť.",
            en: "You'll lose your whole town, your history and your habits. This can't be undone.")
        static let deleteFooter = T(
            cs: "Smaže město, pilíře, návyky, mince i materiál a vrátí appku do stavu po instalaci. Nevratné.",
            sk: "Zmaže mesto, piliere, návyky, mince aj materiál a vráti appku do stavu po inštalácii. Nevratné.",
            en: "Erases your town, pillars, habits, coins and materials, leaving the app as freshly installed. Permanent.")
        static let deleteDoneFooter = T(
            cs: "Hotovo. Ukonči aplikaci (odsuň ji nahoru) a spusť znovu, načte se jako úplně nová.",
            sk: "Hotovo. Ukonči aplikáciu (odsuň ju hore) a spusti znova, načíta sa ako úplne nová.",
            en: "Done. Quit the app (swipe it away) and open it again — it'll start completely fresh.")
    }
}
