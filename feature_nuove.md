═══════════════════════════════════════════════════════════════════════════════
                           FLUERA ENGINE — FEATURE ROADMAP
                          Tutte le Feature IA per il Canvas
═══════════════════════════════════════════════════════════════════════════════


███████████████████████████████████████████████████████████████████████████████
  SEZIONE A — FEATURE ORIGINALI (dal concept iniziale)
███████████████████████████████████████████████████████████████████████████████


1. Il "Flow Playback" Spazio-Temporale ✅ IMPLEMENTATO
L'intersezione tra: Audio Sync + Infinite Canvas + Connections

Lo Status Quo: Tocco un tratto e riparte l'audio (Notability).
Il Livello Top Tier: Siccome in Fluera i concetti sono uniti da vere e proprie Connections, l'utente seleziona una connessione (la linea) e Fluera riproduce l'audio di quando la relazione è stata creata.
Ancora oltre (Il "Cinematic Playback"): Un pulsante "Play". L'app inquadra il primo "Cluster" in ordine temporale, disegna i tratti in tempo reale con l'audio di sottofondo. Quando l'oratore passa all'argomento successivo, la telecamera virtuale scorre fluidamente lungo la "Knowledge Connection" verso il cluster successivo, rivelandolo mentre la voce scorre. Hai appena trasformato appunti caotici in una Presentazione Dinamica automatica (un po' come un Prezi autogenerato dal tuo flusso di pensiero).


2. Auto-Tessitura del "Knowledge Flow" (Il Ragno) ✅ IMPLEMENTATO
L'intersezione tra: NLP Semantico + Knowledge Graph + Background Processing
Fluera ha già il sistema Knowledge Flow per i grafi. E se i collegamenti non li facessi solo tu?

Cosa fa l'IA: Mentre lavori, Atlas scansiona silenziosamente il canvas in background. Se rileva che un gruppo di note in alto a destra ("Fisica Quantistica") è semanticamente collegato a un tuo appunto in basso a sinistra ("Computer Ottici"), fa apparire una connessione fantasma (una linea di luce pulsante, tenue).
Interazione: Se la linea ti piace, ci clicchi sopra o ci passi col dito per renderla "solida". Il tuo grafo della conoscenza cresce da solo, scoprendo pattern che il tuo cervello aveva ignorato.
Implementato in: GhostConnectionWatcher (live + idle mode), ConnectionSuggestionEngine (6 segnali pesati).


3. Espansione a Raggiera (Generative Mind-Mapping) ❌ DA FARE
Stai creando una mappa mentale. Scrivi a mano un concetto centrale: "Ottimizzazione Rendering Flutter". Poi selezioni il nodo e "tiri" col dito una linea verso lo spazio vuoto, tenendo premuto (un "long press").

Cosa fa l'IA: Invece di dover scrivere tu il prossimo nodo, Atlas crea istantaneamente 3-4 bolle olografiche fluttuanti alla fine della linea con dei sotto-argomenti previsti (es. "Impeller", "Tessellazione Vulkan", "Culling").
Interazione: Ne afferri una per confermarla e posizionarla sul canvas, e scarti le altre con uno "swipe". È un brainstorming in "co-op" con l'IA.


4. "Semantic Zoom" Dinamico (Zoom Intelligente) ✅ IMPLEMENTATO
L'intersezione tra: LOD System + Atlas AI + Cluster Detection
Hai un canvas infinito strapieno di appunti dopo mesi di lavoro. Quando rimpicciolisci (zoom out), il testo diventa illeggibile.

Cosa fa l'IA: Sfruttando il sistema LOD (Level of Detail) di Fluera, Atlas sintetizza dinamicamente intere regioni del canvas.
Interazione: Facendo zoom out, 50 appunti sparsi si fondono fluidamente in un unico grande nodo olografico generato dall'IA che dice: "Sviluppo UI e Auth". Quando fai zoom in su quel nodo, si "schiude" rivelando di nuovo i tuoi dettagli originari.
Implementato in: SemanticMorphController (morph continuo 0.0→1.0), God View con super-nodi, AI titles via Atlas, OCR cluster text recognition.


5. Traduzione dell'Inchiostro (Magic Ink-to-System) ❌ DA FARE
L'IA non analizza solo cosa scrivi, ma come lo strutturi nel disegno.

Cosa fa l'IA: Se disegni una tabella a mano un po' storta e ci scrivi dei concetti, Atlas fa brillare i bordi. Se ci fai doppio tap, trasforma quell'inchiostro morto in una vera griglia di dati interattiva o in un Kanban.
Se scrivi una lista puntata con dei quadratini a mano, Atlas capisce che sono "Task" e li sincronizza in modo invisibile con il Time Management di Looponia (Organizer).


6. Cronologia di Pensiero (Il "Replay" Cognitivo) ❌ DA FARE
Tu non ricordi perché 3 mesi fa hai unito due concetti sul canvas.

Cosa fa l'IA: Chiedi ad Atlas "Qual era il filo logico qui?". Atlas oscura dolcemente il canvas attorno a quella zona e "riavvolge" o anima i nodi e le frecce collegate in sequenza temporale, generando una voce testuale fluttuante che ti spiega in linguaggio naturale come è evoluto il tuo pensiero in base all'ordine in cui hai preso quegli appunti.


7. Compressione Semantica (Il collasso dello Spazio-Tempo) ⚠️ PARZIALE
L'intersezione tra: Audio-to-text + Cluster + NLP Locale

Lo Status Quo: Riascoltare e ripassare due ore di lezione richiede due ore. O rileggere un muro di testo.
Il Livello Top Tier: Il "Pinch-to-Compress". Su un Cluster enorme (dove il professore ha parlato per 20 minuti di un concetto, e la trascrizione nascosta è lunghissima), l'utente usa una gesture a pinza. I tratti a mano del Cluster si rimpiccioliscono fino a sparire nel centro e la bolla si trasforma in una Flashcard generata al volo contenente le 5 parole chiave assolute (TF-IDF estrapolate dall'audio di quegli specifici minuti). Stai letteralmente piegando il tempo (20 minuti di audio) e lo spazio (mezzo metro quadrato di appunti) in una singola carta semantica per il ripasso istantaneo.
Stato: La flashcard preview esiste (tap su nodo semantico), ma manca il pinch gesture dedicato.


