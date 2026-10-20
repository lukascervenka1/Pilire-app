# Kalendář — audit a návrh menšího updatu

Datum: 16. 10. 2026. Původní rozsah: audit a návrh. Na navazující odsouhlasení vzhledu truhly navazuje implementace popsaná na konci dokumentu; nálezy výše odkazují na stav před touto implementací.

**Upřesnění po zpětné vazbě:** uživatel chce ponechat detail dne v Kronice. Hlavním směrem updatu je nyní týdenní truhla, postup k odměně a napětí při odhalení její vzácnosti. Původní návrh dalšího shrnutí dne pod mřížkou je nahrazen níže uvedenou podobou.

## Závěr

Kalendář má použitelný základ: přehledný měsíc, návaznost na denní záznamy a týdenní odměnu. Oproti novému vzhledu města ale působí obecně. Ukazuje hlavně barevná políčka; málo připomíná, co hráč svým úsilím vytvořil.

Největší přínos malého updatu bude mít **výraznější týdenní truhla a krátké, příjemně napínavé odhalení odměny**. Kalendář ukazuje postup týdnem a očekávání; osobní historii dne má na starosti Kronika. Krémové pozadí, zaoblení a střídmou paletu bych zachoval.

## Co bylo ověřeno

- Statická kontrola `CalendarView.swift`, modelů, ukládání odměn, lokalizace, plánování pilířů a sdíleného detailu v Kronice.
- Vizuální kontrola existujícího prezentačního screenshotu `docs/screenshots/calendar.jpg`. Nejde o nový záznam běžící aplikace ani o skutečná uživatelská data.
- Samostatné kontroly Foundation pro začátky týdnů podle locale, alternativní systémový kalendář a příklad duplicitního dne; výpočet kontrastu současných barev.
- VoiceOver, velké písmo, chování přes půlnoc a chybu ukládání je potřeba ověřit při implementaci na zařízení. Níže jsou odlišeny doložené nedostatky od podmíněných rizik.

## Hlavní nálezy

| Priorita | Nález a dopad | Navržená změna | Podklad |
| --- | --- | --- | --- |
| P1 | Výpočet odměnového týdne závisí na locale jazyka. Změna CS → EN může změnit začátek týdne i jeho uložený klíč. | Oddělit pravidla odměnového týdne od jazyka rozhraní a zachovat již vyzvednuté odměny. | `CalendarView.swift:14`, `:172`; `UserSettings.swift:144` |
| P1 | Po vyzvednutí aktuální truhly může zůstat neaktivní karta s údajem 7/7 a instrukcí ke splnění týdne. Chybí stav „Vyzvednuto“. | Výslovné stavy: probíhá, připravena, vyzvednuta, uzavřený nesplněný týden. | `CalendarView.swift:264`, `:273` |
| P1 | Detail budoucího naplánovaného dne používá hlášku „Tenhle den zůstal bez splněných pilířů“. | Rozlišit minulost, dnešek a budoucnost. Budoucnost ukazuje plán, nikoli hodnocení výsledku. | `CalendarView.swift:571`; plán zítřka v `DailyView.swift` |
| P1 | Den s několika budovami zobrazí pouze první. Typ detailu se navíc mění podle přítomnosti budovy. | Jeden detail dne se všemi pilíři, časy a všemi postavenými budovami. Použít ho také v Kronice. | `CalendarView.swift:44`, `:431`; `ChronicleView.swift:65` |
| P1 | Úspěšná animace a haptika následují po `saveChanges()`, i když tato metoda chybu ukládání pouze zachytí. | Potvrdit úspěch až po úspěšném uložení. Při selhání obnovit konzistentní stav a nabídnout opakování. | `CalendarView.swift:203`; `Theme.swift:117` |
| P2 | Klepnutí na datum bez záznamu nic neudělá. Chybí návrat na dnešek. | Vyjasnit chování prázdných dnů a přidat „Dnes“. Detail historie zůstává v Kronice. | `CalendarView.swift:9`, `:63`, `:160` |
| P2 | Dokončení se čte především z barvy. Drobné tečky budovy a návyku mají jen 4 body; na hotovém dni jsou obě bílé. | Ponechat mřížku střídmou, přidat rozlišitelný znak dokončení a význam vypsat v detailu i VoiceOver popisku. | `CalendarView.swift:390`, `:415` |
| P2 | Bílá číslice na zelené má vypočtený kontrast přibližně 2,42 : 1. Popisky statistik mají pevnou velikost 10 bodů. | Tmavý text na světlé šalvějové, škálované písmo a adaptivní rozložení statistik. | `CalendarView.swift:110`, `:372`, `:415` |

