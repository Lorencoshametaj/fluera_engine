# Le Leggi UI/UX di Fluera — Dalla Teoria Cognitiva all'Esperienza Enterprise

> *"La forma segue la funzione. La funzione segue la neuroscienza."*

Questo documento è il compagno operativo di [`teoria_cognitiva_apprendimento.md`](teoria_cognitiva_apprendimento.md). Dove quel testo enuncia i **principi cognitivi** che Fluera deve rispettare, questo testo enuncia le **leggi visive e interattive** che li traducono in UI. Ogni legge è ancorata a un principio scientifico, e ogni principio si riflette in decisioni di design concrete. Una UI che viola queste leggi non è solo brutta — è **neurobiologicamente sabotante**.

Il documento serve due obiettivi inseparabili:
1. **Livello visivo enterprise** — la percezione di solidità, coerenza, raffinatezza che lo studente universitario o il professionista si aspetta da uno strumento di produttività serio (Notion, Linear, Figma, Arc, Craft, Cron).
2. **Esperienza d'uso quotidiana** — la fluidità, la prevedibilità e l'assenza di attrito che permettono all'utente di aprire Fluera ogni giorno senza che il software si metta mai *tra lui e il pensiero*.

---

## PARTE I — I Dieci Assiomi Inviolabili

> *Queste dieci regole sono la costituzione di Fluera. Ogni nuova feature, ogni nuovo pannello, ogni nuovo bottone deve passare attraverso questi dieci test. Se ne viola anche uno solo, va riprogettato o scartato.*

### Assioma 1 — Il Canvas è Sacro

> **Il canvas è il territorio cognitivo dello studente. Nulla deve occupare spazio sul canvas se non è stato generato dallo studente stesso.**

**Principio cognitivo:** Sovranità Cognitiva (Parte VI della teoria), Generation Effect (§3), Embodied Cognition (§23).

**Applicazione UI:**
- Tutti gli elementi di interfaccia (toolbar, tool wheel, pannelli, overlay) vivono in un **livello sovra-canvas (UI layer)**, mai nel livello del contenuto (canvas layer).
- Nessun elemento di UI può essere scrollato/spostato *insieme* al canvas: gli UI overlay sono fissi nello spazio dello schermo, mai nello spazio del canvas.
- Gli overlay dell'IA (Ghost Map, bolle-domanda, suggerimenti) sono **semi-trasparenti** (opacity ≤ 0.70) per distinguerli visivamente dal contenuto "reale" dello studente.

**Anti-pattern:** Mai disegnare automaticamente tratti, forme, testi o connessioni sul canvas dello studente. Mai "pulire" o "riorganizzare" il suo lavoro.

---

### Assioma 2 — Il Silenzio è una Feature

> **Durante la scrittura attiva, l'interfaccia deve tendere a zero.**

**Principio cognitivo:** Flow (§24), Cognitive Load — carico estraneo (§9), System 2 (§13).

**Applicazione UI:**
- Quando la penna tocca lo schermo o entro 800ms dall'ultimo tratto, tutta la UI non-essenziale entra in **auto-hide** (fade out 150ms, curva `easeOutCubic`).
- Nessun popup, notifica, tooltip, badge o micro-animazione può comparire durante la scrittura attiva.
- Il cursore del mouse/trackpad si nasconde anch'esso dopo 1500ms di inattività sul canvas.
- Gli indicatori di stato (salvataggio, sync, collaboratori online) collassano in un singolo puntino monocromatico da 4px in un angolo, mai animato durante la scrittura.

**Anti-pattern:** Toolbar sempre visibile a piena opacità, bottoni che pulsano, numeri di notifica, "è arrivato un messaggio" durante il flow.

---

### Assioma 3 — L'IA è Invitata, Mai Presente

> **L'IA non esiste finché lo studente non la chiama. Quando parla, lo fa con la voce più bassa possibile.**

**Principio cognitivo:** Cognitive Offloading (§15), Automation Bias (§14), Atrofia Cognitiva (§21), Sovranità Cognitiva.