8. L'Origamento dei PDF (PDF Unrolling Spaziale) ❌ DA FARE
L'intersezione tra: PDF Renderer + Knowledge Connections

Lo Status Quo: Hai collegato un appunto (Cluster A) alla Pagina 45 di un libro in PDF. Tocchi il link, l'app chiude il canvas e ti sbatte a schermo intero sul PDF a riga 45. Hai perso tutto il contesto mentale di dove eri prima.
Il Livello Top Tier: Il PDF vive dentro il canvas e interagisce con lo spazio. Quando premi la Knowledge Connection che porta alla sorgente, la telecamera fa pan verso il bordo del documento PDF. Il PDF (che magari era visualizzato come un piccolo thumbnail chiuso) si "srotola" fisicamente sul canvas allargandosi esattamente fino alla frase o all'immagine che avevi evidenziato, spingendo gentilmente gli appunti vicini per farsi spazio. Leggi la citazione nel suo contesto originario senza mai abbandonare la tua mappa mentale. Quando hai finito, il PDF si riarrotola su se stesso liberando spazio.


9. Il "Ghost Multiplayer" (Collaborazione Asincrona) ❌ DA FARE
L'intersezione tra: Stroke Recording temporizzato + Audio Sync

Lo Status Quo: Collaborazione in tempo reale stile Miro. Vedi il cursore dell'altro muoversi. Utile per i meeting, inutile per lo studio posticipato.
Il Livello Top Tier: Il tuo compagno di corso ti invia il file Fluera della lezione a cui non sei andato. Tu non vedi semplicemente il risultato finale morto. Premi Start. L'audio del prof parte, e l'inchiostro del tuo compagno inizia a fiorire sul canvas in perfetta sincronia cronologica. Ma la magia è che non è un banale video: è un canvas vivo. Mentre la "versione fantasma" del tuo amico sta disegnando il Lato Sinistro della lavagna nel passato, tu adesso nel presente impugni la pencil e disegni le tue personali annotazioni e Knowledge Connections sul Lato Destro, integrandole col flusso temporale in corso. Stai letteralmente prendendo appunti in collaborazione con il passato.


10. Lo Space-Splitting Fluido ❌ DA FARE


5b. Time-Traversal per i PDF ❌ DA FARE
L'intersezione tra: PDF Renderer + Audio Sync