P1 zde znamená zařadit do prvního updatu kalendáře; tabulka sama o sobě není závěrem, že je nutné zastavit současné vydání.

### Podrobnosti technických rizik

**Týdny a jazyky.** V kontrolním výpočtu s gregoriánským kalendářem připadá datum 16. 10. 2026 pro CS/SK do týdne začínajícího 12. 10., pro EN do týdne začínajícího 11. 10. Výsledek může ovlivnit výslovná systémová preference začátku týdne. Protože stejný začátek tvoří klíč odměny, změna jazyka může vytvořit jiné, překrývající se odměnové období. Doporučení pro malý update: stávajícím uživatelům zachovat dosavadní nastavení týdne a dál ho neměnit při změně jazyka. Převod musí respektovat historické klíče; nemaže se `claimedWeekKeys` ani zůstatky.

**Konzistence kalendáře.** Obrazovka dědí systémový kalendář, samostatná buňka používá znovu `Calendar.current` a některé formátovače mají vlastní locale. Při alternativním systémovém kalendáři může vzniknout rozdíl mezi nadpisem a daty mřížky. Zavést jedno explicitní nastavení kalendáře, časové zóny a pravidel týdne pro celou obrazovku. Politiku změny časové zóny určit i s ohledem na historické denní záznamy, které jsou dnes uložené jako časové okamžiky.

**Duplicitní dny.** Model nemá záruku jednoho záznamu na den. Mřížka při duplicitě vezme první záznam, statistiky počítají všechny. Kontrolní příklad proto ukázal v mřížce nulu a ve statistikách jeden aktivní den. Není doloženo, že se to děje v uživatelské databázi. Zavést jednotné vyhledání/vytvoření denního záznamu a případné sloučení až s ohledem na pilíře a vztahy budov. Samotné přidání unikátního omezení bez migrace není vhodná oprava produkčních dat.

**Výkon.** Vyhledání v mřížce už používá slovník, což je správně. Tento slovník se ale při několika výpočtech znovu sestavuje a odměny zpracovávají celou historii. Připravovat jeden odvozený přehled pro změnu dat: index dnů, souhrn měsíce, stav týdne a množinu vyzvednutých klíčů. Nejprve změřit chování s několikaletou historií; není doložen současný výkonnostní problém.

**Aktuální datum.** Samotné `.now` nevynutí překreslení o půlnoci. Ověřit obnovu při návratu do popředí a přechod přes půlnoc při otevřeném kalendáři; aktualizovat společný zdroj dnešního data. Pro navigaci ukládat začátek měsíce, vybrané datum držet samostatně.

**Odměnová operace.** Kontrola nároku má být společná s operací vyzvednutí, nikoli pouze ve view. Opakované vyzvednutí stejného období musí být bez další odměny. Chyba ukládání nesmí zanechat falešné potvrzení ani umožnit náhodné opakované losování z rozpracovaného stavu. Při opravě se nesmí bez rozmyslu vracet všechny jiné neuložené změny sdíleného kontextu.

## Navržená podoba obrazovky

Pořadí obsahu:

1. **Týdenní truhla jako hlavní prvek:** prostorový model ze dřeva s kováním, datum od–do, sedm značek dnů a jasný postup. Při čekající starší odměně výslovně uvést její týden; aktuální postup nezaměnit za historický nárok.
2. **Měsíc a navigace:** šipky, „Říjen 2026“, malé tlačítko „Dnes“ při prohlížení jiného data.
3. **Měsíční mřížka:** světlá zelená s tmavým číslem a fajfkou, jemná oranžová pro dnešek a čitelné plánované dny. Měsíční historie je vizuálně klidnější než týdenní odměna.
4. **Vedlejší statistiky:** případně jediný stručný řádek pod mřížkou. Žádný další panel s obsahem dne; ten zůstává v Kronice.

### Otevírání truhly

Současné losování již rozlišuje běžnou odměnu (50 %), vzácnou (32 %) a zlatou (18 %). Tyto hodnoty jsou stav implementace, nikoli návrh nového vyvážení. Stávající overlay ukáže vzácnost a obsah hned při zobrazení; čekání a samotné otevření zatím nemá.

