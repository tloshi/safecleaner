# SafeCleaner — roadmap i produktit dhe zhvillimit

**Versioni i planit:** 18 shtator 2026  
**Përdorimi fillestar:** personal, macOS 14+, pa abonim dhe pa backend  
**Drejtimi:** pastrim i përgjithshëm + developer cleanup + analizë sipas projektit

## 1. Synimi

Me kuptu ku shkon hapësira e Mac-ut, me identifiku skedarë që mund të hiqen dhe me pasë kontroll të qartë para çdo ndryshimi. Rezultati matet me saktësinë dhe hapësirën reale të rikuperuar, jo me numrin më të madh të mundshëm në ekran.

Shembujt e dhënë tregojnë dy nevoja:

- Rreth 58.2 GB të përzgjedhura në cache zhvillimi, kryesisht DerivedData dhe Gradle.
- Një skanim tjetër me 7.62 GB në app caches, browser caches, log-e dhe folderë të gjeneruar brenda projekteve.

Këto janë referenca funksionale. Nuk premtohet e njëjta sasi në çdo skanim dhe shifrat e dy aplikacioneve nuk mblidhen: mund të përfshijnë skedarë të njëjtë.

## 2. Parimet që nuk ndryshojnë

1. Skanimi vetëm lexon. Asnjë ndryshim para zgjedhjes dhe konfirmimit.
2. “I rigjenerueshëm” nuk do të thotë “pa pasoja”; shfaqet kostoja e rindërtimit ose rishkarkimit.
3. Asnjë përzgjedhje automatike për kategori që kërkojnë shqyrtim.
4. Trash është veprim tjetër nga fshirja përfundimtare. Versioni fillestar nuk zbraz Trash.
5. Skedarët e ndryshuar, të paqartë ose pa qasje anashkalohen me arsye të dukshme.
6. Nuk fshihen kode burimore, dokumente, foto, kredenciale, biseda ose modele lokale përmes rregullave të përgjithshme.
7. Nuk çaktivizohet SIP dhe nuk përdoret root për të fshehur mungesën e lejeve.
8. Kategoritë nuk mbivendosen në total; prindi dhe fëmija nuk numërohen dy herë.
9. Nuk përdoren premtime “RAM booster”, “100% safe” ose “e përshpejton çdo Mac”.

## 3. UI dhe rrjedhat

### Sistemi vizual

- Native SwiftUI, sfond grafit/blu i errët dhe ngjyrë mint për veprimin kryesor.
- Sidebar rreth 230 pt; përmbajtje me hapësira 24–32 pt; karta me qoshe 12–20 pt.
- SF Symbols dhe tipografi e sistemit; numra të mëdhenj vetëm për matje të rëndësishme.
- Ngjyrë për çdo kategori, por gjithmonë edhe tekst/ikonë për kuptim.
- Minimum i dritares 1000×700; përmbajtja lëviz me scroll kur nuk ka hapësirë.
- Fokus i dukshëm, keyboard navigation, etiketa VoiceOver dhe kontrolle me emra të kuptueshëm.
- UI fillestare në anglisht; lokalizim shqip/anglisht në fazën e përfundimit.

### Pamjet

| Pamja | Përmbajtja dhe veprimet |
|---|---|
| Overview | Disku, hapësira e lirë, koha e skanimit, kandidatët, kategoritë dhe problemet e qasjes |
| Review & clean | Search, filtra, madhësi, path, arsye, pasojë, checkbox, Show in Finder dhe përjashtim |
| Projects | Folderë të zgjedhur, lloji i projektit, aktiviteti dhe artefaktet e gjeneruara |
| Activity | Veprimi, ora, madhësia, origjina, destinacioni në Trash dhe gabimi nëse dështoi |
| Settings | Përjashtime, politika, privatësi dhe më vonë njoftime/lokalizim |

Rrjedha: **Skano → Shqyrto → Përzgjidh → Konfirmo → Kalo në Trash → Verifiko rezultatin.**

Gjendjet e UI: pa skanim; duke skanuar; skanim i anuluar; pa rezultate; rezultate të pjesshme; mungesë lejesh; konfirmim; pastrim në progres; sukses i pjesshëm; dështim. Asnjë gjendje nuk duhet të përdorë vlera shembull sikur të ishin matje reale.

