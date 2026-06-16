# Handoff — Football Live (org.kde.fotballtray)

**Sist oppdatert:** 2026-06-15 (slutt av sesjon 3)

---

## 🟢 START HER (neste sesjon) — nåværende tilstand + åpne punkter

Appen kjører, alt er på ENGELSK, journal er ren. Bakgrunnstjenester aktive:
`fotball-fetcher`, `fotball-server`, **`football-commentator`** (LLM-kommentator PÅ, `gemma4:12b`).
`football-sofascore` er `disabled` (Cloudflare-blokkert, erstattet).

**Bygget i sesjon 3 (detaljer i de mange "Sesjon 3 —"-blokkene lenger ned):**
- Live-score-reaktivitet, ekte formasjonsbane + reserver, valgbare tray-stilgrupper (lagnavn vs resultat/tid),
  lyd-enhet-fiks (alt via `paplay --device`), gode lyder (jubel/fløyter/Tippekampen-bong), event-lyd opt-in.
- **HELE appen på engelsk** (UI + fetcher-strenger + metadata).
- **LLM-kommentator** (Peter-Drury-stil prompt, gemma4:12b) → `commentary.json`-overlay som fetcher fletter
  inn i `match.summary`. **TTS-stemme** (Kokoro `en_GB` bm_george, fallback piper) leser opp; eruptiv på mål
  (pitch +10 %, tempo naturlig), rolig run-of-play. Output-modus (Voice+text/Text/Voice). Periodisk
  «run of play»-kommentar etter 15 min stillhet. Settings-seksjon «Live commentary (AI)» med install/Test/
  modell-knapper (via `fotball-llm-ctl.sh` + plasma5support executable-engine). Test-knappen snakker.
- **Gruppe-tabeller fra ESPNs OFFISIELLE standings** (`fetch_espn_standings`) — ekte resultater + tiebreakere
  (også egen `rank_group()` med head-to-head). **Live knockout-projeksjon** (`project_knockout`, offisiell
  R32-mal + bipartitt matching) med bracket-grafikk + toggle i KnockoutView.
- **Bilde/tekst-skarphet på 4K/fraksjonell skalering**: pixel-ratio-bevisst `_tex`, `OpacityMask` i stedet
  for `MultiEffect`, `Text.NativeRendering` på OutlinedLabel. **Hvit ytre halo fjernet fra OutlinedLabel**
  (bruker ville bare ha den tynne sorte konturen — `style: Text.Outline` på front-Heading).

**⚠️ ÅPNE PUNKTER / NESTE STEG:**
1. **VERIFISER bilde-skarphet** etter OpacityMask-byttet (bruker rapporterte fortsatt soft før det). HVIS
   fortsatt soft → siste utvei: dropp sirkel-masken (direkte Image = garantert skarpt, avrundet firkant).
   Vurder også `Text.NativeRendering` GLOBALT (resten av teksten bruker default QtRendering ennå).
2. **LLM «ask about the match»-chat (FORESLÅTT, ikke bygget):** skjult tekstinput som vises ved tastetrykk/
   knapp; LLM svarer GRUNNET i dataene vi alt har (events/stats/standings/lineups) — lokalt, robust. Web-søk
   som valgfritt lag SENERE (lokal LLM kan IKKE browse selv). Bruker positiv; venter på «kjør».
3. **Fintunings-script** (langsiktig): `commentary_archive.jsonl` → LoRA. Ikke laget.
4. **Bracket-projeksjon:** kun R32 i dag; R16+ kan legges til (trenger R16-seeding-mal).

**⚠️ RESTART (Claude KAN selv):** `find ~/.cache -path '*qmlcache/*.qmlc' -delete; kquitapp6 plasmashell;
( setsid kstart plasmashell >/dev/null 2>&1 & )` — quit-først tillates av hooken. Verifiser fersk PID.
Hvis `kquitapp6` henger (DBus-«No such object path /MainApplication») → prosessen er wedget; `kill -9 <pid>`
+ relaunch. ALDRI `kpackagetool6 -u` (sletter kilden). Etter `config/main.xml`-endring: restart FØR innstillinger åpnes.

---

## ✅ SESJON 3 — LØST (2026-06-15)

Plasmashell ble restartet (quit-først, fersk PID) og journal er ren for fotballtray
(ingen QML-feil/"unavailable"/TypeError). Alle endringer er lastet. **Gjenstår BARE
visuell verifisering mot en EKTE live-kamp** (det var 0 live ved sesjonsslutt).

1. **Live-score-reaktivitet UNDER kamp (punkt 3) — FIKSET.** Rotårsak: `FullRepresentation`
   sin `Repeater { model: displayMatches.length }` (int) fyrer aldri når kun scoren endres
   (samme antall kamper). La til `root.dataVersion` (int, økes i `loadAllData` på hver vellykket
   matches-last) og lot score-bindingene lese den: `matchObj: { root.dataVersion; return
   fullRep.displayMatches[index]; }` + `displayMatches`-binding + CompactRepresentation `matches`.
   Tvinger re-evaluering hver 10–30 s uten å ødelegge utvidet-tilstand (int-modellen beholder delegater).
   ⚠️ Verifiser mot live-kamp at scoren faktisk ticker (mål ~hvert 15.–30. min).
2. **Taktikk = ekte FORMASJONSBANE (punkt 4) — IMPLEMENTERT.** `MatchDetailCard.qml` LINEUP-seksjon
   skrevet helt om. Nye JS-helpere: `formationRows("4-3-3"→[4,3,3])`, `pitchNodesFor(starters,
   formation,isHome)`, `pitchNodes()`. Spillerne plasseres på banen via formasjonsstreng + starter-
   rekkefølge (VERIFISERT live: FotMob gir startere i formasjonsrekkefølge, keeper først; rader =
   `[1].concat(formationRows)`; 11 = startere for både 4-3-3 og 3-4-2-1). Hjemmelag nederste halvdel,
   bortelag øverste speilet. Hver node = draktnummer-disk + navn + rating-badge UNDER (gjenbruker
   `ratingColor()`). La til straffefelt + banemarkeringer. ⚠️ Verifiser visuelt (åpne kamp → Taktikk).
3. **Tray-styling = TO uavhengige stilgrupper (punkt 5, utvidet på brukerønske).** Bruker ville styre
   **lagnavn** og **resultat+tid** hver for seg — egen farge OG egen kontur. Implementert:
   - **Gruppe 1 «Resultat/tid»:** `liveColor` + `liveColorOutline` (eksisterende nøkler). Gjelder score,
     kampminutt/tid, live-dot. Default grønn `#2ecc71`, kontur av. (Bruker har oransje `243,156,18` + kontur på.)
   - **Gruppe 2 «Lagnavn»:** NYE nøkler `teamColor` (Color, default `#ffffff`) + `teamColorOutline`
     (Bool, default `true`) i `main.xml`. Gjelder home/away-forkortelsene.
   - `main.qml`: nye `property color teamColor` + `property bool teamOutline`.
   - `CompactRepresentation`: abbrev → `teamColor`/`teamOutline`; score+tid → `liveColor`/`liveOutline`
     (gjelder nå ALLTID, ikke gated på `status==="in"` — løste pre-match-drukningen).
   - `configGeneral.qml`: to seksjoner (ColorButton + presets + Tilbakestill + kontur-checkbox hver),
     og forhåndsvisningen viser nå BÅDE lagnavn (gruppe 2) og «2 – 1 67′» (gruppe 1) med hver sin stil.
   ⚠️ `teamColor`/`teamColorOutline` skrives ikke til appletsrc før bruker endrer dem (KConfig lagrer kun
   ikke-default), men defaultene (hvit + kontur) gjelder i runtime. **main.xml endret → restart FØR innstillinger åpnes** (gjort).
4. **Bytte-hendelser viser navn (punkt 6) — FIKSET + VERIFISERT.** `_fotmob_parse_events`: for
   `substitution` leses `swap`-feltet (VERIFISERT live mot lineup: `swap[0]=inn, swap[1]=ut`).
   Tekst = `"{inn} for {ut}"`. **262/262 bytter har nå navn** i live-data. Tømte `details_cache.json`
   så ferdige kamper re-parses.