Doporučená sekvence po výslovném klepnutí na „Otevřít truhlu“, celkem přibližně 2,2 sekundy:

1. Okamžitá odezva, jemné zachvění zavřené truhly a haptika.
2. Krátká pauza, neutrální světlo ve spáře. Vzácnost ještě není zřejmá.
3. Otevření víka, odhalení skutečné vzácnosti: klidný záblesk pro běžnou, modré světlo pro vzácnou, teple zlaté pro zlatou.
4. Čitelný název vzácnosti, přesný obsah, odpovídající haptika a tlačítko „Pokračovat“. Zlatá může mít jeden krátký výraznější efekt.

Všechny tři výsledky mají být příjemné. Vyhnout se přeskakování falešných odměn, předstírání těsně uniklé zlaté výhry a dlouhým opakovaným čekáním. Otevření nemusí vyžadovat několik klepnutí. Reduce Motion zobrazí výsledek bez třesení a letu částic.

Výsledek se losuje pouze jednou a nejdřív bezpečně uloží s vyzvednutím; animace pouze odhaluje tento výsledek. Opakované klepnutí, zavření, návrat z pozadí ani restart nesmí umožnit další los za tentýž nárok. Pro obnovení přerušeného odhalení je vhodné uložit také obsah a stav zobrazení konkrétní odměny; samotné historické klíče dnes obsah neuchovávají.

Model truhly lze vytvořit ve stejném střídmém prostorovém stylu jako městské budovy. Efekt nemá potřebovat náročnou celoplošnou scénu. Zvuk je volitelný a respektuje nastavení; hlavní odezvu tvoří pohyb, světlo a haptika.

### Propojení s městem v Kronice

Jako samostatné pozdější zlepšení sdíleného detailu v Kronice lze použít náhledy z existujícího `BuildingPreview` místo velkého emoji a zobrazit všechny budovy dne. Není to hlavní obsah navrženého updatu kalendáře.

Náhledy načítat z cache; při prvním vytvoření nepouštět synchronní render opakovaně v těle view. Stávající cache rozlišuje typ budovy, nikoli její kosmetické varianty. Pro první update stačí reprezentativní model typu; přesnou variantu lze doplnit samostatně. Mřížka nepotřebuje živé 3D scény ani miniaturu na každém dni.

Příklad barev pro hotový den: text `#24452F`, pozadí `#BDD8B9`, vypočtený kontrast přibližně 6,96 : 1. Oranžovou nechat hlavně pro dnešek, výběr a akci. Přesnou kombinaci dneška, výběru a dokončení ověřit společně.

### Texty a stavy

| Situace | Příklad sdělení |
| --- | --- |
| Dnešek, zatím nic hotovo | „Dnes máš před sebou 3 pilíře.“ |
| Budoucí den s plánem | „Na zítřek máš naplánované 3 pilíře.“ |
| Budoucí den bez plánu | „Na tento den zatím nemáš plán.“ |
| Minulý den bez záznamu | „Pro tento den nemáš záznam.“ |
| Částečně splněný den | „2 ze 3 pilířů splněny.“ |
| Hotový den s budovou | „3 ze 3 pilířů. Ve městě přibyla pošta.“ |
| Týden probíhá | „Tento týden: 4 ze 7 dnů s alespoň jedním splněným pilířem.“ |
| Odměna připravena | „Truhla za 12.–18. října je připravená.“ + „Otevřít truhlu“ |
| Odměna vyzvednuta | „Truhla za tento týden je vyzvednutá.“ |

Prohlížení prázdného dne nevytváří nový `DayRecord`. Budoucí plán není nesplněný výsledek. Uzavřený nesplněný týden potřebuje věcné vysvětlení, protože pouhý údaj 6/7 může naznačovat, že je odměna ještě dosažitelná.

Historický obsah truhly nyní není samostatně uložen. Lze zobrazit „Vyzvednuto“, ale konkrétní tehdejší výhru nelze zpětně spolehlivě odvodit ze zůstatků. Takový přehled vyžaduje nový záznam odměny.

## Rozsah doporučeného prvního updatu

1. Výraznější karta týdne s truhlou a sedmi čitelnými značkami postupu.
2. Krátké odhalení odměny s rozlišením běžné, vzácné a zlaté; jeden uložený výsledek pro každé vyzvednutí.
3. Stabilní výpočet týdnů, bezpečné uložení odměny a jasný stav po vyzvednutí.
4. Jemný vizuální refresh mřížky, návrat na dnešek, stručnější statistiky, lepší kontrast a přístupnost.