## 4. Faza 0 — baza e projektit [e implementuar në 0.1]

- Projekt native `.xcodeproj` dhe Swift Package për build/test.
- Ndarje mes UI dhe motorit të skanimit/pastrimit.
- UI me pesë pamje, disk real dhe gjendje fillestare pa të dhëna artificiale.
- Preview vizual i veçantë, i shënuar dhe me pastrimin të çaktivizuar.
- README, roadmap, arkitekturë dhe skript build për aplikacion lokal.

**Kriter përfundimi:** app-i hapet, ndërtohet lokalisht dhe nuk skanon/fshin pa veprim të përdoruesit.

## 4a. Arkitektura dhe UI 0.2 [e implementuar]

- Services me protokolle për skanim, Trash, disk, desktop, validim dhe persistence.
- Repository që koordinon shërbimet përmes dependency injection.
- ViewModel me state machine dhe veprime të tipizuara; Presenter për formatim/agregim.
- Views pasive: vetëm ViewState + action closure, pa filesystem, singleton ose logjikë pastrimi.
- Design system i ndarë dhe animacione për navigim, numra, unazë/progres, rreshta dhe butona.
- Respektim i Reduce Motion; preview pa shërbime reale.
- Teste repository/ViewModel me fake dependencies dhe kontroll automatik i kufijve të shtresave.

## 5. Faza 1 — skanim dhe pastrim bazë [e implementuar, për validim praktik]

### Përfshirë

- Xcode DerivedData; SwiftPM; npm `_cacache`; Gradle `build-cache-1`; CocoaPods; Homebrew downloads; pip.
- Cache të palëve të treta në `~/Library/Caches`, me shqyrtim individual; cache Apple përjashtohen.
- Klasifikim i disa browser cache-ve vetëm brenda rrugëve të cache-it.
- `.log` të pandryshuara për më shumë se 30 ditë; pa zbrazje log-esh aktive.
- Projekte të zgjedhura: zbulim fillestar i `.next`, `.dart_tool` dhe `build` pranë manifestit. **Vetëm skanim.**
- Progres, anulim, gabime, filtra, përjashtime dhe kalim në Trash me konfirmim.
- Kontroll i identitetit/metadatave para veprimit; refuzim i symlinks, hard links, paketave dhe skedarëve specialë.
- Historik lokal; rikthim përmes Finder.

### Kufizime të deklaruara

- Rrugët e veglave janë parazgjedhje, ende pa zbulim konfigurimesh custom.
- Emri dhe vendndodhja e cache-it nuk janë provë absolute që përmbajtja s’ka vlerë.
- Aplikacionet me bundle ID të njohur kontrollohen për aktivitet; procese terminali dhe daemons kërkojnë kujdes manual.
- Validimi para lëvizjes nuk eliminon çdo garë me një proces tjetër që ndryshon filesystem-in.
- Skanimi i projekteve ka kufi thellësie dhe numri folderësh; kufijtë raportohen.
- Nuk ka pastrim të tërë sistemit, automatikë, root helper, dublikatë apo çinstalim në këtë version.

**Kriter përfundimi:** teste për refuzimet, dështimet dhe fixtures; testim UI pa pastrim real; pastaj provë manuale e përdoruesit me një cache të vogël dhe të shqyrtuar.

## 6. Faza 2 — developer cleaner i plotë [prioriteti i ardhshëm]

1. Nxirr rregullat në një katalog të versionuar: ID, rrugë, kushtet, përjashtimet, pasoja, pronari, mënyra e rikthimit dhe burimi i dokumentacionit.
2. Zbulo rrugët reale nga konfigurimi i veglave; mos supozo vetëm vendndodhjet default.
3. Gradle: ndaji build cache, dependency cache dhe distributions; mos e fshi krejt `.gradle`.
4. npm/yarn/pnpm: dallo store/cache nga konfigurimi, credentials dhe linked packages.
5. Pub/Flutter: dallo cache të paketave nga global packages; ruaj SDK-të dhe burimet.
6. Xcode: DerivedData sipas projektit; Archives, DeviceSupport dhe simulator runtimes si kategori të veçanta që kërkojnë shqyrtim. **[simulatorët: e implementuar në 0.5; DeviceSupport, dokumentacioni, device logs dhe arkivat: e implementuar në 0.5.2, shih më poshtë]**
7. Projektet: konfirmo framework-un, build directory custom, procese aktive, Git-tracked files dhe lokale të modifikuara. Vetëm pastaj aktivizo Trash për kategori të miratuara.
8. Shto adapterë zyrtarë për simulatorë dhe Docker kur fshirja direkte e folderëve s’është veprimi i duhur. **[simulatorët: e implementuar në 0.5; Docker: e planifikuar]**