5. **Krasj-bug i `cleanedEvents()` (punkt 7a) — FIKSET.** `(e.clock||"").trim()` →
   `String(e.clock||"").trim()` (+ samme på `e.text`). Tallverdier fra FotMob krasjet popup-rendering.
6. **Lyd: `whistle.wav` var FAKE (oppdaget).** `whistle.wav` var byte-identisk med `cheer.wav`
   (samme md5) — "fløyta" var altså en folkemengde. Syntetiserte en EKTE dommerfløyte med NumPy
   (3.5 kHz + harmoniske + 18 Hz pea-warble, 0.45 s, 98 % energi >2 kHz) → ny `whistle.wav` (CC0).
   La til `whistle_triple.wav` (full tid) + "Trippelfløyte" som valg i rødt-kort-dropdownen +
   `sounds/CREDITS.md`.
7. **`playEventSounds` default `true`→`false`** (calm-tech-anbefaling fra sesjon 2) i `main.xml`.

**Sesjon 3 — lyd-overhaul + FULL ENGELSK-OVERSETTELSE (bruker bestilte):**
- **Hele appen er nå på ENGELSK** (bruker: "alt i denne appen skal være på engelsk"). Oversatt alle
  brukersynlige strenger i ALLE QML-filer + configGeneral + fetcher-genererte event/summary-strenger +
  metadata.json (Name: "Football Live", Description engelsk). Spillernavn beholder diakritiske tegn (riktig).
  ⚠️ KOBLING: fetcher `generate_match_summary` lager nå `"Goals: ..."`; `MatchDetailCard.summaryNarrative/
  summaryGoalList` splitter på `"Goals:"` (var "Mål:"). Hold disse i sync ved framtidige endringer.
  ⚠️ `getStatsList` sentinel er nå `"No data yet"` (sjekkes i QML på 3 steder). `eventKind()`-regexene
  beholder norske alternativer (harmløst; `type`-feltet er primært og er engelsk-normalisert).
- **NYE LYDER (bruker: gamle var bedre).** Fant de gamle gode lydene i `~/Documents/Codex/.../matchpulse/
  applet/sportsbar@robert/sounds/`. Behandlet (trim/fade/loudnorm) → `contents/sounds/`:
  `cheer.wav` (folkejubel), `whistle.wav` (kort må/event-fløyte), `whistle_match.wav` (lang avspark/full
  tid-fløyte), `bong.wav` (den klassiske Tippekampen-dooong), `pling.wav` (myk pling). Slettet synth
  `whistle_triple.wav`. Dropdownene har engelske navn: Crowd cheer / Goal whistle / Referee whistle /
  Tippekampen bong / Soft ping. `main.xml`-defaults: soundOther→pling.wav, soundRedCard→whistle_match.wav.
  Test-knappen ruter nå til valgt lydenhet. `sounds/CREDITS.md` oppdatert.

**Sesjon 3 — runde 2 skarphet (bruker: fortsatt soft + tekst også uskarp):**
- **Bilder:** byttet `MultiEffect`-maskering → `OpacityMask` (Qt5Compat.GraphicalEffects) i FlagImage +
  TeamBadge (skarpere på fraksjonell skalering; ren alpha-multiplikasjon, ingen myk alpha-ramp). Beholdt
  pixel-ratio-bevisst `_tex`. Qt5Compat.GraphicalEffects bekreftet installert.
- **Tekst:** `OutlinedLabel` (tray CIV/ECU/score/tid) bruker nå `renderType: Text.NativeRendering` →
  skarpe glyfer snappet til piksler på fraksjonell skalering.
- **Audit for flere HiDPI-feil:** ingen rå `Image` uten sourceSize (treffene var FlagImage), ingen
  Canvas/ShaderEffect, ingen løse `layer.enabled`. Resterende tekst (grupper/kort) bruker default QtRendering
  — kan få NativeRendering globalt hvis fortsatt soft.
- ⚠️ Hvis bilder FORTSATT soft etter OpacityMask: siste utvei = droppe sirkel-masken (direkte Image-render
  = garantert skarpt, men firkant/avrundet i stedet for sirkel).

**Sesjon 3 — BILDE-SKARPHET på 4K/fraksjonell skalering (bruker: mange uskarpe bilder):**
- **Rotårsak:** skjermen er **3840×2160 (4K)** med **Xft.dpi 139 ≈ 1.45× fraksjonell skalering**. Kildebildene
  er fine (flagg 640px, logoer 500px), men `FlagImage`/`TeamBadge` rasteriserte MultiEffect-lagene i en
  FAST logisk størrelse (`size*3`) som ikke skalerte med pixel-ratio → resampling på 4K = uskarpt.
- **Fiks:** `_tex` er nå pixel-ratio-bevisst: `size * max(2, Screen.devicePixelRatio) * 2` (oversampling).
  Strammere maske-kant (`maskSpreadAtMin 1.0→0.25`, mindre fjæring). `TournamentHeader`-emblemet fikk
  pixel-ratio-bevisst `sourceSize` (begge dimensjoner) + `mipmap`. Tømte plasmashell imagecache.
- ⚠️ Hvis FORTSATT uskarpt: neste steg er å erstatte MultiEffect-maskeringen (kjent for å mykne på
  fraksjonell skalering) med en skarpere klippe-metode, eller droppe sirkel-masken.

**Sesjon 3 — gruppe-tabeller fra ESPNs OFFISIELLE standings + pitch +10%:**
- **Gruppene var ikke i synk (Mexico 0 kamper).** Rotårsak: fetcher beregnet tabeller fra ESPN-scoreboardets
  smale standard-vindu (5 kamper) + lagnavn-mismatch (Czechia vs Czech Republic). Fiks: ny
  `fetch_espn_standings(tournament_id)` henter `/apis/v2/sports/soccer/<id>/standings` (12 grupper, ekte
  resultater + ESPNs egne tiebreakere + rank + abbrev=landkode + logoer). `build_tournament_data` bruker
  den (fallback til `compute_group_tables`). `all_group_teams` bygges nå fra faktiske standings-lag.
  Verifisert: Mexico P1 3pts (2-0), USA/Germany/Scotland 3pts osv. Gruppe G-L 0 kamper = ekte (spilles senere).
- **Stemme-pitch +10%** (mellom de to forrige; helium borte siden tempo kompenseres).
- **Stemmen hørtes ut som helium (for rask).** `fotball-tts.sh`: pitch-skiftet kompenseres nå med `atempo`
  (=1/pitch) så TEMPOET holdes naturlig — ingen chipmunk. Mål = beskjeden +6 % pitch + 5 dB + kokoro speed
  1.04 (nesten normal); run-of-play rolig.
- **Knockout-projeksjon var rotete/stygg → ekte bracket-grafikk:** `KnockoutView.qml` projeksjonsvisning
  omskrevet fra brede rader til `GridLayout` (2 kolonner) med kompakte stablede kort: «Match N» +
  hjemmelag-rad (flagg + navn + posisjonsmerke) + hårstrek + bortelag-rad, gull aksent-stripe. Mye ryddigere.

**Sesjon 3 — sterkere mål-stemme + Test-snakker + WC-tiebreakere:**
- **Mål-stemmen var for lik run-of-play (bruker: begge dull).** `fotball-tts.sh` har nå STOR kontrast:
  mål/kort = kokoro speed 1.15 + ffmpeg pitch+tempo ×1.13 + volum +6 dB (soar à la Peter Drury — video
  XCEaTjH7BtA); run-of-play = speed 0.92 + pitch ×0.96 − 1 dB. (Kokoro bm_george er fortsatt målt;
  Bark/Chatterbox = tyngre opsjon for ekte skrik om ønsket.)
- **Test-knappen GENERERER + SNAKKER nå:** `fotball-llm-ctl.sh test [device]` lager en Drury-mållinje,
  lagrer som `__test__` (type goal) i commentary.json, og spiller via `fotball-tts.sh __test__ <device>`.
  configGeneral sender `deviceCombo.currentValue`.