Samostatně později: plánování na libovolné datum, přesouvání úkolů, roční přehled, podrobné analytiky a obousměrná synchronizace s Apple Kalendářem. Současný export přes EventKit je oddělená funkce; pro navržený refresh nejsou potřeba další oprávnění. Pravidlo truhly „alespoň jeden pilíř každý ze sedmi dnů“ bych při tomto updatu zachoval; jeho změna by zasahovala odměnový systém.

## Ověření při implementaci

- CS/SK/EN, změna jazyka uprostřed týdne a po vyzvednutí truhly; žádná další odměna za stejné období.
- Přechod měsíce/roku, únor v přestupném roce, změna letního času, alternativní systémový kalendář a změna časové zóny podle zvolené politiky.
- Prázdná historie, zítřejší plán, několik budov v jednom dni, již vyzvednutá truhla a několik starších čekajících odměn.
- Výslovně simulovaná chyba ukládání: bez úspěšné oslavy; po opakování/restartu konzistentní zůstatky a stav vyzvednutí.
- Migrační data s historickými klíči týdne a případnými duplicitními denními záznamy; zachování pilířů a vztahů budov.
- VoiceOver: buňky jako tlačítka, celé datum, stav a informace o výběru; popisky šipek; zaměření a zavření odměnového dialogu.
- Větší písmo, Reduce Motion a nejmenší podporovaný iPhone na výšku. Současný rozvrh dává při šířce 375 bodů buňku širokou přibližně 42 bodů; upravit mezery a aktivní plochy pro pohodlné ovládání.
- Návrat do popředí, otevřená obrazovka přes půlnoc, několikaletá historie a první načtení náhledů bez cache.

Drobná související oprava: rozsah týdne zobrazovat jednoznačně přes hranici měsíce i roku a opravit český/slovenský tvar počtu truhel pro 5 a více (`Strings.swift:359`).

## Implementace po odsouhlasení směru

- Nová karta týdenní odměny nad mřížkou: sedm značek, rozsah týdne, otevření připravené truhly a výslovný stav vyzvednutí.
- Vlastní prostorový model z matného dřeva s kováním, prkny, nýty, dutým vnitřkem, mincemi a malým travnatým podstavcem. Statická karta používá jeden cachovaný náhled; krátká živá scéna při otevření se po dokončení přestane průběžně vykreslovat.
- Otevření trvá přibližně 2,2 sekundy: zachvění, neutrální světlo, víko, vzácnost a obsah. Běžná/vzácná/zlatá používají rozdílné světlo a haptiku. Reduce Motion má okamžité odhalení.
- Odměna i vyzvednutí se uloží před zobrazením. Nové volitelné pole uchová čekající výsledek do potvrzení; po návratu se odhalí tentýž výsledek.
- Pravidla týdne jsou oddělena od jazyka. U starších účtů se začátek odvodí z poslední vyzvednuté truhly, jinak z dosavadního nastavení. Překrývající se historické týdny se znovu neodmění.
- Mřížka má světlejší zelenou, tmavá čísla, fajfku, sémantická tlačítka a větší aktivní plochy. Přibylo „Dnes“ při prohlížení jiného měsíce; popisky statistik a výška buněk reagují na velikost písma.
- Nevznikl další panel s detailem dne. Změny detailu Kroniky, plánování, kosmetické výhry a ostatní původní nálezy mimo tento rozsah zůstávají samostatnými návrhy.

### Provedené kontroly

- Debug a Release sestavení aplikace pro simulátor; samostatný náhled sestavený ze skutečných komponent.
- Přechod dočasné databáze se starým modelem na nový: zachovány zůstatky, klíče odměn, pilíře a vztah budovy k dni.
- `zsh Tests/check-weekly-chest.sh`: úplný/neúplný týden, budoucí dny, vyzvednutí, duplicitní den, změny času, hranice roku, jazyky, překryv historických týdnů; uložení, opakování, znovuotevření databáze, potvrzení a skutečně odmítnutý zápis do databáze otevřené pouze pro čtení.
- Vizuální kontrola samostatného náhledu na iPhonu 17 a dočasném iPhonu SE (375 bodů), včetně největšího systémového písma. Použita pouze paměťová testovací data.
- Ruční průchod s VoiceOver na fyzickém zařízení nebyl součástí této kontroly. Aplikace zůstává podle svého nastavení na výšku a ve světlém vzhledu.
