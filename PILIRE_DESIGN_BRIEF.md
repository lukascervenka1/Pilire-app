# Pilíře — design brief pro prezentační web

> Tenhle dokument dej Claudeovi jako podklad, když po něm chceš vytvořit
> landing page. Obsahuje **co Pilíře jsou**, **co se v nich děje** a hlavně
> **přesnou vizuální identitu vytaženou přímo z appky** (barvy, styl, izometrické
> město, ptáci, mraky), aby web vypadal jako pokračování hry, ne jako cizí šablona.

---

## 1. Co je Pilíře (elevator pitch)

**Pilíře** jsou jemná, gamifikovaná iOS appka na budování návyků a zvládání
všedního dne. Není to další produktivní to-do list — je to **hra o životě**.
Každý den si dáš pár malých úkolů („pilíře dne"), a když je splníš, získáváš
**materiál**, ze kterého si na plovoucím ostrově stavíš vlastní **3D low-poly
městečko**.

**Pro koho:** lidé, co chtějí budovat návyky bez tlaku a výčitek. Přátelské k ADHD.
Nikdy netrestá, nekřičí, netlačí. Je to **pomocník, ne dozorce**.

**Jedna věta:** *Splň své pilíře dne a nech své městečko růst.*

---

## 2. Co se v aplikaci děje (funkce)

Landing page má vyprávět tenhle příběh — od malého úkolu k rostoucímu městu.

- **Pilíře dne** — pár úkolů na dnešek. Splnění = okamžitá odměna (dřevo).
  Zadávání je hravé, ne strohé. Den se na konci „uzavře" podržením tlačítka.
- **Materiálová ekonomika** — dřevo, cihly, ocel. Za splněné pilíře stavíš.
- **3D městečko na plovoucím ostrově** — izometrická low-poly mapa, kterou si
  buduješ: domky, radnice, kostel, hospoda se zahrádkou, farma, věž, obchody…
- **Momentum** — jemná obdoba streaku. Roste, když jsi aktivní, pomalu klesá,
  **nikdy netrestá**. Násobí odměny.
- **Návyky** — opakující se úkoly s časem a nenásilnými připomínkami (styl
  Duolingo: jedna tichá zpráva, žádné výčitky). Vše jde vypnout.
- **Kalendář** — přehled měsíce ve stylu Duolinga: dny podbarvené podle úspěchu,
  **týdenní truhla** s náhodnou odměnou, když splníš celý týden.
- **Kronika** — historie tvých dnů a toho, co jsi za ně postavil.
- **Zoo** — za mince si pořídíš zvířata (pes, husky, liška, vlk, srnec, kráva,
  kůň, alpaka), která se **procházejí po mapě**, obcházejí domy, večer chodí spát
  (kromě nočních), a hráč je může dotykem probudit.
- **Živá mapa** — den/noc podle reálného času, mraky vrhající stín, přelétající
  **ptáci**, motýli ve dne, světlušky v noci, počasí (slunce/déšť/mlha), kouř
  z komínů, tekoucí fontána.

**Tón hlasu (copy):** česky, přátelsky, lidsky. Žádná strojová spisovnost, žádné
pomlčky uprostřed vět, žádné výčitky. Klid, teplo, povzbuzení. Např. *„Pilíř dne
máš hotový, dobrá práce."*

---

## 3. Vizuální identita (přesně z appky)

Aplikace je **zamčená ve světlém, teplém „krémovém" režimu** s oranžovým akcentem.
Estetika: **měkké low-poly, oblé tvary, plochý (lambert) shading, Monument Valley
vibe** — klidné, útulné, hravé, ne dětinské.

### 3.1 Barvy (hex vytažené z kódu)

**Krémová základna (UI pozadí, karty):**

| Role | Hex | Poznámka |
|---|---|---|
| Cream top (pozadí nahoře) | `#F7F2E6` | pergamen |
| Cream bottom (pozadí dole) | `#E8EDDB` | jemně do zelena |
| Panel / karta | `#F7F2E3` | povrch panelů |
| Warm label (sekundární text) | `#736654` | teplá šedohnědá |

**Akcent (oranžový gradient — CTA, aktivní prvky, „hammer" tlačítko):**

| Role | Hex |
|---|---|
| Accent top | `#FAA338` |
| Accent bottom | `#ED8529` |

> Gradient shora dolů `#FAA338 → #ED8529`. Tohle je hlavní značková barva.

**Doplňkové:**

| Role | Hex |
|---|---|
| „Splněno" zelená (Duolingo styl) | `#6BB870` |
| Dřevo | `#946B40` |
| Cihly | `#CC6B52` |
| Ocel | `#738599` |

**Nebe podle denní doby (gradienty pozadí mapy — skvělé na hero sekci):**

| Fáze | Gradient (shora dolů) |
|---|---|
| Den (default) | `#A8D4ED → #D1E8E6 → #EDF2E0` |
| Svítání | `#C7B8DB → #F5CCB8 → #FAE6CC` |
| Soumrak | `#756BA8 → #E69E7A → #F7D19E` |
| Noc | `#1A2142 → #293861 → #3D5270` |
| Mlha | `#CCD6D6 → #DEE6E0` |

**Ostrov / terén:**

| Role | Hex |
|---|---|
| Tráva (základ) | `#8CB86B` |
| Tráva světlá / tmavá skvrna | `#9EC776` / `#7AA861` |
| Hlína (boky ostrova) | `#856B57` |

**Budovy (akcenty střech/fasád):**

| Skupina | Hex |
|---|---|
| Obytné (chalupa, domek, stodola, farma, stáje) | `#C77D57` (terakota) |
| Občanské (hospoda, kovárna, tržiště, obchody, pošta) | `#5C7A99` (břidlicová modrá) |

**Zvířata (barvy srsti, pro ilustrace):**
pes `#B8854D` · husky `#8C99A8` · liška `#D97A3D` · vlk `#80858F` ·
srnec `#A8784D` · kráva `#4D4D52` · kůň `#755238` · alpaka `#D6C2A3`.

### 3.2 Tvary a rádiusy

- Karty: **radius 20 px**. Řádky/menší prvky: **radius 12 px**.
- Žádné ostré hrany, ale ani přerádiusované bubliny (max ~20 px na kartách).
- Low-poly geometrie: **zkosené kvádry**, **jehlany a kužely** (střechy),
  **kapsle** (těla zvířat), koule (koruny stromů). Vždy jemné zkosení hran.

### 3.3 Typografie

- Aplikace používá **systémový rounded font (SF Pro Rounded)** — oblý, přátelský,
  teplý. Web má držet stejný charakter: **oblý, měkký, ne korporátní**.
- Doporučení pro web (oblé, hravé, ne z „AI defaultů"): pro display třeba
  **Fredoka** nebo **Baloo 2**, pro delší text čitelný humanistický bezpatkový
  font. **Nepoužívat** Inter, Roboto, Arial, Playfair, ani ostré geometrické grotesky.
- Nadpisy tučné, kulaté, klidně velké. Text vzdušný, hodně bílého (krémového) místa.

### 3.4 Pohyb / animace

- Jemné, klidné, nikdy hektické. 150–300 ms, jen `transform`/`opacity`.
- Vhodné mikrointerakce: pomalu **plující mraky**, tiše **přelétající ptáci**,
  lehké „dýchání" akcentního tlačítka, staggered odhalování sekcí při scrollu.
- Respektovat `prefers-reduced-motion`.

---

## 4. Hero sekce — izometrické město (klíčový vizuál)

Uživatel chce v hero části **mapu z Pilířů** s budovami, ptáky a mrakem. Cíl je
**rekreovat izometrické low-poly městečko na plovoucím ostrově** (SVG nebo CSS,
klidně lehký `<canvas>`/Three.js, ale statické SVG bohatě stačí).

**Kompozice:**

1. **Nebe:** vertikální gradient denní oblohy `#A8D4ED → #D1E8E6 → #EDF2E0`.
   Vpravo nahoře **teplé slunce** (měkký kruh, lehká záře).
2. **Plovoucí ostrov:** zaoblený izometrický „kvádr" trávy `#8CB86B` s tmavší
   spodní hlínou `#856B57`, plovoucí ve vzduchu (pod ním nic, klidně pár
   odlomených kousků země). Kamera shora pod ~35°, natočení 45° (klasická 2.5D).
3. **Budovy (low-poly domky):** kvádr + **jehlanová/sedlová střecha**. Střechy
   obytných domů terakota `#C77D57`, veřejných budov břidlicová modrá `#5C7A99`.
   Zdi krémové/béžové. Malá okna, dveře. Rozmísti nepravidelně, 5–8 budov.
4. **Cesty:** světle šedé **zapuštěné dlážděné cestičky**, které se klikatí mezi
   domy (mírně organické, ne rovné mřížky).
5. **Zeleň:** stromy = **kužel** (jehličnan) nebo **koule na kmínku** (listnáč),
   pár keřů. Malý **rybníček** (modrá placka) s rákosím.
6. **Ptáci:** 2–3 jednoduché ptačí siluety (tmavé „V" / kužel s křídly) plující
   nad ostrovem, jemná animace pohybu do strany.
7. **Mraky:** 1–2 měkké bílé shluky (překrývající se zaoblené tvary) pomalu
   plující, vrhající jemný stín na trávu.
8. **Ambient:** volitelně pár motýlů/teček světla, jemný kouř z komína.

**Nálada:** klidné dopoledne na útulném ostrově. Teplé, měkké stíny, hodně
prostoru. Ne přeplácané.

> Tip: nejjednodušší věrná varianta je **ploché izometrické SVG** ve stejné
> paletě. Každý dům = pár polygonů (přední stěna, boční stěna, dvě plochy střechy)
> s mírně odlišnými odstíny pro nasvícení (světlejší nahoře/zprava, tmavší vlevo).

---

## 5. Doporučená struktura landing page

1. **Hero** — velký nadpis + podnadpis + izometrická mapa (viz výše) + CTA
   („Stáhnout na App Store" / „Chci to zkusit"). Akcent oranžový gradient.
2. **Jak to funguje** — 3 kroky: *Splň pilíře dne → Získej materiál → Postav
   městečko.* Každý s malým low-poly obrázkem.
3. **Funkce** — bento/karty: živá mapa, momentum, návyky s jemnými připomínkami,
   kalendář s týdenní truhlou, kronika, zoo se zvířaty.
4. **Filozofie** — sekce o jemnosti: „Nikdy netrestá. Žádné výčitky. Pomocník pro
   každý den, přátelský k ADHD."
5. **Zoo / živá mapa** — ukázka zvířat procházejících se po ostrově, den/noc.
6. **CTA / patička** — opakované CTA, jméno appky, krémové pozadí.

---

## 6. Skutečné assety „přímo z Pilířů"

Web bude věrný, když použije **stejnou paletu a stejný low-poly jazyk** (výše).
Pokud chceš do stránky opravdové screenshoty přímo z appky:

- Udělej na iPhonu **screenshot mapy** (záložka Město) v denním světle a přilož
  ho — dá se použít jako hero obrázek nebo předloha pro překreslení do SVG.
- Ikona appky (flat Monument Valley styl) je v repu:
  `Pilire/Assets.xcassets/AppIcon.appiconset/` (light/dark/tinted PNG) — dá se
  použít jako favicon a logo.
- 3D modely zvířat (glTF) jsou v `Pilire/Animals3D/` — z nich se dají vyrenderovat
  statické obrázky, případně vložit lehký 3D náhled.

---

## 7. Čemu se vyhnout

- Generickým SaaS šablonám, fialovým gradientům na bílé, ostrým korporátním
  fontům (Inter/Roboto), stock fotkám lidí u počítače.
- Studenému, „produktivnímu" tónu. Pilíře jsou **teplé, klidné, hravé**.
- Přeplácané hero grafice. Míň je víc — čistý ostrov, pár domů, pár ptáků, mrak.
- Tvrzením o trestání/tlaku. Naopak zdůrazni jemnost a přívětivost.

---

*Palety a hodnoty v tomto dokumentu jsou vytažené přímo ze zdrojového kódu
(`Theme.swift`, `TownScene.swift`, `ContentView.swift`, `Animals.swift`), takže
web bude barevně sedět 1:1 s hrou.*