**Simulatorët (0.5, 30 tetor 2026) — e implementuar:** skanimi ekzekuton dy komanda vetëm-lexim
(`xcrun simctl runtime list -j`, `xcrun simctl list devices -j`) përmes `ToolRunner`, i vetmi vend
ku aplikacioni nis një proces; ekzekutuesi validohet dhe argumenti i vetëm që vjen nga rezultati i
skanimit është një UUID i raportuar nga vetë simctl. Ofrohen vetëm: runtime të fshishëm, jo më të
rinjtë për platformë, të papërdorur 30 ditë dhe pa pajisje të ndezur ose të përdorur së fundmi;
pajisje të fikura, të disponueshme, me të dhëna, të papërdorura 30 ditë. Heqja bëhet me
`simctl runtime delete <id>` / `simctl delete <udid>` një nga një, pas një ri-inventari (nëse
artikulli u përdor pas skanimit, lihet në vend si “changed”). Kjo është heqje e përhershme, jo
Trash: UI-ja e thotë në rresht, në përmbledhjen e përzgjedhjes, në dialogun e konfirmimit dhe në
Activity. Simulator.app i hapur bllokon tërë grupin. Fixtures pozitive/negative në
`SimulatorTests.swift`. **Kufizime:** nuk heq runtime të padisponueshëm dhe nuk prek
`/Library/Developer/CoreSimulator/Caches`; nuk ka ende adapter për Docker, NDK ose AVD.

**Android SDK (0.5.1, 30 tetor 2026) — e implementuar:** versionet e NDK-së që asnjë projekt nën
folderët e zgjedhur nuk i emërton (`ndkVersion` në `build.gradle(.kts)`; versioni më i ri i
instaluar ruhet gjithmonë; një referencë e pazgjidhur si `flutter.ndkVersion` deklarohet në
arsye), system images që asnjë pajisje virtuale nuk i përdor (`image.sysdir.1` në `config.ini`
të çdo AVD) dhe folderi `snapshots` i çdo AVD-je të fikur (kërkohet mungesa e
`hardware-qemu.ini.lock`). Të treja shkojnë në Trash përmes rrugës ekzistuese me kontroll
snapshot-i: `sdkmanager --uninstall` vetë vetëm fshin folderin, kështu që Trash është i njëjti
veprim me rikthim. Kurrë `userdata-qemu.img*`, `sdcard.img`, `config.ini` ose vetë `.avd`.
Pronari: Android Studio. SDK jashtë home nuk skanohet dhe raportohet. **Kufizime:** nuk prek
`~/.gradle`, `~/.konan`, cache-t e Android Studio-s apo `platforms/`, `build-tools/`.

**Xcode stores (0.5.2, 30 tetor 2026) — e implementuar:** simbolet e pajisjeve
(`<platformë> DeviceSupport/<hyrje>`) për çdo version OS përveç më të riut për platformë (versioni
lexohet si numri i parë me pika në emrin e folderit; dy pajisje me të njëjtin version mbahen të
dyja), çdo indeks nën `DocumentationCache`, çdo folder pajisjeje nën `DeviceLogs` /
`iOS Device Logs` skedari më i ri i të cilit është 30 ditë i vjetër, dhe çdo `.xcarchive` 180 ditë
i vjetër sipas `CreationDate` në `Info.plist` (ose emrit të folderit me datë). Të gjitha shkojnë në
Trash përmes rrugës ekzistuese me pronar Xcode. Arkivat nuk rigjenerohen: arsyeja emërton
aplikacionin, versionin, build-in dhe bundle ID-në, pasoja thotë se simbolizimi i crash-eve të
atij build-i humbet; kurrë të parazgjedhura. Fixtures pozitive/negative në `XcodeStoresTests.swift`.
**Kufizime:** nuk prek `Products/`, `UserData/Previews`, `XCTestDevices`, `XCPGDevices`,
`DVTDownloads` apo `~/Library/Caches/com.apple.dt.Xcode`; versioni më i ri i simboleve mbahet edhe
kur pajisja është përditësuar që atëherë.