**Applicazione UI:**
- **Nessun** "suggerisci", "completa", "migliora", "espandi" visibile a meno che l'utente non sia in un flusso esplicitamente invocato (Stadio 1, 2, 9).
- Nessuna "lampadina", "scintilla", "stella magica" nella UI di default. Queste icone sono riservate ai momenti in cui l'utente ha chiesto l'IA.
- L'invocazione dell'IA avviene tramite:
  - un **gesto deliberato** (es. three-finger tap, long-press su un nodo specifico),
  - un **bottone dedicato** sempre nella stessa posizione (coerenza Jakob's Law),
  - un **comando vocale** se lo studente ha attivato la registrazione.
- Ogni output dell'IA è visivamente **diverso** dal contenuto generato dall'utente: tratto ghost, font differente, colore dedicato (es. il viola dei tool di selezione non può mai essere usato per output IA — serve un colore riservato).

**Anti-pattern:** "Claude sta elaborando…", "Vuoi che aggiunga un esempio?", banner permanenti con "AI Assistant online".

---

### Assioma 4 — La Latenza è il Vero Design

> **Ogni millisecondo di ritardo tra intenzione e feedback rompe la cognizione incarnata. Il tratto deve esistere prima del pensiero.**

**Principio cognitivo:** Embodied Cognition (§23), Flow (§24), Doherty Threshold (400ms).

**Budget di latenza (non-negoziabili):**

| Interazione | Budget | Conseguenza della violazione |
|-------------|--------|------------------------------|
| Penna → tratto visibile | ≤ 10ms (GPU Live Stroke Overlay) | Rottura embodied cognition |
| Tap su bottone toolbar | ≤ 50ms feedback visivo | Sensazione di "app rotta" |
| Apertura tool wheel (long-press) | ≤ 120ms dalla soglia | Gestura percepita come "laggosa" |
| Cambio tool (penna→gomma) | ≤ 200ms stato attivo | Rottura del flow creativo |
| Zoom/pan | 60 FPS costanti | Nausea, perdita di orientamento spaziale |
| Apertura canvas salvato | ≤ 400ms al primo tratto possibile | Ansia da attesa, distrazione |
| Risposta AI socratica | ≤ 1200ms o skeleton dinamico | Interruzione del ciclo cognitivo |

**Applicazione UI:**
- Ogni interazione ha un feedback **ottico < 16ms** (un singolo frame a 60fps), anche quando l'operazione reale impiegherà di più. Il feedback differito (skeleton, progress bar, shimmer) va mostrato solo dopo 400ms di attesa.
- **Palm rejection perfetto** su tablet: la mano appoggiata non deve mai generare tratti, mai deselezionare, mai aprire menu.

**Anti-pattern:** Spinner fin dal primo click, throttling visibile, "Loading…" per operazioni locali.

---

### Assioma 5 — La Posizione è Sacra

> **Dove lo studente ha messo una cosa è parte del significato della cosa. Non spostare nulla senza il suo consenso.**

**Principio cognitivo:** Cognizione Spaziale (§22), Place Cells, Metodo dei Loci, Extended Mind (§29).

**Applicazione UI:**
- **Nessun auto-layout, snap-to-grid obbligatorio, auto-arrange, "riordina il canvas"**.
- Lo snap opzionale deve essere disabilitato di default e attivabile solo su gesto esplicito (es. con modificatore).
- Riaprire un canvas = aprire nella **identica posizione, zoom, rotazione** dell'ultima sessione. Mai "fit to screen", mai "ritorna al centro".
- I pannelli laterali (layers, variabili, chat) memorizzano posizione, larghezza e stato aperto/chiuso **per ogni canvas**, non globalmente.
- Drag di un nodo da parte dell'utente = spostamento immediato, senza "nicho" verso posizioni suggerite.

**Anti-pattern:** "Auto-organize", "Clean canvas", "Reset layout", fit-to-screen all'apertura, magnetismo invadente.

---

### Assioma 6 — Uno Strumento, Uno Stato

> **In ogni momento, esattamente uno strumento è attivo. Lo stato è sempre visibile, sempre ambiguo-zero.**

**Principio cognitivo:** Cognitive Load (§9), Miller's Law (4-7 elementi), Hick's Law (less choice = faster decision).

**Applicazione UI:**
- Lo strumento attivo ha:
  - un **bordo colorato** con il colore semantico del tool (blu=penna, rosso=gomma, viola=lazo/selezione, ambra=righello/pan, ciano=media, smeraldo=testo digitale) — questi token sono già definiti in [`toolbar_tokens.dart`](fluera_engine/lib/src/canvas/toolbar/toolbar_tokens.dart) e **non vanno mai inventati ad hoc altrove**,
  - un **background con alpha 0.10** (light) o **0.22** (dark),
  - un'**icona pesante** (filled) mentre tutti gli altri sono outline.
- Il cambio di tool è atomico: non esistono stati intermedi "in transizione" che durano più di 220ms.
- Il cursore/pointer assume la forma dello strumento attivo (puntina della penna, cerchio della gomma, crosshair del lazo).

**Anti-pattern:** Due strumenti attivi contemporaneamente, stato ambiguo ("forse è la penna, forse l'evidenziatore"), icon set miste (alcuni filled, altri outline, altri coloured per ragioni arbitrarie).

---

### Assioma 7 — Il Contenuto è Verticale, l'Interfaccia è Orizzontale

> **Il canvas cresce in tutte le direzioni. L'UI persiste sui bordi e non invade mai il centro.**

**Principio cognitivo:** Spatial Cognition (§22), Flow (§24), Antidoto alla Passività (§30).

**Applicazione UI:**
- Le zone di UI fisse occupano **al massimo il 20% dell'area viewport** (toolbar superiore + pannello laterale opzionale).
- Nessun pannello apre su overlay centrale (modal) durante la scrittura. I modal sono **riservati a operazioni one-shot** (export, condivisione, impostazioni), mai al workflow di studio.
- Le bolle-domanda dell'IA (Stadio 1) sono ancorate **ai nodi dello studente**, non al viewport — seguono il canvas in pan/zoom.
- I pannelli laterali (Layer Panel, Variable Manager) sono **resizable**, con larghezza memorizzata per canvas, e **collassabili a zero** lasciando solo una striscia di 24px.

**Anti-pattern:** Modal a tutto schermo per azioni frequenti, pannelli fissi che si espandono oltre il 30%, popup centrali che coprono il lavoro, toast persistenti.

---

### Assioma 8 — La Coerenza è il Vero Branding

> **Lo stesso gesto produce sempre lo stesso risultato. La stessa icona significa sempre la stessa cosa. Il colore di una funzione è scolpito nel marmo.**

**Principio cognitivo:** Jakob's Law (mental model), Cognitive Load estraneo (§9), Memoria transattiva.

**Applicazione UI — tavola di coerenza globale:**

| Dimensione | Regola | Fonte |
|------------|--------|-------|
| Colori semantici | Ogni tool ha UN colore, definito una sola volta | [`toolbar_tokens.dart`](fluera_engine/lib/src/canvas/toolbar/toolbar_tokens.dart) |
| Animation fast | 150ms | `animFast` |
| Animation normal | 220ms | `animNormal` |
| Animation slow | 300ms | `animSlow` |
| Activate curve | `easeOutCubic` | token |
| Deactivate curve | `easeInCubic` | token |
| Surface blur | sigma 20.0 | glassmorphism token |
| Surface opacity dark | 0.80 | token |
| Surface opacity light | 0.90 | token |
| Touch target | ≥ 44pt iOS / ≥ 48dp Android / ≥ 32px desktop | WCAG 2.5.5 |
| Border radius tools | 12px | design system unico |
| Border radius panels | 16px | design system unico |
| Border radius modal | 20px | design system unico |

**Anti-pattern:** Due curve di animazione diverse per la stessa azione, colori hard-coded dentro widget, "questo pulsante fa animazione da 180ms perché è più bello", bottoni di dimensioni diverse per azioni equivalenti.

---

### Assioma 9 — L'Imperfezione è Conservata, la Funzione è Perfetta

> **Il tratto a mano dello studente è sacro e non va mai "corretto". Ma l'infrastruttura intorno deve essere chirurgicamente precisa.**

**Principio cognitivo:** Desirable Difficulties (§5), Generation Effect (§3), Embodied Cognition (§23).

**Applicazione UI:**
- **Nessun auto-straighten, auto-shape, auto-cleanup** sui tratti. Una linea storta resta storta. Un cerchio imperfetto resta imperfetto.
- La **shape recognition** è un tool *separato* (viola) che l'utente attiva esplicitamente quando vuole la conversione.
- **L'handwriting recognition** è silenzioso: usato internamente per search/OCR/IA, **mai** per convertire il tratto visivo in testo digitato senza richiesta esplicita.
- Per contro: grid, guide, allineamenti dei pannelli UI, tipografia, icone, spaziatura — sono **rigorosamente precisi** a livello di pixel.

**Anti-pattern:** "Abbiamo raddrizzato la tua linea per te!", conversione automatica handwriting→testo dopo X secondi, suggerimenti "vuoi che rendiamo questo cerchio perfetto?".

---

### Assioma 10 — L'Apprendimento Viene Prima della Produttività

> **Fluera non è un'app di produttività. È una palestra cognitiva. Ogni volta che una scelta UX privilegia "fare prima" vs "imparare meglio", imparare meglio vince.**

**Principio cognitivo:** Principio Aureo dell'IA nell'Apprendimento (Parte III), Productive Failure (T4), Illusion of Fluency (§11).

**Applicazione UI:**
- Nessun "riassumi per me", "fai tu", "completa al posto mio" come azioni di primo livello.
- Funzioni che riducono lo sforzo cognitivo (auto-expand, auto-outline, template) sono **legittime solo in Stadio 2/3** (dopo lo sforzo autonomo), mai in Fase 1/2 della Parte VI.
- La Modalità Esame (Fog of War) è **più scomoda** della modalità normale — e questo è un feature, non un bug.
- Gli errori visibili (nodi rossi, correzioni, Ghost Map) sono celebrati visivamente come *progresso*, non nascosti come imbarazzi.

**Anti-pattern:** "Rendi la mia mappa più bella con un click", "Riassumi questa sessione in 3 bullet", streak/badge per "quante volte hai usato l'IA".

---

## PARTE II — Il Sistema Visivo Enterprise

> *L'enterprise visual level non è gold trim e gradient saturi. È la sensazione che ogni pixel è stato pesato. Linear, Arc, Craft, Cron, Figma — tutti condividono la stessa grammatica: tipografia sobria, sistema di spazio matematico, motion di 200-300ms con curve specifiche, colore usato come significato non come decorazione.*

### 2.1 Tipografia

**Regole:**
- **Un solo display family** per la UI (es. Inter, Geist, SF Pro). Mai più di uno.
- **Un family secondario monospace** solo per LaTeX, codice, timestamp, coordinate.
- **Nessun font "handwriting"** nella UI — l'handwriting vive SOLO sul canvas attraverso la penna dello studente.
- **Scala tipografica matematica** (modulo 1.25 o 1.333):
  - 11px · 12px · 14px · 16px · 20px · 24px · 32px — mai valori intermedi.
- **Pesi ammessi:** 400 (body), 500 (medium UI), 600 (semibold — titoli), 700 (bold — rarissimo, solo CTA primari). Vietati 300, 800, 900 nella UI.
- **Line-height:** 1.3 per titoli, 1.5 per body, 1.2 per UI control labels.
- **Letter-spacing:** 0 di default. Tracking positivo (+0.02em) solo su uppercase e micro-label.

**Anti-pattern:** Titoli in 5 pesi diversi, font decorativo nel nome app, testo fluido senza scala, italic usato per enfatizzare.

---

### 2.2 Colore — Il Sistema Semantico

**Fondamento:** Il colore **non è decorazione**. Ogni colore nel sistema ha un significato cognitivo e funzionale preciso. Un colore usato fuori dal suo significato è un bug.

**Palette semantica (ereditata da [`toolbar_tokens.dart`](fluera_engine/lib/src/canvas/toolbar/toolbar_tokens.dart)):**

| Colore | Significato | Dove può apparire | Dove NON può apparire |
|--------|-------------|-------------------|----------------------|
| **Blu-600** | Creazione primaria (penna, nodo base) | Tool attivo "pen", indicatori di scrittura | Errori, selezione, IA |
| **Rosso-600** | Distruzione (gomma, delete, errore grave) | Tool "eraser", undo critici, errore alta confidenza | Loading, neutro |
| **Viola-600** | Manipolazione / selezione | Lasso, shape recognition, LaTeX, recall, branch | Creazione primaria |
| **Ambra-500** | Navigazione / ausiliari | Ruler, pan, guide, warning non bloccante | CTA primari |
| **Ciano/Teal** | Media (immagini, audio, PDF) | Image tool, recording, search | Testo |
| **Smeraldo-600** | Testo digitale / successo | Digital text, conferme Stadio 1 | Errori |
| **Grigio-500** | UI neutra | Bordi pannelli, separator, placeholder | Feedback semantico |
| **Porpora AI** *(riservato)* | Output IA | Bolle socratiche, Ghost Map, overlay centaur | Qualsiasi contenuto utente |

**Intensità e alpha canonici:**
- Background attivo (light): base color @ 0.10
- Background attivo (dark): base color @ 0.22
- Border attivo: base color @ 0.45
- Ghost / suggerimento: base color @ 0.25
- Focus ring: base color @ 0.60, spread 2px

**Dark mode come prima classe.** Lo studio notturno è la norma, non l'eccezione. Il dark theme non è un "accessory" — deve essere progettato *prima* del light. Le opacità sopra sono tarate per dark. Il light theme le mantiene ma con blend su sfondo chiaro.

**Contrast WCAG:**
- Testo body: ≥ 4.5:1 (WCAG AA)
- Testo grande / icon: ≥ 3:1
- Focus ring: ≥ 3:1 contro entrambi gli stati adiacenti

**Anti-pattern:** Rainbow gradient su CTA, colore "brand" usato per errori, rosso che non significa distruttivo, blue+purple indistinguibili per un color-blind deuteranope.

---

### 2.3 Spacing / Grid

**Una sola scala:** **4px base** — tutti gli spazi sono multipli di 4.
- 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96.
- **Mai 5, 7, 10, 13, 15**. Se un designer vuole 10, si sceglie 8 o 12 dopo riflessione, mai si scappa dalla scala.

**Spacing semantico:**
- **Spazio intra-componente:** 4–8px (es. icona + label)
- **Spazio inter-componente correlato:** 12–16px (es. gruppo di tool)
- **Spazio tra sezioni:** 24–32px
- **Spazio tra pannelli:** 48–64px
- **Margine di respiro attorno al canvas:** 0px — il canvas fluisce fino al bordo del viewport. L'UI galleggia *sopra*.

**Grid su toolbar:** colonne di 48px esatti per ogni slot tool, con 4px di gutter. Nessun slot può uscire da questo ritmo.

---

### 2.4 Elevation e Glassmorphism

**Il sistema di elevation di Fluera ha 4 livelli, non di più:**

| Livello | Uso | Effetto |
|---------|-----|---------|
| **0 — piatto** | Canvas, bottoni secondari inline | nessuna ombra, nessun blur |
| **1 — emergente** | Toolbar, pannelli laterali | backdrop-blur 20px, surface @ 0.80/0.90, shadow molto sottile (blur 16, y-offset 4, alpha 0.08) |
| **2 — fluttuante** | Tool wheel, popover, context menu | backdrop-blur 24px, surface @ 0.85/0.92, shadow più marcata (blur 32, y-offset 8, alpha 0.14) |
| **3 — modale** | Dialog import/export, permissioni | backdrop-blur 32px sullo sfondo (dim 0.45 nero), dialog con shadow prominente |

**Glassmorphism responsabile:**
- Solo su superfici che coprono contenuto *non critico per la lettura*. Mai sotto testo denso.
- Blur statico, mai animato (le transizioni di blur costano GPU e rovinano il 60fps).
- Fallback semplice su low-end devices: surface solida con alpha 0.96 + hairline border.

---

### 2.5 Motion — Il Ritmo del Software

**Le tre durate (già nel design system):**
- `animFast = 150ms` — feedback immediato (hover, tap ripple, tooltip appear)
- `animNormal = 220ms` — cambi di stato principali (tool switch, panel open/close)
- `animSlow = 300ms` — transizioni di contesto (apertura tool wheel, overlay IA)

**Curve:**
- Apparizione / espansione: `easeOutCubic` (veloce all'inizio, dolce alla fine)
- Sparizione / collasso: `easeInCubic` (dolce all'inizio, veloce alla fine)
- Movimento fisico (drag, pan momentum): `easeOutQuart` + decelerazione naturale

**Leggi di motion:**
- **Nessuna animazione bloccante** — l'utente deve poter iniziare l'azione successiva durante la transizione precedente. Le animazioni sono informative, non prescrittive.
- **Reduced motion:** quando il sistema lo richiede (`MediaQuery.of(context).disableAnimations` o iOS/Android setting), tutte le animazioni collassano a 0ms o a un crossfade da 100ms massimo. I contenuti non devono sparire né perdersi.
- **Nessun bounce** su elementi funzionali. Il bounce è riservato a momenti di celebrazione rari (Stadio 3 ricordo corretto dopo streak lungo).
- **Nessuna parallax** nel canvas. La parallax rompe la cognizione spaziale (§22): la posizione codifica la memoria, se scorre diversamente l'àncora si perde.

**Anti-pattern:** Animazione di 800ms per un menu, spring bounce su hover, fade di 50ms che fa "strobe", motion "divertente" che distrae.

---

### 2.6 Iconografia

**Una sola libreria di icone** (es. Lucide, Phosphor Regular, SF Symbols su iOS — ma UNA sola per tutto il progetto).

**Regole:**
- **Weight unico:** Regular per tutto. Filled solo per "stato attivo". Mai mix arbitrario.
- **Griglia 24×24** per toolbar, **20×20** per dense UI, **16×16** per inline label.
- **Stroke width:** 1.5px o 2px — non si alternano dentro la stessa schermata.
- **Contorno:** le icone outline condividono la stessa curvatura (border-radius visivo equivalente).
- **Nessuna icona "carina" inventata.** Se non esiste un'icona chiara per un concetto, si usa una label testuale. Meglio "Ruler" scritto che un'icona incomprensibile.

**Anti-pattern:** Mix Font Awesome + Material + custom, icone da 18 e 22px nella stessa row, icone emoji (💡) nella UI produttiva.

---

### 2.7 Iconografia Cognitiva Riservata

Alcune feature di Fluera sono **uniche al prodotto** e meritano segnaletica grafica dedicata. Queste icone vivono in un sottoinsieme separato:

| Funzione | Segno visivo | Dove |
|----------|-------------|------|
| Ghost Map | Griglia a puntini fantasma, viola AI @ 0.30 | Stadio 2 |
| Fog of War | Sfumatura gaussiana sovrapposta, grigio caldo | Modalità Esame |
| Knowledge Flow | Nodi + archi animati | Zoom out massimo |
| Tap-to-Seek | Waveform in miniatura + timestamp | Nodi con audio ancorato |
| Cross-dominio | Freccia curva con glow lineare sottile | Ponti Passo 9 |
| Cognitive Scar (ipercorrezione consolidata) | Bordo doppio rosso + verde | Nodi corretti post-Stadio 2 |

Queste sono le "forme firma" di Fluera. Non vanno riutilizzate per nulla di generico.

---

## PARTE III — Le Due Modalità: Toolbar e Tool Wheel

> *Fluera offre due grammatiche di input mutualmente esclusive. La prima è istituzionale, la seconda è intima. Una è la grammatica dell'ufficio, l'altra è la grammatica del tatami.*

### 3.1 La Dualità e il Perché

La **Toolbar** è la UI tradizionale: una riga orizzontale o verticale di bottoni sempre visibile, pensata per dispositivi con puntatore preciso (mouse, trackpad) e per la scoperta iniziale. È la modalità **affidabile, discoverable, enterprise**.

La **Tool Wheel** è una UI radiale invocata con long-press sotto la penna: non occupa spazio stabile, appare dove serve, scompare quando non serve. È la modalità **immersiva, ergonomica, da flow**.

Il preference `WheelModePref` ([`wheel_mode_pref.dart`](fluera_engine/lib/src/config/wheel_mode_pref.dart)) determina quale delle due l'utente usa. **Le due modalità non coesistono nella stessa sessione.** L'utente sceglie il proprio linguaggio di input, e la UI lo rispetta.

**Perché non entrambe contemporaneamente?**
- Redundancy cognitiva — due percorsi per lo stesso comando → Hick's Law peggiorato, cognitive load aumentato.
- Competizione visiva — una toolbar sempre visibile + una wheel che appare rompono l'Assioma 2 (silenzio).
- Coerenza del gesto — il long-press ha un significato diverso in ciascuna modalità, deve essere riservato.

**Tabella decisionale per l'utente:**

| Contesto | Modalità consigliata |
|----------|---------------------|
| Desktop Mac/Windows con trackpad | Toolbar |
| Desktop con tavoletta grafica (Wacom) | Tool wheel |
| Laptop senza touch | Toolbar |
| iPad Pro + Apple Pencil | Tool wheel |
| Tablet Android + stylus | Tool wheel |
| iPhone/Android phone | Toolbar (wheel richiede spazio) |
| Prima volta in assoluto | Toolbar (discovery) |
| Sessione di studio profondo | Tool wheel |

### 3.2 Regole della Toolbar

**Posizionamento:**
- **Fixed top** oppure **pinned left** (scelta utente, persistente per workspace).
- Mai bottom durante scrittura attiva (interferisce col polso della mano dominante).
- Mai galleggiante (floating toolbar): rompe la coerenza spaziale e invade il canvas.

**Composizione:**
- **Top row:** back button, canvas title (in-place editable), quick actions (share/export su dispositivi dove lo spazio lo permette).
- **Tools area:** sequenza orizzontale di tool button, 48px ciascuno, gutter 4px. Ordine fisso: creazione (penna, matita, testo, forme) → selezione (lasso) → distruzione (gomma) → ausiliari (righello, pan) → media (immagine, PDF) → utility (layers, search, export) → AI.
- **Tab bar contestuale:** quando un tool è attivo, una seconda riga mostra le opzioni del tool (colori, spessore, pressione). Questa riga **appare con animazione da 220ms** e **scompare se nessun tool è selezionato per >3s**.

**Collapse:**
- Un chevron nell'angolo collassa la toolbar a una **striscia da 8px** con solo il colore del tool attivo visibile.
- Il gesto di collapse è memorizzato per workspace.
- Quando collassata, hover/tap sulla striscia la riespande in 150ms.

**Behaviour durante scrittura:**
- Auto-hide (opacità da 1.0 a 0.15) dopo 1500ms dall'ultimo tratto.
- Hover (desktop) o tap sulla zona (touch) la riporta a piena opacità in 150ms.

### 3.3 Regole della Tool Wheel

**Trigger:**
- **Long-press a 350ms** sul canvas con qualsiasi dito o penna.
- Il punto di long-press determina il centro della wheel → la wheel appare *sotto il pollice* dello studente, ergonomicamente.
- La prima apertura della sessione include un **haptic feedback medium** (tablet/mobile) — le successive, haptic light per non stancare.

**Anatomia:**
- **Anello principale (ring 1):** 8 item massimi — Brush, Text, Insert, Shape, Undo, Tools, Map, Atlas (vedi `RadialMenuItem` in [`canvas_radial_menu.dart`](fluera_engine/lib/src/canvas/overlays/canvas_radial_menu.dart)).
- **Sub-ring (ring 2):** compare con drag-out radiale sull'item del ring 1 che ha sub-items (Brush → Pen/Pencil/Marker/Highlighter/Charcoal/Watercolor/Airbrush/Oil).
- **Raggio ring 1:** 120px. Raggio ring 2: 180px. Gap: 16px.
- **Diametro minimo touchable per segmento:** 44pt lato più corto (Fitts' Law + WCAG).

**Feedback:**
- L'item sotto il dito: scala 1.08, bordo colore semantico del tool, haptic light.
- Gli altri item: opacità 0.75, scala 1.0.
- Il centro della wheel mostra **il label del tool evidenziato** in typography M14/semibold.

**Dismiss:**
- Rilasciare il dito → il tool evidenziato si attiva, wheel scompare in 150ms (easeInCubic).
- Drag al centro o fuori dall'anello → dismiss senza cambio tool.
- Dismiss sempre reversibile tramite undo universale.

**Feature gate:**
- Item in fase sperimentale (es. Multiview, GPU shaders beta) restano nascosti finché `V1FeatureGate` non li abilita. Mai mostrarli disabilitati nel ring — non è enterprise lasciare "grey ghost" in un pattern radiale.

### 3.4 Coerenza tra le Due Modalità

Anche se l'utente ne vede solo una, **le due grammatiche devono condividere:**

| Dimensione | Regola |
|------------|--------|
| Colori semantici | Identici (stessi token) |
| Ordine dei tool | Coerente: stessa gerarchia tool-primari / tool-selezione / tool-distruzione / tool-ausiliari |
| Shortcut tastiera | Identici in entrambe le modalità (B=brush, E=eraser, L=lasso, T=text, R=ruler…) |
| Stato attivo visivo | Stesso bordo + background @ 0.10/0.22 |
| Undo/Redo | Gestito allo stesso modo (Cmd+Z / due dita tap) |
| Tool disabilitati | Non compaiono in tool wheel; in toolbar sono disabled @ 0.35 solo se il contesto li richiede |

**Anti-pattern:** Tool wheel che usa il verde per la penna e toolbar che usa il blu. Shortcut che funziona solo in una modalità. Nomi diversi per lo stesso tool ("Brush" nella wheel, "Pen" nella toolbar).

### 3.5 Il Toggle tra Modalità

**Non deve essere un gesto rapido.** Cambiare modalità è una decisione di workflow, non un'azione frequente.

- Il toggle vive nelle **Impostazioni → Input**, mai come bottone primario nel canvas.
- Al cambio, un **tutorial di 2 step** (10s totali) mostra il gesto principale della nuova modalità. Disattivabile dopo la prima volta.
- Lo stato è **persistito per dispositivo** (un utente può preferire toolbar su Mac e wheel su iPad — è naturale).

---

## PARTE IV — Le Leggi del Daily Use

> *L'esperienza quotidiana di Fluera è misurata in micro-interazioni. Aprire l'app deve essere come entrare in una stanza che ricorda esattamente come l'avevi lasciata.*

### 4.1 Il Ritorno alla Stanza

**Il primo frame dopo l'apertura è un contratto con l'utente.**

Quando l'utente apre Fluera:
1. **Entro 400ms** il canvas dell'ultima sessione è visibile nella **identica posizione, zoom, stato pannelli, tool attivo**.
2. Il cursore appare dove era stato lasciato.
3. Nessuna splash animation che imponga il brand (Fluera non si celebra — lavora).
4. Nessun "Welcome back!" (rompe §1 Spacing e crea cringe).
5. Eventuali nodi Zeigarnik (§7) pulsano discretamente per riattivare la tensione cognitiva interrotta.

### 4.2 Salvataggio Silenzioso

- Il salvataggio è **automatico, continuo, invisibile**.
- Nessun "Save" button nel menu principale. Cmd+S è riservato per "checkpoint manuale" (snapshot denominato) con feedback minimale (piccolo tick nell'angolo per 800ms).
- Lo stato di sync mostra **un solo puntino**: verde (sincronizzato), ambra (in corso), rosso (conflitto — solo allora si apre un dialog).

### 4.3 Undo Universale

**Principio:** Nessuna azione deve essere irreversibile senza una conferma esplicita.

- **Cmd/Ctrl + Z** funziona in ogni contesto: tratto, spostamento, cambio colore, apertura pannello, drag di nodo, cancellazione.
- La cronologia è **per canvas**, non globale, e persiste tra sessioni per 30 giorni almeno.
- Il redo è **Cmd/Ctrl + Shift + Z** e mai **Cmd/Ctrl + Y** (scelta di campo: Shift+Z è multi-platform consistent).
- Operazioni distruttive (delete canvas, delete layer) usano la timeline di Fluera (storia branching): possono sempre essere recuperate dalla cronologia, anche dopo giorni.

### 4.4 Gestures Canoniche

**Sul canvas (touch/trackpad):**

| Gesto | Azione | Note |
|-------|--------|------|
| Tratto singolo con penna | Disegna con tool attivo | Palm rejection sempre attivo |
| Tap con dito | Seleziona nodo / dismiss overlay | Mai disegna (regola assoluta in wheel-mode) |
| Two-finger pan | Pan del canvas | Sempre, mai modificato da tool attivo |
| Pinch | Zoom del canvas | Centro del pinch = pivot |
| Two-finger tap | Undo rapido | Alternativa touch a Cmd+Z |
| Three-finger tap | Redo rapido | Alternativa touch |
| Long-press (wheel mode) | Apre tool wheel | 350ms soglia |
| Long-press (toolbar mode) | Apre context menu nodo | 500ms soglia |
| Double-tap su nodo | Entra in edit mode | Universale |

**Da tastiera (desktop):**
- **Barra spaziatrice tenuta:** pan temporaneo (come in Figma/Illustrator)
- **Z tenuto:** zoom temporaneo con trackpad
- **Cmd + 0:** fit-to-selection (mai auto all'apertura!)
- **Cmd + 1:** zoom 100%
- **Cmd + K:** command palette (se esiste) — **mai invocata se si sta scrivendo**

**Regole inviolabili:**
- Un gesto = un'azione. Se un gesto fa cose diverse in contesti diversi, l'utente ha perso fiducia.
- Nessun gesto "segreto" non documentabile. Se esiste un shortcut, appare nelle Impostazioni → Scorciatoie.

### 4.5 Onboarding senza Tutorial

**Principio:** Il tutorial migliore è l'assenza di tutorial. La curva di discovery emerge dall'interfaccia.

- **Primo avvio:** canvas vuoto, toolbar completa visibile (anche se la preference è wheel), 3 elementi discreti:
  - Un floating tip "Prova a scrivere con la penna" che scompare al primo tratto.
  - Un mini-indicatore sulla toolbar "← Gli strumenti sono qui".
  - Un bottone "Impostazioni input" per chi vuole cambiare modalità subito.
- **Mai tour modali bloccanti con "Next / Next / Next".**
- **Progressive disclosure:** feature avanzate (Ghost Map, Fog of War, Apprendimento Solidale) appaiono nella UI solo dopo un trigger di proficienza (es. dopo N nodi creati, dopo prima settimana).
- **Help sempre raggiungibile via Cmd+?** che apre una command palette searchable, mai un overlay a tutto schermo.

### 4.6 Notifiche — Il Diritto al Silenzio

**Fluera è un'app silenziosa per design.**

- **Nessuna notifica push** per default. Eventuali reminder SRS sono **opt-in esplicito**.
- **Nessun badge rosso** sull'icona dell'app.
- **Nessun banner "Hai X nodi da ripassare oggi"** all'apertura.
- Le notifiche legittime (conflitto di sync, errore export) appaiono come toast in basso-destra, dismissabili con X, con auto-dismiss a 6s, mai stacked più di 2 alla volta.

### 4.7 Accessibilità come Requisito, non Feature

- **Contrast ratio ≥ 4.5:1** per body text (WCAG AA).
- **Touch target ≥ 44×44pt** per qualsiasi bottone interattivo (WCAG 2.5.5).
- **Focus ring visibile** su ogni elemento navigabile da tastiera, stile coerente (2px, colore AI/accent, offset 2px).
- **Screen reader labels** su tutti i tool (mai lasciare solo l'icona).
- **Reduced motion:** tutte le animazioni collassano a crossfade 100ms o meno.
- **Color-blind safe:** ogni stato critico è codificato **con almeno due canali** (colore + icona / forma / testo). Errore = rosso + icona X + bordo tratteggiato.
- **Internationalization (l10n):** ogni stringa passa da `gen/l10n`. Nessun testo hard-coded. Layout RTL-ready per arabo/ebraico.
- **Font scaling:** l'app rispetta la preferenza di sistema (Dynamic Type su iOS, Font scale Android) entro il 0.85×–1.3×.
- **Keyboard parity:** ogni funzione invocabile da mouse/touch ha un equivalente da tastiera, salvo il gesto stesso del disegno.

### 4.8 Performance Budget

**I numeri che non si negoziano:**

| Metrica | Budget |
|---------|--------|
| Cold start → canvas interattivo | ≤ 1.2s (desktop) / ≤ 1.8s (mobile) |
| Warm open → canvas interattivo | ≤ 400ms |
| Frame rate durante drawing | 60fps (120fps dove supportato) |
| Frame rate durante pan/zoom | 60fps, dropped frames ≤ 2% |
| Input latency penna | ≤ 10ms (GPU overlay) |
| Memory idle con canvas medio | ≤ 400 MB |
| Memory idle con canvas grande (>5k nodi) | ≤ 900 MB |
| Binary size app | ≤ 80 MB iOS / ≤ 100 MB Android |

Ogni feature nuova deve passare un check di performance prima del merge. Il canvas infinito (Parte VIII della teoria — un canvas = tutta la triennale) è il worst-case sempre da verificare.

---

## PARTE V — Le Leggi Anti-Pattern (Cosa Non Fare Mai)

> *Quello che NON fai è forse più importante di quello che fai. Ogni anti-pattern qui elencato è visto in app concorrenti — ed è esattamente il motivo per cui non sono Fluera.*

### 5.1 Anti-Pattern Enterprise

| Anti-pattern | Perché è sbagliato | Alternativa |
|--------------|--------------------|-------------|
| Gradient saturi / rainbow button | Decorazione senza significato; rumore visivo | Colore semantico solido |
| Skeuomorfismo gratuito (texture carta, legno) | Distrae, affatica, data il prodotto | Piatto + glassmorphism controllato |
| Layout "centrato vetrina" (hero section) | Fluera è uno strumento, non una landing page | Apertura diretta al workspace |
| Onboarding modali 10-step | Impone complessità prima del valore | Discovery nell'uso reale |
| Popup "Rate us" dopo X giorni | Rompe Assioma 2 + Assioma 10 | Link passivo in About |
| Micro-transaction UI aggressiva | Tradimento della fiducia | Modello a subscription chiara |
| Dashboard con 20 widget | Cognitive overload | Canvas come home |
| Menu hamburger su desktop | Scomparsa delle affordance | Toolbar esplicita |
| Login forzato per vedere il prodotto | Attrito pre-valore | Canvas locale anche senza account |

### 5.2 Anti-Pattern Cognitivi (Fluera-Specific)

| Anti-pattern | Principio violato | Perché è particolarmente grave |
|--------------|-------------------|--------------------------------|
| "Summarize with AI" button sempre visibile | §11 Illusion of Fluency, §15 Cognitive Offloading | Amplifica il vizio che Fluera combatte |
| Auto-format handwriting → digital text | §3 Generation, §23 Embodied | Cancella il lavoro neurobiologico |
| Streak / daily goal dashboard | T2 Autodeterminazione — esterocentrizza la motivazione | Trasforma lo studio in chore |
| Leaderboard pubblica tra studenti | §12 Growth Mindset sabotato (focus su risultato vs sforzo) | Ansia competitiva |
| "Suggested next action" persistente | §30 Antidoto passività | Restituisce la passività all'IA |
| Template "mind map vuoto" con struttura precostruita | §5 Desirable Difficulties, §22 Cognizione Spaziale | Ruba allo studente l'atto costitutivo |
| Auto-arrange dei nodi | §22 Place Cells | Distrugge letteralmente il Palazzo della Memoria |
| "Pulisci il canvas" / rimuovi nodi inutilizzati | Tutti | Il canvas è diario, ogni nodo è traccia |
| Notifiche "Hai dimenticato X" prima del tentativo di recupero | §2 Active Recall | Uccide il retrieval practice |
| AI che corregge mentre scrivi | §3, §4 Ipercorrezione, §5, §24 Flow | Devastante |

### 5.3 Anti-Pattern Commerciali

- **Paywall sul core cognitivo** — il ciclo Passi 1-4 deve essere sempre gratuito. Monetizzi su cloud sync, collaborazione, export avanzati, IA premium. Mai sul meccanismo di apprendimento.
- **Downgrade percepito** — se un utente scende di piano, il suo canvas resta leggibile e modificabile. Si disattivano solo funzioni *opzionali*.
- **Dark pattern retention** — annullare l'abbonamento dev'essere visibile quanto sottoscriverlo, e non richiedere più di 2 click.

---

## PARTE VI — Gli Stati Visivi Speciali

> *Fluera ha modalità cognitive peculiari che nessun'altra app ha. Ognuna merita un linguaggio visivo dedicato — coerente col design system, ma riconoscibile a colpo d'occhio.*

### 6.1 Stato di Scrittura Attiva

**Trigger:** penna tocca schermo, o mouse in drag, o keyboard focus su text node.

**UI:**
- Toolbar/wheel fade-out a opacity 0.15 entro 150ms.
- Pannelli laterali collassano a striscia 8px.
- Cursor del sistema sparisce (desktop).
- **Nessun** indicatore AI, nessun suggerimento, nessuna bolla.
- L'unico elemento visibile oltre al canvas è l'indicatore di pressione/angolo della penna (opzionale, in alto a destra, opacity 0.40).

### 6.2 Stato Post-Tratto (Affordance Passive)

**Trigger:** 3 secondi dopo l'ultimo tratto senza nuova azione.

**UI:**
- Toolbar riemerge al 100% opacity.
- Sul blocco appena scritto: piccoli "handles" compaiono ai quattro angoli (4×4px, colore tool attivo @ 0.50) per permettere resize/move **se l'utente ci passa sopra**.
- Se il blocco contiene un `?` o un contorno tratteggiato → glow pulsante leggero (Zeigarnik loop visivo).

### 6.3 Stato di Interrogazione Socratica (Stadio 1)

**Trigger:** utente invoca "Mettimi alla prova".

**UI:**
- **Bolle-domanda IA** appaiono ancorate ai nodi rilevanti: pill 24px di altezza, background porpora AI @ 0.20, border porpora AI @ 0.45, testo in porpora AI @ 1.0.
- Slider di confidenza (1-5) appare vicino alla bolla: 5 cerchi vuoti, tap per attivare, colore verde in crescita.
- Nodi interrogati pulsano con contorno ambra (domanda aperta), poi verde (risposta data), rosso (errore scoperto — con haptic medium per lo shock dell'ipercorrezione §4).

### 6.4 Stato di Confronto Centauro (Stadio 2 — Ghost Map Overlay)

**Trigger:** utente invoca "Confronta".

**UI:**
- Un **toggle strip** in alto ("Ghost Map attiva") con X per dismiss istantaneo. Sempre visibile.
- **Nodi mancanti** 🔴: sagoma tratteggiata rossa (dash 4-4) nella posizione suggerita, contenuto nascosto (blur totale). Tap → richiede allo studente di scrivere la propria ipotesi prima di rivelare.
- **Connessioni errate** 🟡: alone giallo attorno alla freccia, con un piccolo "?" nel mezzo.
- **Nodi corretti** 🟢: bordo verde sottile (1px) @ 0.60 — feedback positivo *misurato*.
- **Connessioni mancanti** 🔵: linee punteggiate blu (opacity 0.50) tra nodi dello studente. Lo studente le "solidifica" disegnando sopra con la penna.
- **Shock visivo:** i nodi ad alta confidenza dichiarata risultati errati pulsano con un'onda rossa a 300ms, haptic medium, suono opzionale discreto. Quando lo studente corregge, la cicatrice cognitiva resta visibile (bordo doppio rosso+verde).

### 6.5 Stato di Fog of War (Modalità Esame)

**Trigger:** utente attiva esplicitamente Modalità Esame su una zona.

**UI:**
- La zona viene coperta da un **blur gaussiano** (σ=14) con un overlay scuro @ 0.25.
- Le sagome dei nodi restano visibili come "ghost shapes" ma il contenuto è illeggibile.
- Un counter in alto mostra: "Visitati 0 / N · Verdi 0 · Rossi 0".
- Tap su una sagoma → chiede allo studente di dichiarare "Ricordo" o "Non ricordo" prima di rivelare.
- Rivelazione corretta: swipe di luce verde sulla sagoma (300ms).
- Rivelazione errata: lampo rosso + haptic medium.
- Al termine: la nebbia si alza in 600ms (crossfade) e la mappa di padronanza resta visibile finché l'utente non dismiss.

### 6.6 Stato di Apprendimento Solidale

**Trigger:** collaboratore entra (lettura / co-costruzione).

**UI:**
- **Avatar ring 24px** in alto a destra per ogni collaboratore presente.
- **Cursore-fantasma** del visitatore: un piccolo puntatore con il suo colore personale + label nome (auto-hide dopo 3s di inattività).
- Se è in modalità co-costruzione: i suoi tratti vengono resi con il suo colore personale, mai sovrascrivibili dall'altro.
- **Chat opzionale**: pannello laterale destro collassabile, toggle con shortcut.
- Quando il collaboratore lascia: notifica minima "X ha lasciato il canvas" in toast da 3s.

### 6.7 Stato Offline / Errore

- **Offline:** un singolo banner sottile (24px) sopra la toolbar, ambra, testo "Offline — il lavoro è salvato localmente". Dismissabile, riappare solo se si tenta un'azione cloud.
- **Errore grave (conflitto sync, crash recovery):** dialog modale, contenuto chiaro con 3 opzioni massimo ("Mantieni locale" / "Usa remoto" / "Confronta"), mai linguaggio tecnico ("Error 500: connection refused").
- **Errore non bloccante (export fallito):** toast 6s con bottone "Riprova".

---

## PARTE VII — Matrice di Coerenza Toolbar ↔ Wheel

> *Questa matrice è un contratto. Qualsiasi deviazione è un bug di coerenza.*

| Aspetto | Toolbar | Tool Wheel | Coerente? |
|---------|---------|-----------|-----------|
| Colore "penna" attivo | blue-600 | blue-600 | ✅ obbligatorio |
| Colore "gomma" attivo | red-600 | red-600 | ✅ |
| Colore "lazo" attivo | violet-600 | violet-600 | ✅ |
| Shortcut B = brush | ✅ | ✅ | ✅ |
| Shortcut E = eraser | ✅ | ✅ | ✅ |
| Animation switch tool | 220ms easeOutCubic | 220ms easeOutCubic | ✅ |
| Label "Eraser" | testo visibile | testo nel centro wheel | ✅ stessa stringa l10n |
| Undo | Cmd+Z / button | Cmd+Z / two-finger tap | ✅ |
| Feature-gated tool | disabled @ 0.35 + tooltip | assente dal ring | ⚠️ intenzionalmente diverso |
| Ordine semantico tool | creazione → selezione → distruzione → aux | uguale, mappato su angoli fissi | ✅ |
| Feedback haptic su tap | no (desktop) / light (touch) | light sempre | ⚠️ intenzionalmente diverso |
| Scomparsa durante scrittura | fade-out | già invisibile | ✅ equivalente |

**Chi valida questa matrice?** Un design review obbligatorio per ogni PR che tocca tool, colori, o gesture. Nessun bypass.

---

## PARTE VIII — Il Linguaggio Visivo delle Parti Speciali

### 8.1 Nodi e Tipologia

Ogni nodo del canvas ha uno **stato visivo** che codifica più dimensioni:

| Stato | Segno |
|-------|-------|
| Nodo nuovo (scritto nella sessione) | Tratto a piena opacità |
| Nodo consolidato (Stadio 3, ricordato correttamente più volte) | Opacità 0.70 — il cervello lo possiede |
| Nodo debole (dimenticato nell'ultimo ripasso) | Bordo ambra discreto + glow pulsante lento |
| Nodo incompleto (Zeigarnik) | Contorno tratteggiato ambra |
| Nodo corretto dopo ipercorrezione | Bordo doppio: strato esterno rosso (traccia errore), strato interno verde (correzione) |
| Nodo con audio ancorato (§32) | Waveform in miniatura 8px nell'angolo + timestamp |
| Nodo cross-dominio (ponte §9) | Glow laterale sottile sulla freccia uscente |

### 8.2 Frecce e Connessioni

- **Freccia corta (intra-zona):** solid line, 1.5px, colore neutro grigio-500.
- **Freccia lunga (cross-dominio):** curva Bézier, 2px, gradient sottile dal colore della zona A al colore della zona B.
- **Freccia suggerita dall'IA:** tratteggiata (dash 6-4), porpora AI @ 0.50 — richiede azione manuale dello studente per solidificarla.
- **Freccia errata (Ghost Map):** alone giallo, "?" al centro, invita alla correzione.

### 8.3 Zoom Semantico — Level of Detail

Tre break-point di zoom, con LOD crescente:

| Zoom | Che cosa si vede | Principio |
|------|------------------|-----------|
| **Satellite (< 30%)** | Solo macro-zone, label di materia, nodi-monumento più grandi | Cognizione sistemica |
| **Quartiere (30–100%)** | Cluster di nodi, connessioni principali, titoli | Categorizzazione |
| **Dettaglio (>100%)** | Contenuto pieno, formule, scrittura a mano in piena definizione | Precisione analitica |

La transizione tra livelli è continua (mai "snap"), con crossfade di 200ms dei livelli di dettaglio.

---

## PARTE IX — Principi di Progettazione Universali (Ricontestualizzati)

> *Le classiche leggi UX di Nielsen/Norman/Hick/Fitts, riscritte per il contesto Fluera.*

- **Fitts' Law:** Tool wheel sotto il pollice > toolbar distante. Target ≥ 44pt.
- **Hick's Law:** Ring 1 della wheel max 8 item. Toolbar tools primari ≤ 9.
- **Miller's Law (4±2):** Non mostrare mai più di 5 scelte simultanee senza gerarchizzarle.
- **Jakob's Law:** Cmd+Z, Cmd+S, Cmd+Shift+Z, Cmd+F sono sacri. Non innoviamo dove l'utente ha già un mental model.
- **Doherty Threshold (400ms):** Ogni azione ha feedback entro 400ms, o mostra progresso.
- **Tesler's Law:** Ogni sistema ha complessità irriducibile. La complessità del canvas infinito vive *nel cervello dello studente*, non nell'UI. L'UI resta minimale.
- **Aesthetic-Usability Effect:** UI bella = percepita più usabile. Ma attenzione: bello ≠ decorato. Bello = ritmo, coerenza, respiro.
- **Peak-End Rule:** La fine di una sessione (Stadio 2 Ghost Map con correzioni) è ciò che lo studente ricorda. Merita cura eccezionale.
- **Gestalt Proximity/Similarity:** Nodi correlati → vicini (lo studente decide, non l'IA). Tool simili → stesso colore.
- **Errore recoverable:** Tutto è undo-able. Nessuna azione è mai "definitiva" senza double-confirm.

---

## PARTE XI — Voce, Copy e Microcopy

> *L'enterprise si sente prima nella lingua che negli shadow. Un prodotto scritto male sembra amatoriale anche se è graficamente impeccabile.*

### 11.1 La Voce di Fluera

Fluera parla come **un professore esperto che si fida dello studente**: competente, discreto, rispettoso del tempo altrui. Mai commerciale, mai scolastico, mai paternalista.

| Dimensione | Regola |
|------------|--------|
| Persona | "Tu" sempre, mai "Lei" né "voi" — la relazione è diretta ma non familiare |
| Tempo verbale | Presente indicativo per azioni, passato prossimo per completamenti |
| Voce | Attiva sempre. "Salvo" non "Il salvataggio è in corso" |
| Lunghezza | Brevissima. Ogni parola deve guadagnarsi il suo spazio |
| Sentimento | Neutro competente. Mai entusiasta ("Fantastico!"), mai allarmista ("Attenzione!"), mai scusante ("Ci dispiace molto...") |

**Anti-pattern:** "Benvenuto, {nome}! Sei pronto per una nuova giornata di apprendimento?", "Oops! Qualcosa è andato storto 😅", "Ottimo lavoro! 🎉".

### 11.2 Button Labels

- **Verbi imperativi, una sola parola dove possibile:** "Salva", "Esporta", "Annulla", "Elimina", "Crea".
- **Verbo specifico per azioni distruttive:** "Elimina" (permanente), "Archivia" (recuperabile), "Rimuovi" (da contesto, l'entità resta). Mai interscambiabili.
- **CTA primaria per dialog:** riprende il verbo dell'azione, mai "OK" generico.
  - Sbagliato: "Vuoi eliminare questo canvas? [Annulla] [OK]"
  - Giusto: "Elimina definitivamente '{nome}'? [Annulla] [Elimina]"

### 11.3 Error Messages — La Formula

Ogni messaggio d'errore segue la struttura a 3 parti:

```
[Cosa è successo] + [Perché è rilevante] + [Cosa puoi fare]
```

**Esempi:**
- ❌ "Error 500: Network request failed"
- ✅ "Il canvas non si è sincronizzato. Le modifiche sono al sicuro sul dispositivo. Riproveremo automaticamente."

- ❌ "Invalid password"
- ✅ "La password non è corretta. Riprova o reimpostala."

**Mai:**
- Codici d'errore nudi come primo livello
- Linguaggio che colpevolizza l'utente ("Hai sbagliato...")
- Messaggi che non offrono un passo successivo
- Errori generici ("Something went wrong") senza alternativa

### 11.4 Microcopy Critica

| Contesto | Regola | Esempio |
|----------|--------|---------|
| Empty state invitante, mai istruttivo | "Lo spazio è tuo. Inizia dove ti sembra naturale." | non "Clicca qui per creare il tuo primo nodo" |
| Loading specifico | "Carico il canvas di Chimica Organica" | non "Caricamento..." |
| Tooltip al hover | Aggiunge valore, non ripete il label | "Gomma · E · Tieni Shift per area" |
| Conferma distruttiva | Esplicita la conseguenza numerica | "Elimina 23 nodi e 14 connessioni" |
| Placeholder input | Mostra struttura attesa | "cerca concetti, nodi, canvas…" non "inserisci query" |

### 11.5 Internazionalizzazione (l10n)

- **Tutte le stringhe via `gen/l10n`**, zero hard-coding.
- **Plurali via ICU MessageFormat** (`{count, plural, one {1 nodo} other {# nodi}}`) — mai concatenazione.
- **Gender-aware** dove l'italiano lo richiede.
- **Test layout con +30% lunghezza** (tedesco) e **RTL** (arabo, ebraico) prima di ogni release.
- **Locale date/time:** 24h Italia, 12h USA. Mai hardcoded.
- **Target iniziali:** IT, EN, ES. Priorità basate sul bacino d'utenza beta, non su tassi di conversione ipotetici.

---

## PARTE XII — Gli Stati dell'Interfaccia

> *Uno stato di UI mal progettato è peggiore di nessuno stato. Ogni istante in cui l'app non è nel suo stato "primario" è un momento di verità.*

### 12.1 Empty States

Gli empty state in Fluera sono **invitazionali**, non istruttivi. Non spiegano cosa fare — invitano a cominciare.

| Contesto | UI |
|----------|-----|
| Canvas vuoto (prima volta) | Superficie completamente vuota. Un tip discreto che scompare al primo tratto. |
| Canvas vuoto (sessioni successive) | Vuoto totale. Zero tip. L'utente sa cosa fare. |
| Library vuota | Un solo bottone grande centrato: "Crea il tuo primo canvas". Nessun template. Nessuna demo. |
| Search senza risultati | "Nessun risultato per '{query}'. Prova sinonimi o espandi la ricerca cross-canvas." |
| Selezione vuota in context action | Il menu non si apre. Il gesto viene ignorato. |
| AI senza domande da porre (raro) | "Il tuo canvas è già molto completo o molto sparso. Aggiungi qualche nodo per darmi materiale." |

**Anti-pattern:** illustrazioni cartoonesche, mascotte, "It looks like you don't have any canvases yet! Create one to get started 🚀".

### 12.2 Loading States

**Principio:** Il loading ideale è *invisibile*. Quando è inevitabile, è *specifico*.

- **< 400ms:** nessun indicatore. L'utente non se ne accorge (Doherty Threshold).
- **400ms – 2s:** skeleton coerente con il layout finale. Mai spinner generico.
- **2s – 10s:** skeleton + testo specifico ("Importo pagina 12 di 48").
- **> 10s:** progress bar determinata se la durata è conosciuta, bottone "Annulla" sempre presente.

**Skeleton coerenti, non decorativi:**
- Un nodo in caricamento = rettangolo con bordo dashed del colore tool, stessa dimensione attesa.
- Pannello in caricamento = righe pulsanti nello stesso layout del contenuto finale.
- Mai shimmer su oggetti che dureranno < 400ms (blink effect = rumore visivo).

**Anti-pattern:** spinner a tutto schermo che copre il canvas, "Loading... 0%... 0%... 0%... 99%", shimmer su bottoni.

### 12.3 Error States

| Gravità | UI |
|---------|-----|
| **Info** (es. "Offline, lavoro salvato localmente") | Banner 24px sopra toolbar, colore ambra @ 0.20. Auto-dismiss al ripristino. |
| **Non-bloccante** (es. "Export fallito") | Toast 6s in basso-destra con bottone "Riprova". |
| **Recuperabile** (es. "Conflitto sync") | Dialog con 2-3 opzioni chiare, mai più. |
| **Bloccante** (es. "Licenza scaduta") | Schermata dedicata, sempre con percorso di risoluzione. |
| **Fatale** (rarissimo, es. corruzione dati) | Modal con contatto supporto + export locale dei dati. |

**Retry policy visibile:** "Riproverò automaticamente tra 30s" è più rassicurante di un silenzio che nasconde il retry.

### 12.4 Success States

**Regola d'oro:** i successi quotidiani sono **silenziosi**. Solo i momenti di svolta meritano celebrazione — e anche quelli, misurata.

| Success | Feedback |
|---------|----------|
| Save manuale (Cmd+S) | Tick 12px nell'angolo per 800ms, haptic light |
| Export completato | Toast 3s con bottone "Apri file" |
| Stadio 3 recall corretto | Swipe di luce verde sul nodo (300ms), haptic success, nessun testo |
| Primo canvas completato (milestone) | Toast celebrativo 4s, una sola volta nella vita |
| Ghost Map ≥60% corretta | Badge discreto nella timeline, non permanente |

**Mai:**
- Confetti, coriandoli, fuochi d'artificio.
- Suoni di celebrazione ricorrenti.
- Modal "🎉 Congratulazioni!" che interrompono il flow.
- Streak counter visibile che genera ansia.

### 12.5 Transition States

- Ogni cambio di stato ha un'animazione di entrata ≤ 220ms.
- Mai "jump" improvviso tra skeleton e content — crossfade 200ms minimo.
- Stati concorrenti (es. loading + toast errore) si compongono, non si sovrappongono: un solo *stato primario* alla volta.

---

## PARTE XIII — Navigazione Globale

> *L'enterprise moderno si naviga con la tastiera. Linear, Notion, Arc, Raycast — tutti hanno una command palette. Fluera non è un'eccezione.*

### 13.1 Command Palette (Cmd/Ctrl + K)

**Anatomia:**
- Dialog centrato, 640px × auto-height, max 480px altezza.
- Input in alto con placeholder "cerca comandi, canvas, nodi…".
- Lista risultati sotto, raggruppati per categoria (Comandi · Canvas · Nodi · Impostazioni · Aiuto).
- Ogni risultato mostra: icona, label, shortcut (se esiste), categoria.
- Navigazione solo tastiera: ↑/↓, Enter, Esc.

**Ranking:**
- History personale pesata (ultimi 30 giorni).
- Fuzzy match con punteggio.
- Frequency bias — comandi usati spesso salgono.
- Zero dipendenza da cloud: funziona offline.

**Contenuto:**
- **Tutti** i comandi della toolbar e della wheel, con lo stesso nome.
- Navigazione: "Vai a canvas…", "Apri zona Chimica Organica".
- Impostazioni: "Cambia modalità input", "Attiva focus mode".
- Azioni contestuali: "Elimina selezione", "Esporta selezione".
- Help: qualsiasi voce della documentazione.

**Regola di invocabilità:** Cmd+K non funziona durante la scrittura attiva (penna sullo schermo). Si attiva solo quando l'utente ha chiaramente "staccato". Questo protegge l'Assioma 2.

### 13.2 Library e File Management

**Vista default:** grid di canvas con thumbnail (snapshot dell'ultima viewport visibile — non del canvas intero, per preservare memoria spaziale).

**Ordinamento:** Ultimo aperto (default) · Ultimo modificato · Nome · Dimensione. Scelta persistente per utente.

**Organizzazione:**
- **Pin** per canvas prioritari (max 5).
- **Cartelle** opzionali, trascinabili, nestate fino a 3 livelli (oltre è cognitive load).
- **Tag** colorati, applicabili a più canvas. Mai richiesti.
- **Archive** ≠ Delete. Archive conservato 90+ giorni in "Archivio", recuperabile con un click. Delete richiede conferma esplicita + timer di grazia 24h.

**Bulk actions:** multi-select (Shift+click, Cmd+click, rubber band), azioni comuni (archivia, tag, esporta, duplica).

### 13.3 Search

**Tre livelli di search, un'unica interfaccia:**

1. **Title search:** match veloce sul nome del canvas — risultati istantanei < 50ms.
2. **Text search:** full-text sui nodi digitali + OCR delle handwriting convertite in indice (invisibile all'utente).
3. **Handwriting search:** query in testo, match su handwriting via OCR indicizzato.

**Risultati:**
- Miniatura del cluster rilevante (non solo snippet testuale — la posizione spaziale fa parte del match).
- Snippet con evidenziazione del match.
- Bottone "Apri qui" che porta **esattamente alla posizione** del match nel canvas, non all'inizio.

**Search nel canvas aperto:** Cmd+F, overlay in alto, iter con ↑/↓ attraverso i match, ciascuno con flash visivo sulla posizione.

### 13.4 Deep Links

Ogni canvas (e ogni posizione) è un URL:
```
fluera://canvas/{id}?x=1024&y=2048&zoom=0.8
```

- Copia link → porta all'identico punto.
- Shareable in chat, email, note.
- Deep link esterni (browser) aprono l'app installata o redirect al web preview.

---

## PARTE XIV — Form Factors, Piattaforme e Cross-Device

> *Fluera gira su 6 piattaforme. Una UI che va bene su tutte è un compromesso. Sei UI che rispettano ognuna la propria piattaforma sono enterprise.*

### 14.1 Le Sei Classi di Form Factor

| Form factor | Canvas | UI primaria | Gesti dominanti |
|-------------|--------|------------|----------------|
| **Desktop large** (≥1440px) | ~75% viewport | Toolbar top + 2 panels laterali | Mouse + tastiera |
| **Laptop** (1024–1440px) | ~85% viewport | Toolbar top compatta, panels slide-over | Trackpad + tastiera |
| **Tablet landscape** (iPad Pro 12.9") | ~100% viewport | Toolbar OR wheel | Penna + multi-touch |
| **Tablet portrait** (iPad 11") | ~100% viewport | Wheel preferita | Penna + multi-touch |
| **Phone** (≥375px) | ~100% viewport | Wheel only + bottom sheet | Touch + stylus (raro) |
| **Web** (browser) | adattivo | Toolbar top | Mouse + tastiera |

**Regola del 100%:** sui dispositivi tablet/phone il canvas occupa il 100% del viewport. La UI galleggia sopra (Assioma 7).

### 14.2 Platform Conventions (Rispettate)

Fluera segue le convenzioni native di ogni OS. Nessuna "app a-la-web unificata" che ignora le differenze.

| Piattaforma | Convenzione rispettata |
|-------------|----------------------|
| **macOS** | Traffic lights, menu bar system, Cmd shortcuts, swipe back trackpad, Mission Control support |
| **Windows** | Title bar con controls, Alt+F4, Ctrl shortcuts, snap zones, Fluent scrollbar |
| **iOS** | Swipe back edge, Dynamic Type, haptic Taptic Engine, Files app integration, Stage Manager |
| **iPadOS** | Pencil hover (iPad M2+), Scribble, Stage Manager multi-window, external keyboard shortcuts |
| **Android** | Predictive back (14+), Material motion, system Share sheet, File provider |
| **Linux** | GNOME/KDE conventions, XDG portals per file system, Wayland input |
| **Web** | Browser history integrata con navigation stack, keyboard shortcut coerenti, install as PWA |

**Anti-pattern:** Cmd+W su Windows, traffic lights su Linux, swipe-to-dismiss su desktop.

### 14.3 Cross-Device Continuity

**Il problema:** un utente inizia a prendere appunti su iPad in aula e vuole continuare su Mac in biblioteca.

**La soluzione Fluera:**
- Stato sincronizzato in near-real-time: posizione viewport, zoom, tool attivo, pannelli aperti.
- **Ma la penna segue il device**: un tratto iniziato su un dispositivo non si teletrasporta — si chiude quando lasci il device.
- **Handoff opt-in**, non automatico: aprire Fluera sul device B mostra "Stavi lavorando su '{canvas}' su iPad 2 minuti fa. Continuare da lì?"
- **Conflict resolution CRDT** per contenuto concorrente (stroke/nodi): merge non distruttivo, ogni stroke preservato con ownership.
- **Last-writer-wins** solo per operazioni atomiche idempotenti (spostamento, cambio colore).

### 14.4 Responsive Breakpoints Interni

Ogni pannello ha breakpoint di collasso:

| Larghezza disponibile | Toolbar | Layer Panel | Variable Manager |
|----------------------|---------|-------------|------------------|
| ≥ 1280px | Full | Expanded | Expanded |
| 1024–1280px | Full | Expanded | Collapsed to strip |
| 768–1024px | Compact (icon only) | Slide-over on demand | Hidden, accessible via shortcut |
| < 768px | Bottom sheet / wheel | Modal | Modal |

---

## PARTE XV — Canali Sensoriali: Haptic, Audio, Focus Mode

### 15.1 Il Linguaggio Haptic

Il feedback tattile ha la stessa dignità del feedback visivo. Fluera definisce un **vocabolario haptic** coerente.

| Tipo | Uso | Esempi |
|------|-----|--------|
| **Light** | Conferma leggera | Tap tool, hover wheel item, selezione nodo |
| **Medium** | Cambio stato significativo | Attivazione tool, apertura wheel, checkpoint save |
| **Heavy** | Momento cognitivo di svolta | Shock ipercorrezione (§4), delete confermata, errore bloccante |
| **Success** | Feedback di riuscita | Stadio 3 recall corretto, sync completata con successo |
| **Warning** | Attenzione non-bloccante | Offline detected, conflitto sync risolvibile |
| **Selection change** | Micro-feedback | Scroll picker colore, slider confidenza |

**Regole:**
- **Mai durante scrittura attiva** (penna sullo schermo): l'haptic rovinerebbe il feedback del tratto stesso.
- **iOS Taptic Engine preferito**, Android Vibrator fallback con pattern equivalenti.
- **Opt-out per utente** in settings, ma sempre on di default.
- **Reduced haptics** (iOS setting): rispettato — tutti gli haptic collassano a zero eccetto success/warning critici.

### 15.2 Audio UI

**Fluera è un'app silenziosa.** Nessun suono UI di default. Nessun click, nessun swoosh, nessun ping.

**Eccezioni, tutte opt-in:**
- **Pen scratch** (alcuni utenti lo adorano, molti lo odiano): simulazione rumore penna su carta. Off di default.
- **Stadio 3 success tone**: breve tono armonico (< 300ms) per il verde del recall corretto.
- **Error notification**: beve alert non intrusivo, solo per errori bloccanti.

**Mai:**
- Suoni per ogni tap/click.
- Musica di sottofondo.
- Spoken prompts ("Welcome back!").
- Suoni quando la registrazione vocale inizia/finisce (intrusivo in aula).

### 15.3 Focus Mode (Zen Mode)

**Trigger:** Cmd+Shift+F / item dedicato / gesto a 4 dita verso l'interno.

**Comportamento:**
- Collassa **tutto**: toolbar, pannelli, indicatori, badge, cursore.
- Il canvas diventa l'intero viewport.
- Solo il tratto della penna è visibile.
- Un micro-indicatore 8px in alto-destra segnala "Focus attivo" — dismissabile.
- Uscita: Esc, gesto a 4 dita inverso, tap sul micro-indicatore.

**Use case:** studio profondo, simulazione esame, presentazione a schermo condiviso.

---

## PARTE XVI — Interazioni Avanzate

### 16.1 Context Menu

**Trigger:** right-click (desktop) / long-press con dito (non penna) / Ctrl+click (macOS).

**Regole:**
- Max 7 item primari, oltre in sotto-menu.
- Ordine canonico: **View/Edit → Structural → Destructive**.
- Destructive action sempre in fondo, separata da divider, rendered in rosso.
- Icona sempre presente a sinistra del label.
- Shortcut visibile a destra, se esiste.

**Context menu su nodo:**
```
Modifica                         E
Cambia colore                    C
─────────────
Duplica                         ⌘D
Collega a…                       K
Sposta in layer…                 ⇧L
Aggiungi nota vocale             V
─────────────
Elimina                          ⌫  (rosso)
```

### 16.2 Drag & Drop

**Da esterno a canvas:**
- Trascinamento file → drop zone animata (rettangolo tratteggiato ambra, label "Rilascia per inserire").
- **Image files** → ImageNode nella posizione del drop.
- **PDF** → PDFNode con apertura automatica (o dialog "Importa come PDFNode / Apri in nuova zona").
- **Text/MD files** → TextNode digitale, contenuto visibilmente marcato come "non tuo" per §3 Generation (bordo sottile viola AI @ 0.30).
- **.fluera files** → import branch nella library.

**Intra-canvas:**
- Drag nodo → shadow fluttuante durante il movimento.
- Nessun snap obbligatorio. Snap opzionale (Shift per attivare).
- Undo del drag sempre disponibile.

**Da Fluera a esterno:**
- Drag di selezione → snapshot PNG/SVG trascinabile in Finder, browser, Figma, Slack, email.
- Il file trascinato conserva metadata (link back al punto del canvas) in formato custom dove supportato.

### 16.3 Clipboard (Cut/Copy/Paste)

**Cmd/Ctrl + C / X / V universale.**

| Cosa copi | Cosa ottieni incollando |
|-----------|------------------------|
| Nodo singolo | Nodo identico, nuova posizione |
| Selezione multipla | Cluster completo con connessioni interne preservate |
| Cross-canvas | Trasferimento preservando stile, connessioni interne intatte, connessioni esterne rotte con avviso |
| Testo da altra app | TextNode digitale, marcato "incollato" con bordo viola AI |
| Image da altra app | ImageNode |
| Canvas snapshot da altra Fluera | Zona importata come gruppo, deletabile in blocco |

**Regola §3 (Generation Effect):**
> Tutto il contenuto incollato da fuori — testo, immagini, nodi AI-generated — è **visivamente marcato** con un bordo distintivo (1px viola AI). Questo comunica al cervello dello studente "questo non l'hai fatto tu" e invita alla rielaborazione. Lo studente può "confermare come proprio" un nodo copiato solo riscrivendolo a mano — a quel punto il bordo sparisce.

### 16.4 Selection

| Gesto | Azione |
|-------|--------|
| Tap singolo su nodo | Selezione singola |
| Shift + tap | Aggiungi / rimuovi dalla selezione |
| Cmd + tap | Toggle nella selezione (stesso di Shift, platform-coerente) |
| Drag su area vuota | Rubber band multi-select |
| Cmd + A | Seleziona tutto **nel viewport visibile** (mai tutto il canvas infinito — sarebbe catastrofico) |
| Esc | Deseleziona |
| Double-tap nodo | Entra in edit mode |

**Visualizzazione:**
- Selezione singola: bordo 2px colore accent + 4 handle agli angoli.
- Selezione multipla: bounding box tratteggiato che racchiude tutto + singoli bordi sottili sui nodi.
- **Numero di elementi selezionati** visibile in toolbar (o floating chip) quando > 1.

---

## PARTE XVII — Storico, Time Travel, Versioning

> *Il canvas di Fluera è un diario cognitivo. Il diario deve essere immortale, e ogni pagina — anche quelle strappate — deve essere recuperabile.*

### 17.1 Undo / Redo

Già definito in Parte IV. Punti chiave ricapitolati:
- Cmd/Ctrl + Z universale, Cmd/Ctrl + Shift + Z per redo.
- Cronologia per canvas, persistente tra sessioni (≥ 30 giorni).
- Funziona per ogni azione: tratto, spostamento, colore, apertura pannello, delete.

### 17.2 Timeline Visualization

**Shortcut:** Cmd+H / item dedicato nella wheel.

**UI:**
- Timeline orizzontale in basso, 80px di altezza.
- Ogni step = tick verticale, densità proporzionale all'attività.
- Hover su tick → mini-preview del canvas a quel punto.
- Click su tick → torna a quel punto **senza perdere il futuro** (Fluera usa branching: la timeline originale è preservata come ramo alternativo).

### 17.3 Branching (WAL-based, già in architettura)

- Se torni indietro e modifichi, il ramo originale si preserva come "Branch B".
- Icona "alberello" 🌿 12px appare vicino al titolo del canvas quando esiste timeline alternativa.
- Vista full: gesto dedicato → diagramma a river/tree delle branches con date e mini-preview.
- Merge tra branch: possibile, richiede conferma esplicita.
- **Mai cancellare branch automaticamente.** Auto-cleanup solo dopo 90 giorni e con preavviso all'utente.

### 17.4 Named Checkpoints

**Cmd+S = checkpoint manuale con label.**

- Dialog inline 280px: input "Nome checkpoint" (placeholder "es. Prima dell'esame di Chimica Organica").
- Checkpoint salvato con thumbnail, data, nota opzionale.
- Visibile nella Timeline come pallino più grande.
- Restore checkpoint: **crea un nuovo branch**, mai sovrascrive la storia corrente.

### 17.5 Cinematic Playback

Riferimento alla teoria (§32). UI:
- Trigger da Timeline → "Riproduci la crescita".
- Playback con controlli play/pause/speed (1×, 2×, 4×).
- Mostra il canvas che si ricostruisce tratto dopo tratto, con camera che segue il punto di editing.
- Se il canvas ha registrazioni audio ancorate: l'audio originale si riproduce sincronizzato.
- Opzione "Export come video" per condividere il percorso di studio.

### 17.6 Versioning vs Deletion

- **Undo** = micro-reversione intra-sessione.
- **Branch** = divergenze macro, tutte preservate.
- **Archive** = canvas fuori dalla vista principale, recuperabile con un click.
- **Delete** = uscita definitiva dopo 24h di grace period; archivio ricostruibile via GDPR export fino a 30 giorni.
- **GDPR hard delete** = su richiesta esplicita dell'utente, con conferma via email, rimozione totale entro 72h.

---

## PARTE XVIII — Apprendimento Solidale: Permessi, Presenza, Inviti, Trust

> *La collaborazione in Fluera è un'eccezione cognitivamente costosa, non la norma. Deve avvenire solo quando lo studente la sceglie esplicitamente, e deve proteggere la sovranità del suo canvas.*

### 18.1 I Livelli di Permesso

Quattro livelli, esclusivi:

| Livello | Cosa può fare l'ospite | Default |
|---------|----------------------|---------|
| **Privato** | Nulla — solo il proprietario accede | ✅ default |
| **Visita (read-only)** | Naviga, zoom, legge. Non scrive. Cursore-fantasma visibile all'anfitrione. | — |
| **Markers** | Come Visita + può lasciare marker temporanei (pallini colorati) + chat | — |
| **Co-costruzione** | Editor su una **zona designata dall'anfitrione**, mai sull'intero canvas. Tratti con colore personale. | — |

**Regola assoluta:** il cambio di permesso è **esplicito** e **revocabile in qualsiasi momento**. Revocare non distrugge i contributi dell'ospite — li "congela" in un layer marcato.

### 18.2 Presenza

- **Avatar ring** 24px in top-right per ogni collaboratore presente.
- Stati: **Attivo** (cerchio pieno), **Idle > 3min** (cerchio pulsante 0.50), **Offline** (cerchio vuoto grigio).
- **Cursore-fantasma** colorato (colore personale) nella posizione corrente del visitatore.
- **Label nome** solo al hover sul cursore — label permanente sarebbe rumore visivo continuo.
- **Audio/video chat opzionale** in pannello laterale, mai auto-attivata.

### 18.3 Inviti

**Due modalità:**
1. **Link shareable** con TTL (24h default, configurabile fino a 30 giorni).
2. **Invito diretto** a utente Fluera (se ha l'account) via handle.

**Generazione link:**
- Dialog: permesso granulare selezionato al momento della generazione (Visita / Markers / Co-costruzione).
- Zona accessibile (per Co-costruzione): selezione bounding box sul canvas.
- Lista link attivi sempre visibile in settings del canvas, revocabili con un click.

### 18.4 Trust Signals

**L'utente deve sempre sapere chi sta vedendo il suo canvas.**

- **Friend** (utente noto già interagito): icona ✓ verde piccola accanto all'avatar.
- **Sconosciuto via link**: icona ? ambra, richiede accettazione esplicita alla prima apertura ("{nome} vuole visitare il tuo canvas. Consenti?").
- **Log di accesso** visibile in settings canvas: "Chi ha visto cosa, quando".
- **Block / Report** come azioni di primo livello sul profilo del visitatore.

### 18.5 Il Canvas Dell'Ospite Resta Intatto

Quando un ospite ti visita, **il suo canvas non è accessibile a te** a meno che non ti inviti reciprocamente. Le visite sono asimmetriche per default — la reciprocità è un atto esplicito.

---

## PARTE XIX — Impostazioni, Personalizzazione, Privacy

### 19.1 Organizzazione delle Impostazioni

**Pannello modale**, non deep-nested. Sezioni top-level (mai più di 8):

1. **Account** — profilo, subscription, sign-in methods
2. **Canvas** — default behaviors, autosave interval, appearance
3. **Input** — toolbar vs wheel, gesture remapping (limitato), pen presets
4. **Aspetto** — dark/light/auto, accent color (max 3 scelte), font size
5. **IA** — modelli, data sharing, offline mode
6. **Privacy & Dati** — cookie/telemetry, export, delete
7. **Scorciatoie** — lista completa, customizzabili
8. **Avanzate** — developer options, debug, beta features

Ogni sezione max ~10 setting visibili, altri dietro "Avanzate".

**Search inline** tra le settings (Cmd+K funziona anche qui).

### 19.2 Limiti della Personalizzazione

**La personalizzazione è cognitive load.** Fluera la limita intenzionalmente.

| Permesso | Non permesso |
|----------|--------------|
| Dark/light mode + auto | 50 colori accent arbitrari |
| 3 accent colors prefissati | Gradient custom su UI |
| Pen presets (colore, spessore, texture) | Custom theme engine (tipo VS Code) |
| Toolbar position (top/left) | Toolbar at bottom (sotto-ottimale ergonomicamente) |
| Wheel opt-in | Mix toolbar + wheel insieme |
| Shortcut remap | Rimuovere shortcut canonici (Cmd+Z, Cmd+S) |
| Lingua UI | Font family UI custom |

**Principio:** l'utente scelga tra *opzioni curate*, non da uno spazio di design infinito.

### 19.3 Privacy e Trust Signals

**Ogni azione che tocca dati mostra cosa tocca.**

| Badge / indicatore | Dove compare |
|--------------------|--------------|
| "💾 Salvato localmente" | Status bar, canvas non ancora sincronizzato |
| "☁️ Sincronizzato" | Status bar |
| "🔒 End-to-end encrypted" | Canvas privati con E2EE attiva (GDPR Art. 32 / SQLCipher) |
| "📍 Dati in EU-Frankfurt" | Settings · Privacy — location indicator |
| "🤖 Invio a IA: 3 nodi" | Quando IA è invocata, prima dell'invio al server |

### 19.4 Data Ownership

- **GDPR export:** un click → ZIP completo (canvas in formato `.fluera` + JSON metadata + export visual PNG/PDF per comodità).
- **Account deletion:** percorso chiaro, con export automatico prima + conferma via email + grace period 30gg + hard delete dopo.
- **Nessun "Sei proprio sicuro? Perderai il 30% di sconto!"** — dark pattern vietato.

### 19.5 AI Data Policy

- Setting "Usa i miei canvas per migliorare l'IA?" → **OFF di default**. Rispetta autonomia cognitiva (T2 della teoria).
- Quando IA viene invocata, un piccolo toast trasparente mostra: "Invio 3 nodi all'IA". L'utente vede cosa viene condiviso.
- **Opzione "Solo IA locale"** per utenti con alte esigenze di privacy: usa solo modelli on-device (Apple Intelligence, ollama locale), funzionalità ridotta ma zero data leak.

---

## PARTE XX — Discovery Progressiva delle Feature

> *Ghost Map, Fog of War, Apprendimento Solidale, Cross-Dominio — sono feature potenti ma complesse. Non si imparano leggendo un tutorial. Si scoprono quando si è pronti.*

### 20.1 Trigger di Rivelazione

Ogni feature avanzata ha **prerequisiti** di maturità dell'utente prima di comparire nella UI.

| Feature | Prerequisito |
|---------|--------------|
| **Ghost Map** (Stadio 2) | ≥ 20 nodi + ≥ 1h cumulativa + ≥ 3 sessioni |
| **Fog of War** (Modalità Esame) | ≥ 1 Ghost Map completata |
| **Apprendimento Solidale** | ≥ 2 canvas creati |
| **Cross-Dominio (ponti §9)** | ≥ 2 zone semanticamente distinte sul canvas |
| **Time Travel Playback** | ≥ 14 giorni d'uso cumulativo |
| **Modalità Focus** | Sempre disponibile (primitive) |
| **Command Palette** | Sempre disponibile |
| **Registrazione vocale sincronizzata** | Sempre disponibile |

**Perché funziona:**
- Non sovraccarica il nuovo utente.
- Crea un senso di *crescita con l'app*: le funzioni appaiono quando servono.
- Ogni comparsa è un **momento didattico** — l'utente ora è pronto a usarle produttivamente.

### 20.2 Contextual Hints

Quando una feature diventa disponibile, appare **un hint discreto**, una sola volta:

- Banner 40px in alto, colore ambra @ 0.15, bordo sottile.
- Testo: "Hai 20 nodi. Puoi ora chiedere all'IA di interrogarti (Ghost Map). Provalo quando vuoi."
- Due bottoni: "Provalo ora" · "Non ora".
- **Mai più di 1 hint per sessione**, mai bloccante, dismissabile per sempre.

### 20.3 Tooltip e Help Contestuale

- Hover prolungato (600ms) su item toolbar/wheel → tooltip con: short description · shortcut · link a docs.
- **Cmd+?** apre Help palette searchable (sotto-palette di Cmd+K).
- Docs sono **in-app**, non link esterni che aprono il browser (rompono il flow).

### 20.4 Milestone Celebrations (Misurate)

Piccole celebrazioni per momenti reali, non per engagement artificiale:

| Milestone | Quando | Feedback |
|-----------|--------|----------|
| Primo canvas completato | ≥ 20 nodi + chiuso la prima volta | Toast 4s |
| Prima Ghost Map ≥ 60% | Al completamento | Toast + badge in Timeline (non persistent-visible) |
| Primo canvas condiviso | Al primo invito accettato | Toast discreto |
| Prima correzione post-ipercorrezione | Nodo rosso → verde in Stadio 2 | Flash visivo già esistente + checkpoint auto nominato |
| 30 giorni di uso regolare | Opt-in metric | Una sola frase: "Un mese sul canvas. Continua così." |

**Mai:**
- Streak giornaliero visibile che crea ansia.
- Badge/achievement da collezionare.
- Leaderboard pubblica tra studenti.
- Celebration che interrompe il lavoro in corso.

### 20.5 First-Run Experience

**La prima apertura di Fluera:**

1. **Schermata account** (se serve sign-in): 3 opzioni chiare (Google / Apple / Email), senza social pressure ("Unisciti a milioni di studenti!").
2. **Scelta modalità input**: uno schermo semplice con 2 card (Toolbar / Wheel), preview animata di 3s per ciascuna, e "Cambierai idea in Impostazioni in qualsiasi momento".
3. **Canvas vuoto immediato**: nessun tour. Solo un tip discreto che scompare al primo tratto.
4. **Giorno 2+**: 1 hint contestuale al massimo, solo se la feature è rilevante per ciò che l'utente sta facendo.

---

## PARTE XXI — Il Manifesto Visivo di Fluera

> *Dieci frasi che ogni designer, developer e product manager di Fluera deve poter recitare a memoria.*

1. **Il canvas è il territorio. La UI è il perimetro. Il perimetro serve, non domina.**
2. **Il silenzio non è assenza di design. È il design più difficile.**
3. **L'IA è invitata, mai presente. Parla con la voce più bassa della stanza.**
4. **Ogni millisecondo di latenza è un tradimento della cognizione incarnata.**
5. **La posizione che lo studente sceglie è sacra. Mai spostarla senza consenso.**
6. **Uno strumento, uno stato. L'ambiguità è cognitive load estraneo.**
7. **L'imperfezione del tratto umano è un feature neurobiologico. L'infrastruttura attorno deve essere perfetta.**
8. **Apprendere viene prima di produrre. Se devi scegliere, scegli imparare.**
9. **Toolbar o tool wheel: una grammatica alla volta, entrambe perfettamente coerenti.**
10. **Un canvas di Fluera aperto dopo un anno deve sembrare esattamente come l'hai lasciato — perché è dentro di te, non sul nostro server.**

---

## Appendice A — Checklist PR per UI/UX

Ogni pull request che tocca UI/UX deve rispondere "sì" a tutte queste domande prima del merge:

- [ ] I colori utilizzati sono nei token di [`toolbar_tokens.dart`](fluera_engine/lib/src/canvas/toolbar/toolbar_tokens.dart) o nel theme centrale?
- [ ] Le animazioni usano `animFast/Normal/Slow` con curve `easeIn/OutCubic`?
- [ ] Gli spacing sono multipli di 4?
- [ ] Tutte le stringhe passano da `gen/l10n`?
- [ ] Il touch target minimo è ≥ 44pt?
- [ ] Il contrast text è ≥ 4.5:1 in dark e light?
- [ ] Esiste la versione reduced-motion?
- [ ] Lo stato funziona sia in modalità toolbar che wheel?
- [ ] Esiste uno shortcut da tastiera coerente cross-platform?
- [ ] Lo stato è undo-able?
- [ ] La feature è silenziosa durante la scrittura attiva?
- [ ] La feature non trasforma l'IA in entità proattiva?
- [ ] La feature non distrugge la posizione spaziale scelta dall'utente?
- [ ] La feature preserva l'imperfezione del tratto a mano?
- [ ] È stato testato il worst-case: canvas con >5000 nodi, 60fps?

Se anche una sola risposta è "no", il lavoro non è finito.

---

## Appendice B — Rapporto con la Teoria Cognitiva

Questo documento è la **proiezione visiva** di [`teoria_cognitiva_apprendimento.md`](teoria_cognitiva_apprendimento.md). La mappa:

| Sezione di questo doc | Principi teorici ancorati |
|-----------------------|---------------------------|
| Assioma 1 (Canvas sacro) | Sovranità cognitiva, §3 Generation, §23 Embodied |
| Assioma 2 (Silenzio) | §24 Flow, §9 Cognitive Load, §13 Sistema 2 |
| Assioma 3 (IA invitata) | §14 Automation Bias, §15 Offloading, §21 Atrofia |
| Assioma 4 (Latenza) | §23 Embodied, Doherty Threshold |
| Assioma 5 (Posizione) | §22 Place Cells, Metodo dei Loci, §29 Extended Mind |
| Assioma 6 (Uno strumento) | §9 Cognitive Load, Hick/Miller |
| Assioma 7 (Contenuto verticale) | §22 Spatial, §30 Antidoto passività |
| Assioma 8 (Coerenza) | Jakob's Law, memoria transattiva |
| Assioma 9 (Imperfezione) | §5 Desirable Difficulties, §3 Generation |
| Assioma 10 (Imparare > produrre) | Principio Aureo, T4 Productive Failure |
| Parte III (Toolbar vs Wheel) | §24 Flow, §23 Embodied (wheel ergonomica), §9 Cognitive Load |
| Parte VI (Stati speciali) | Tutte le Parti VI-VIII della teoria |
| Parte XI (Voce e copy) | §9 Cognitive Load estraneo (linguaggio tecnico = rumore), T1 Metacognizione (messaggi chiari aiutano l'auto-valutazione) |
| Parte XII (Stati UI) | §24 Flow (silenzio di loading corto), §7 Zeigarnik (loading specifico mantiene tensione cognitiva positiva) |
| Parte XIII (Navigazione globale) | §22 Spatial (deep link porta a posizione esatta), §26 Zoom Semantico (search con miniatura spaziale) |
| Parte XIV (Form factors, cross-device) | §22 Place Cells (posizione preservata cross-device), §29 Extended Mind (il canvas è l'estensione, non il device) |
| Parte XV (Canali sensoriali) | §23 Embodied Cognition (haptic = feedback propriocettivo), §24 Flow (audio silente), §5 Desirable Difficulties (focus mode = attrito anti-distrazione) |
| Parte XVI (Interazioni avanzate) | §3 Generation (paste esterno marcato visivamente), §22 Spatial (drag preserva posizione) |
| Parte XVII (Storico, time travel) | §12 Growth Mindset (playback mostra crescita), §22 Spatial (checkpoint = locus temporale nel Palazzo) |
| Parte XVIII (Apprendimento solidale) | Parte IX della teoria intera: Peer Instruction, Protégé §8, Conflitto Socio-Cognitivo, Memoria Transattiva |
| Parte XIX (Impostazioni, privacy) | T2 Autodeterminazione (autonomy via data control), §9 Cognitive Load (personalizzazione limitata) |
| Parte XX (Discovery progressiva) | §19 ZPD/Scaffolding (feature appare nella zona prossimale dell'utente), T1 Metacognizione (l'utente sa di essere pronto) |

Ogni volta che nasce un dubbio di design, la risposta non si cerca in questo documento: si cerca nella teoria cognitiva. Questo documento è solo il *traduttore*.

---

> [!IMPORTANT]
> **Il design di Fluera non è un gusto. È una conseguenza.**
>
> Ogni scelta visiva, ogni animazione, ogni pixel deriva da un principio cognitivo scientificamente documentato. Un'UI che non rispetta questi principi non è "meno bella" — è **neurobiologicamente dannosa** per lo studente che cerca di imparare. Fluera è uno strumento medicale per il cervello: trattiamo le sue leggi visive con la stessa severità con cui un farmaco rispetta il dosaggio.