- **WC-tiebreakere (innbyrdes oppgjør):** `compute_group_tables` bruker nå `rank_group()`: 1) poeng,
  2) målforskjell, 3) scorede mål, deretter HEAD-TO-HEAD mini-tabell (poeng→gd→mål) blant likt plasserte
  lag (`_h2h_stats`), så total-gf som siste. Enhetstestet. 3.-plass-rangering for knockout = poeng/gd/gf (FIFA).
- Genererte + spilte en live-kommentar for pågående kamp på Creative-enheten (bruker ba om det).

**Sesjon 3 — lyd-enhet-fiks + 15-min-kommentar + eruptiv mål-stemme + KNOCKOUT-PROJEKSJON:**
- **Lyd spilte på feil enhet:** QtMultimedia `MediaPlayer.device`-bytte virker IKKE på PipeWire. Ny
  `~/.local/bin/fotball-play.sh <file> [device]` ruter via `paplay --device`. `main.qml.playSoundFile()` +
  configGeneral Test-knapp bruker den nå. Lagret config-verdi ER et gyldig pulse-sink-navn (verifisert).
- **15-min-regel:** `GENERAL_INTERVAL 420→900`, og `_last_general[mid]` nullstilles ved HVER ny hendelse →
  run-of-play-kommentar kun etter 15 min UTEN hendelser.
- **Eruptiv mål-stemme:** `fotball-tts.sh` etterbehandler mål/kort med ffmpeg `asetrate*1.07 + volume 3dB`
  (høyere pitch+tempo+volum = spent kommentator); run-of-play forblir rolig.
