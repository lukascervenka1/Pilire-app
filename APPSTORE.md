# App Store — Pilíře 1.0

Podklady pro App Store Connect. Limity znaků jsou ověřené skriptem
(název ≤ 30, podtitul ≤ 30, promo ≤ 170, klíčová slova ≤ 100, popis ≤ 4000).

---

## Společné údaje (všechny jazyky)

| Pole | Hodnota |
|---|---|
| Bundle ID | `Aimplementace.cz.Pilire` |
| SKU | `pilire-ios-1` |
| Primární jazyk | Čeština |
| Primární kategorie | Produktivita (Productivity) |
| Sekundární kategorie | Hry → Simulace (Games → Simulation) |
| Cena | Zdarma, bez nákupů v aplikaci |
| Dostupnost | Jen iPhone; v *Pricing and Availability* vypnout „iPhone and iPad Apps on Apple Silicon Macs“ a „Apple Vision Pro“ |
| Copyright | 2026 Lukáš Červenka |
| Privacy Policy URL | https://github.com/lukascervenka1/Pilire-app/blob/main/PRIVACY.md |
| Support URL | https://aimplementace.cz (musí na ní být kontakt; jinak odkaz na README v repu) |
| Marketing URL | nepovinné, lze nechat prázdné |

### App Privacy (nutriční štítek)
**Data Not Collected.** Aplikace nemá účet, analytiku, reklamy ani síťová
volání. Data se ukládají jen v zařízení (SwiftData). To odpovídá
`PrivacyInfo.xcprivacy` v balíčku.

### Věkové hodnocení
Ve všech kategoriích dotazníku **None / No**. Výsledek: **4+**.
Hostinec má na vývěsním štítu malý korbel. Nejde o konzumaci ani zobrazování
alkoholu, takže podle mě nespadá pod „Alcohol, Tobacco, or Drug Use or
References“.
Výjimka: pokud by recenzent hodnocení vrátil, zaškrtni *Infrequent/Mild*.

### Export compliance
`ITSAppUsesNonExemptEncryption = NO` je v Info.plist, takže se na šifrování
App Store Connect u buildů ptát nebude.

---

## 🇨🇿 Čeština

**Název** (30)
```
Pilíře: Návyky a městečko
```

**Podtitul** (30)
```
Splň svůj den, postav město
```

**Promo text** (170, lze měnit kdykoli bez nové recenze)
```
Žádné série, které můžeš přerušit, a žádné výčitky. Splň pár věcí, na kterých dnes záleží, a sleduj, jak na tvém ostrově roste městečko.
```

**Klíčová slova** (100, oddělená čárkou bez mezer)
```
zvyky,úkoly,rutina,ADHD,motivace,denní plán,to do,seznam,hra,ostrov,stavění,budovy,zvířata,cíle
```

**Popis**
```
Pilíře jsou klidná aplikace na návyky, která se hraje jako malá hra. Každý den si pojmenuješ pár věcí, na kterých záleží. Za každou splněnou dostaneš materiál a z něj stavíš 3D městečko na létajícím ostrově, který patří jen tobě.

Žádné červené křížky, žádné přerušené série, žádné výčitky. Když den vynecháš, nic nevyhoří. Tvoje město na tebe počká.

PILÍŘE DNE
• Pár věcí, které drží tvůj den. Ne nekonečný seznam úkolů.
• Splněný pilíř = dřevo hned. Uzavřený den = cihly a ocel.
• Něco nevyšlo? Přenes to na dnešek jedním ťuknutím, nebo to nech být.
• Nevíš, čím začít? Nech si vylosovat malý, zvládnutelný úkol.
• Z čehokoli uděláš pravidelný návyk s vlastním časem a jedním tichým připomenutím.

TVOJE MĚSTEČKO
• Přes 25 budov: od stanu a chaloupky přes statek, kovárnu, hasičárnu a nemocnici až po zámek a katedrálu.
• Silnice kreslíš tahem prstu. Stromy, lavičky, rybník, ohniště a krmítko, na které opravdu létají ptáci.
• Cokoli můžeš kdykoli přesunout nebo uložit do inventáře.
• Zvířata: pes, husky, liška, vlk, srnec, kráva, kůň a alpaka. Chodí si po ostrově, v noci spí a psovi postavíš boudu s jeho jménem.
• Živý ostrov: den a noc podle skutečného času, počasí, mraky, vodopády, motýli a světlušky.

MOMENTUM MÍSTO SÉRIÍ
Momentum ukazuje, jak pravidelně se vracíš, a násobí tvoje odměny. Roste, když jsi aktivní, a po pauze klesá jen pomalu. Nikdy tě netrestá.

KALENDÁŘ A KRONIKA
• Kalendář vybarvený podle toho, jak dny dopadly.
• Týdenní truhla s překvapením, když se ukážeš každý den v týdnu.
• Kronika všech uzavřených dnů a toho, co se za ně postavilo.
• Odznaky za milníky.
• Sezónní události: na Halloween a o Vánocích přibudou speciální budovy a dekorace.

SOUKROMÍ
Žádný účet, žádné reklamy, žádné sledování, žádný server. Všechno zůstává v tvém telefonu a aplikace funguje i offline. Kalendář a Připomínky jsou volitelné a aplikace do nich jen zapisuje.

Pilíře jsou zdarma, bez reklam a bez nákupů v aplikaci.
```

