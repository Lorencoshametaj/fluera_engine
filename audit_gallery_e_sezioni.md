# Audit Gallery Fluera + Analisi Cognitiva delle "Sezioni"

> *"Un canvas può contenere l'intera triennale. Se è vero, cosa resta da fare alla gallery? E cosa resta da fare alle sezioni?"*

Questo documento chiude due dossier rimasti aperti dopo lo sprint UX di aprile 2026:

1. **La Gallery dell'app Fluera** è coerente con le 21 parti e i 10 assiomi di [`leggi_ui_ux.md`](leggi_ui_ux.md)? Dove sabota il modello cognitivo?
2. **Le "sezioni"** (`SectionNode` + Hub Sheet + Workspace Dashboard) — le abbiamo costruite perché servivano, o perché sapevamo costruirle? La teoria cognitiva dice che servono?

Il vincolo di design è dichiarato in Parte VIII di `leggi_ui_ux.md` e in §22 di [`teoria_cognitiva_apprendimento.md`](teoria_cognitiva_apprendimento.md):

> **UN canvas può contenere l'intera triennale.** Non molti canvas collegati, non un file per materia — un solo spazio continuo navigabile.

Se prendiamo questo vincolo sul serio, tutto cambia: la gallery diventa quasi inutile, e le sezioni come rettangoli con bordi diventano un residuo di un'epoca precedente (Notion, Figma, Miro) che Fluera doveva sorpassare.

Il documento porta **una tesi netta**: le sezioni come le abbiamo costruite non servono. Serve il loro *effetto* — ancore navigative — ma non la loro *forma* (rettangoli renderizzati). La raccomandazione è sostituirle con **Spatial Bookmark**, metadati puri senza rendering, visibili solo al livello di zoom satellite.

---

## Metodologia

Ogni affermazione del documento è ancorata a:
- Un principio cognitivo numerato in `teoria_cognitiva_apprendimento.md` (es. §22 Place Cells).
- Una parte numerata o un assioma di `leggi_ui_ux.md` (es. Assioma I, Parte VIII.3).
- Un file:line dell'implementazione attuale, verificabile in repo.

Dove una scelta di design conflige con la teoria, lo segnalo con `[!IMPORTANT]`. Dove una scelta è corretta ma incompleta, con `[!TIP]`. Dove è fuori dal perimetro di questo audit, con `[!NOTE]`.

---

## PARTE A — Audit Gallery

### A.1 Il flusso attuale