- **Live knockout-projeksjon (#22):** fetcher `project_knockout(tables)` bygger R32 fra dagens stillinger
  (topp 2 + 8 beste 3.-plasser) via offisiell 2026-mal `R32_TEMPLATE` + bipartitt matching (`_match_thirds`,
  Kuhn) av 3.-plasser til kvalifiserte slots. Output `projectedKnockout` i tournament.json (16 kamper,
  verifisert: «Brazil vs Japan» osv.). `KnockoutView.qml`: «🔮 Show live projection»-toggle (samme knapp av/på).

**Sesjon 3 — BRITISK-TV-KOMMENTATOR-STIL + Kokoro-stemme + multimodal (bruker bestilte, research gjort).**
Research cachet: `~/.claude/research-cache/football-commentator-voice-style-2026.md`.
- **Tekststil:** `SYSTEM_PROMPT` i `football-commentator.py` omskrevet til Peter Drury/Martin Tyler-stil
  (poetisk, dramatisk, present tense, erupt på mål). gemma4:12b @ temp 0.85 gir utmerkede linjer
  («Gakpo ignites the stadium! A thunderbolt of pure intent…»).
- **Stemme — Kokoro:** installerte `kokoro-onnx` + `~/.local/share/kokoro/{kokoro-v1.0.onnx,voices-v1.0.bin}`.
  `~/.local/bin/fotball-kokoro.py` syntetiserer med britisk mannsstemme **bm_george** (mer naturlig enn piper).
  `fotball-tts.sh` bruker Kokoro hvis modellen finnes, ELLERS piper (fallback). Prosodi per hendelse:
  mål/kort = eruptiv (raskere/høyere), run-of-play = rolig.
- **Multimodal modell:** gemma4:12b (sluppet 2026-06-03) er multimodal (tekst+bilde+lyd+video native).
  ⚠️ Ollama mater foreløpig BARE tekst+bilde (lyd/video = åpen Ollama-feature #11798). Beholdt som default;
  settings-tekst oppdatert til å nevne dette.

**Sesjon 3 — TTS-stemme + output-modus + reserver + periodisk kommentar (bruker bestilte):**
- **Formasjonsbane: reserver under banen** + banen wrappet i `tacticsCol` ColumnLayout; pitch
  `gridUnit*30`, popup-høyde `54→62` for å få plass. `getHomeSubs()/getAwaySubs()` (starter==false),
  vist som chips per lag ("Substitutes" + lag-abbrev + navn + rating).
- **TTS-stemme:** `~/.local/bin/fotball-tts.sh <match_id> [device]` leser commentary.json-teksten,
  syntetiserer med **piper** (engelsk stemme `~/.local/share/piper/en_GB-alan-medium.onnx`, lastet ned),
  spiller via `paplay --device`. Fallback espeak-ng. `main.qml.speakNewCommentary()` kalles i loadAllData,
  snakker NY kommentar (dedup på `aiCommentaryId`, baseline ved oppstart), gated på `commentaryMode`.
- **Output-modus** `commentaryMode` (both|sound|text, default both) i main.xml + combo i settings
  ("Voice + text / Text only / Voice only"). Fetcher-merge setter `aiCommentaryId` (ts) for dedup.
- **Periodisk «run of play»-kommentar:** `football-commentator.py` `maybe_general()` hver 420 s per
  live-kamp, prompt med score + possession/xG/shots fra stats. Arkiveres som kind=general.
- ⚠️ Alt verifisert (piper TTS spilte av, helper testet); mangler ekte live-kamp for full demo.

**Sesjon 3 — LLM-INNSTILLINGER + install-knapper (bruker bestilte).** Ny seksjon "Live commentary (AI)"
i `configGeneral.qml`:
- Bruker `org.kde.plasma.plasma5support` (executable-engine) til å kjøre helper-scriptet
  `~/.local/bin/fotball-llm-ctl.sh` (subkommandoer: status/install-ollama/pull-model/set-model/enable/
  disable/test). `status` printer JSON som QML parser → ✓/✗-indikatorer (Ollama / Model / Running).
- Knapper: Install Ollama (kun synlig hvis ikke installert), Download/install model (ollama pull),
  Use (set-model → systemd drop-in `…/football-commentator.service.d/model.conf` + restart), Enable/Disable
  (systemctl), Test (sample-generering), Refresh. Editerbar modell-combo fylt fra `ollama list`.
- Alle helper-handlinger verifisert i terminal. ⚠️ Selve config-dialogen krever at BRUKER åpner Innstillinger
  for visuell verifisering (lastes lazy fra disk; qmlcache tømt). plasma5support-import bekreftet tilgjengelig.

**Sesjon 3 — LLM-KOMMENTATOR AKTIVERT (bruker: "ja").** Hele pipelinen omskrevet og verifisert:
- `football-commentator.py` ble OMSKREVET til selvstendig tjeneste: leser live-hendelser fra
  `matches.json` keyEvents (mål/selvmål/rødt kort), genererer ENGELSK 1-linjes kommentar via Ollama, skriver
  til `commentary.json`-overlay. INGEN Sofascore (Cloudflare-blokkert) — `football-sofascore.service` er nå
  `disabled`. Baseliner eksisterende hendelser ved oppstart (ingen burst).
- `gemma4:12b` valgt (allerede installert; satt i service-env `OLLAMA_MODEL`). Verifisert generering:
  «HAALAND! The Norwegian powerhouse thunders a header into the back of the net! …» (~10 s første kall).
- Fetcher: `merge_ai_commentary()` i `write_cache` fletter overlay → `match["summary"]` + `aiCommentary:true`
  HVER syklus, så kommentaren overlever at matches.json overskrives hvert 10. s. Verifisert ende-til-ende.
- QML: «🎙 Live commentary»-markør + kursiv tekst i sammendrag-callouten når `aiCommentary`.
- Arkiv: `commentary_archive.jsonl` (for fintuning, brukerens langsiktige ønske).
- ⚠️ Mangler kun en EKTE live-kamp for å se i aksjon (0 live ved sesjonsslutt). Bytt modell via
  `Environment=OLLAMA_MODEL=...` i service-fila. Logg: `journalctl --user -u football-commentator -f`.

**Sesjon 3 — formasjonsbane-opprydding (bruker: navn lå oppå hverandre):**
- Banen var for lav → de to lagenes angrepslinjer kolliderte på midtstreken. Fikset: høyere bane
  (`gridUnit*23`→`32`), større midtgap (yFrac home `0.95-t*0.37`, away `0.05+t*0.37` → halvdelene stopper
  ved 0.58/0.42). Etternavn-only via `shortName()` (beholder van/de/von-partikler) → fjerner
  "Moisés Caice…"-trunkering + mindre rot. Større node (78px) + bold 10px navn.

**Sesjon 3 — flagg/logo-skarphet (bruker rapporterte uskarpe bilder):**
- **Rotårsak:** `FlagImage.qml`/`TeamBadge.qml` brukte `layer.enabled: true` på kilde-Image-en, som
  rasteriserer til en FBO på STØRRELSEN AV DET LILLE ITEM-et før MultiEffect-maskering → kastet bort
  oppløsningen (selv 500px-logoer ble downsamplet). Fikset: `layer.textureSize` = 3× + `layer.smooth` +
  `mipmap: true` + `sourceSize` = 3× på både bilde-kilden OG maske-rektangelet (skarp sirkel-kant).
- **Flagg var dessuten lavoppløselige:** `get_flag_url` hentet `flagcdn.com/w160` (160px). Endret til
  `w640` (4×). Slettet cachede `flag_*.png` så de re-lastes; verifisert 640px nå.

**Sesjon 3 — flere oppfølgingsfikser (bruker rapporterte):**
- **Ferdige kamper sorteres nå FERSKEST ØVERST.** `fetch_all_matches` sort: live → upcoming (soonest
  first) → finished (`matchTime` DESCENDING). Var ascending (kommentaren løy). Verifisert.
- **"Verdensmesterskap"/"VM" → "World Cup"** (norsk lekkasje i data): `parse_espn_match` league-override
  + `LEAGUE_NAMES["FIFA.WORLD"/"FIFA.WORLD.MEN"]`. TournamentHeader-undertekst trimmet til "2026 · Canada /
  Mexico / USA" (unngår "World Cup / World Cup 2026"-dobbel).
- **Mål-chip-bug:** da "Mål:"→"Goals:" ble byttet, ble `substring(i+4)` (lengden av "Mål:") stående mens
  "Goals:" er 6 tegn → første chip viste "s: Antoine Semenyo 2…". Fikset med `i + marker.length`.

**Sesjon 3 — oppfølgingsfikser (bruker rapporterte):**
- **Bortelagets navn fulgte ikke stilgruppen:** ved omkoblingen til to stilgrupper ble bare HJEMME-abbrev
  oppdatert; borte-abbrev hang igjen på `textColor` + `liveColorOutline`. Fikset → begge bruker nå
  `teamColor`/`teamOutline` (CompactRepresentation.qml).
- **Lydenhet ble alltid ignorert (alltid standard):** `dev.id` er `QByteArray` i QtMultimedia 6; `main.qml`
  sammenliknet `dev.id === soundOutputDevice` (streng) → aldri match → falt til default. Fikset med
  `String(dev.id) === String(soundOutputDevice)`. `configGeneral.qml`: dropdownen lagrer nå id som eksplisitt
  `String` (fikser også `indexOfValue`-gjenoppretting), og Test-knappen ruter gjennom valgt enhet
  (`resolveTestDevice()` + `testAudioOut.device`).

**Gjenstår etter sesjon 3 (krever bruker / live-kamp / beslutning):**
- Visuell verifisering av alt over mot en live-kamp (formasjonsbane, live-score-tick, kontur, tray-farge).
- Innstillingssiden + fargevelger-lagring (krever at bruker åpner innstillinger — ikke verifiserbart av meg).
- **LLM-kommentator IKKE aktivert** (ollama 0.30.8 ER installert; tjenester `disabled`). Krever
  `phi4-mini`-pull (~2.5 GB) + 2 vedvarende tjenester + en live-kamp å teste mot. Avventer brukervalg.
- Fintunings-script (langsiktig, ikke bygget).

---

## ⚠️ DET FØRSTE DU MÅ GJØRE

**1. RESTART PLASMA FØR DU RØRER INNSTILLINGENE. `main.xml` endret seg sist sesjon
(ny `liveColorOutline`-nøkkel + `liveColor` er nå type `Color`):**

> ✅ **CLAUDE KAN RESTARTE PLASMA SELV** (oppdaget sist sesjon). `guard-plasmashell.py`-hooken
> blokkerer bare en `plasmashell`-LAUNCH som mangler `kquitapp6 plasmashell` i SAMME kommando.
> «Quit-først» er eksplisitt tillatt. Kjør dette i ÉN Bash-kommando (rydder cache + restarter):
> ```bash
> find ~/.cache -path '*qmlcache/*.qmlc' -delete 2>/dev/null
> kquitapp6 plasmashell 2>/dev/null
> ( setsid kstart plasmashell >/dev/null 2>&1 & )
> ```
> Verifiser med `pgrep -x plasmashell` + `ps -o etimes=` at PID er fersk. `setsid`+`&` detacher så
> prosessen overlever at Bash-tool-et returnerer.

> ⚠️ **`systemctl --user restart plasma-plasmashell.service` VIRKER IKKE her** — tjenesten er
> `disabled`/`inactive` og styrer IKKE den kjørende plasmashell. IKKE `kstart6` (finnes ikke).

> 🐛 **KJENT FELLE (bruker traff den):** Hvis du åpner innstillingene FØR restart etter en
> `main.xml`-endring, blir den nye `cfg_*`-property-en "foreldreløs" (ingen backing-entry i kjørende
> skjema) → config-init feiler → **alle verdier nullstilles til default** (f.eks. live-fargen hopper
> tilbake til grønn) og «Bruk» lagrer ikke. Dette er IKKE en kodebug — koden er konsistent og verifisert.
> Fiks: restart plasmashell, så åpne innstillingene. Brukerens farge må sannsynligvis velges på nytt
> (ble nullstilt). **REGEL: hver gang `config/main.xml` endres → restart plasmashell før innstillinger åpnes.**

**2. VERIFISER disse (ble implementert men ikke sett etter restart):**
- **Fargevelger LAGRER nå** (byttet til Plasmas `KQuickControls.ColorButton` + config-type `Color`;
  alias til custom property lagret IKKE). Innstillinger → Utseende → velg farge → Bruk → tray + dropdown
  skal bli den fargen. Sjekk at `liveColor=...` dukker opp i appletsrc etter lagring.
- **Hendelser** = visuelle ikoner (⚽/kort/piler), ikke tekstrader.
- **Statistikk** = unison split-track + xG-rad.
- **Kampsammendrag** = stylet callout med målscorer-chips.

**3. ÅPEN BUG Å FIKSE (bruker rapporterte, ikke løst):** Live-score i tray/popup oppdateres angivelig
ikke UNDER kampen, bare etterpå. Sjekk reaktivitets-kjeden: `refreshTimer`(main.qml) → `loadAllData()`
→ `matchData` → `getDisplayMatches()` → `MatchDetailCard.matchObj` / CompactRepresentation `activeMatch`.
Mistanke: Repeater-delegater i FullRepresentation rebygges ikke når `displayMatches.length` er uendret;
verifiser at score-Text re-evaluerer `matchObj.homeScore` på hver refresh (evt. tving via en `onMatchDataChanged`
eller bind score eksplisitt). Test mot en live VM-kamp (mål skjer ~hvert 15.–30. min).

**4. ØNSKET FEATURE (bruker GJENTOK — viktig): Taktikk-fanen som ekte FORMASJONSBANE.** I dag viser Taktikk
to tekstkolonner (spiller + rating) — bruker vil IKKE ha dette. Bruker vil ha **hver spiller plassert der
de spiller på en fiktiv fotballbane i grensesnittet, med rating/score-badge UNDER hver spiller** (som FotMob/
Sofascore sin "lineup pitch"). Dataene støtter det: ESPN-lineup har `formationPlace` per spiller +
`formations.home/away` ("4-3-3"); FotMob har posisjoner + ekte ratings. Plan: parse formasjonsstrengen
("4-3-3" → rekker [keeper=1, forsvar=4, midt=3, angrep=3]), legg spillerne i rader på den grønne banen
(hjemmelag nederste halvdel, bortelag øverste halvdel speilet), liten spiller-node (drakt/initialer) med
**score-badge rett under** (gjenbruk `ratingColor()`). `MatchDetailCard.qml` LINEUP-seksjonen (den dempede
grønne banen med midtlinje/sirkel) er lerretet — bytt ut de to tekstkolonnene med absolutt-posisjonerte noder.

**5. KONTUR — FEIL MÅL, MÅ FLYTTES (bruker presiserte):** Kontur-koden finnes (`OutlinedLabel.qml` +
`liveColorOutline` Bool + `root.liveOutline`), men jeg la den på SCORE + MINUTT (de fargede). **Bruker vil ha
den hvit/svart-konturen på LAGFORKORTELSENE «NED»/«JPN»** — den MØRKE teksten som drukner mot det lyseblå
panelet. Neste sesjon: bruk `OutlinedLabel` på de to abbrev-`Kirigami.Heading`-ene i CompactRepresentation
(home/away abbrev, ~linje 69 + 100), `outlined: root.liveOutline`. Vurder om score/minutt fortsatt skal ha
kontur (de er allerede fargede og synlige) — sannsynligvis er det abbrev som trenger den mest.

**7. TRAY-FARGER + EN KRASJ-BUG (bruker rapporterte at farger i resultat/lagnavn «ikke virker lenger»):**
   To ting å undersøke neste sesjon:
   - **(a) Krasj-bug funnet i journal:** `MatchDetailCard.qml` `cleanedEvents()` (~linje 620):
     `(e.clock || "").trim()` kaster `TypeError: 'trim' of object 66 is not a function` når `e.clock`
     er et TALL (ikke streng). **Fiks: `String(e.clock || "").trim()`.** Samme mønster sjekk andre `.trim()`
     på event-felt. Denne kan kaskadere og ødelegge rendering i popup-en.
   - **(b) Tray-farge på resultat/lagnavn:** live-fargen (`root.liveColor`) gjelder KUN når
     `activeMatch.status === "in"` — brukerens skjermbilde viste en PRE-MATCH (CIV–ECU, kl 01:00) → ingen
     live-farge der er KORREKT, ikke en bug. MEN verifiser på en EKTE live-kamp at: scoren faktisk blir
     `liveColor` etter at score ble byttet fra `Kirigami.Heading` til `OutlinedLabel` (sjekk at
     `OutlinedLabel.color`-bindingen → `front.color` virker reaktivt). Lagforkortelsene (`homeAbbrev`/
     `awayAbbrev`, CompactRepresentation ~linje 72/102) bruker ALLTID `Kirigami.Theme.textColor` — de har
     aldri vært farget av liveColor; avklar med bruker om de OGSÅ skal farges/kontures (jf. punkt 5 — bruker
     vil ha hvit kontur på nettopp disse abbrev-ene).

**6. BYTTE-HENDELSER MANGLER SPILLERNAVN (bruker rapporterte):** Alle bytter viser bare «Bytte» uten hvem
inn/ut. ✅ UNDERSØKT: FotMob-bytte-event har navnene i **`swap`-feltet** (IKKE `nameStr`/`player`, som er null):
`swap[0]` og `swap[1]` = {name,id}. Fiks i `_fotmob_parse_events` (fetcher): for `type=="substitution"`,
sett text = f"Bytte: {swap[0].name} → {swap[1].name}" (⚠️ VERIFISER rekkefølge inn/ut — FotMob-konvensjon
antas `swap[0]=inn, swap[1]=ut`, men dobbeltsjekk mot en kjent kamp). 
**Antallet bytter (~10) er EKTE, ikke duplikater** — verifisert at hver har ULIKE spillere; 5 bytter/lag =
VM 2026-grensen (3 på 70' = Nederland trippelbytte). Når navn vises blir det åpenbart at de er reelle. Ingen dedup nødvendig.

---

## Hva er dette

KDE Plasma 6 system-tray-plasmoid (QML/Kirigami) som viser **live fotballresultater**,
statistikk, lagoppstilling, og turneringsdata (grupper/sluttspill/toppscorere).
Under mesterskap (nå: VM 2026) får widgeten mesterskapstema med farger, logo og maskot.

**Heter "Football", IKKE "soccer".** Alle brukersynlige strenger og navn skal være football.
(ESPN API-URLer bruker `/sports/soccer/` internt — det kan ikke endres, det er ESPNs path.)

---

## Arkitektur og filer

### Frontend (plasmoid)
`/home/robert/.local/share/plasma/plasmoids/org.kde.fotballtray/`
- `contents/ui/main.qml` — rot (PlasmoidItem), datainnlasting, theming, filtrering
- `contents/ui/CompactRepresentation.qml` — tray-ikon (score/flagg/tid + mål-ticker)
- `contents/ui/FullRepresentation.qml` — popup (pill-tabs: Kamper | Turnering)
- `contents/ui/configGeneral.qml` — innstillinger (KCM.SimpleKCM, cfg_*-aliaser)
- `contents/ui/Theme.js` — per-liga fargetema
- `contents/ui/components/` — 15 komponenter (se under)
- `contents/config/{config.qml,main.xml}` — config-registrering
- `metadata.json` — X-Plasma-API-Minimum-Version: 6.0 (påkrevd for Plasma 6)

### Backend (data)
- `~/.local/bin/fotball-data-fetcher.py` — henter ESPN/OpenLigaDB/Wikipedia → matches.json
  (systemd: `fotball-fetcher.service`)
- `~/.cache/fotballtray/httpserver.py` — serverer JSON+bilder på `127.0.0.1:9876`
  (systemd: `fotball-server.service`)
- Data: `~/.cache/fotballtray/{matches,tournament,leagues,teams}.json` + `images/`

### Live LLM-kommentator (NYTT — skjelett, IKKE aktivert ennå)
- `~/.local/bin/football-sofascore.py` — poller Sofascore live-API (incidents/stats/xG),
  oppdager nye hendelser → skriver til `commentary_queue.jsonl` (systemd: `football-sofascore.service`)
- `~/.local/bin/football-commentator.py` — leser kø, kaller Ollama (norsk kommentator-prompt),
  patcher `matches.json` (summary + keyEvents) (systemd: `football-commentator.service`)
- `~/.local/bin/football-commentator-setup.sh` — installerer Ollama + phi4-mini + aktiverer tjenester
- Genererte kommentarer arkiveres i `commentary_archive.jsonl` (for senere fintuning)

---

## 🚨 FARER (ikke gjenta disse feilene)

1. **ALDRI kjør `kpackagetool6 -u <path>` på plasmoid-mappen.** Den SLETTER kildemappa
   (`contents/`) selv når den rapporterer "feilet". Dette skjedde i en tidligere sesjon
   og hele widgeten måtte gjenskapes fra minnet. For å laste på nytt: restart plasmashell.

2. **`plasmashell` KAN restartes av Claude** via «quit-først» i én kommando (`kquitapp6 plasmashell`
   + `setsid kstart plasmashell &`). Hooken tillater det når quit er med. En BAR launch uten quit blokkeres.

3. **QML-cache:** Etter redigering, rydd cachen så endringer plukkes opp:
   ```bash
   rm -f ~/.cache/plasmashell/qmlcache/*.qmlc
   ```

4. **Plasma 6 QML-fallgruver som har bitt oss:**
   - `alignment:` finnes IKKE på RowLayout/ColumnLayout — bruk `Layout.alignment` på barn
   - `clearButtonShown` finnes IKKE på QQC2 TextField (var PlasmaComponents2)
   - `property string x` lager automatisk `signal xChanged()` — IKKE deklarer den manuelt også
   - `ComboBox.currentValue` er ~read-only — gjenopprett valg via `currentIndex = indexOfValue(...)`
   - `Kirigami.FormData.label` virker BARE på direkte barn av Kirigami.FormLayout
   - `anchors.fill: parent` + forelder som leser `implicitHeight: child.implicitHeight` = binding loop

---

## Nylig fikset (denne sesjonen)

**Design-overhaul (godkjent av bruker):**
- Flagg: ekte sirkulær klipping via `MultiEffect { maskEnabled }` (Qt 6.11) + glossy overlay +
  dobbel ring-border (mørk innside + lys utside) for kontrast på alle bakgrunner.
  Nasjoner = runde flagg, klubber = avrundede firkanter. (FlagImage.qml, TeamBadge.qml)
- Popup bredere: `gridUnit*42` → `gridUnit*58` så alle 12 VM-grupper (A–L) vises i 2 kolonner
- Pill-stil tabs overalt (FullRepresentation, TournamentView, MatchDetailCard)
- GroupTable: V/U/T-kolonner med semantiske farger, kvalifiserings-stripe for topp 2
- MatchDetailCard: status-pille, grønn glow på live, lagfarge-accenter
- Kirigami-tokens: `Kirigami.Units.shortDuration/longDuration` for animasjoner (respekterer
  systemets animasjonshastighet), `Kirigami.Theme.positiveTextColor/neutralTextColor/
  negativeTextColor` for live/HT/rødt-kort, `roundedIconSize()` for tray-ikoner
- TournamentHeader: fjernet Math.random()-flicker og RotationAnimation.Alternate (Qt6-ugyldig)

**Bugfikser:**
- `alignment:` på RowLayout i TournamentView (var LASTEBLOKKER for hele widgeten) → fjernet
- GroupTable binding loop (`anchors.fill` + implicitHeight) → top/left/right anchors
- `clearButtonShown` i TeamSelector → fjernet
- **configGeneral.qml-innstillingssiden var BLANK** → rotårsak: `TeamSelector.qml` hadde
  BÅDE `property string selectedTeams` OG `signal selectedTeamsChanged(string)` — duplikat
  (property lager auto-signal) → "Type TeamSelector unavailable" → hele config-siden feilet.
  **FIKSET** ved å fjerne den manuelle signal-deklarasjonen + de manuelle emit-kallene.
  ⚠️ **MÅ VERIFISERES etter restart** (jeg kunne ikke restarte selv).
- configGeneral funksjonelle fikser: ButtonGroup→QtObject (DisplayModeButton er Rectangle,
  ikke AbstractButton), fjernet selvrefererende leagueValue-binding, eksplisitte labels for
  nested spinbox/slider, ComboBox-gjenoppretting via indexOfValue
- StatBar binding loop: `parent.width` → `statBar.width`

---

## 🔊 LYDVARSLER — TEST-KNAPP + HENDELSESLYDER (sesjon 2)

- **BUG FIKSET:** `playSound()` i main.qml spilte ALLTID hardkodet `pling.wav` → lyd-dropdownene
  (cfg_soundFollowed/cfg_soundOther) ble aldri brukt. Nå: `playSoundFile(file)` + `playGoalSound(isFollowed)`
  velger riktig lyd basert på `isFollowedMatch(m)` (egne lag → soundFollowed, andre → soundOther).
- **Test-knapp** ved hver lyd-dropdown i innstillingene (`playTest(file)` med egen `MediaPlayer`,
  `Qt.resolvedUrl("../sounds/"+file)`).
- **Hendelseslyder:** ny config `soundRedCard` (default whistle) + `playEventSounds` (Bool, default true).
  main.qml `checkForNewRedCards()` teller `type==="redcard"`-events per live-kamp og spiller `playEventSound()`
  når antallet øker (samme mønster som mål-deteksjon; trigger ikke på oppstart). Kjøres i `loadAllData`.
- **Lydfiler i `contents/sounds/`:** cheer.wav, pling.wav, whistle.wav (cheer+whistle er like store — sjekk
  om whistle faktisk er en fløyte; bør erstattes med ekte dommerfløyte).

**✅ RESEARCH FERDIG** → `~/.claude/research-cache/football-event-sound-notifications-2026.md`. Hovedfunn:
- Apper bruker IKKE én lyd per hendelse — de kollapser til **~3 timbre-familier**: (1) **folkemengde-jubel**
  = mål for eget lag, (2) **dommerfløyte** x1/x2/x3 (1=avspark/foul, **2=pause, 3=full tid** — ekte konvensjon),
  også rødt kort/straffe, (3) **myk «ding» + lav «groan»** = nøytral/negativ (andre lags mål = stille ding,
  mål imot = lav groan, IKKE jubel). (Sofascore = 3 kanaler; FotMob har egen "goal conceded"-lyd; OneFootball
  field-recordet ekte PL-fløyte.)
- **Calm-tech-regel (VIKTIG):** kun **eget-lag-mål-jubel PÅ by default**, ALT annet opt-in. Et widget som
  brøler uoppfordret mens du jobber er verre enn en mobil-app. Gule kort/bytter/hjørnespark = KUN visuelt.
  ⚠️ **ANBEFALT ENDRING NESTE SESJON:** sett `playEventSounds` default `false` (er `true` nå) — rødt kort-lyd
  bør være opt-in. Legg til master-volum + per-hendelse-toggles + per-turnering-mute + respekter Do-Not-Disturb.
- **Foreslått event→lyd-tabell** (utvid `checkForNewRedCards` til en generell `checkForNewEvents`):
  eget mål=jubel(PÅ) · mål imot=groan(av) · andre lags mål=ding(av) · rødt kort=enkel fløyte(av) ·
  straffe=fløyte(av) · avspark=enkel fløyte(av) · full tid=trippel-fløyte(av) · gult/bytte=ingen.
- **CC0-lydkilder (trygt for open-source):** **freesound.org filtrert til CC0** (PRIMÆR, ingen kreditering,
  trygg redistribusjon; eks. fløyte `freesound.org/people/Pablo-F/sounds/90743/`). pixabay/mixkit som backup
  (commercial OK MEN forby republisering av rå fil → ikke pakk som nedlastbart asset-sett; CC0 unngår dette).
  Søk: `crowd cheer`, `goal crowd`, `referee whistle single/double/triple`, `notification ding`, `negative tone`.
  Lag en `CREDITS`-fil med kilde+lisens per fil. Unngå pond5/tunepocket (betalt).

## 🎟️ VISUELLE HENDELSER (sesjon 2)

Hendelses-fanen omskrevet fra ren tekst til visuelle ikoner:
- **Backend** (`_fotmob_parse_events`): normaliserte typer (goal/owngoal/yellowcard/redcard/substitution/
  half/addedtime) + norske etiketter ("Mål – X (assist: Y)", "Gult kort – X", "Bytte", "Pause"),
  skiller gult/rødt via FotMob `card`-felt, selvmål via `ownGoal`, straffemål via `goalDescription`,
  klokke med apostrof. ⚠️ FotMob `timeStr` kan være int → må str()-coerces (kostet en bug: enrich
  feilet → events falt til ESPN mens xG/lineup allerede var satt → detailSource ble None).
- **Frontend** (MatchDetailCard): `eventKind()` klassifiserer på `type` først (FotMob), tekst-fallback
  (ESPN). `cleanedEvents()` dropper tomme + støy (delay/drinks/VAR). Visuelle ikoner: ⚽ ball for mål
  (mål-rad uthevet med aksent-tint + bold), tegnede gult/rødt kort-rektangler (rotert -8°), inn/ut-piler
  (▲grønn/▼rød) for bytte, periode-markører som sentrert dim skillelinje.

## ⚽ FOTMOB PRIMÆRKILDE + xG/EKTE RATINGS (sesjon 2)

Implementert `enrich_with_fotmob(match)` i fetcheren (subagent): overlay på ESPN for
status in/ht/post. `/api/data/matches?date=` → fuzzy navn-match → `/api/data/matchDetails?matchId=`.
Gir **xG** (`stats.expectedGoals`), **ekte Opta-ratings** (`performance.rating`, flagget `realRating`),
oppstilling, formasjon, events. ESPN er fallback (28/39 kamper FotMob, 11 faller til ESPN på navn-mismatch).
Cacher FotMob-id per kamp + `detailSource: fotmob`. Ingen 403/x-mas så langt — hvis det dukker opp,
logges det og ESPN beholdes. Verifisert: NED-JPN xG 0.45/0.18, ratings 5.5–7.8.

## 🎨 FARGEVELGER-BUG + UNISON STAT-DESIGN (sesjon 2)

- **Fargevelger lagret ikke** (2 årsaker): (1) plasmashell var eldre enn `main.xml`-endringen →
  skjema ikke lastet; (2) VIKTIGST: `property alias cfg_liveColor` til en **custom Rectangle-property**
  ble IKKE persistert av KCM-en (bekreftet: `liveColor` dukket aldri opp i appletsrc selv etter restart).
  **LØSNING:** byttet til Plasmas kanoniske `org.kde.kquickcontrols.ColorButton` + config-type `Color`
  (default `#2ecc71`), `property alias cfg_liveColor: liveColorButton.color`. `main.qml`:
  `liveColor: Plasmoid.configuration.liveColor`. Dette er den dokumenterte måten og lagrer pålitelig.
  ⚠️ LÆRDOM: for farge-config i Plasma, bruk ColorButton + type Color — IKKE alias til egen string-property.
  ⚠️ LÆRDOM: endrer du `config/main.xml`, MÅ plasmashell restartes for nye/endrede nøkler.
- **Kampsammendrag** stylet som callout (svak bakgrunn + venstre aksent-stripe), narrativ-linje +
  målscorere som små ⚽-chips (`summaryNarrative()`/`summaryGoalList()` splitter på "Mål:").
- **StatBar** omskrevet: moderne split-track (home fyller fra venstre, away fra høyre), unison palett
  (aksent = `liveColor` vs rolig nøytral, IKKE rå lag-farger), uthevet ledende verdi. xG-rad vises nå.
- **Oppstillings-bane** tonet ned til rolig mørk grønn + subtil midtlinje/sirkel.
- **Popup** `gridUnit*64 → 72` (mer tekst-plass).

## 📊 STATISTIKK/TAKTIKK FIKSET — leste FEIL ESPN-nøkler (sesjon 2)

Bruker: "taktikk og statistikk blir aldri hentet". Research-agent verifiserte LIVE at ESPN
returnerer ALT — `enrich_with_details` leste bare feil JSON-nøkler:
- **Stats**: leste `data["statistics"]` (alltid null) → RIKTIG: `data["boxscore"]["teams"][i]["statistics"]`
  (flat liste {name, displayValue}, `homeAway` på team-objektet). Lagt til alias `wonCorners→corners`,
  `totalTackles→tackles`. ESPN har INGEN xG.
- **Oppstilling**: leste `roster["entries"]` + `entry["player"]` → RIKTIG: `roster["roster"]` + `entry["athlete"]`.
  Formasjon på `roster["formation"]` (var allerede riktig).
- Tømte `~/.cache/fotballtray/details_cache.json` (holdt gamle TOMME parser-resultater for ferdige kamper).
- ✅ Verifisert: live NED-JPN = 28 stats + 26 oppstilling + formasjon; ferdige Bundesliga = 29 stats + 20 oppstilling.
- Spiller-ratings er fortsatt 6.0+hendelser-heuristikk (ESPN har ingen ekte). Cache-notat:
  `~/.claude/research-cache/football-live-stats-data-sources-2026.md`.

**GJENSTÅR (anbefalt neste steg fra research): FotMob** som primærkilde for ekte xG + Opta-ratings +
shotmap. Endepunkt `https://www.fotmob.com/api/data/matchDetails?matchId=` (ikke Cloudflare-blokkert),
id-matching via `/api/data/matches?date=YYYYMMDD` + fuzzy lagnavn. Full mapping i cache-notatet.
(SofaScore-skjelettet = 403/Cloudflare, ikke brukbart uten TLS-impersonation.)

## 🎨 VALGBAR LIVE/RESULTAT-FARGE (sesjon 2)

Bruker kan nå velge farge på alt som var grønt (score, kampminutt, live-dot, kvalifiserings-stripe).
- `config/main.xml`: ny `liveColor` (String, default "" = tema-grønn).
- `main.qml`: `property color liveColor` (config-hex eller `Kirigami.Theme.positiveTextColor`).
- `configGeneral.qml`: ny "Utseende"-seksjon — full `ColorDialog` (QtQuick.Dialogs) + 7 hurtigvalg-prikker
  + Tilbakestill + live forhåndsvisning. Alias `cfg_liveColor` → swatch.colorValue (String).
- Brukt via `root.liveColor` i CompactRepresentation (tray), MatchDetailCard (`property color liveColor`,
  sendt fra FullRepresentation), GroupTable (`qualColor`, sendt fra TournamentView).

## 🏴 FLAGG I TABELLENE + BREDERE POPUP (sesjon 2)

- **Backend** (`fotball-data-fetcher.py`): `compute_group_tables` beriker hver lag-rad med
  `countryCode` + `flag` (lokal `/img/flag_<cc>.png` via `local_image_url_for_team`); `compute_top_stats`
  beriker toppscorere/assists best-effort (kun når lagstrengen løses til et land).
- **GroupTable.qml**: ny flagg-kolonne (rund `FlagImage`), strammere numeriske kolonnebredder
  (wPos/wFlag/wP/wGD/wPts som properties) så navn får mest plass.
- **TournamentView.qml** (toppscorere/assists): liten `FlagImage` foran navn, vises KUN når `flag` finnes
  (assists mangler ofte lag → ingen stygg "?"-fallback).
- **KnockoutView.qml**: `TeamBadge` på hver side av scoren + tabular score.
- **FullRepresentation.qml**: popup-bredde `gridUnit*58 → 64` så lange navn ("Bosnia and Herzegovina") + flagg får plass.

Flagg-bildene serveres lokalt (verifisert HTTP 200). MÅ verifiseres visuelt etter restart.

## 🔧 TABELL/LISTE KOLLAPSET TIL BREDDE 0 — fikset (sesjon 2)

Gruppe-tabellen (og match-lista) rendret med ALLE kolonner oppå hverandre på x=0.
Rotårsak: innhold i en `ScrollView` med `width: parent.width` er SIRKULÆRT — innholdets
bredde ← ScrollViewens innholdsbredde ← innholdets implicit-bredde (≈0 for `Layout.fillWidth`-
only barn som GroupTable/MatchDetailCard) → bredde 0 → kolonnene klemmes sammen.
**Fiks: bind innholdsbredden til `<scrollViewId>.availableWidth`** (utledet fra ScrollViewens
egen geometri, ikke sirkulær; trekker fra scrollbar). Gjort i alle 4 ScrollView-faner:
TournamentView (Grupper/Sluttspill/Toppscorere) + FullRepresentation (Kamper).
⚠️ Generell lærdom: ALDRI `width: parent.width` på direkte ScrollView-innhold i Plasma 6.

## 🔧 INNSTILLINGSSIDEN — 2. rotårsak funnet og fikset (sesjon 2)

TeamSelector-fiksen virket (ingen "Type TeamSelector unavailable" mer), men en NY feil
gjorde siden blank: `configGeneral.qml:85: Cannot assign to non-existent property "spacing"`.
**`Kirigami.FormLayout` har ingen `spacing`-egenskap** — den styrer sin egen radavstand.
Fjernet linja. MÅ verifiseres etter restart (config-dialogen lastes lazy fra disk).

## ✅ STOR DESIGN-OVERHAUL — IMPLEMENTERT (sesjon 2), MÅ VERIFISERES ETTER RESTART

Bruker valgte "rett i QML" (hoppet over canvas-mockups). Implementert iht. research-konklusjonen
nedenfor. **Alle 4 filene er skrevet om — verifiser visuelt etter plasmashell-restart:**

- **`Theme.js`** — la til `desaturate(hex,factor,lift)` + `softAccent(leagueId)`. Mettede liga-farger
  trekkes mot egen luma så de ikke "vibrerer" på mørk bakgrunn.
- **`TournamentHeader.qml`** — HELT omskrevet: 170px animert banner (maskot+5 orbs+pulse-loops) →
  slank ~2.6 gridUnit STATISK stripe (lite emblem + navn + år/vertsby-undertekst, venstrejustert,
  flat desaturert tint + 3px aksent-kant til venstre). Null ambient-loops; én engangs fade-in.
- **`MatchDetailCard.qml`** — kollapset rad omskrevet til flat 3-sone `[status | lag stablet | score]`.
  Badge 22px, tabular bold score (`font.features {tnum:1}`), én live-dot (8px + 1.6s soft halo,
  gated på `reduceMotion = Kirigami.Units.longDuration<=1`), mål-flash (scale-pop) på score-endring,
  3px desaturert lagfarge-stripe, hårstrek-divider (fillHeight, IKKE implicitHeight → unngår loop),
  ingen tunge borders. Det utvidbare panelet (stats/taktikk/hendelser) beholdt.
- **`GroupTable.qml`** — lean 5-kol `Pos | Lag | P | +/- | Pts(bold)`, tynn grønn kvalifiserings-
  stripe (3px) for topp 2, droppet V/U/T. Data har `played` og `gd` direkte.

⚠️ **IKKE verifisert etter restart** (kan ikke restarte plasmashell selv). Sjekk særlig:
match-rad-høyde/justering, at live-dot pulser, at gruppe-tabellen ikke er for trang.
Hvis noe er blankt → `journalctl --user -b | grep -iE "fotball|unavailable|qml"`.

Gjenstår fra design-research (ikke gjort): desaturere `homeColor`/`awayColor` i StatBar-grafer er
delvis (stripen er desaturert, men StatBar-fyllet bruker fortsatt rå farge); gruppe-crest mangler
(ingen logo-felt i dataene). Generelt videre finpuss ønskes fortsatt.

---

## 🎨 (ARKIV) STOR DESIGN-OVERHAUL — opprinnelig bestilling

Brukeren synes designet fortsatt er "utrolig stygt" og lite moderne — særlig **dropdown-popupen**
og **den animerte maskoten/banneret øverst**. Banneret skal ENTEN bort ELLER lages helt på nytt
med en moderne tanke. Vi gjorde grundig design-research (2 parallelle agenter) før beslutning.
**Bruk `/canvas-design`-skillen** til å lage moderne mockup(er) av den nye looken FØR QML-implementasjon,
så vi låser visuell retning først.

**Research er lagret i cachen (les disse først):**
- `~/.claude/research-cache/event-branding-glanceable-widgets-2026.md` — mascot/banner-avgjørelsen
- `~/.claude/research-cache/football-livescore-app-visual-design-2026.md` — kort/rad/typografi-specs
- `~/.claude/research-cache/ui-design-trends-2026.md` — generell 2026-baseline

**Research-konklusjon (entydig på tvers av Apple Sports, FotMob, Sofascore, calm-tech-litteratur):**

1. **DREP det animerte banneret.** Maskot + 5 bouncende orbs + pulsende logo + floating-loop =
   nøyaktig det moderne apper har gått bort fra. `Animation.Infinite`-løkker i en alltid-synlig
   widget bryter calm-tech-prinsippet OG WCAG 2.2.2 (Pause/Stop/Hide).
   → **Anbefalt (Option A):** erstatt 170px-banneret med en slank ~48px (`gridUnit*2.5`) STATISK
   header-stripe: lite offisielt emblem + turneringsnavn + vertsby/år-undertekst, venstrejustert,
   flatt/svakt tintet bakgrunn. Tråd turneringens aksentfarge inn i RESTEN av UI-et (status-pille,
   skillelinjer, valgt-tilstand) — DET er det som signaliserer "VM-modus", ikke en stor illustrasjon.
   Null ambient animasjon; behold evt. én engangs fade-in når temaet aktiveres. Gjenvinner ~120px
   til kamper. (Theme.js-fargene er for mettede for dark mode — desaturér dem.)

2. **Match-kort → flate RADER, ikke bordede kort.** 3-sone layout `[status | lag stablet | score]`.
   Badge ~20-24px (ikke helten), lagnavn medium 500, **score tabular/mono bold 700** (tabular figures
   så score-kolonnen ikke hopper når 1→11 live). Hierarki via vekt+farge, ikke størrelse.
   Radhøyde ~44-52px, hårstrek-skillelinjer, ikke border per kort.

3. **Live-emphasis:** ÉN liten dot (8-10px) + live-minutt tintet, myk halo-puls 1.6s, respekter
   `prefers-reduced-motion`. Aldri puls på hele raden, aldri full rød bakgrunn.

4. **Farge/flate:** dark-first men tintet near-black (ikke #000), mest nøytralt, desaturerte aksenter,
   elevation via lysere flate (ikke tunge skygger/borders).

5. **Grupper/tabeller:** slank 5-kolonne (Pos | crest+navn | P | +/- | **Pts** bold), tynn farget
   kvalifiserings-stripe (3-4px) til venstre, marker fulgt lag. Dropp W-D-L i smal popup.

6. **Bevegelse hører kun til state-endringer** (mål-flash, status flipper til live), 1-3s så STOPP.
   Ingen ambient loops.

**Konkret rekkefølge for neste sesjon:**
a. `/canvas-design` → mockup av (i) ny slank header-stripe, (ii) match-rad, (iii) gruppe-tabell — vis bruker, få OK.
b. Implementer i QML: skriv om `TournamentHeader.qml` (slank stripe), `MatchDetailCard.qml` (flat rad),
   `GroupTable.qml` (slank), desaturér `Theme.js`.
c. Restart + verifiser med bruker.

---

## TODO / neste steg

1. **[HØYEST PRIORITET] Verifiser innstillingssiden** vises etter restart (TeamSelector-fiksen).
   Hvis fortsatt blank → sjekk journal for neste "Type X unavailable" og fiks den komponenten.

2. **Aktiver live LLM-kommentator** (brukeren har bedt om dette, skjelett er bygget men ikke kjørt):
   ```bash
   bash ~/.local/bin/football-commentator-setup.sh
   ```
   Dette installerer Ollama + phi4-mini (~2.5 GB) og starter begge tjenestene.
   Test med en live-kamp (VM 2026 pågår). Sjekk: `journalctl --user -u football-commentator -f`
   - Sofascore-lagmatching er fuzzy (lagnavn) — kan trenge justering hvis kamper ikke matches
   - Sofascore kan rate-limite/kreve cookies — `football-sofascore.py` har en warmup-request

3. **Fintuning av egen modell** (brukerens langsiktige ønske): samle par fra
   `commentary_archive.jsonl`, format `{input: event_json, output: commentary}`, mål 2000+ par,
   LoRA-trening med unsloth. Brukeren har `llama.cpp` i `/home/robert/llama.cpp`.
   Fintuning-script er IKKE laget ennå — brukeren spurte om det til slutt.

4. **Generelt videre designarbeid** ønskes — gjør det moderne og vennlig overalt.

---

## Nyttige kommandoer

```bash
# Restart desktop (bruker kjører):  kquitapp6 plasmashell; kstart plasmashell
#   (IKKE kstart6 / IKKE systemctl plasma-plasmashell — se felle øverst i fila)
# Rydd QML-cache:                    rm -f ~/.cache/plasmashell/qmlcache/*.qmlc
# Se widget-feil:                    journalctl --user -b | grep -i "fotball\|qml\|unavailable"
# Sjekk data:                        curl -s http://127.0.0.1:9876/matches.json | python3 -m json.tool | head
# Backend-status:                    systemctl --user status fotball-fetcher fotball-server
# Kommentator-logg:                  journalctl --user -u football-commentator -f
```

## Arbeidsstil-notat fra bruker
Bruk subagenter når flere uavhengige oppgaver kan kjøres parallelt (f.eks. audit av
render-kjede vs config-kjede samtidig). Dette ble eksplisitt etterspurt.