---

## 🇸🇰 Slovenčina

**Názov**
```
Pilíře: Návyky a mestečko
```

**Podtitul**
```
Splň svoj deň, postav mesto
```

**Promo text**
```
Žiadne série, ktoré môžeš prerušiť, a žiadne výčitky. Splň pár vecí, na ktorých dnes záleží, a sleduj, ako na tvojom ostrove rastie mestečko.
```

**Kľúčové slová**
```
zvyky,úlohy,rutina,ADHD,motivácia,denný plán,to do,zoznam,hra,ostrov,stavanie,budovy,zvieratá,ciele
```

**Popis**
```
Pilíře sú pokojná aplikácia na návyky, ktorá sa hrá ako malá hra. Každý deň si pomenuješ pár vecí, na ktorých záleží. Za každú splnenú dostaneš materiál a z neho staviaš 3D mestečko na lietajúcom ostrove, ktorý patrí len tebe.

Žiadne červené krížiky, žiadne prerušené série, žiadne výčitky. Keď deň vynecháš, nič nevyhorí. Tvoje mesto na teba počká.

PILIERE DŇA
• Pár vecí, ktoré držia tvoj deň. Nie nekonečný zoznam úloh.
• Splnený pilier = drevo hneď. Uzavretý deň = tehly a oceľ.
• Niečo nevyšlo? Prenes to na dnešok jedným ťuknutím, alebo to nechaj tak.
• Nevieš, čím začať? Nechaj si vylosovať malú, zvládnuteľnú úlohu.
• Z čohokoľvek urobíš pravidelný návyk s vlastným časom a jednou tichou pripomienkou.

TVOJE MESTEČKO
• Viac ako 25 budov: od stanu a chalúpky cez statok, kováčsku dielňu, hasičskú stanicu a nemocnicu až po zámok a katedrálu.
• Cesty kreslíš ťahom prsta. Stromy, lavičky, jazierko, ohnisko a kŕmidlo, na ktoré naozaj lietajú vtáky.
• Čokoľvek môžeš kedykoľvek presunúť alebo uložiť do inventára.
• Zvieratá: pes, husky, líška, vlk, srnec, krava, kôň a alpaka. Chodia si po ostrove, v noci spia a psovi postavíš búdu s jeho menom.
• Živý ostrov: deň a noc podľa skutočného času, počasie, mraky, vodopády, motýle a svetlušky.

MOMENTUM NAMIESTO SÉRIÍ
Momentum ukazuje, ako pravidelne sa vraciaš, a násobí tvoje odmeny. Rastie, keď si aktívny, a po pauze klesá len pomaly. Nikdy ťa netrestá.

KALENDÁR A KRONIKA
• Kalendár vyfarbený podľa toho, ako dni dopadli.
• Týždenná truhlica s prekvapením, keď sa ukážeš každý deň v týždni.
• Kronika všetkých uzavretých dní a toho, čo sa za ne postavilo.
• Odznaky za míľniky.
• Sezónne udalosti: na Halloween a cez Vianoce pribudnú špeciálne budovy a dekorácie.

SÚKROMIE
Žiadny účet, žiadne reklamy, žiadne sledovanie, žiadny server. Všetko zostáva v tvojom telefóne a aplikácia funguje aj offline. Kalendár a Pripomienky sú voliteľné a aplikácia do nich len zapisuje.

Pilíře sú zadarmo, bez reklám a bez nákupov v aplikácii.
```