Lo Status Quo: Sottolineare un PDF è un'azione inerte.
Il Livello Top Tier: Mentre registri l'audio di una conferenza in cui il relatore commenta un paper, l'utente evidenzia una riga col pennarello evidenziatore (gestito dallo splendido render Metal/Impeller che hai ottimizzato). Tre mesi dopo, tocca quella highlight gialla: parte l'audio del relatore. E non solo, se avevi "tirato" una connection da quell'highlight a un appunto laterale, l'intera struttura temporale batte allo stesso ritmo.



███████████████████████████████████████████████████████████████████████████████
  SEZIONE B — NUOVE FEATURE IA (dall'analisi del codebase)
  Scoperte analizzando l'infrastruttura esistente del motore.
███████████████████████████████████████████████████████████████████████████████


─── TIER 1: FATTIBILI SUBITO (l'infrastruttura esiste già) ───────────────────


11. 🧲 Smart Auto-Layout (Riorganizzazione Intelligente)
L'intersezione tra: AtlasActionExecutor + SelectionManager + CanvasStateExtractor

L'utente seleziona N nodi sparsi → Atlas li riorganizza in un layout semanticamente logico.
L'infrastruttura c'è già: AtlasAction.moveNode, SelectionManager.alignLeft/Right, CanvasStateExtractor. Manca solo un nuovo tipo di azione Atlas (layout_nodes) che prenda gli ID e restituisca una griglia/radiale/flowchart ottimizzata. Atlas conosce già le posizioni e i contenuti → può disporre i nodi in modi significativi:
- Flowchart temporale (ordine di creazione)
- Mappa concettuale radiale (nodo hub al centro)
- Griglia tematica (raggruppati per argomento)
Serve: 1 nuova AtlasAction + prompt engineering + animazione spring.


12. 🎯 Predictive Connection Builder
L'intersezione tra: ConnectionSuggestionEngine + Knowledge Flow drag gesture

Mentre trascini una connessione da un cluster, Atlas evidenzia i target probabili.
Hai tutto: ConnectionSuggestionEngine.computeSuggestions() + scoring a 6 segnali. Basta invocarla in real-time durante il drag con focusClusterId = source, e illuminare i cluster target con score >0.4 con un glow proporzionale allo score.
Serve: ~50 righe nel gesture handler + render glow sui cluster target.


13. 🎯 Context-Aware Brush Suggestions
L'intersezione tra: ConnectionSuggestionEngine (analisi colori) + Brush Engine

Mentre scrivi, Atlas suggerisce colore/spessore del pennello basandosi sul contesto.
La ConnectionSuggestionEngine già analizza colori dominanti per cluster. Estensione naturale:
- Se stai scrivendo in un cluster di "Definizioni" (tutti blu), suggerisci blu.
- Se appunti "Importante!" → suggerisci rosso/arancione.
- Notifica sottile: un micro-dot sul color picker che pulsa.
Serve: Analisi cluster attivo → suggerimento colore → dot animato.


14. 📋 Smart Clipboard (Copia Aumentata)
L'intersezione tra: CanvasStateExtractor + Scene Graph spatial queries

Quando copi/incolli un gruppo di nodi, Atlas propone dove posizionarli in modo "intelligente".
CanvasStateExtractor.extractFromViewport può analizzare il canvas corrente, trovare "spazi vuoti" semanticamente sensati, e suggerire la posizione di incolla con un preview ghost.
Serve: Spatial query per spazi vuoti + preview overlay.


15. ✍️ Smart Handwriting Cleanup (Abbellimento Intelligente)
L'intersezione tra: Digital Ink OCR + ProStroke points + Bezier curves

Atlas analizza la scrittura a mano e propone una versione "pulita" — stessa calligrafia, ma drizzata e regolarizzata.
Hai già OCR (Digital Ink), hai stroke points (ProStroke.points), hai trasformazioni nel scene graph. L'idea:
- Riconoscimento del testo scritto → rigenera gli stroke con curve Bezier regolarizzate.
- Mantiene il "flavor" della calligrafia (angoli, pressione media) ma elimina tremolii.
- Preview fantasma sovrapposto all'inchiostro originale → swipe per accettare.
Serve: Algoritmo di regolarizzazione bezier + preview overlay + undo.


─── TIER 2: IMPATTO ALTO, RICHIEDE NUOVO CODICE SIGNIFICATIVO ────────────────


16. 🗣️ Voice-to-Canvas (Dettatura Spaziale)
L'intersezione tra: Sherpa Transcription + Atlas AI + AtlasActionExecutor

"Metti un nodo 'Termodinamica' vicino a quello di Fisica" — comandi vocali spaziali.
Hai già: Sherpa transcription, Atlas AI per parsing naturale, AtlasActionExecutor per le azioni. Manca il bridge:
- Streaming transcription → Atlas parsa il comando → esegue azioni.
- Comandi: "crea", "connetti X a Y", "sposta", "cancella".
- Feedback visuale: pulse sul nodo creato/mosso.
Serve: Bridge transcription→Atlas + nuovi prompt commands + UI feedback.


17. 🧩 Ink Pattern Recognition (Riconoscimento Strutture Avanzato)
L'intersezione tra: Digital Ink + Shape Detection + TabularInteractionTool

Disegni una tabella storta → Atlas la riconosce e la converte in una griglia interattiva.
Estensione della feature #5 (Traduzione dell'Inchiostro). Servono:
- Shape detector avanzato (linee parallele → tabella, cerchi con frecce → flowchart).
- Mapping stroke pattern → widget strutturato (tabella, kanban, timeline).
- Il tabular tool (tabular_interaction_tool.dart) è già pronto per le tabelle.
Serve: ML shape classifier + mapping pattern→widget + animazione conversione.


18. 🌐 Cross-Canvas Intelligence (Intelligenza Inter-Documento)
L'intersezione tra: CanvasStateExtractor + Storage System + Atlas AI

Atlas confronta appunti di canvas DIVERSI per trovare connessioni nascoste.
Ogni canvas viene estratto con CanvasStateExtractor → embedding summary. Quando apri un canvas, Atlas silenziosamente confronta i cluster con quelli di altri file Fluera:
- "Hai scritto di Termodinamica anche nel canvas 'Fisica I' — vuoi collegare?"
- Ghost inter-document connection.
Serve: Canvas summary embeddings + cross-file comparison + UI per link inter-canvas.


19. 📊 Auto-Difficulty Tagging (Stima Complessità per il Ripasso)
L'intersezione tra: Atlas AI + SemanticMorphController + Flashcard System

Atlas analizza il contenuto di ogni cluster e assegna un livello di difficoltà (1-5 stelle) basato sulla complessità linguistica e concettuale.
Questo arricchisce il Semantic Zoom: nodi con stelle rosse = argomenti da ripassare. Utile per la flashcard review.
Serve: Prompt Atlas per difficulty scoring + badge nel semantic view.


20. 🎬 Smart Presentation Mode (Export Presentazione)
L'intersezione tra: Cinematic Playback + Camera Flight + Knowledge Graph

Atlas genera una presentazione sequenziale automatica dal knowledge graph.
Hai il cinematic playback + camera flight. Basta che Atlas determini:
1. L'ordine di presentazione (topological sort del knowledge graph).
2. I punti di "wait" (cluster grandi = più tempo).
3. I testi di transizione tra cluster ("Passando da X, collegato a Y perché...").
- Export come video con voice-over sintetico.
Serve: Topological sort + transition text generation + video export.


21. 🔄 Spaced Repetition Engine (Flashcard Intelligenti con SM-2)
L'intersezione tra: Flashcard Preview + Atlas AI + Storage

Atlas converte automaticamente i cluster in deck di flashcard con scheduling SM-2.
Le flashcard già esistono come preview. L'evoluzione:
- Ogni cluster → Front (titolo AI) + Back (OCR text completo + audio correlato).
- Algoritmo SM-2 per scheduling (interval, easeFactor, repetitions).
- Overlay "Study Mode" che presenta le flashcard in sequenza.
- Haptic feedback per "know" / "don't know".
Serve: SM-2 scheduler + Study Mode overlay + persistence.


22. 🧬 Semantic Diff (Tracciamento Evoluzione Concetti)
L'intersezione tra: _aiTitleTextHashes + History System + Atlas AI

Quando l'utente modifica un cluster (aggiunge tratti, cambia testo), Atlas mostra un "diff semantico".
Prima: "Newton + Forza" → Dopo: "Newton + Forza + F=ma + Terza legge".
Notifica sottile: "📈 Concetto espanso: +Terza legge di Newton".
- Usa _aiTitleTextHashes per tracciare cambiamenti.
- Timeline delle evoluzioni semantiche di ogni cluster.
Serve: Diff engine semantico + timeline overlay + notifica.


─── TIER 3: VISIONARIO — RICHIEDE R&D ───────────────────────────────────────


23. 🖼️ Image Understanding (Comprensione Visuale con Gemini)
L'intersezione tra: ImageNode + Gemini Multimodal + Knowledge Graph

Atlas analizza le immagini sul canvas (foto di lavagne, diagrammi, scatti di libri) e le integra nel grafo semantico.
ImageNode esiste, CanvasStateExtractor lo converte in path. Gemini 3.1 supporta multimodal. L'idea:
- Invii l'immagine a Gemini → riconosce il contenuto → crea connessioni con cluster testuali correlati.
- Foto di una lavagna → OCR + knowledge connection automatica con gli appunti dello stesso argomento.
Serve: Gemini vision API + auto-connection builder + UI per preview risultati.


24. 🌊 Emotional Ink Analysis (Analisi Emotiva della Scrittura)
L'intersezione tra: ProDrawingPoint.pressure + Velocity calculation + Atlas AI

Atlas analizza la pressione, velocità e tremori della scrittura per inferire lo stato emotivo dell'utente.
ProDrawingPoint ha pressure, il calcolo di velocità è nel brush engine. Possibile:
- Scrittura veloce + pressione alta = "Stress/Urgenza".
- Tratti lenti + pressione uniforme = "Concentrazione".
- Etichetta colorata sul cluster: 🟢 Calmo / 🟡 Attivo / 🔴 Agitato.
- Utile per il ripasso: "Eri agitato quando hai scritto questo — ripassalo".
Serve: Feature extraction da stroke data + emotion classifier + badge UI.


25. 🕸️ Knowledge Gap Detection (Rilevamento Lacune nel Sapere)
L'intersezione tra: Knowledge Graph analysis + Atlas AI + Connection Suggestions

Atlas analizza il grafo della conoscenza e identifica "buchi" — argomenti che dovrebbero essere collegati ma non lo sono.
Il grafo di conoscenza (clusters + connections) può essere analizzato:
- Cluster isolati senza connessioni = potenziali "orfani".
- Argomenti mancanti: se A→B e B→C esistono ma A→C no, suggerisci il link.
- "Il tuo grafo di Fisica ha 0 connessioni con Matematica. Vuoi che Atlas trovi i legami?"
Serve: Graph analysis algorithms + gap detection + suggestion UI.


26. 🎵 Ambient Soundscape Generation
L'intersezione tra: Semantic Analysis + Audio System + Canvas Content

Basandosi sul contenuto del canvas, Atlas genera un soundscape ambientale.
Canvas di Astronomia → suoni cosmici. Canvas di Biologia → suoni naturali. Non per la produttività, ma per l'immersione:
- Analisi semantica dei titoli → mapping a preset audio.
- Volume proporzionale allo zoom (zoom out = più ampio).
Serve: Theme-to-audio mapping + ambient audio engine + volume controller.


27. 📐 Formula Chain Solver (Risolutore Catene di Formule)
L'intersezione tra: LaTeX Editor/Renderer + Knowledge Connections + CAS Engine

Atlas riconosce catene di formule LaTeX sul canvas e risolve i sistemi automaticamente.
Hai il LaTeX editor/renderer completo. Se l'utente scrive:
- F = ma su un cluster, a = 9.81 m/s² su un altro, m = 5 kg.
- Atlas collega automaticamente le variabili e mostra: F = 49.05 N.
- Visualizzazione: linee dorate tra le variabili condivise.
Serve: Variable extraction da LaTeX + CAS solver + golden link renderer.


28. 🗺️ Study Path Generator (Generatore Percorso di Studio)
L'intersezione tra: Knowledge Graph + Auto-Difficulty + Cinematic Flight

Atlas analizza tutti i cluster e genera un "percorso di studio" ordinato.
Basato su:
- Topological sort del knowledge graph (prerequisiti prima).
- Complessità crescente (auto-difficulty tagging).
- Tempo stimato per cluster (basato su word count + formula density).
- Output: una timeline interattiva che guida lo zoom attraverso i nodi nell'ordine giusto.
Serve: Topological sort + difficulty scoring + study timeline UI + camera guidance.



███████████████████████████████████████████████████████████████████████████████
  SEZIONE C — GESTURES
███████████████████████████████████████████████████████████████████████████████

undo -> tap con due dita
redo -> tap con tre dita