Entry point: [fluera_canvas_gallery.dart:38](../Fluera/lib/gallery/fluera_canvas_gallery.dart#L38).

Lo studente apre l'app → splash → **gallery grid** → seleziona un canvas → (se ha sezioni) **Hub Sheet** o **Workspace Dashboard** → apre il canvas nel viewport salvato.

Componenti principali:

| Componente | Path | Funzione |
|------------|------|----------|
| `FlueraCanvasGallery` | [fluera_canvas_gallery.dart:38](../Fluera/lib/gallery/fluera_canvas_gallery.dart#L38) | Entry widget, grid/list toggle, sort, filter, search, folder navigation |
| `_CanvasCard` | [_canvas_card.dart:7](../Fluera/lib/gallery/_canvas_card.dart#L7) | Card con snapshot PNG + metadata + section preview badges |
| `CanvasHubSheet` | [canvas_hub_sheet.dart:34](../Fluera/lib/gallery/canvas_hub_sheet.dart#L34) | Bottom sheet con minimap + jump-to-section |
| `_WorkspaceDashboard` | [_workspace_dashboard.dart](../Fluera/lib/gallery/_workspace_dashboard.dart) | Sostituisce la grid per canvas con sezioni; dedica ~60% alla section grid |

Feature presenti: grid/list, sort (date/name), paper type filter, search, folder nesting con breadcrumb, bulk select, create/delete/rename/duplicate/move/share. Snapshot PNG cached in memory.

Feature assenti: archive, star/pin canvas, tag system, color-code canvas, export dalla gallery, **Resume last canvas come primary action**, **command palette integrata**.

### A.2 Conformità agli assiomi

Valutazione della gallery attuale contro i 10 Assiomi Inviolabili (Parte I di `leggi_ui_ux.md`):

| Assioma | Gallery oggi | Verdetto |
|---------|--------------|----------|
| **I — Canvas Sacro** | La gallery è meta-livello sul canvas, non tocca il canvas stesso | ✅ Non viola |
| **II — Silenzio è una Feature** | Empty state curato, no notifiche push, icona animata discreta | ✅ Ok |
| **III — IA Invitata, Mai Presente** | Nessuna IA in gallery (corretto: l'IA vive dentro il canvas) | ✅ Ok |
| **IV — Latenza è Design (Doherty ≤400ms)** | Splash 2.5s → gallery → tap canvas → Hub Sheet → canvas. Tre livelli di friction prima dello studio | ❌ **Violazione** |
| **V — Posizione Sacra (Place Cells)** | La gallery organizza per data/nome/folder, mai spazialmente | ❌ **Violazione concettuale** |
| **VI — Uno Strumento, Uno Stato** | Grid/list toggle, sort, filter, folder mode, selection mode, search mode: stati plurimi | ⚠️ Borderline |
| **VII — Contenuto Verticale, UI Orizzontale** | La gallery è tutta UI senza contenuto verticale (ok per meta-livello) | ✅ Ok |
| **VIII — Coerenza è Branding** | Material Design standard, coerente col resto app | ✅ Ok |
| **IX — Imperfezione Conservata** | N/A (non c'è contenuto utente a livello di gallery) | — |
| **X — Apprendimento > Produttività** | La gallery ricorda una Files app, non uno strumento di studio | ⚠️ Tono sbagliato |

Le due violazioni gravi (**IV** e **V**) sono le stesse: **la gallery è una metafora di file manager**. Un file manager è un oggetto produttivo (organizza documenti), non cognitivo (organizza conoscenza). Per uno studente che costruisce un Palazzo della Memoria, tornare allo studio dovrebbe essere istantaneo e senza passare da un indice cronologico di "file".

### A.3 Gaps funzionali

Cosa manca rispetto a quello che `leggi_ui_ux.md` chiede:

**1. Resume come default (Parte IV, Assioma IV).** Lo studente che riapre l'app vuole tornare *dove stava lavorando*, non vedere una lista di cartelle. La Parte IV.1 specifica: *"Ritorno alla stanza ≤400ms"*. Oggi servono almeno 3 tap (splash → gallery → card → hub → canvas).

**2. Command palette integrata (Parte XIII.1).** `leggi_ui_ux.md` prescrive `Cmd+K` come entry point universale ("Vai a canvas…", "Apri zona Chimica Organica"). Nell'app oggi esiste una command palette nel canvas, ma non come entry point dalla gallery né come shortcut globale.

**3. Deep link (Parte XIII.4).** Un link `fluera://canvas/xyz?viewport=...` dovrebbe aprire direttamente il canvas alla posizione indicata. Oggi il routing esiste ma non è esposto come cittadino di prima classe.

**4. Search spaziale (Parte XIII.3).** La search attuale è solo title+id; `leggi_ui_ux.md` chiede risultati con miniatura spaziale ("la posizione nel canvas fa parte del match"). Manca completamente.

**5. Empty state cognitivo, non produttivo.** Oggi l'empty state dice *"No Canvases Yet — Create Your First Canvas"*. Dovrebbe dire qualcosa tipo *"Inizia il tuo Palazzo della Memoria"* (Assioma X, tono cognitivo).

### A.4 Gaps cognitivi

Qui il problema diventa strutturale.

> [!IMPORTANT]
> **La gallery attuale incoraggia il pattern "un file per materia" che la Parte VIII demolisce.** Uno studente che apre Fluera e vede 12 card ("Analisi I", "Chimica", "Fisica"…) riceve il messaggio implicito: *"qui è giusto avere dodici canvas separati, uno per materia"*. È esattamente l'errore cognitivo che `teoria_cognitiva_apprendimento.md` riga 1075 identifica: *"ogni materia in un documento separato = dieci frammenti disconnessi"*.

Tre gaps cognitivi:

**1. Grouping cronologico anti-Place-Cells.** Oggi la gallery raggruppa per "Today / Yesterday / This Week / Older" ([fluera_canvas_gallery.dart:222-250](../Fluera/lib/gallery/fluera_canvas_gallery.dart#L222-L250)). Il tempo di creazione è un asse ortogonale alla memoria spaziale. Le Place Cells (§22) non codificano *quando* ho creato un canvas, codificano *dove* vivono i concetti. Raggruppare per data rinforza la metafora sbagliata (file, documento, task).

**2. Folder gerarchiche vs geografia.** Le folder con `parentFolderId` ([fluera_canvas_gallery.dart:427-433](../Fluera/lib/gallery/fluera_canvas_gallery.dart#L427-L433)) sono una struttura ad albero. Il canvas è una struttura **planare e continua**. Mischiare i due modelli produce cognitive load inutile: lo studente deve decidere *"metto questo in una folder o lo lascio in root?"* — una decisione produttiva che non ha alcun effetto sull'apprendimento.

**3. La Workspace Dashboard come file manager 2.0.** Quando un canvas ha sezioni, lo studente vede una grid 2-colonne di "section cards" con nome, preview, gradient ([_workspace_dashboard.dart:709-806](../Fluera/lib/gallery/_workspace_dashboard.dart#L709-L806)). È visivamente identica a una gallery di file. Stessa metafora, stesso errore cognitivo, applicato *dentro* il canvas anziché *sopra* di esso.

> [!TIP]
> La gallery non va eliminata, va **svuotata del suo ruolo di prima schermata**. Deve diventare una superficie secondaria ("Tutti i canvas…") per casi eccezionali — la maggior parte delle sessioni dovrebbe saltarla completamente.

---

## PARTE B — Il Problema delle Sezioni

### B.1 Cos'è oggi una sezione

Modello: [`SectionSummary`](lib/src/storage/section_summary.dart) (23 righe, tutte semplici):

```dart
class SectionSummary {
  final String id;
  final String name;
  final double x, y, width, height;
  final int? bgColor;
  final String? preset;
}
```

Nodo scene graph: [`SectionNode`](lib/src/core/nodes/section_node.dart). Renderizzato sul canvas come **rettangolo con bordo + background colorato + label del nome**.

Persistenza: colonna `sections_json` in SQLite (schema v14), estratta a ogni auto-save dalla scene graph ([sqlite_storage_adapter.dart:1445-1491](lib/src/storage/sqlite_storage_adapter.dart#L1445-L1491)).

Superfici di UI:

- **Card in gallery**: mostra i primi 3 nomi di sezione come badge ([_canvas_card.dart:168-171](../Fluera/lib/gallery/_canvas_card.dart#L168-L171)).
- **Hub Sheet**: bottom sheet con minimap + lista tappabile di sezioni → jump al viewport calcolato ([canvas_hub_sheet.dart:361-449](../Fluera/lib/gallery/canvas_hub_sheet.dart#L361-L449)).
- **Workspace Dashboard**: grid 2-colonne di section cards con gradient, pin, filter ([_workspace_dashboard.dart:709-806](../Fluera/lib/gallery/_workspace_dashboard.dart#L709-L806)).
- **Rendering sulla canvas**: il rettangolo visibile con bordo e bg, sempre, a ogni livello di zoom.

Funzionalmente, una sezione fa **due cose** distinte:
1. **Delimita visivamente una regione** (rettangolo con bordo).
2. **Fornisce un'ancora navigativa** (nome + viewport calcolabile dal bounding box).

Questa fusione è il nodo del problema.

### B.2 Confronto con la teoria cognitiva

Procedo principio per principio.

**§22 "Le Zone-Àncora (i Quartieri del Palazzo)"** — `teoria_cognitiva_apprendimento.md` riga 454-457:

> *"La prima volta che studi una materia, scegli un'area del canvas. Chimica in alto a destra. Fisica in alto a sinistra. Non serve pianificare: posiziona il primo nodo dove ti sembra naturale. Le sessioni successive espanderanno quella zona organicamente. Col tempo, ogni materia 'occupa' una regione riconoscibile."*

Il meccanismo teorico è **emergenza**: la zona esiste perché lo studente ha *iniziato a scrivere lì*. Non esiste un atto separato di "definire la zona". In Fluera oggi, creare una sezione è invece un atto esplicito e precedente: apri il menu, scegli "Sezione", traccia il rettangolo, dai il nome. Questo **inverte il flusso cognitivo**: prima definisci il contenitore, poi metti dentro. La teoria dice l'opposto.

**§22 "Chunking Visivo"** — riga 529-532:

> *"Lo studente raggruppa naturalmente i nodi in cluster spaziali. I concetti correlati stanno vicini, separati da spazio vuoto dai concetti non correlati. Il chunking diventa visivamente evidente: ogni cluster è un 'chunk' nel Palazzo, **e lo spazio bianco tra i cluster è il confine tra i chunk**."*

Il confine, secondo la teoria, **è lo spazio bianco**. Un bordo disegnato è un oggetto in più che compete con il contenuto per l'attenzione. Fluera oggi ha *entrambi*: lo spazio bianco tra cluster + il bordo del rettangolo della sezione. È ridondante nel caso migliore, interferente nel caso peggiore.

**Parte VIII "Un Solo Canvas, Tutto Dentro"** — riga 1080:

> *"Il palazzo della memoria è un'**unica città navigabile**, non stanze isolate."*

Un rettangolo con bordo è, visivamente e semioticamente, una stanza. Molti rettangoli con bordi sono molte stanze. La logica della Parte VIII è opposta: una città continua con quartieri che sfumano l'uno nell'altro.

**Assioma I "Il Canvas è Sacro"** — Parte I di `leggi_ui_ux.md`:

> *"Nessuna imposizione di template; lo spazio è sovranità dello studente."*

Una sezione con preset (`preset: "lecture" | "exam" | ...`) è, letteralmente, un template imposto. Lo studente sceglie da una lista predefinita come classificare una regione del proprio Palazzo. Questo è il contrario della sovranità.

**Assioma V "La Posizione è Sacra"**:

> *"Place Cells: la memoria spaziale è la base neurologica."*

Le Place Cells operano sulla **posizione**, non sull'appartenenza a un rettangolo. Il cervello non ha bisogno di sapere *"questo nodo è dentro la sezione Chimica"* — gli basta sapere *"questo nodo è in alto a destra"*. L'informazione aggiuntiva "appartiene alla sezione X" è cognitivamente rumorosa, non utile.

### B.3 Il problema di scala

Il vincolo dichiarato è *un canvas = tutta la triennale*. Se applico questo vincolo al pattern "sezione per argomento":

- 12 esami per anno × 3 anni = 36 esami.
- Ogni esame ha 3-5 macro-argomenti = 108-180 sezioni.
- La Workspace Dashboard oggi è una grid 2-colonne. 150 section cards in grid 2-colonne = 75 righe di scroll.

> [!IMPORTANT]
> **A scala triennale, la Workspace Dashboard collassa.** Una grid da 150 elementi non è una dashboard, è un archivio. È esattamente il pattern che la Parte VIII vuole eliminare: *"ogni materia in un documento separato = dieci frammenti disconnessi"*. La Workspace Dashboard, se scalata a triennale, diventa una gallery-dentro-il-canvas: due livelli della stessa metafora sbagliata.

### B.4 Cosa NON va buttato

La funzione di **re-entry rapido** è sacrosanta (Assioma IV, Doherty Threshold; Parte XIII.4 deep link). Serve una primitiva che:

- Dica "torna qui in <400ms".
- Abbia un nome umano ("Termodinamica — Cap. 3").
- Sia richiamabile da command palette, deep link, Hub Sheet.
- Non occupi spazio visivo sul canvas durante lo studio.

Questa primitiva oggi si chiama "sezione" e fa troppe cose. Va spacchettata: **tieni la funzione, butta la forma**.

---

## PARTE C — Raccomandazione: Spatial Bookmark

> [!IMPORTANT]
> **Tesi: le sezioni come le abbiamo costruite non servono. Va tenuto il loro effetto navigativo, non la loro forma rettangolare.**
>
> Proposta: sostituire `SectionNode` con una primitiva nuova, **`SpatialBookmark`**, che è solo un metadato navigativo — niente rendering, niente bordo, niente template, niente preset.

### C.1 Design di `SpatialBookmark`

```
SpatialBookmark {
  id         : String
  name       : String                // "Termodinamica — Cap. 3"
  cx, cy     : double                // centro del viewport target
  zoom       : double                // livello di zoom (default: 1.0)
  color      : int?                  // solo per label in minimap; null = neutro
  createdAt  : DateTime
  lastVisit  : DateTime?             // per ordinare "ultimi visitati"
}
```

Differenze chiave rispetto a `SectionSummary`:

| Aspetto | `SectionSummary` (oggi) | `SpatialBookmark` (proposto) |
|---------|------------------------|-----------------------------|
| Rendering sul canvas | Sì (rettangolo + bordo + bg) | **No, mai** |
| Bounding box | Sì (x, y, w, h) | No (solo centro + zoom) |
| Preset/template | Sì (`preset: "lecture" \| ...`) | **No** |
| Creazione | Esplicita prima di scrivere | Esplicita dopo aver scritto ("Pin this view") |
| Visibilità a zoom 100% | Sempre | **Mai** |
| Visibilità a zoom <30% (satellite) | Sempre | **Label fluttuante** |
| Appartenenza nodi | Nodi "dentro" la sezione | Nessuna appartenenza |

### C.2 Flusso di creazione

Oggi: menu → "Sezione" → traccia rettangolo → dai nome.

Proposto: l'utente studia normalmente, posiziona nodi, lascia emergere un quartiere. Quando vuole tornarci facilmente, gesto esplicito *"Pin this view"* (comando da menu, shortcut, o gesto long-press sulla minimap). Viene salvato il viewport corrente come bookmark nominato.

Questo rispetta §22 "Il Palazzo non si progetta — si abita" (riga 487): la zona esiste prima del bookmark, non dopo.

### C.3 Visibilità a più livelli di zoom

La Parte VIII.3 "Zoom Semantico — Level of Detail" di `leggi_ui_ux.md` definisce quattro livelli:

| Livello | Zoom range | Cosa si vede oggi | Cosa si vedrà con bookmark |
|---------|-----------|---------------------|---------------------------|
| **Satellite** | <30% | Macro-zone, materie, nodi-monumento | **+ Label bookmark fluttuanti** (testo semitrasparente ancorato al centro bookmark) |
| **District** | 30-70% | Cluster, gruppi di concetti | Nessun elemento aggiuntivo (la zona è autoevidente dallo spazio) |
| **Building** | 70-150% | Nodi individuali, connessioni | Nessun elemento aggiuntivo |
| **Room** | >150% | Testo, formule, dettagli | Nessun elemento aggiuntivo |

> [!TIP]
> Solo il livello satellite mostra le label. A qualsiasi altro zoom, il canvas è pulito: nessun bordo, nessun bg, nessun nome. Lo studente vede solo i propri tratti. Questa è la materializzazione dell'Assioma I ("Canvas Sacro") e del principio §22 ("i confini sono spazio bianco").

### C.4 Superfici di UI dopo la sostituzione

**Hub Sheet**: continua a esistere, ma diventa una lista di bookmark (non sezioni). Stessa UX di oggi (lista → tap → viewport jump), primitiva diversa. La minimap mostra i bookmark come **punti** (non rettangoli), con label al passaggio del dito.

**Workspace Dashboard**: semplificata drasticamente. Non più grid 2-colonne di section card. Diventa:

```
┌──────────────────────────────────────────────┐
│  Resume (large, primary action)               │
│  └─ "Termodinamica — Cap. 3"                  │
│     Ultima visita: 2 ore fa                   │
├──────────────────────────────────────────────┤
│  Bookmark recenti (max 5)                     │
│  • Analisi I — Integrali                      │
│  • Chimica — Legami covalenti                 │
│  • Fisica — Onde                              │
│  • Filosofia — Kant                           │
│  • +12 altri bookmark (Cmd+K)                 │
├──────────────────────────────────────────────┤
│  Minimap (½ schermata)                        │
│  [mappa canvas con label bookmark]            │
└──────────────────────────────────────────────┘
```

Compatibile con cellulare/tablet/desktop (form factor già supportati dalla dashboard oggi).

**Card della gallery**: rimuove i "section preview badges" (primi 3 nomi di sezione). Li sostituisce con "ultimo bookmark visitato" se esiste.

### C.5 Migration del dato esistente

Il dato attuale non va perso. Ogni `SectionSummary` può essere convertita in `SpatialBookmark`:

```
bookmark.name      = section.name
bookmark.cx        = section.x + section.width / 2
bookmark.cy        = section.y + section.height / 2
bookmark.zoom      = computeZoomToFit(section.width, section.height, viewportSize)
bookmark.color     = section.bgColor  (opzionale)
bookmark.createdAt = section.createdAt  (se disponibile, altrimenti now)
```

Schema DB: introdurre `bookmarks_json` in schema v16, deprecare `sections_json`. Rimuovere il rendering del `SectionNode` dalla scene graph (il nodo stesso può restare per un transitorio come scheletro silenzioso, ma non viene più disegnato).

> [!NOTE]
> Questo documento **non è un plan di implementazione**. La migrazione richiede: refactor del `SectionNode`, aggiornamento dello schema DB, refactor di `CanvasHubSheet` e `_WorkspaceDashboard`, UX del gesto "Pin this view", label satellite con semitrasparenza sensibile allo zoom. Merita un plan separato dopo la decisione di Lorenzo.

### C.6 Fallback conservativo

Se in fase di implementazione emergessero vincoli (es. utenti beta che hanno investito tempo a disegnare sezioni con cura estetica e le vogliono tenere), un fallback conservativo è:

- Mantenere `SectionNode` come primitiva deprecata ma renderizzata.
- Renderla visibile **solo a zoom <30%** (satellite), invisibile al livello di scrittura.
- A zoom 100% sparisce il bordo, resta solo la label come bookmark.

Questo preserva la continuità spaziale al livello di studio, consente la label navigativa al livello mappa, e non rompe i canvas esistenti. È compatibile con Parte VIII.3 "Level of Detail". Non è la tesi di questo documento — è una via d'uscita se la tesi principale incontra ostacoli.

---

## PARTE D — Riflessi sulla Gallery

Con `SpatialBookmark` al posto di `SectionNode`, e con il vincolo "un canvas = la triennale", la gallery non può più essere la prima schermata.

### D.1 Resume come default

Apertura app → **ultimo canvas aperto, viewport salvato** (`lastViewport` esiste già in `CanvasMetadata`, [fluera_storage_adapter.dart:95-99](lib/src/storage/fluera_storage_adapter.dart#L95-L99)).

- Zero frizione tra tap icona e ripresa studio.
- Coerente con Assioma IV (Doherty ≤400ms).
- Coerente con §22 ("tornare in una zona riattiva la memoria spaziale"): lo studente riprende *dove* stava, non *cosa* stava facendo.

Se non c'è ancora nessun canvas (primo avvio), allora — e solo allora — si mostra la gallery in modalità empty state ("Inizia il tuo Palazzo della Memoria").

### D.2 Gallery come superficie secondaria

La gallery diventa accessibile da:

1. **Command palette** (`Cmd+K` o gesto dedicato): "Tutti i canvas…" apre l'attuale gallery. Coerente con Parte XIII.1 di `leggi_ui_ux.md`.
2. **Icona libreria** in una toolbar minima (non intrusiva, opzionale).
3. **Long-press** sul titolo del canvas corrente → "Cambia canvas".

Nessuna di queste è la prima schermata. Se l'utente ha un solo canvas (caso maggioritario col vincolo triennale), la gallery non viene *mai* mostrata spontaneamente.

### D.3 Folder: edge case, non default

Le folder (`FolderMetadata`, [fluera_storage_adapter.dart:154](lib/src/storage/fluera_storage_adapter.dart#L154)) restano disponibili per casi eccezionali: studenti che tengono studio separato da sketching/hobby, utenti che hanno progetti distinti. Nessuna folder creata di default. Nessun grouping cronologico forzato.

> [!IMPORTANT]
> Sparisce l'incoerenza gerarchica: con bookmark dentro canvas unico e folder solo come edge case, **resta un solo livello di organizzazione**: il canvas stesso, con bookmark come layer navigativo puro. Non più due livelli paralleli (folder gerarchiche in gallery + sezioni rettangolari in canvas) che replicano la stessa metafora a due scale.

### D.4 Workspace Dashboard dopo la decisione

La dashboard si svuota dei suoi ruoli attuali:

- **Rimosso:** grid 2-colonne di section card, filter per sezioni, pin sezioni, canvas carousel.
- **Rimane:** Resume action primaria + lista ultimi bookmark + minimap con label.
- **Aggiunto:** shortcut a command palette per navigazione bookmark su larga scala.

Risultato: una schermata che fa *una cosa sola* (far riprendere lo studio) invece di 5 cose (carousel + minimap + grid + filter + actions). Coerente con Assioma VI ("Uno Strumento, Uno Stato").

---

## Appendice — Checklist di coerenza post-decisione

Prima di mergeare un'implementazione che deriva da questa analisi, verificare:

- [ ] Il canvas si apre in ≤400ms dall'icona app (Assioma IV).
- [ ] A zoom 100% non esiste alcun bordo rettangolare imposto sul canvas (Assioma I + §22).
- [ ] Le label di zona appaiono **solo** a zoom satellite <30% (Parte VIII.3).
- [ ] Il re-entry a una zona specifica funziona via: command palette, deep link, Hub Sheet, minimap (Parte XIII).
- [ ] La Workspace Dashboard non è più una grid di "section card" (Parte VIII).
- [ ] La gallery non è più la prima schermata dell'app (Assioma IV + Parte X).
- [ ] Nessun preset imposto a un bookmark (Assioma I).
- [ ] I bookmark si creano solo dopo che la zona esiste, non prima (§22 "Il Palazzo si abita, non si progetta").
- [ ] Lo spazio bianco tra cluster è il confine naturale tra chunk (§22 Chunking Visivo).
- [ ] La primitiva `SpatialBookmark` è metadato puro, non elemento della scene graph renderizzato.

---

## Riepilogo esecutivo

**Sezioni: non servono nella forma attuale.** Vanno sostituite da `SpatialBookmark` — ancore navigative nominate che vivono come metadato, senza rendering sul canvas. Motivazione cognitiva: §22 (zone emergenti, non predefinite), Parte VIII (continuità spaziale), Assioma I (no template), Assioma V (posizione > appartenenza a rettangolo). Funzione di re-entry mantenuta al 100%; forma rettangolare eliminata.

**Gallery: va ridotta, non potenziata.** Con un canvas unico che contiene la triennale, la gallery come prima schermata è un anacronismo da file manager. Default: Resume ultimo canvas. Gallery relegata a superficie secondaria accessibile da command palette. Le folder sopravvivono come edge case, non come default.

**Impatto operativo.** Una sola direzione di implementazione, due workstream:
1. Refactor `SectionNode → SpatialBookmark` + migration schema v14 → v16.
2. Refactor flusso di apertura app: Resume di default, gallery via comando.

Entrambi i workstream sono autonomi e possono avanzare in parallelo, ma richiedono plan di implementazione dedicati. Questo documento chiude solo la fase di analisi cognitiva e di decisione architetturale.