---

## 🇬🇧 English (U.K.) + English (U.S.)

Stejný text vlož do obou anglických lokalizací. Bez U.S. verze se v USA
zobrazí čeština.

**Name**
```
Pilíře: Habits & Tiny Town
```

**Subtitle**
```
Finish your day, grow a town
```

**Promotional Text**
```
No streaks to break, no guilt. Finish a few things that matter today and watch a little town grow on a floating island that's all yours.
```

**Keywords**
```
habit tracker,routine,ADHD,to do,daily planner,tasks,goals,motivation,city builder,island,cozy,game
```

**Description**
```
Pilíře (“pillars”) is a gentle habit app that plays like a small game. Each day you name a handful of things that matter. Every one you finish earns materials, and you spend them on a 3D town growing on a floating island that's entirely your own.

No red crosses, no broken streaks, no guilt. Miss a day and nothing burns down. Your town is still there, waiting.

PILLARS OF THE DAY
• A few things that hold up your day. Not an endless to-do list.
• Finish a pillar and get wood right away. Close the day for bricks and steel.
• Didn't get to something? Carry it to today with one tap, or let it go.
• Not sure where to start? Draw a small, doable task at random.
• Turn anything into a recurring habit with its own time and a single quiet reminder.

YOUR TOWN
• Over 25 buildings, from a tent and a cottage to a farmstead, a blacksmith, a fire station, a hospital, a château and a cathedral.
• Paint roads with your finger. Add trees, benches, a pond, a fire pit and a bird feeder that birds actually visit.
• Move anything at any time, or put it away in your inventory.
• Animals: a dog, a husky, a fox, a wolf, a deer, a cow, a horse and an alpaca. They wander the island, sleep at night, and your dog gets a kennel with its name on it.
• A living island: day and night that follow the real clock, weather, drifting clouds, waterfalls, butterflies and fireflies.

MOMENTUM, NOT STREAKS
Momentum reflects how regularly you show up and multiplies your rewards. It grows when you're active and slips only slowly after a break. It never punishes you.

CALENDAR AND CHRONICLE
• A calendar tinted by how each day went.
• A weekly chest with a surprise when you show up every day of the week.
• A chronicle of every day you closed and what it built.
• Badges for milestones.
• Seasonal events: special buildings and decorations for Halloween and Christmas.

PRIVACY
No account, no ads, no tracking, no server. Everything stays on your phone and the app works fully offline. Calendar and Reminders access is optional, and the app only ever writes to them.

Pilíře is free, with no ads and no in-app purchases.
```

---

## App Review Information

- **Sign-in required:** No.
- **Contact:** Lukáš Červenka, e-mail a telefon vyplň v App Store Connect.
- **Notes** (anglicky, aby to recenzent přečetl):

```
Pilíře is a habit app with a small city-building game. No account or network connection is needed; all data stays on the device.

Quick path through the app:
1. On first launch, pick a language and accept or decline the notification prompt.
2. On the Pillars tab, add a pillar (task) and tick it off. You receive wood.
3. Press and hold "Close the day" to receive bricks and steel.
4. Tap the hammer button in the middle of the tab bar ("Build something") and place a building on the island. Long-press any building to drag it elsewhere.

Calendar (write-only) and Reminders access are optional. They are requested only when the user exports a task or habit, and the app never reads existing events.

The app is free with no in-app purchases, ads, analytics or tracking.
```

---

## Snímky obrazovky

Hotové v `AppStore/screenshots/{cs,sk,en}/`. Formát je 1320 × 2868, tedy sada 6,9″,
ze které si App Store menší velikosti zmenší sám. Nahrávají se v tomto pořadí:

1. `01_island`: celý ostrov, „Pilíře“ a „Zdarma · Bez reklam · Bez účtu“.
2. `02_town`: městečko zblízka.
3. `03_pillars`: dnešní pilíře (3/5).
4. `04_build`: katalog budov.
5. `05_night`: město v noci.
6. `06_calendar`: kalendář s truhlou.
7. `07_badges`: odznaky.

V obou anglických lokalizacích (U.K. i U.S.) použij složku `en`.

Snímky vznikly v simulátoru iPhone 17 Pro Max v Debug buildu. Argumenty
`-screenshotHour`, `-screenshotWeather`, `-screenshotZoom` a `-screenshotSeed`
(viz `ScreenshotMode.swift`) nastaví čas, počasí a zoom. Seed doplní ukázkovou
historii dnů. V Release buildu nic z toho neexistuje.

## „Co je nového“

Nejnovější verze je nahoře. Stejné novinky ukazuje i okno ve hře
(`Pilire/ReleaseNotes.swift`) a Nastavení → Novinky. Limit pole je 4000 znaků.

### 1.0.2

🇨🇿
```
Plánuj dopředu a uprav si den po svém:

• Pilíře teď naplánuješ na libovolný den a čas. Ťukni na hodiny vedle „Přidat pilíř…“.
• Pilíř smažeš, i když není hotový. Návyk můžeš jen pro dnešek vynechat.
• Pilíře i návyky seřadíš přetažením.
• Návyky mohou mít pevný čas a připomínka přijde přesně tehdy. Nový návyk přidáš hned nahoře.
• Psi a husky mají plynulejší pohyby: u misky opravdu jedí, po nakrmení vrtí ocasem a v boudě si lehnou ke spánku.
• Týdenní truhla i kalendář počítají týden od pondělí do neděle.
```

🇸🇰
```
Plánuj dopredu a uprav si deň po svojom:

• Piliere teraz naplánuješ na ľubovoľný deň a čas. Ťukni na hodiny vedľa „Pridať pilier…“.
• Pilier zmažeš, aj keď nie je hotový. Návyk môžeš len pre dnešok vynechať.
• Piliere aj návyky zoradíš potiahnutím.
• Návyky môžu mať pevný čas a pripomienka príde presne vtedy. Nový návyk pridáš hneď hore.
• Psy a husky majú plynulejšie pohyby: pri miske naozaj jedia, po nakŕmení vrtia chvostom a v búde si ľahnú spať.
• Týždenná truhlica aj kalendár počítajú týždeň od pondelka do nedele.
```

🇬🇧 (U.K. i U.S.)
```
Plan ahead and shape your day your way:

• Plan pillars for any day and time. Tap the clock next to “Add a pillar…”.
• Delete a pillar even if it isn't done, or skip a habit just for today.
• Drag pillars and habits into your own order.
• Habits can have a set time, and the reminder comes right then. New habits are added at the top.
• Smoother dogs and huskies: they really eat at the bowl, wag after a meal and curl up in their kennel.
• The weekly chest and the calendar now count weeks from Monday to Sunday.
```

### 1.0.1

🇨🇿
```
• Týdenní truhla v novém kabátě: v kalendáři vidíš, jak se k ní každým dnem blížíš, a při otevření se dozvíš, jestli je odměna běžná, vzácná, nebo zlatá.
• Zvířata teď koupíš přímo v katalogu stavění – ťukni na kladívko a vyber kategorii Zvířata.
```

🇸🇰
```
• Týždenná truhlica v novom šate: v kalendári vidíš, ako sa k nej každým dňom blížiš, a pri otvorení zistíš, či je odmena bežná, vzácna alebo zlatá.
• Zvieratá si teraz kúpiš priamo v katalógu stavania – ťukni na kladivo a vyber kategóriu Zvieratá.
```

🇬🇧
```
• A new weekly chest: the calendar shows how close you are each day, and opening it reveals whether your reward is common, rare or golden.
• Adopt animals straight from the build catalogue – tap the hammer and pick Animals.
```