**Paketa e sigurisë (0.5.3, 30 tetor 2026) — e implementuar:** (1) kontroll i skedarëve të hapur
përmes libproc menjëherë para çdo lëvizjeje në Trash: nëse një proces i përdoruesit mban të hapur
një skedar, folderin e punës ose ekzekutuesin brenda artikullit, artikulli lihet në vend dhe
procesi emërtohet me pid; tabela lexohet një herë për grup (rifreskohet pas 10 s); proceset e
përdoruesve të tjerë nuk shihen pa root. (2) Lëvizje të verifikuara: një lëvizje numërohet vetëm
kur burimi nuk ekziston më; artikujt që përdoruesi nuk mund t'i shkruajë listohen si "Not
movable" në vend që të dështojnë më vonë. (3) Lista e vendeve që nuk ofrohen kurrë (`~/.ssh`,
`~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, keychains, Mail, Messages, Safari, cookies,
accounts, preferences, backup-et e iPhone-it, Photos, iCloud/CloudStorage), e zbatuar në skaner
dhe sërish në motorin e pastrimit. (4) Full Disk Access: aplikacioni mban mend se të dërgoi te
paneli dhe në nisjen tjetër thotë nëse leja është aktive. (5) Teste strukturore: `swift test`
provon nga pema e burimit se vetëm një vend lëviz në Trash, asgjë nuk fshin, vetëm një vend nis
procese, vetëm një flet me rrjetin dhe vetëm një lexon tabelën e proceseve. **Kufizime:**
skedarët e hartuar në memorie (dylib të ngarkuara) nuk numërohen si të hapur; nuk ka ende
njoftim periodik pa skanim, pamje "çfarë u rrit" apo etiketë "tipike / vendim i yti".

**Docker:** inventar fillimisht. Volumes dhe të dhëna të containers nuk trajtohen si cache; asnjë komandë e përgjithshme prune pa listë konkrete dhe konfirmim.

**Kriter përfundimi:** për çdo rregull, fixture pozitive/negative, dokumentacion aktual, kontroll aktiviteti dhe provë se projekti rindërtohet. Pa fshirje masive të folderëve me emër të zakonshëm.

## 7. Faza 3 — pastrimi i përgjithshëm [pas katalogut të rregullave]

- Browser adapters: Safari, Chrome, Firefox, Edge, Brave; ndarje strikte mes cache, cookies, sesioneve, historikut dhe fjalëkalimeve.
- AI tools: rregulla të verifikuara për cache të përkohshme; bisedat, workspace-t, indekset me vlerë dhe modelet lokale të përjashtuara si parazgjedhje.
- Log-e dhe crash reports: moshë/pronar, kufi mbajtjeje dhe asnjë truncation automatik të log-eve aktive.
- Instalues `.dmg`/`.pkg`, ZIP dhe Downloads si kandidatë për shqyrtim, jo junk automatik.
- Mbetje aplikacionesh me lidhje të verifikuar me bundle ID dhe grupet e përbashkëta; mos nxirr përfundim vetëm nga mungesa në `/Applications`.
- Trash me përmbajtje të dukshme dhe veprim të veçantë për fshirje përfundimtare, vetëm nëse vendosim ta shtojmë.

**Kriter përfundimi:** tests dhe fixtures për profile të shumta, aplikacione të hapura, shtigje custom dhe ruajtjen e sesioneve/të dhënave.

## 8. Faza 4 — disk explorer dhe dublikata

- Skanim i gjerë vetëm për analizë, me hartë të folderëve, skedarë të mëdhenj dhe filtra.
- Mbështetje për volumes të zgjedhura, pa dyfishim të APFS Data volume, mounts ose hard links.
- Dublikata: grupim sipas madhësisë → hash → verifikim final; zgjedhje e kopjes që ruhet nga përdoruesi.
- Photo libraries, packages, backup-e dhe cloud placeholders të përjashtuara si parazgjedhje.
- Mos shkarko skedarë nga cloud vetëm për t’i matur ose krahasuar.
- Dallo logical size, allocated size, purgeable space dhe vlerësimin e rikuperimit.

**Kriter përfundimi:** emra të njëjtë me përmbajtje tjetër nuk shpallen dublikatë; zero prekje e burimeve jashtë scope-it të miratuar; UI mbetet responsive në pemë të mëdha.

## 9. Faza 5 — rikthim dhe besueshmëri

- Plan pastrimi i ruajtur para ekzekutimit, me journal për çdo hap dhe gjendje pas crash-it.
- Rikthim në app nga Trash, trajtim i konfliktit të emrit, destinacion i munguar dhe Trash i zbrazur.
- Kontroll më i fortë për procese aktive dhe filesystem races; kufizim i privilegjeve dhe testim adversarial.
- Politika për batch të pjesshëm, anulim mes item-eve dhe histori të gjatë.
- Njoftime kur hapësira është e ulët dhe skanime periodike opt-in; pa fshirje në background si default.
- Matje e lirimit real pas veprimit dhe dallim nga shuma teorike e kandidatëve.

**Kriter përfundimi:** crash/restart nuk humb gjurmën e veprimeve; rikthimi nuk mbishkruan skedarë; dështimet tregohen saktë.

## 10. Faza 6 — përfundimi dhe shpërndarja

- Audit VoiceOver, keyboard-only, contrast, dritare më të vogla dhe tekst i gjatë.
- Lokalizim shqip/anglisht; formate GB/GiB dhe locale të qëndrueshme.
- Teste në versionin minimal të macOS dhe versionin aktual; Intel vetëm nëse kërkohet.
- Profile performance: kohë skanimi, CPU, RAM, I/O dhe anulim i shpejtë.
- DMG, versioning dhe release notes për përdorim personal.
- Developer ID signing/notarization dhe mekanizëm update vetëm nëse app-i do të shpërndahet te të tjerët.
- Shqyrtim i veçantë i sandbox/entitlements dhe kanalit të shpërndarjes; ndërtimi lokal aktual nuk është paketë e noterizuar.

## 11. Radha konkrete e punës pas 0.1

1. Hape UI-n dhe kontrollo skanimin real pa përzgjedhur asgjë.
2. Shqyrto “skipped locations” dhe kalibro rregullat për Mac-un tënd.
3. Shto një root projektesh dhe verifiko rezultatet scan-only kundrejt Finder-it.
4. Nxirr katalogun e rregullave në data të testueshme me provenance.
5. Plotëso Gradle dhe Xcode, sepse në shembullin tënd përbënin shumicën e hapësirës.
6. Aktivizo pastrimin e projekteve vetëm pas validimit sipas framework-ut.
7. Zgjero browser/AI rules; pastaj disk explorer, dublikata dhe rikthim në app.

## 12. Çka quhet sukses

- Zero fshirje jashtë listës së konfirmuar.
- Zero kalim automatik në permanent delete kur Trash dështon.
- Zero symlink traversal ose fshirje e kodit burimor nga rregulla të përgjithshme.
- Çdo rezultat ka path, arsye, pasojë dhe status të qartë.
- Skanimi mund të anulohet dhe gabimet nuk fshihen nga raporti.
- Nuk raportohet “hapësirë e liruar” vetëm sepse një skedar u zhvendos në Trash.
- Testet mbulojnë rrezikun real; provat nuk përdorin cache-t personale si fixtures.

Vlerësimi i kohës bëhet pas provës së 0.1 dhe inventarit të veglave të instaluara. Fazat kanë kritere dalëse, jo afate artificiale që nxisin pastrim të pasigurt.


## 13. Claude review — 0.4 (3 tetor 2026)

**E implementuar:** integrim opsional direkt me Anthropic Messages API; Haiku 4.5 si model ekonomik,
Sonnet 5.5 si alternativë; API key në Keychain; përmbledhje e grupuar deri në 16 grupe, pa emra,
rrugë, përmbajtje skedarësh ose gabime të papërpunuara. Një kërkesë vetëm pas veprimit të përdoruesit,
1200 tokenë dalje maksimum, request body deri në 12 KB, shfaqje e tokenëve realë, cache në memorie
për analizën e fundit identike, anulim dhe pa retries automatike. Rekomandimet vetëm filtrojnë
listën për shqyrtim; nuk përzgjedhin dhe nuk autorizojnë pastrim.

**Shtuar më 30 tetor 2026 (0.4.1):** modelet Haiku 5.5 (ekonomik, parazgjedhje) dhe Sonnet 5.5,
me `effort: low` dhe `max_tokens` 4000 sepse të dy modelet arsyetojnë para përgjigjes dhe ai
arsyetim llogaritet brenda kufirit; përgjigjet lexohen sipas llojit të bllokut, jo pozicionit.
Butoni **Test key** bën një kërkesë falas te Models API (pa të dhëna skanimi, pa tokenë) dhe
treguesi i statusit të çelësit (pa çelës / i ruajtur por i patestuar / duke u testuar / i pranuar /
dështoi) shfaqet në Settings dhe në Claude review. Gabimet e Anthropic shfaqen me llojin dhe
mesazhin e tyre (të pastruara dhe të kufizuara), dhe nën butonin e dërgimit shkruhet pse është i
çaktivizuar. Versioni i API-së: 2026-10-21.

**Kufizime / e planifikuar:** AI analizon vetëm kandidatët ekzistues; nuk shton disk explorer,
adapterë Android/Gradle/simulatorësh ose kontrolle të reja të ciklit të jetës së projekteve.
Nuk njeh përdorimin real/aktivitetin nga madhësia e grupit. Nuk ka cache persistente ose buxhet
mujor brenda app-it. Input tokens nuk maten saktë përpara kërkesës; byte cap kufizon payload-in.
Integrimi live me key të përdoruesit dhe faturimi real mbeten për provë nga përdoruesi.

## 14. Mbrojtja e projekteve, "Select all" dhe gabimet e pastrimit (e pa-publikuar, 3 tetor 2026)

**E implementuar:**

- **"Don't touch" për projekt.** Ekrani Projects liston projektet e gjetura nga skanimi i fundit;
  projekti i mbrojtur nuk skanohet, pastrimi e refuzon çdo artikull brenda tij, dhe mbetet në listë
  edhe pasi çaktivizohet ("Not scanned yet" deri në skanimin e ardhshëm).
- **Select all** me tri gjendje mbi listën e Review; vetëm rreshtat e shfaqur, kurrë "Scan only".
- **Pastrimi nuk dështon më në heshtje** (shkaku më i mundshëm: një aplikacion i hapur refuzonte
  tërë batch-in). Artikujt e një aplikacioni të hapur lihen në vend me emrin e aplikacionit; çdo
  dështim hap dialog sipas shkakut. "Open Full Disk Access" ofrohet vetëm për EPERM, jo për EACCES
  (pronar tjetër / sudo), ku Full Disk Access s'ndihmon.
- **Statusi i punës në çdo ekran** dhe API key mund të ruhet gjatë skanimit (më parë fusha ishte e
  bllokuar pa shpjegim për gjithë kohëzgjatjen e skanimit).

- **Ekrani i rezultatit të pastrimit:** çdo aplikacion i hapur shfaqet një herë me numrin e
  artikujve dhe madhësinë, me buton **Quit** (mbyllje normale, kurrë force-quit; rezultati
  vëzhgohet: Closed / Still open) dhe "Select N remaining in Review" për artikujt e aplikacioneve të
  mbyllura — prapë kalojnë nëpër Review dhe konfirmim.

- **Progresi i pastrimit:** konfirmimi, progresi dhe rezultati janë një sheet i vetëm; shirit sipas
  madhësisë, "N of M items", artikulli që po rikontrollohet tani dhe "Stop after this item" (ndalet
  vetëm mes artikujve). Rezultati shfaqet edhe kur gjithçka lëvizi.

**E pa-verifikuar:** nëse build-i me hardened runtime mund t'i mbyllë aplikacionet e tjera pa
entitlement-in `com.apple.security.automation.apple-events`.

**Kufizim / e planifikuar:** kontrolli i aplikacionit të hapur mbulon vetëm artikujt me
`ownerBundleID`. Build output-i i projekteve dhe `Caches/Google` (Chrome + Android Studio) s'kanë
pronar, prandaj lëvizin edhe kur IDE/browser-i është i hapur. Duhet hartë pronarësh.

**E pa-verifikuar:** asnjë pastrim real; refuzimet reale EPERM/EACCES nuk u riprodhuan.
