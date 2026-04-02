# Specifica Implementativa Fluera — Dal Principio al Codice

> **Scopo:** Tradurre ogni principio della Teoria Cognitiva dell'Apprendimento in regole comportamentali concrete, testabili e implementabili per lo sviluppo del motore Fluera.
>
> **Documento di riferimento:** `teoria_cognitiva_apprendimento.md`
>
> **Struttura:** Segue i 12 Passi della Parte X, uno per sezione. Per ogni passo: cosa DEVE fare il software, cosa NON DEVE fare, gli stati dell'IA, le soglie tecniche, e i criteri di accettazione.

---

## PASSO 1 — Appunti a Mano Durante la Lezione

### Contesto

Il Passo 1 è il momento fondativo di tutto il percorso. Lo studente è in aula (o davanti a un video/libro) e prende appunti in tempo reale. Tutto ciò che il software fa o non fa in questo momento determina la qualità della codifica iniziale.

**Principi attivati:** Chunking (§9), Levels of Processing (§6), Embodied Cognition (§23), Flow State (§24), Generation Effect (§3), Spatial Cognition (§22), Multimodal Encoding (§28), Desirable Difficulties (§5), Palazzo della Memoria, Zeigarnik (§7)

---

### 1.1 — Stato del Canvas all'Apertura

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P1-01 | Aprirsi su uno **spazio bianco infinito e silenzioso** — nessun template, nessuna struttura, nessun suggerimento | Desirable Difficulties §5 — il vuoto costringe il Sistema 2 ad attivarsi | 0 elementi UI nel viewport al primo lancio (eccetto toolbar) |
| P1-02 | Se lo studente ha già un canvas con contenuto, **aprirsi esattamente alla posizione e zoom dell'ultima sessione** | Spatial Cognition §22 — la posizione è parte della memoria | Posizione e scala salvate con precisione di 1px / 0.01x |
| P1-03 | Se lo studente naviga verso la zona di una nuova materia, **permettere l'espansione infinita** in qualsiasi direzione senza limiti o "bordi" | Extended Mind §29 — il canvas è il mondo interiore | Pan/zoom verso coordinate mai visitate deve funzionare senza lag o jump |
| P1-04 | Mostrare solo una **toolbar minimale** (penna, colori, gomma, annulla) che scompare durante la scrittura attiva | Flow §24 — nessuna distrazione | Toolbar in auto-hide dopo 2s dall'ultimo tocco sull'interfaccia (non sul canvas) |
| P1-05 | Offrire un **feedback tattile** (haptic) al primo tratto su una zona vergine del canvas — conferma che lo studente sta "occupando" uno spazio nuovo | Embodied Cognition §23 — il gesto deve avere peso | Haptic pulse leggero (UIImpactFeedbackGenerator.light) |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P1-06 | Mostrare suggerimenti tipo "Inizia a scrivere qui" o placeholder | Generation §3 | Sostituisce la decisione spaziale dello studente con una proposta del software |
| P1-07 | Proporre template vuoti (mappe mentali, griglie, Cornell notes, etc.) | Desirable Difficulties §5 | Rimuove la difficoltà desiderabile di creare la propria struttura |
| P1-08 | Attivare l'IA per suggerire una struttura iniziale | Cognitive Offloading §15 | La struttura DEVE emergere dalla mente dello studente, non dall'algoritmo |
| P1-09 | Mostrare tutorial o onboarding overlay sul canvas durante il primo utilizzo | Flow §24 | Spezza il primo contatto tra studente e spazio vuoto |
| P1-10 | Caricare contenuti di sessioni passate come "suggerimenti" di dove continuare | Generation §3 | Lo studente deve scegliere attivamente dove posizionare il nuovo contenuto |

---

### 1.2 — Comportamento Durante la Scrittura Attiva

> **Stato dell'IA:** 💤 **Completamente dormiente.** Nessun processo IA attivo. Il modulo IA non deve ricevere, analizzare o elaborare nulla durante questa fase.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P1-11 | **Latenza del tratto ≤10ms** — il tratto deve apparire prima che la mano si sia mossa visibilmente | Embodied Cognition §23 — il tratto è un'estensione del pensiero | GPU Live Stroke Overlay attivo. Misurato con timestamp touch → primo pixel renderizzato |
| P1-12 | **Sensibilità alla pressione e all'inclinazione** — il tratto deve "sentirsi" come inchiostro su carta | Embodied Cognition §23, Handwriting Advantage §25 | Min 256 livelli di pressione. Angolo di inclinazione influenza larghezza tratto |
| P1-13 | **Palm rejection perfetto** — la mano appoggiata non genera MAI tratti involontari | Flow §24 — un tratto involontario rompe il Flow | 0 false positives in test di 30min di scrittura continua |
| P1-14 | **Libertà spaziale totale** — lo studente può scrivere in qualsiasi punto, in qualsiasi direzione, a qualsiasi scala | Spatial Cognition §22, Palazzo della Memoria | No vincoli di layout, no margini, no "pagine", no snap-to-grid |
| P1-15 | **Zoom e pan a due dita** fluidi e mai in conflitto col tratto della penna | Flow §24 | Nessun caso in cui un gesto di zoom venga interpretato come tratto |
| P1-16 | **Cambio strumento in <200ms** (colore, spessore, gomma) con zero sforzo cognitivo | Flow §24, Multimodal Encoding §28 | Shortcut fisico sulla penna (doppio tap) o gesto rapido |
| P1-17 | **Auto-hide della toolbar** durante la scrittura — il canvas diventa SOLO penna e superficie | Flow §24 | Toolbar sparisce dopo 2s dall'inizio del primo tratto. Riappare con tap su area toolbar |
| P1-18 | **I colori sono sempre accessibili** anche durante la scrittura attiva — tramite color shortcut, non tramite navigazione UI | Multimodal Encoding §28, Flow §24 | Max 1 gesto per cambiare colore |
| P1-19 | **Annulla/Ripristina** (undo/redo) istantanei e illimitati | Flow §24 — l'errore non deve costare tempo | Undo ≤50ms. Cronologia illimitata nella sessione |
| P1-20 | **Suono e haptic al cambio strumento** — feedback sensoriale che conferma la modalità senza guardare | Embodied Cognition §23 | Haptic + suono distinto per ogni strumento (opzionale, configurabile) |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P1-21 | Raddrizzare automaticamente le linee tracciate a mano | Generation §3, Embodied §23 | L'imperfezione del tratto è una traccia mnestica motoria — raddrizzarla la cancella |
| P1-22 | Convertire automaticamente la scrittura a mano in testo digitato (HTR) | Generation §3, Levels of Processing §6 | Il tratto calligrafico personale è superiore neurobiologicamente al testo tipografico |
| P1-23 | "Agganciare" (snap) i tratti a griglie invisibili | Spatial Cognition §22 | La posizione scelta dallo studente è sacra — è un locus nel Palazzo della Memoria |
| P1-24 | Suggerire completamenti di forme ("Volevi fare un cerchio?") | Desirable Difficulties §5 | Lo sforzo di disegnare una forma imperfetta È la codifica |
| P1-25 | Mostrare QUALSIASI popup, notifica, tooltip o overlay mentre la penna è a contatto o entro 2s dall'ultimo tratto | Flow §24 | Ogni interruzione rompe il Flow e richiede 15-25 minuti per rientrare (ricerca Csikszentmihalyi) |
| P1-26 | Far analizzare il contenuto scritto all'IA in background | Cognitive Offloading §15, System 1/2 §13 | Se l'IA elabora in background, prima o poi il risultato verrà mostrato — e quello è offloading |
| P1-27 | Mostrare un indicatore "l'IA sta pensando" o "analisi in corso" | Autonomy (T2) | La consapevolezza che qualcuno sta "guardando" cambia il comportamento dello studente |
| P1-28 | Proporre link automatici tra il blocco appena scritto e blocchi precedenti | Generation §3 | Le connessioni devono essere generate dallo studente — è l'atto di tracciare la freccia che codifica la relazione |
| P1-29 | Riorganizzare automaticamente i nodi per "migliorare" il layout | Spatial Cognition §22, Palazzo della Memoria | La posizione è un locus. Muoverlo è come riarredare il palazzo di qualcuno mentre dorme |
| P1-30 | Riprodurre animazioni, transizioni o effetti visivi non richiesti durante la scrittura | Flow §24 | Qualsiasi movimento nell'area periferica della visione cattura l'attenzione e rompe il Flow |

---

### 1.3 — Comportamento Post-Tratto (Pausa >3 secondi)

Lo studente ha alzato la penna e sta pensando. Il canvas può offrire **affordance passive** — mai suggerimenti attivi.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P1-31 | Mostrare **connettori discreti** (piccoli punti) alle estremità dei blocchi scritti — solo al passaggio del dito/penna sopra | Concept Mapping §27 | Connettori visibili solo su hover/proximity. Opacità 30% → 100% su hover |
| P1-32 | Permettere di assegnare un **colore retroattivo** al blocco appena scritto | Multimodal Encoding §28 | Gesto rapido: long-press sul blocco → selettore colore minimale |
| P1-33 | Permettere di **spostare/ridimensionare** il blocco scritto per riposizionarlo nel Palazzo | Spatial Cognition §22 | Drag & drop fluido ≤16ms per frame |
| P1-34 | Mostrare un **indicatore di nodo incompleto** (contorno tratteggiato) se il blocco contiene un "?" visibile o sembra un concetto parziale | Zeigarnik §7 | Riconoscimento del "?" nel tratto (opzionale, pattern recognition leggero) |
| P1-35 | Permettere di tracciare **frecce** tra nodi con un gesto intuitivo (drag da connettore a connettore) | Concept Mapping §27, Palazzo della Memoria (Strade) | Il gesto di connessione deve essere intuitivo: ≤2 azioni |
| P1-36 | Permettere di **etichettare** le frecce scrivendo a mano sopra di esse | Elaborazione Profonda §6 | La scrittura a mano sulle frecce dev'essere fluida come sul canvas |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P1-37 | Suggerire "Vuoi che l'IA espanda questo concetto?" | Cognitive Offloading §15 | Lo studente deve sentire il vuoto e la tensione del nodo incompleto — non avere una scorciatoia |
| P1-38 | Mostrare contenuti correlati da internet o dal materiale del corso | Active Recall §2 | Se il contenuto arriva dall'esterno, lo studente non sta generando — sta leggendo |
| P1-39 | Analizzare il contenuto scritto per offrire feedback non richiesto | Autonomy T2 | Feedback non richiesto viola la sovranità cognitiva |
| P1-40 | Suggerire automaticamente connessioni tra nodi | Generation §3, Concept Mapping §27 | L'atto di decidere quali nodi connettere e quali no È un atto di comprensione |
| P1-41 | Convertire automaticamente il contenuto in un formato diverso (testo, outline, flashcard) | Generation §3, Embodied §23 | Il formato scelto dallo studente (scrittura a mano, disegno, frecce) è intenzionale e codifica informazione |

---

### 1.4 — Interazione con lo Spazio: Costruzione del Palazzo della Memoria

Queste regole governano come lo studente costruisce il suo Palazzo mentre prende appunti.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P1-42 | **Zoom continuo e fluido** dall'intera triennale fino alla singola parola — senza step, senza scatti | Zoom Semantico §26, Palazzo (Piani) | Interpolazione lineare del zoom. FPS ≥60 durante pinch |
| P1-43 | **LOD (Level of Detail)** — a zoom-out, i nodi piccoli diventano blob colorati irriconoscibili; zoomando in, appaiono i dettagli | Zoom Semantico §26 | Almeno 3 livelli di LOD: blob → titolo → contenuto completo |
| P1-44 | **Pan infinito** in tutte le direzioni senza limiti, bordi o "muri" | Extended Mind §29 | No coordinate massime. Lo spazio è matematicamente illimitato |
| P1-45 | **Memory position** — ad ogni chiusura dell'app, salvare posizione e zoom esatti | Spatial Cognition §22 | Persistere viewport state nel database locale |
| P1-46 | **Colori persistenti e significativi** — se lo studente scrive in blu, il tratto resta blu per sempre a meno che lui non lo cambi | Multimodal Encoding §28, Palazzo (Stanze) | No modifica automatica dei colori |
| P1-47 | **Spazio bianco illimitato tra cluster** — i gruppi di nodi devono poter essere separati da distanze arbitrarie | Chunking §9, Palazzo (Quartieri) | Il rendering deve gestire nodi a coordinate molto distanti senza performance issues |
| P1-48 | **Frecce di qualsiasi lunghezza** — da nodi adiacenti a nodi distanti migliaia di pixel | Palazzo (Strade), Interleaving §10 | Rendering efficiente delle frecce lunghe (culling, LOD sulle frecce) |

---

### 1.5 — Stato dell'IA durante il Passo 1

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 💤 DORMIENTE                      │
│                                                  │
│  • Modulo IA: NON attivo                         │
│  • Analisi contenuto: NESSUNA                    │
│  • Riconoscimento handwriting: NESSUNO           │
│  • Suggerimenti: NESSUNO                         │
│  • Indicatore visivo IA: INVISIBILE              │
│  • Unica eccezione: pattern "?" per Zeigarnik    │
│    (opzionale, locale, non IA)                   │
│                                                  │
│  L'IA si sveglierà SOLO al Passo 3,             │
│  su invocazione esplicita dello studente.        │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!CAUTION]
> ### La Regola Suprema del Passo 1
> **Ogni feature che "aiuta" lo studente durante il Passo 1 è un danno cognitivo.** L'aiuto sottrae fatica. La fatica è la codifica. Sottrarre fatica = sottrarre apprendimento. Il software in questo passo ha UN SOLO compito: essere un foglio di carta infinito, reattivo e silenzioso. Tutto il resto è rumore.

---

### 1.6 — Criteri di Accettazione (QA Checklist)

Ogni criterio DEVE essere verificato prima del rilascio:

- [ ] **CA-01:** Lo studente può aprire il canvas e scrivere il primo tratto in <3s dall'apertura dell'app
- [ ] **CA-02:** Il tratto ha latenza ≤10ms in tutti i dispositivi target
- [ ] **CA-03:** 30 minuti di scrittura continua: 0 interruzioni da parte del software
- [ ] **CA-04:** 30 minuti di scrittura continua: 0 tratti involontari da palm rejection
- [ ] **CA-05:** Zoom da 0.01x a 100x: ≥60 FPS, nessuno scatto
- [ ] **CA-06:** Pan verso coordinate mai visitate: nessun bordo raggiunto
- [ ] **CA-07:** Cambio colore: ≤1 gesto, ≤200ms
- [ ] **CA-08:** Undo: ≤50ms, cronologia illimitata
- [ ] **CA-09:** Chiusura e riapertura: stessa posizione e zoom, pixel-perfect
- [ ] **CA-10:** Nessun elemento IA visibile durante tutta la sessione di scrittura
- [ ] **CA-11:** Nessun suggerimento, template o placeholder visibile al primo lancio
- [ ] **CA-12:** Toolbar auto-hide funzionante: scompare entro 2s, riappare al tap
- [ ] **CA-13:** Connettori visibili solo su hover, non default
- [ ] **CA-14:** Frecce tracciabili tra qualsiasi coppia di nodi, a qualsiasi distanza
- [ ] **CA-15:** LOD attivo: a zoom-out i nodi piccoli diventano blob, a zoom-in appaiono i dettagli

---
---

## PASSO 2 — L'Elaborazione Solitaria: Riscrivere Senza Guardare

### Contesto

Il Passo 2 avviene **2-4 ore dopo** il Passo 1, nello stesso giorno. Lo studente chiude libro/slide/video e tenta di ricostruire i concetti **dalla memoria**, in una zona adiacente del canvas, senza guardare i propri appunti del Passo 1.

Questo è il passo con il **design più critico**: il software deve rendere facile NON sbirciare, senza essere coercitivo. Il fallimento (nodi che non si ricordano) non è un bug — è la **Productive Failure (T4)** che prepara il cervello ai Passi successivi.

**Principi attivati:** Active Recall (§2), Generation Effect (§3), Spacing (§1), Levels of Processing (§6), Productive Failure (T4), Metacognition (T1), Zeigarnik (§7), Spatial Cognition (§22), Ipercorrezione (§4)

---

### 2.1 — Attivazione della Modalità Ricostruzione

Lo studente decide di passare dal Passo 1 al Passo 2. Il software deve facilitare questa transizione con una feature specifica: la **Modalità Ricostruzione** (Recall Mode).

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-01 | Offrire un'azione esplicita **"Modalità Ricostruzione"** accessibile dalla toolbar o da un gesto (es. long-press su zona vuota) | Metacognition T1 — lo studente decide consapevolmente di passare al recall | Accesso in ≤2 gesti dalla scrittura. Nessuna attivazione automatica |
| P2-02 | All'attivazione, **schermare (blur/oscurare) tutti i nodi del Passo 1** nella zona corrente — rendendoli invisibili ma presenti | Active Recall §2 — il contenuto deve essere recuperato dalla memoria, non riletto | Blur gaussiano sufficiente a rendere il testo illeggibile (raggio ≥20px). I blob colorati restano vagamente visibili come "sagome" |
| P2-03 | Evidenziare visivamente una **zona adiacente vuota** come "area di ricostruzione" — con un sottile bordo o cambio tonalità dello sfondo | Spatial Cognition §22 — la ricostruzione vive in uno spazio separato ma vicino | Il bordo è discreto (opacità 15-20%), non invasivo. Colore neutro |
| P2-04 | Mostrare un **timer opzionale** (contatore del tempo trascorso) in angolo, semi-trasparente | Metacognition T1 — consapevolezza del tempo dedicato al recall | Timer non obbligatorio. Opacità 30%. No allarmi, no pressione |
| P2-05 | Mostrare un **contatore dei nodi ricostruiti** vs stima dei nodi originali (opzionale, attivabile) | Metacognition T1 — quantificare il progresso del recall | Contatore discreto: "Ricostruiti: 7 · Originali: ~12" |
| P2-06 | Permettere di **navigare** liberamente nella zona di ricostruzione con pan e zoom, mantenendo la schermatura sui nodi originali | Spatial Cognition §22 | La schermatura segue il viewport: i nodi originali restano blurrati ovunque si navighi |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P2-07 | Attivare automaticamente la Modalità Ricostruzione (es. "Sono passate 2 ore, vuoi ricostruire?") | Autonomy T2 | La decisione di quando fare recall deve essere dello studente — non una notifica push |
| P2-08 | Bloccare completamente l'accesso ai nodi del Passo 1 (es. eliminare la possibilità di sbirciare) | Autonomy T2 | Lo studente deve poter scegliere di rivelare, ma la rivelazione deve essere un atto esplicito e consapevole (vedi P2-16) — non un blocco forzato |
| P2-09 | Mostrare un "punteggio" o "voto" durante la ricostruzione | Growth Mindset §12 | Il recall non è un esame — è un esercizio. I punteggi creano ansia da prestazione |
| P2-10 | Suggerire "Hai dimenticato qualcosa" o "Prova a ricordare X" | Active Recall §2, Generation §3 | Qualsiasi suggerimento è un indizio che contamina il recall puro |

---

### 2.2 — Comportamento Durante la Ricostruzione (Scrittura Attiva in Recall Mode)

Lo studente scrive in una zona vuota del canvas, tentando di ricostruire dalla memoria ciò che aveva scritto nel Passo 1. Tutte le regole del Passo 1 sulla scrittura attiva (P1-11 → P1-30) continuano a valere integralmente. In più:

> **Stato dell'IA:** 💤 **Ancora dormiente.** Nessuna analisi. Nessun suggerimento. L'IA si sveglierà solo al Passo 3.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-11 | Tutte le regole P1-11 → P1-30 (scrittura attiva) **restano attive identiche** | Tutti i principi del Passo 1 | Nessuna differenza di comportamento della penna tra Passo 1 e Passo 2 |
| P2-12 | Lo studente può usare **colori diversi** da quelli del Passo 1 per la ricostruzione — nessuna imposizione | Multimodal Encoding §28 | Piena libertà cromatica |
| P2-13 | Lo studente può **posizionare i nodi ricostruiti ovunque** — non è obbligato a replicare la posizione originale | Spatial Cognition §22, Generation §3 | La ricostruzione è una nuova generazione, non una copia. Posizioni diverse = nuova comprensione |
| P2-14 | Offrire un **marker "non ricordo"** con un gesto rapido — crea un nodo rosso vuoto con bordo tratteggiato nella posizione corrente | Productive Failure T4, Zeigarnik §7 | Gesto: doppio tap su zona vuota in Recall Mode → crea nodo rosso vuoto. ≤1 gesto |
| P2-15 | I nodi "non ricordo" devono avere un **aspetto visivo distinto e drammatico** — rosso, tratteggiato, semi-trasparente — che comunichi visivamente "QUI C'È UNA LACUNA" | Ipercorrezione §4, Metacognition T1 | Colore: rosso (#FF3B30). Bordo tratteggiato. Opacità 60%. Icona "?" al centro |
| P2-16 | Permettere una funzione **"Sbircia"** (peek) che rivela temporaneamente UN singolo nodo originale per 3 secondi, poi lo ri-offusca — con un costo visivo (il nodo "sbirciato" viene marcato in giallo) | Active Recall §2 — se sbirci, almeno paghi il prezzo metacognitivo di sapere che hai sbirciato | Long-press su nodo blurrato → reveal 3s → ri-blur automatico. Nodo marcato giallo |
| P2-17 | Il nodo "sbirciato" (giallo) deve restare **permanentemente marcato** come "assistito" nel confronto finale | Metacognition T1, Ipercorrezione §4 | Tag `peeked: true` su quel nodo, visibile nel confronto |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P2-18 | Mostrare i nodi originali non blurrati "a richiesta generica" (es. pulsante "mostra tutto") | Active Recall §2 | La rivelazione deve essere nodo-per-nodo (peek), mai globale — altrimenti il recall è finito |
| P2-19 | Indicare DOVE nello spazio si trovavano i nodi originali (es. sagome posizionali) | Generation §3, Spatial Cognition §22 | La ricostruzione della POSIZIONE è parte del recall spaziale. Mostrare dove erano uccide il retrieval delle Place Cells |
| P2-20 | Suggerire quanti nodi mancano o quali argomenti non sono stati coperti | Active Recall §2 | Il non sapere quanti nodi mancano È la tensione metacognitiva. Quantificarla riduce lo sforzo |
| P2-21 | Attivare l'IA per verificare la correttezza di ciò che lo studente sta ricostruendo | Active Recall §2, Productive Failure T4 | La ricostruzione può essere errata — e DEVE essere errata dove lo studente non sa. Il feedback arriverà al Passo 3 |
| P2-22 | Dare feedback in tempo reale (verde = giusto, rosso = sbagliato) durante la scrittura | Productive Failure T4 | Il feedback immediato distrugge il Productive Failure. Lo studente deve completare la ricostruzione PRIMA di scoprire gli errori |

---

### 2.3 — La Fase di Confronto (Reveal)

Quando lo studente decide di aver finito la ricostruzione, attiva il **Confronto** — il momento in cui la schermatura sui nodi originali viene rimossa e i due "set" sono visibili fianco a fianco.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-23 | Il confronto si attiva SOLO su **azione esplicita dello studente** ("Ho finito, mostra il confronto") | Autonomy T2, Productive Failure T4 | Pulsante o gesto esplicito. Mai automatico |
| P2-24 | **Rimuovere il blur gradualmente** (animazione di reveal ~1s) — non un flash istantaneo | Embodied Cognition §23 — la transizione deve essere percepita come importante | Animazione: blur radius da 20px a 0px in ~1000ms, easing ease-out |
| P2-25 | Mostrare i nodi originali e i nodi ricostruiti **fianco a fianco** nello spazio — il canvas mostra entrambe le zone simultaneamente | Concept Mapping §27, Metacognition T1 | Auto-zoom per inquadrare entrambe le zone. Il layout spaziale relativo resta intatto |
| P2-26 | **Evidenziare visivamente le differenze:** nodi presenti solo nell'originale (lacune → rosso), nodi presenti in entrambi (ricordati → verde), nodi presenti solo nella ricostruzione (aggiunte → blu) | Ipercorrezione §4, Metacognition T1 | Overlay colorato semi-trasparente sui nodi: rosso (opacità 30%), verde (opacità 20%), blu (opacità 20%) |
| P2-27 | I nodi "sbirciati" (peek, gialli) devono essere evidenziati **separatamente** — lo studente vede quanti nodi ha potuto ricostruire da solo e quanti ha dovuto sbirciare | Metacognition T1 | Colore giallo (#FFCC00) con icona occhio |
| P2-28 | Permettere allo studente di **navigare** tra le lacune (nodi rossi) con un gesto "prossima lacuna" | Zeigarnik §7 — le lacune devono attrarre l'attenzione | Navigazione: swipe o pulsante "→" per saltare al prossimo nodo rosso |
| P2-29 | Per ogni lacuna (nodo rosso), permettere allo studente di **scrivere a mano** la correzione direttamente accanto al nodo mancante | Generation §3, Ipercorrezione §4 | La correzione è un tratto a mano, non una copia. Lo studente DEVE riscrivere con la penna |
| P2-30 | Salvare la **mappa di lacune** (quali nodi ricordati, quali no, quali sbirciati) come metadato della sessione per l'SRS dei passi successivi | Spacing §1, Metacognition T1 | Metadato persistito: `{nodeId, status: recalled|missed|peeked, confidence?, timestamp}` |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P2-31 | Copiare automaticamente i nodi mancanti nella zona di ricostruzione | Generation §3 | Il contenuto mancante DEVE essere riscritto a mano dallo studente — è la correzione motoria che crea la traccia mnestica |
| P2-32 | Assegnare un "voto" o "percentuale" al recall | Growth Mindset §12 | Il numero nudo è demotivante. Lo studente deve vedere la mappa di lacune visivamente, non un numero |
| P2-33 | Suggerire "Vuoi che l'IA ti spieghi i concetti mancanti?" | Active Recall §2, Productive Failure T4 | Le lacune devono creare tensione Zeigarnik (§7) che guiderà lo studio successivo — non risolversi immediatamente |
| P2-34 | Fusionare automaticamente la ricostruzione con l'originale | Spatial Cognition §22, Generation §3 | I due set devono restare visivamente separati — la ricostruzione è una "seconda mano" nella stessa zona del Palazzo |

---

### 2.4 — Stato dell'IA durante il Passo 2

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 💤 ANCORA DORMIENTE               │
│                                                  │
│  • Modulo IA: NON attivo                         │
│  • Analisi contenuto: NESSUNA                    │
│  • Confronto originale/ricostruzione: LOCALE     │
│    (diff strutturale, NO interpretazione IA)     │ 
│  • Suggerimenti: NESSUNO                         │
│  • Verifica correttezza: NESSUNA                 │
│                                                  │
│  Il confronto nel Passo 2 è puramente VISIVO     │
│  e SPAZIALE — lo studente vede da solo cosa      │
│  manca. L'IA interviene solo al Passo 3.         │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> ### La Funzione del Passo 2 nel Framework
> Il Passo 2 ha **due obiettivi**, entrambi indipendenti dall'IA:
> 1. **Active Recall** — lo sforzo di ricostruire cementa i nodi ricordati
> 2. **Mappa di Lacune** — i nodi NON ricordati diventano il piano di attacco per il Passo 3 (IA Socratica)
>
> Se lo studente salta il Passo 2 e va direttamente al Passo 3, l'IA interrogherà su TUTTO — senza sapere cosa lo studente sa e cosa no. Il Passo 2 calibra il Passo 3.

---

### 2.5 — Transizione verso il Passo 3

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-35 | Dopo il confronto, offrire un'azione **"Avvia Interrogazione Socratica"** che transiziona al Passo 3 | Metacognition T1 | Pulsante visibile dopo il reveal. Mai automatico |
| P2-36 | Passare la **mappa di lacune** al modulo IA come contesto per il Passo 3 — l'IA saprà quali nodi lo studente NON ha ricordato e concentrerà le domande lì | Spacing §1, ZPD §19 | Payload JSON: lista nodi con status recalled/missed/peeked |
| P2-37 | Permettere allo studente di tornare a **scrivere liberamente** (disattivare la Modalità Ricostruzione) senza perdere i dati del confronto | Autonomy T2 | Toggle in barra: "Esci da Modalità Ricostruzione". I dati sono salvati |

---

### 2.6 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-16:** Attivazione Modalità Ricostruzione: ≤2 gesti, ≤500ms
- [ ] **CA-17:** Blur sui nodi originali: testo illeggibile, blob colorati vagamente visibili
- [ ] **CA-18:** Marker "non ricordo" creabile con ≤1 gesto (doppio tap)
- [ ] **CA-19:** Funzione "Sbircia" (peek): reveal 3s → ri-blur automatico → nodo marcato giallo
- [ ] **CA-20:** Confronto reveal: animazione graduale (~1s), no flash
- [ ] **CA-21:** Evidenziazione differenze: 3 colori distinti (rosso/verde/blu + giallo per peek)
- [ ] **CA-22:** Navigazione tra lacune: swipe o pulsante "→" funzionante
- [ ] **CA-23:** Mappa lacune salvata come metadato con nodeId e status per ogni nodo
- [ ] **CA-24:** Nessun intervento IA durante l'intera durata del Passo 2
- [ ] **CA-25:** Tutte le regole di scrittura attiva del Passo 1 (P1-11→P1-30) verificate anche in Recall Mode
- [ ] **CA-26:** Uscita dalla Modalità Ricostruzione: i dati del confronto sono persistiti
- [ ] **CA-27:** Transizione al Passo 3: mappa lacune trasmessa al modulo IA come contesto

---

### 2.7 — Approfondimento: Free Recall vs. Spatial Recall

> *Questa sezione chiarisce un'ambiguità di design che, se risolta male, compromette l'intero Passo 2.*

La letteratura distingue due tipi di retrieval radicalmente diversi:

- **Free Recall (Tulving, 1967):** Ricostruire il contenuto in ordine libero, senza cue. Lo studente scrive "tutto quello che ricorda" senza aiuti posizionali.
- **Spatial Recall (Place Cells §22):** Ricostruire il contenuto ricordando dove era posizionato nello spazio. Lo studente tenta di ricreare la geometria del Palazzo.

**Il Passo 2 di Fluera deve supportare ENTRAMBI**, ma in momenti diversi:

| Fase | Tipo di Recall | Cosa vede lo studente | Cosa testa |
|------|---------------|----------------------|------------|
| **Fase A: Free Recall** | Contenuto puro | Canvas vuoto senza nessun indizio — nemmeno blob colorati | *Cosa* ricordo? |
| **Fase B: Spatial Recall** | Posizione + contenuto | Blob vagamente visibili (sagome dei nodi originali senza testo) — indici posizionali | *Dove* l'avevo messo? Cosa c'era lì? |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-38 | Offrire la scelta tra **Due Modalità** al momento dell'attivazione del Recall Mode: "Free Recall" (schermo completamente vuoto) e "Spatial Recall" (blob visibili) | Active Recall §2 — il Free Recall è più difficile ma produce ricordi più robusti | Toggle visivo chiaro al momento dell'attivazione. Default: Free Recall |
| P2-39 | In **Free Recall**, la zona originale è completamente vuota — nessun blob, nessuna sagoma, nessun indizio posizionale. Lo studente scrive in uno spazio bianco puro | Active Recall §2 | Opacità dei nodi originali: 0%. Nessun rendering |
| P2-40 | In **Spatial Recall**, i nodi originali appaiono come **blob colorati sfocati** — posizione e colore visibili, contenuto testuale illeggibile | Spatial Cognition §22 — testa il retrieval posizionale | Shapes riconoscibili (riquadri colorati con blur). Testo al 100% illeggibile |
| P2-41 | Lo studente può **passare da Free a Spatial** durante la sessione (es. inizia in Free, quando è bloccato passa a Spatial per gli indizi posizionali) ma NON viceversa | Desirable Difficulties §5 — si parte dal più difficile | Transizione unidirezionale: Free → Spatial ✅ · Spatial → Free ❌ |
| P2-42 | Se lo studente passa da Free a Spatial, il sistema **registra il momento** del passaggio per la mappa di lacune | Metacognition T1 | Metadato: `{switchedToSpatialAt: timestamp, nodesRecalledBefore: n, nodesRecalledAfter: m}` |

> [!TIP]
> **Free Recall è più faticoso (=più efficace)** ma può essere frustrante per studenti alle prime armi. La regola suggerita è: iniziare in Free, passare a Spatial quando il recall si blocca. Il passaggio stesso è un dato metacognitivo prezioso — indica quanto dello studente dipende dalla memoria posizionale vs. dalla memoria semantica.

---

### 2.8 — Approfondimento: Il Problema del Recall Parziale

La versione attuale ha solo 3 stati: **ricordato** (verde), **non ricordato** (rosso), **sbirciato** (giallo). Ma nella realtà, il recall non è binario. Lo studente potrebbe:

- Ricordare il concetto ma non la formula
- Ricordare il titolo ma non il contenuto
- Ricordare l'essenza ma con un dettaglio errato
- Ricordare il nodo ma non le sue connessioni

#### Il Sistema a 5 Livelli di Recall

| Livello | Icona | Colore | Significato | Esempio |
|---------|-------|--------|-------------|---------|
| **5 — Recall Perfetto** | ✅ | Verde pieno | Lo studente ha ricostruito il nodo con precisione e nel posto giusto | Ha riscritto la formula corretta, nella posizione approssimativa giusta |
| **4 — Recall Sostanziale** | 🟢 | Verde chiaro | Il concetto c'è ma mancano dettagli o la posizione è diversa | Ha scritto "2° principio termodinamica: l'entropia aumenta" ma senza la formula |
| **3 — Recall Parziale** | 🟡 | Arancione | Lo studente ricorda qualcosa ma è frammentario o impreciso | Ha scritto "qualcosa sull'entropia..." senza dettagli |
| **2 — Tip-of-Tongue** | 🟠 | Arancione scuro | Lo studente sa che c'era qualcosa ma non riesce a evocarlo | Ha creato un nodo "?? qualcosa di termodinamica..." |
| **1 — Miss Totale** | ❌ | Rosso | Lo studente non ricorda che esistesse quel nodo | Nessun nodo creato — la lacuna emerge solo al confronto |
| **0 — Sbirciato** | 👁️ | Giallo | Lo studente ha usato la funzione peek | Non conta come recall autonomo |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-43 | Dopo il confronto, permettere allo studente di **auto-valutare** ogni nodo ricostruito con il livello di recall (5→1) tramite gesto rapido | Metacognition T1 — la valutazione del proprio recall è metacognizione pura | Swipe o tap ripetuti sul nodo per ciclare tra i livelli. Max 1 gesto per assegnare il livello |
| P2-44 | Il livello di recall auto-valutato viene **salvato nel metadato** del nodo e usato dall'SRS nei Passi successivi | Spacing §1 | Schema: `{nodeId, recallLevel: 1-5, peeked: bool, timestamp, recallType: free|spatial}` |
| P2-45 | I nodi con recall ≤2 (Tip-of-Tongue e Miss) devono essere trattati come **priorità massima** dall'IA Socratica nel Passo 3 | ZPD §19 | L'IA riceve i livelli e calibra le domande: recall 1-2 → domande di base, recall 3 → domande di precisione, recall 4-5 → domande di transfer |
| P2-46 | L'auto-valutazione è **opzionale**. Se lo studente non la fa, il sistema assegna recall binario (verde/rosso) automaticamente | Autonomy T2 | Fallback: nodo ricostruito = verde (recall 5), nodo non ricostruito = rosso (recall 1) |

> [!WARNING]
> **L'auto-valutazione NON deve essere un freno.** Se lo studente trova tedioso assegnare un livello a ogni nodo, deve poter scegliere la modalità semplice (verde/rosso binario). La complessità è un'opzione per chi vuole massimizzare l'efficacia — mai un obbligo. Lo studente che non vuole usarla DEVE ottenere comunque un'esperienza completa e funzionale.

---

### 2.9 — Approfondimento: Cos'è un "Nodo"?

Problema critico: il sistema deve sapere cosa conta come "unità di recall" per poter:
- Contare i nodi originali vs. ricostruiti
- Mostrare le differenze nel confronto
- Passare la mappa lacune all'IA

Ma lo studente scrive a mano liberamente — come fa il sistema a sapere dove finisce un nodo e inizia un altro?

#### Regola di Design: Il Nodo è un Cluster Spaziale

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P2-47 | Un **nodo** è un insieme di tratti raggruppati spazialmente, separati da **spazio bianco significativo** da altri gruppi | La segmentazione è basata sulla prossimità spaziale, non sul contenuto semantico |
| P2-48 | L'algoritmo di segmentazione è **offline e locale** — viene eseguito dopo che lo studente ha finito di scrivere nel Passo 1, non in tempo reale | Non deve interferire con la scrittura attiva. Nessun calcolo durante il Flow |
| P2-49 | Lo studente può **correggere manualmente** i raggruppamenti: dividere un cluster troppo grande in due nodi separati, o fondere due cluster piccoli in un nodo unico | La segmentazione automatica è un suggerimento, non un decreto |
| P2-50 | L'algoritmo di segmentazione usa un **threshold spaziale configurabile**: tratti entro N pixel di distanza = stesso nodo. Default: N = dimensione media di un blocco di testo scritto a mano (~150px) | Il threshold deve essere tunabile perché la calligrafia varia da studente a studente |
| P2-51 | Non è necessario che la segmentazione sia perfetta. La **tolleranza all'errore** è alta perché la mappa lacune è un'indicazione, non un punteggio esatto | Falsi positivi (un nodo diviso in due) e falsi negativi (due nodi fusi) sono accettabili se ≤15% |

---

### 2.10 — Approfondimento: Sessioni Multiple di Recall (Successive Relearning)

La ricerca di Rawson & Dunlosky (2011) dimostra che il recall singolo non basta — servono sessioni multiple distanziate. La loro regola pratica è il **"3 e 3"**:
- **3 recall corretti** nella prima sessione di apprendimento
- **3 sessioni di riapprendimento** distanziate nel tempo

Il Passo 2 non avviene una sola volta. Lo studente tornerà a fare recall sulla stessa materia più volte nei giorni successivi (Passi 6, 8, 10).

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-52 | Il sistema deve **salvare la cronologia** di ogni sessione di recall per ogni zona del canvas: quando è stata fatta, quanti nodi ricordati, quanti mancati | Successive Relearning (Rawson & Dunlosky, 2011) | DB schema: `recall_sessions(zone_id, timestamp, total_nodes, recalled, missed, peeked, recall_type)` |
| P2-53 | Mostrare allo studente, quando attiva il Recall Mode, una **mini-cronologia** delle sessioni precedenti su quella zona: "Ultima ricostruzione: 3 giorni fa · Recall: 8/12" | Metacognition T1, Spacing §1 | Visualizzazione discreta in barra, opzionale |
| P2-54 | Il livello di blur nel Spatial Recall può essere **adattivo** tra sessioni: alla prima ricostruzione, i blob sono molto visibili; alla terza, i blob sono quasi trasparenti | Desirable Difficulties §5 — la difficoltà aumenta col numero di sessioni | Opacità blob: sessione 1 = 50%, sessione 2 = 30%, sessione 3+ = 15% |
| P2-55 | Nelle sessioni successive, mostrare un **indicatore di progresso** per ogni nodo: "Questo nodo l'hai ricordato 2/3 volte" | Successive Relearning, Metacognition T1 | Contatore per nodo visibile nell'overlay di confronto |
| P2-56 | Dopo **3 recall corretti consecutivi** (livello ≥4) di uno stesso nodo in sessioni diverse, il nodo viene marcato come **"padroneggiato"** (icona stella) e l'SRS rallenta gli intervalli per quel nodo | Rawson & Dunlosky "3 e 3" | Flag: `mastered: true` dopo 3 recall ≥4 in sessioni distanziate ≥24h |

---

### 2.11 — Approfondimento: Design Emozionale — Celebrare i Successi

> [!IMPORTANT]
> Il Passo 2 non riguarda solo le lacune. Riguarda anche il **successo del ricordare**. Se il design si concentra solo su ciò che manca (nodi rossi), lo studente percepirà il Passo 2 come un'esperienza punitiva. Deve essere anche un'esperienza di **riconoscimento del proprio progresso**.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-57 | I nodi ricordati con successo (recall ≥4) devono avere un **feedback visivo positivo** al momento del reveal — un breve pulse di verde, un'animazione di "conferma" | Self-Determination T2 (competence), Growth Mindset §12 | Animazione: pulse verde 500ms, ease-in-out. Sottile, non invadente |
| P2-58 | Al termine del confronto, mostrare un **sommario positivo** prima della lista delle lacune: "Hai ricostruito 8 nodi su 12 dalla memoria!" con enfasi sulla parte piena, non su quella vuota | Growth Mindset §12 | Testo positivo PRIMA del conteggio lacune. Formulazione: "X su Y ricostruiti" non "Y-X mancanti" |
| P2-59 | Nelle sessioni successive, mostrare il **miglioramento** rispetto alla sessione precedente: "Sessione precedente: 8/12. Oggi: 10/12. +2 nodi!" | Growth Mindset §12, Metacognition T1 | Delta positivo evidenziato in verde. Delta negativo: discreto, non drammatico |
| P2-60 | I nodi **padroneggiati** (3 recall corretti) devono avere un'estetica visiva che comunica "traguardo raggiunto" — bordo dorato, icona stella | Self-Determination T2 (competence) | Bordo: #FFD700. Stella piccola nell'angolo del nodo |
| P2-61 | NON usare mai la parola **"fallimento"**, **"errore"** o **"sbagliato"** nell'interfaccia del Passo 2. Solo "ricordato/da rivedere", "ricostruito/non ricostruito" | Growth Mindset §12 | Audit copy: 0 occorrenze di linguaggio negativo nell'UI del Recall Mode |

---

### 2.12 — Approfondimento: Il Problema della Scala

Cosa succede quando il canvas contiene centinaia di nodi (es. un intero semestre)?

#### Decisioni di Design

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P2-62 | Il Recall Mode opera sempre su una **zona selezionata** dal canvas, non su tutto il canvas | Lo studente seleziona l'area da ricostruire (es. un capitolo, un argomento) — non l'intera materia in una volta |
| P2-63 | La selezione della zona avviene con un **gesto di area** (es. disegno di un rettangolo con due dita, o lasso) prima dell'attivazione | Il gesto deve essere naturale e rapido. ≤3 secondi per selezionare l'area |
| P2-64 | Il sistema può **suggerire zone** basate sulla cronologia di studio: "Vuoi ricostruire l'argomento 'Termodinamica'?" — ma solo come opzione, mai unica scelta | Autonomy T2 | Suggerimento basato su quale zona ha il recall più vecchio o più debole |
| P2-65 | Per studenti avanzati, offrire un **Recall Mode "panoramico"** che opera su una zona più grande (es. una materia intera) con LOD — zoom out mostra solo i nodi-monumento, lo studente ricostruisce a livello macro prima e poi zooma per i dettagli | Zoom Semantico §26, Palazzo (Piani) | Ricostruzione multi-scala: prima i "quartieri", poi le "strade", poi i "dettagli" |

---

### 2.13 — Approfondimento: Il Sistema "Sbircia" (Peek) — Costo Progressivo

La funzione "Sbircia" (P2-16) è potente ma pericolosa. Se sbirciare costa troppo poco, lo studente lo farà compulsivamente e il recall diventa una farsa. Se costa troppo, lo studente eviterà di usarlo anche quando un indizio lo aiuterebbe a sbloccarsi.

#### Il Costo Progressivo dello Sbirciare

| Peek # | Durata Reveal | Costo Visivo | Razionale |
|--------|--------------|-------------|-----------|
| **1° peek** (nella sessione) | 3 secondi | Nodo marcato giallo | Costo basso — è legittimo aver bisogno di un indizio |
| **2° peek** | 2 secondi | Nodo marcato arancione | Il tempo ridotto costringe una lettura più veloce |
| **3° peek** | 1.5 secondi | Nodo marcato rosso-arancio | Stai sbirciando troppo — forse questa zona è troppo avanzata |
| **4°+ peek** | 1 secondo | Nodo marcato rosso + notifica discreta: "Forse dovresti rivedere gli appunti del Passo 1 prima di ricostruire" | Il sistema segnala che il recall è prematuro — lo studente potrebbe aver bisogno di più studio prima |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P2-66 | Il costo dello sbirciare **scala** con il numero di peek nella sessione — durata più breve, marcatura più severa | Desirable Difficulties §5 | Timer: 3s → 2s → 1.5s → 1s. Colori: giallo → arancione → rosso-arancio → rosso |
| P2-67 | Dopo il 4° peek nella stessa sessione, mostrare un **suggerimento gentile** (non bloccante): "Forse questo argomento richiede un'altra lettura prima della ricostruzione" | ZPD §19 — se lo studente è troppo lontano dalla comprensione, il recall è frustrazione, non apprendimento | Tooltip discreto, dismissable in 1 tap. Non blocca l'utilizzo |
| P2-68 | Il contatore di peek si **resetta** ad ogni nuova sessione di recall | Spacing §1 | Il costo progressivo è per sessione, non cumulativo globale |
| P2-69 | I peek **non rivelano mai le frecce/connessioni** dei nodi sbirciati — solo il contenuto del singolo nodo | Generation §3 — le relazioni tra nodi devono essere ricostruite dallo studente | Il nodo appare in isolamento, senza frecce verso i nodi adiacenti |
| P2-70 | I nodi sbirciati NON contano come "ricostruiti" nel sommario finale — anche se lo studente successivamente riscrive il nodo sbirciato | Active Recall §2 | Status: `peeked`. Non può essere promosso a `recalled` nella stessa sessione |

---

### 2.14 — Criteri di Accettazione Estesi (QA Checklist — Approfondimento)

- [ ] **CA-28:** Free Recall Mode: 0 indizi visivi nella zona originale (opacità 0%)
- [ ] **CA-29:** Spatial Recall Mode: blob colorati visibili, testo 100% illeggibile
- [ ] **CA-30:** Transizione Free → Spatial funzionante; Spatial → Free bloccata
- [ ] **CA-31:** Sistema a 5 livelli di recall: assegnamento con ≤1 gesto per nodo
- [ ] **CA-32:** Fallback binario (verde/rosso) funzionante se lo studente non auto-valuta
- [ ] **CA-33:** Segmentazione nodi: threshold spaziale configurabile, correzione manuale funzionante
- [ ] **CA-34:** Cronologia sessioni: dati persistiti e visualizzabili
- [ ] **CA-35:** Blur adattivo tra sessioni: opacità decresce con il numero di sessioni
- [ ] **CA-36:** Flag "padroneggiato" dopo 3 recall ≥4 in sessioni distanziate ≥24h
- [ ] **CA-37:** Sommario positivo: testo "X su Y ricostruiti" mostrato PRIMA delle lacune
- [ ] **CA-38:** Delta miglioramento: "+N nodi" mostrato nelle sessioni successive
- [ ] **CA-39:** Selezione zona per Recall: gesto di area funzionante in ≤3s
- [ ] **CA-40:** Peek costo progressivo: durata e colore scalano correttamente (3s→2s→1.5s→1s)
- [ ] **CA-41:** Peek non rivela connessioni/frecce — solo il contenuto del nodo isolato
- [ ] **CA-42:** 0 occorrenze di "fallimento", "errore", "sbagliato" nell'UI del Recall Mode
- [ ] **CA-43:** Nodo padroneggiato: bordo dorato + stella visibile

---
---

## PASSO 3 — L'Interrogazione Socratica: L'IA Si Sveglia

### Contesto

Il Passo 3 è il momento in cui l'IA esce dal letargo. Per la prima volta nel percorso, il software diventa attivo e reagisce al contenuto dello studente. Ma con una regola ferrea: **l'IA pone domande — mai risposte**.

Il Passo 3 riceve dal Passo 2 la **mappa di lacune** (nodeId + recall level + peeked status). Questo permette all'IA di concentrare le domande dove serve, non interrogare su tutto.

**📅 Quando:** Stesso giorno o giorno seguente al Passo 2.

**Principi attivati:** Socratic Tutor (§20), ZPD (§19), Ipercorrezione (§4), Active Recall (§2), Protégé Effect (§8), Spacing (§1), Metacognition (T1), Productive Failure (T4)

---

### 3.1 — Attivazione dell'IA (Il Risveglio)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-01 | L'IA si attiva **SOLO su invocazione esplicita** dello studente: gesto dedicato, bottone "Mettimi alla Prova", o comando vocale | Autonomy T2 — lo studente decide quando essere interrogato | Nessuna attivazione automatica. Nessun suggerimento proattivo tipo "Vuoi essere interrogato?" |
| P3-02 | All'attivazione, l'IA **legge silenziosamente il canvas** (handwriting recognition interno) — SENZA convertire il tratto in testo visibile | Generation §3 — il tratto originale resta sacro | L'HTR avviene in background, output invisibile. Tempo di analisi: ≤5s per canvas con ≤50 nodi |
| P3-03 | L'IA riceve la **mappa di lacune del Passo 2** come contesto e la usa per calibrare le domande | ZPD §19, Spacing §1 | Se la mappa è disponibile: priorità ai nodi missed/peeked. Se non disponibile (Passo 2 saltato): interrogazione uniforme |
| P3-04 | Mostrare un **indicatore discreto** che l'IA è attiva: un piccolo punto luminoso nel bordo del canvas, pulsante lentamente | Metacognition T1 — lo studente sa che l'IA è "presente" | Punto: 8px, opacità 60%, pulse 2s. Colore: ambra/dorato |
| P3-05 | L'IA può essere **disattivata** in qualsiasi momento con un gesto (es. scorrere il punto luminoso fuori schermo, o il bottone stesso) | Autonomy T2 | Disattivazione istantanea. Le domande già presenti restano visibili ma congelate |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P3-06 | Attivarsi autonomamente ("Sono passate 24 ore... vuoi essere interrogato?") | Autonomy T2 | L'IA non è un coach con un programma. Lo studente ha l'agency |
| P3-07 | Mostrare un'animazione di "caricamento" o "analisi in corso" che crei aspettativa | Flow §24 | La transizione deve essere fluida, non un evento |
| P3-08 | Richiedere connessione internet per l'interrogazione di base | Autonomy T2 | Il modello socratico deve funzionare offline (modello locale) quando possibile |

---

### 3.2 — Generazione delle Domande

L'IA genera 4 tipi di domande, ciascuno attivato da un principio diverso:

#### I 4 Tipi di Domande Socratiche

| Tipo | Esempio | Principio | Quando usarla |
|------|---------|-----------|---------------|
| **A — Domanda di Lacuna** | "Vedo che hai scritto sulla termodinamica, ma manca qualcosa tra entropia e energia libera. Cosa c'è in mezzo?" | Active Recall §2, Zeigarnik §7 | Nodo missed (recall 1) nella mappa lacune |
| **B — Domanda di Sfida** | "Sei sicuro che A causi B? E se fosse il contrario?" | Ipercorrezione §4, Desirable Difficulties §5 | Nodo con connessione potenzialmente errata |
| **C — Domanda di Profondità** | "Puoi spiegare *perché* questo è vero, non solo *che cosa* è?" | Levels of Processing §6, Elaborazione | Nodo con recall ≥4 (lo studente lo "sa" ma forse solo superficialmente) |
| **D — Domanda di Transfer** | "Questo principio ti ricorda qualcosa in un'altra materia del tuo canvas?" | Transfer T3, Interleaving §10 | Nodo padroneggiato — serve a creare ponti cross-dominio |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-09 | Le domande appaiono come **bolle semi-trasparenti ancorate spazialmente** accanto ai nodi rilevanti — NON in un pannello laterale, NON in una chat separata | Spatial Cognition §22 — le domande vivono nello spazio del canvas | Bolla: sfondo scuro al 70% opacità, bordo ambra, testo bianco. Ancorata al nodo con una linea sottile |
| P3-10 | Ogni bolla contiene **solo la domanda** — mai la risposta, mai un suggerimento, mai un'opzione multipla | Socratic Tutor §20, Generation §3 | 0 risposte visibili nelle bolle. Solo domande aperte |
| P3-11 | Le domande appaiono **una alla volta**, non tutte insieme. Lo studente deve rispondere (o saltare) prima di ricevere la prossima | Flow §24, Cognitive Load §9 | Max 1 bolla-domanda attiva contemporaneamente. Coda di domande non visibile |
| P3-12 | L'ordine delle domande segue la **priorità della mappa lacune**: prima i nodi con recall 1 (miss totale), poi recall 2 (tip-of-tongue), poi recall 3, fino ai nodi con recall 5 (solo domande di Transfer) | ZPD §19 | Ordinamento: recall ascending. Tipo D solo per nodi con recall ≥4 |
| P3-13 | Le domande di Tipo A e B si concentrano sui **nodi non ricordati o sbirciati** del Passo 2. Le domande di Tipo C e D si concentrano sui **nodi ricordati** | ZPD §19 | Matrice: recall 1-2 → tipo A/B, recall 3 → tipo B/C, recall 4-5 → tipo C/D |
| P3-14 | L'IA **adatta la difficoltà** in tempo reale: se lo studente risponde correttamente a 3 domande consecutive, la prossima è un livello più profonda (C→D). Se sbaglia 2 consecutive, la prossima è un livello più fondamentale (C→A) | ZPD §19, Flow §24 (bilanciare sfida e competenza) | Sliding window: ultime 3 risposte determinano il livello della prossima |
| P3-15 | Le bolle-domanda sono **dismissabili** con un gesto rapido — lo studente può saltare qualsiasi domanda | Autonomy T2 | Swipe per dismissare. La domanda saltata viene registrata come "skipped" nel metadato |
| P3-16 | Il numero totale di domande per sessione è **limitato** e configurabile (default: 8-12 domande) | Cognitive Load §9, Flow §24 | Lo studente non deve sentirsi "intrappolato" in un interrogatorio infinito |

---

### 3.3 — Il Meccanismo Confidenza → Risposta → Rivelazione (Il Cuore dell'Ipercorrezione)

Questo è il meccanismo più importante del Passo 3. Per ogni domanda, la sequenza è:

```
1. L'IA mostra la domanda (bolla ancorata al nodo)
        ↓
2. Lo studente DICHIARA la propria confidenza (1-5)
   prima di rispondere
        ↓
3. Lo studente RISPONDE scrivendo a mano sul canvas
   (non digitando, non parlando)
        ↓
4. L'IA VALUTA la risposta e rivela il risultato:
   → Corretto + alta confidenza = ✅ verde
   → Corretto + bassa confidenza = 🟢 verde chiaro
   → Errato + bassa confidenza = 🟡 ambra (lacuna nota)
   → Errato + alta confidenza = 🔴 ROSSO SHOCK (ipercorrezione!)
```

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-17 | Prima di ogni risposta, lo studente deve **dichiarare il livello di confidenza (1-5)** con un gesto rapido (slider orizzontale o 5 puntini) | Ipercorrezione §4 — la confidenza pre-risposta è il prerequisito per lo shock | Slider: ≤1 gesto. I 5 livelli devono essere assegnabili in <1s |
| P3-18 | Lo studente **risponde scrivendo a mano** sul canvas, nello spazio accanto alla bolla-domanda o accanto al nodo | Generation §3, Embodied Cognition §23 | La risposta è un tratto di penna. Nessuna digitazione. L'area di risposta si espande automaticamente |
| P3-19 | Lo studente può anche rispondere **disegnando** (diagramma, freccia, schema) — non solo scrivendo testo | Multimodal Encoding §28, Elaborazione §6 | Il sistema accetta qualsiasi tratto come risposta — non solo testo riconosciuto |
| P3-20 | Dopo la risposta, l'IA mostra il **risultato** con un colore-stato che dipende dall'incrocio confidenza × correttezza | Ipercorrezione §4 | 4 stati visivi distinti (vedi schema sopra). Colore applicato come alone sul nodo |
| P3-21 | L'**errore ad alta confidenza** (confidenza ≥4, risposta errata) è l'evento più importante del Passo 3. Il nodo deve pulsare con un **effetto visivo drammatico** (flash rosso, vibrazione, bordo ondulato) | Ipercorrezione §4 — lo shock visivo cementa la correzione nella memoria | Haptic: medium impact. Animazione: pulse rosso 1.5s, outline ondulato per 5s. Mai intimidatorio — potente ma non punitivo |
| P3-22 | Per l'errore ad alta confidenza, l'IA mostra un **breadcrumb** (non la risposta!) sotto la bolla: "Ripensa a [indizio vago]... la risposta è collegata a [concetto correlato]." Lo studente deve tentare di nuovo | ZPD §19, Socratic §20 | Il breadcrumb è un indizio, mai la soluzione. Max 15 parole |
| P3-23 | Dopo l'errore ad alta confidenza, il nodo viene **marcato permanentemente** con un indicatore "shock" (bordo rosso) che lo rende visivamente distinguibile nelle sessioni future | Ipercorrezione §4, Spacing §1 | Tag: `hypercorrection: true, originalConfidence: N`. Visivo: bordo rosso sottile permanente |

---

### 3.4 — Il Sistema di Breadcrumb (Indizi Socratici Graduali)

Quando lo studente è bloccato, non conosce la risposta, o ha risposto erroneamente, l'IA offre un **sistema di indizi a 3 livelli** — mai la risposta diretta.

| Livello | Nome | Cosa rivela | Esempio |
|---------|------|------------|---------|
| **Breadcrumb 1** | L'Eco Lontano | Un indizio vagamente correlato, poco più di una direzione | "È qualcosa che riguarda l'equilibrio tra due grandezze..." |
| **Breadcrumb 2** | Il Sentiero | Un indizio più specifico che circoscrive il dominio | "Pensa alla relazione tra entropia e temperatura... in quale contesto le hai viste insieme?" |
| **Breadcrumb 3** | La Soglia | L'indizio massimo — la risposta è a un passo, ma lo studente deve fare l'ultimo salto | "La formula che cerchi collega ΔG, ΔH e TΔS. Quale segno ha il termine dell'entropia?" |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-24 | I breadcrumb sono accessibili **su richiesta esplicita** dello studente (es. pulsante "Indizio" nella bolla, o gesto) — mai automatici | Autonomy T2, Generation §3 | Pulsante visibile ma non prominente. Label: "Indizio" o icona lampadina |
| P3-25 | I breadcrumb si **sbloccano in sequenza**: non si può accedere al Livello 2 senza aver prima visto il Livello 1 | ZPD §19 — lo scaffolding è graduale | UI: bottone "Indizio" → Breadcrumb 1 → bottone "Altro indizio" → Breadcrumb 2 → "Ultimo indizio" → Breadcrumb 3 |
| P3-26 | Ogni breadcrumb usato viene **registrato** nel metadato del nodo — il sistema SRS saprà "questo nodo ha richiesto 2 indizi" | Spacing §1, Metacognition T1 | Schema: `{nodeId, hintsUsed: 0-3, hintsTimestamps[]}` |
| P3-27 | Se lo studente usa tutti e 3 i breadcrumb e **ancora non sa rispondere**, l'IA NON rivela la risposta. Mostra un messaggio: "Questo concetto ha bisogno di più lavoro. Torna agli appunti del Passo 1 e riscrivilo." | Productive Failure T4 — il fallimento dopo 3 indizi è un segnale che lo studente è fuori dalla ZPD | Il nodo viene marcato come "fuori-ZPD" (tag: `belowZPD: true`). Colore: grigio scuro |
| P3-28 | I nodi marcati "fuori-ZPD" vengono **rimossi dalla coda** dell'interrogazione corrente e riproposti nella sessione successiva dopo ulteriore studio | ZPD §19 | Questi nodi non ricevono altre domande nella sessione corrente — non serve insistere |
| P3-29 | L'IA NON fornisce MAI la risposta completa. Nemmeno dopo 3 breadcrumb. La risposta deve **sempre** venire dallo studente o dal ritorno ai materiali | Generation §3, Socratic §20 | 0 risposte complete generate dall'IA nell'intero Passo 3 |

---

### 3.5 — Comportamento del Canvas durante l'Interrogazione

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-30 | I nodi interrogati pulsano con un **contorno sottile colorato** che indica lo stato: ambra = domanda aperta, verde = risposta corretta, rosso = errore ad alta confidenza | Spatial Cognition §22, Metacognition T1 | Pulse: 1px → 3px, periodo 2s. Colore applicato al bordo del nodo |
| P3-31 | Il canvas resta **completamente scrivibile** durante l'interrogazione — lo studente può aggiungere nodi, tracciare frecce, disegnare, spostare contenuti | Extended Mind §29, Generation §3 | L'interrogazione non "blocca" il canvas. È un dialogo che avviene SOPRA il canvas vivo |
| P3-32 | Lo studente può **navigare** (pan, zoom) liberamente durante l'interrogazione. La bolla-domanda attiva segue il nodo a cui è ancorata | Spatial Cognition §22 | La bolla è ancorata al nodo con posizione relativa persistente |
| P3-33 | Le risposte scritte a mano dal lo studente vengono **salvate come nuovi tratti** nel canvas, distinguibili visivamente dai tratti del Passo 1 (es. colore leggermente diverso, o sottile indicatore "P3") | Metacognition T1 | Tag: `writtenDuringStep: 3`. Colore opzionale: leggermente più chiaro degli appunti originali |
| P3-34 | Tutte le regole di scrittura attiva del Passo 1 (P1-11→P1-30) **restano attive** durante il Passo 3 | Tutti i principi di scrittura | Nessun degradamento della qualità del tratto durante l'interrogazione |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P3-35 | Bloccare la scrittura/modifica del canvas durante le domande ("prima rispondi, poi scrivi") | Extended Mind §29, Flow §24 | Lo studente potrebbe avere bisogno di esplorare il canvas per trovare la risposta — questa è retrieval spaziale |
| P3-36 | Mostrare la risposta corretta dopo un errore, anche come "spiegazione" | Socratic §20, Generation §3 | L'IA DEVE ridirigere lo studente verso i propri appunti, NON fornire la risposta |
| P3-37 | Usare quiz a scelta multipla o vero/falso | Generation §3, Desirable Difficulties §5 | Le scelte multiple attivano il riconoscimento (System 1), non la generazione (System 2). La risposta deve essere generata da zero |
| P3-38 | Mostrare un timer o un conto alla rovescia per rispondere | Flow §24, Autonomy T2 | La pressione temporale non produce apprendimento profondo — produce ansia e risposte superficiali |
| P3-39 | Valutare la calligrafia, l'ortografia o la formattazione della risposta | Embodied §23, Generation §3 | L'IA valuta il CONTENUTO semantico, non la forma. Un concetto scritto in modo "brutto" ma corretto è un successo |
| P3-40 | Mostrare tutte le domande in una lista ("Hai 12 domande da fare") | Cognitive Load §9 | La visione dell'intera coda crea ansia da prestazione. Una alla volta, senza sapere quante mancano |

---

### 3.6 — Edge Case: Lo Studente Non Ha Lacune

Se lo studente ha un recall elevato (tutti i nodi recall ≥4 dal Passo 2), l'IA non ha lacune su cui concentrarsi.

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P3-41 | In questo caso, l'IA passa direttamente a **domande di Tipo C (Profondità) e D (Transfer)** | Lo studente "sa" tutto, ma sa tutto superficialmente? Le domande di profondità lo testano |
| P3-42 | Se lo studente risponde correttamente anche alle domande C e D, l'IA comunica: "Questa zona sembra solida. Vuoi passare al Passo 4 (Confronto Centauro) per una verifica completa?" | Il Passo 3 non è obbligatorio se non ci sono lacune — il Passo 4 farà la verifica strutturale |
| P3-43 | La sessione di interrogazione può terminare **prima** del numero massimo di domande se l'IA non ha più domande utili da porre | Non sprecare il tempo dello studente con domande ridondanti |

---

### 3.7 — Edge Case: Lo Studente è Completamente Perso

Se dal Passo 2 emerge che lo studente ha un recall ≤2 su quasi tutti i nodi (ha dimenticato quasi tutto):

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P3-44 | L'IA **riduce drasticamente** il numero e la difficoltà delle domande — 3-4 domande di Tipo A, molto basiche | ZPD §19 — lo studente è sotto la zona. Interrogarlo su ciò che non sa produce solo frustrazione |
| P3-45 | Dopo le domande base, l'IA suggerisce gentilmente: "Forse vale la pena rileggere i tuoi appunti del Passo 1 prima di continuare. Puoi tornare qui dopo." | ZPD §19, Growth Mindset §12 | Il suggerimento è gentile, non un giudizio. Formulazione: "vale la pena rileggere", non "non hai capito nulla" |
| P3-46 | I nodi vengono marcati come "fuori-ZPD" (grigio scuro) e l'interrogazione viene sospesa fino alla prossima sessione | Productive Failure T4 | La sospensione è un atto di cura, non una punizione. Il fallimento è produttivo solo se c'è un minimo di base su cui costruire |

---

### 3.8 — Stato dell'IA durante il Passo 3

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 🔶 SOCRATICO                      │
│                                                  │
│  • Modulo IA: ATTIVO (on-demand)                 │
│  • Analisi canvas: SÌ (HTR interno, invisibile)  │
│  • Genera: DOMANDE (mai risposte)                │
│  • Modifica canvas: MAI                          │
│  • Scrive sul canvas: MAI                        │
│  • Mostra risposte: MAI                          │
│  • Livello adattivo: ZPD dinamico                │
│  • Disattivazione: in qualsiasi momento          │
│                                                  │
│  L'IA è un INQUISITORE BENEVOLO.                 │
│  Chiede. Non dice. Non tocca. Non modifica.      │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!CAUTION]
> ### La Regola Suprema del Passo 3
> **L'IA non dice MAI la risposta.** Nemmeno dopo 3 breadcrumb. Nemmeno se lo studente la implora. Nemmeno se è frustrante. L'unica via per ottenere la risposta è: (1) generarla da sé, (2) tornare agli appunti e riscoprirla, (3) aspettare il Passo 4 dove la Ghost Map rivelerà la struttura mancante. L'IA che dà la risposta distrugge l'intero framework in un istante.

---

### 3.9 — Dati Generati dal Passo 3 (per i Passi Successivi)

Il Passo 3 produce il dataset più ricco dell'intero percorso:

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "zone": "canvas_zone_id",
  "questionsAsked": 10,
  "questionsAnswered": 8,
  "questionsSkipped": 2,
  "results": [
    {
      "nodeId": "node_123",
      "questionType": "A|B|C|D",
      "confidenceBefore": 4,
      "answerCorrect": false,
      "hypercorrection": true,
      "hintsUsed": 1,
      "belowZPD": false,
      "responseTime_ms": 45000
    }
  ],
  "adaptiveDifficulty": {
    "startLevel": 2,
    "endLevel": 3,
    "adjustments": ["+", "+", "-", "+", "="]
  }
}
```

Questo dataset alimenta:
- **Passo 4** — la Ghost Map sa dove concentrarsi
- **Passo 6-8** — l'SRS calibra gli intervalli di ripasso
- **Passo 10** — la Fog of War sa quali aree sono più deboli

---

### 3.10 — Transizione verso il Passo 4

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P3-47 | Al termine dell'interrogazione, mostrare un **sommario positivo**: "Hai risposto a 8 domande su 10. 3 ipercorrezioni registrate — queste le ricorderai." | Growth Mindset §12, Metacognition T1 | Testo positivo. Le ipercorrezioni sono presentate come CONQUISTE, non come fallimenti |
| P3-48 | Offrire un'azione **"Avvia Confronto Centauro"** per passare al Passo 4 | Metacognition T1 | Pulsante visibile dopo il sommario. Mai automatico |
| P3-49 | Passare al Passo 4 l'intero **dataset del Passo 3** (confidenze, errori, breadcrumb usati, nodi fuori-ZPD) | Centauro §16 | Payload completo per la Ghost Map |
| P3-50 | Permettere di **terminare la sessione** senza passare al Passo 4 — lo studente può fare il Passo 4 un altro giorno | Autonomy T2, Spacing §1 | I dati del Passo 3 sono persistiti e disponibili per il Passo 4 successivo |

---

### 3.11 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-44:** Attivazione IA: solo su invocazione esplicita, 0 attivazioni automatiche
- [ ] **CA-45:** HTR interno: canvas analizzato in ≤5s per ≤50 nodi, output invisibile all'utente
- [ ] **CA-46:** Bolle-domanda: ancorate spazialmente ai nodi, sfondo scuro 70%, bordo ambra
- [ ] **CA-47:** 1 domanda alla volta: la coda non è visibile allo studente
- [ ] **CA-48:** Slider confidenza: ≤1 gesto, ≤1s per assegnare il livello 1-5
- [ ] **CA-49:** Risposta scritta a mano: tratti salvati come nuovi contenuti nel canvas
- [ ] **CA-50:** 0 risposte generate dall'IA visibili allo studente nell'intero Passo 3
- [ ] **CA-51:** Errore ad alta confidenza: haptic medium + flash rosso 1.5s + outline ondulato 5s
- [ ] **CA-52:** Breadcrumb: 3 livelli accessibili in sequenza, mai la risposta completa
- [ ] **CA-53:** Dopo 3 breadcrumb senza risposta: messaggio "torna agli appunti", nodo marcato fuori-ZPD
- [ ] **CA-54:** Difficoltà adattiva: sliding window 3 risposte, livello sale/scende correttamente
- [ ] **CA-55:** Domande dismissabili: swipe per saltare, stato "skipped" registrato
- [ ] **CA-56:** Limite domande per sessione: configurabile, default 8-12
- [ ] **CA-57:** Canvas scrivibile durante l'interrogazione: tutte le regole P1-11→P1-30 attive
- [ ] **CA-58:** 0 quiz a scelta multipla o vero/falso nell'intero Passo 3
- [ ] **CA-59:** Edge case "nessuna lacuna": passa a domande C/D, poi suggerisce Passo 4
- [ ] **CA-60:** Edge case "tutto perso": riduce a 3-4 domande base, suggerisce rileggere, sospende
- [ ] **CA-61:** Dataset JSON completo e persistito al termine della sessione
- [ ] **CA-62:** Sommario finale: tono positivo, ipercorrezioni presentate come conquiste
- [ ] **CA-63:** Disattivazione IA: istantanea, bolle congelate, canvas torna a modalità scrittura
- [ ] **CA-64:** Nodi fuori-ZPD: marcati grigio scuro, rimossi dalla coda corrente
- [ ] **CA-65:** Nodi con ipercorrezione: bordo rosso permanente visibile nelle sessioni future

---
---

## PASSO 4 — Il Confronto Centauro: Lo Specchio Critico

### Contesto

Il Passo 4 è il primo momento in cui l'IA **genera contenuto strutturale** — una concept map di riferimento dell'argomento. Ma questo contenuto NON viene mai scritto sul canvas dello studente. Viene sovrapposto come **overlay semi-trasparente removibile** (la Ghost Map). Lo studente vede dove il suo canvas diverge dalla mappa ideale, e corregge **di propria mano**.

Il Passo 4 riceve dal Passo 3 l'intero dataset (confidenze, ipercorrezioni, nodi fuori-ZPD, breadcrumb usati). La Ghost Map sa esattamente dove concentrare il feedback.

**📅 Quando:** Immediatamente dopo il Passo 3, o il giorno seguente.

**Principi attivati:** Centauro (§16), Concept Mapping (§27), Ipercorrezione (§4), Levels of Processing (§6), Extended Mind (§29), Generation (§3), Spatial Cognition (§22)

---

### 4.1 — Attivazione del Confronto Centauro

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-01 | Il Confronto si attiva **SOLO su invocazione esplicita** dello studente: bottone "Verifica il mio canvas" o gesto dedicato | Autonomy T2 | Mai automatico. Nessun suggerimento proattivo |
| P4-02 | All'attivazione, l'IA genera internamente una **concept map di riferimento** dell'argomento, basata sulla materia, il livello dello studente e i nodi già presenti nel canvas | Concept Mapping §27 | Tempo di generazione: ≤8s. Lo studente vede un indicatore di "preparazione" discreto (barra di progresso sottile, non popup) |
| P4-03 | La concept map di riferimento è **contestualizzata** al canvas dello studente: l'IA non genera una mappa generica, ma una mappa calibrata su ciò che lo studente ha scritto e sul livello della materia | ZPD §19, Centauro §16 | La mappa include solo concetti al livello dello studente — non concetti avanzati che non ha ancora studiato |
| P4-04 | L'overlay viene sovrapposto come un **livello separato** semi-trasparente sopra il canvas — posizionato in modo da allinearsi spazialmente ai nodi esistenti dello studente | Spatial Cognition §22 | Opacità overlay: 40-50%. Il canvas sottostante resta visibile |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P4-05 | Generare una mappa completamente separata dal canvas ("Ecco la mappa corretta, confrontala con la tua") | Spatial Cognition §22, Centauro §16 | Il confronto deve essere spaziale e sovrapposto — il divario tra le due mappe è visibile NELLO STESSO SPAZIO |
| P4-06 | Mostrare la mappa ideale PRIMA che lo studente abbia tentato l'Interrogazione Socratica (Passo 3) | Productive Failure T4, Generation §3 | Lo studente deve prima aver esaurito il proprio sforzo autonomo |
| P4-07 | Modificare, spostare o cancellare QUALSIASI cosa dal canvas dello studente | Extended Mind §29 | Il canvas è sacro. L'overlay è un ospite temporaneo, mai un padrone |

---

### 4.2 — Il Sistema di Overlay a 4 Colori (La Ghost Map)

La Ghost Map usa un linguaggio visivo a 4 colori che lo studente impara rapidamente:

| Colore | Elemento | Significato | Aspetto Visivo | Azione dello Studente |
|--------|----------|-------------|----------------|----------------------|
| 🔴 **Rosso** | Sagoma vuota tratteggiata | **Nodo mancante** — un concetto che dovrebbe esserci ma non c'è nel canvas | Contorno tratteggiato rosso, interno vuoto, posizione approssimativa nel canvas. Icona "?" al centro | Tentare di scrivere il contenuto a mano PRIMA di toccare per rivelare |
| 🟡 **Giallo** | Alone pulsante su freccia | **Connessione errata** — una freccia tra nodi che non dovrebbe esserci, o che punta nella direzione sbagliata | Alone giallo (#FFCC00) sulla freccia + icona "?" | Cancellare con la gomma e ridisegnare correttamente |
| 🟢 **Verde** | Bordo sottile su nodo | **Nodo corretto e completo** — il concetto è accurato | Bordo verde discreto (2px, opacità 50%). No animazione | Nulla — è conferma positiva |
| 🔵 **Blu** | Linea punteggiata tra due nodi | **Connessione mancante** — una relazione tra concetti che lo studente non ha tracciato | Linea punteggiata blu (#007AFF) tra due nodi dello studente. Etichetta opzionale con tipo di relazione | Tracciare la freccia con la penna, trasformandola in tratto solido |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-08 | I **nodi mancanti (rossi)** mostrano solo la sagoma e la posizione — il contenuto è **nascosto**. Lo studente vede CHE manca qualcosa e DOVE, ma non COSA | Generation §3 — anche nella rivelazione, l'ultimo sforzo è dello studente | Sagoma: rettangolo tratteggiato, dimensione proporzionale alla complessità del concetto mancante. 0 testo visibile inizialmente |
| P4-09 | Per ogni sagoma rossa, lo studente deve **tentare di scrivere** il contenuto a mano nello spazio della sagoma PRIMA di poterla rivelare | Generation §3, Productive Failure T4 | Il tocco sulla sagoma per rivelare è bloccato finché lo studente non ha scritto almeno un tratto nell'area. Timer minimo: 10s dall'apparizione della sagoma |
| P4-10 | Dopo il tentativo di scrittura, lo studente **tocca la sagoma** → il contenuto dell'IA si rivela gradualmente (fade-in 1s) come testo digitale semi-trasparente SOTTO il tratto dello studente | Ipercorrezione §4 — il confronto visivo tra il tentativo e la risposta corretta è il momento ipercorrettivo | Il testo dell'IA è digitale (non handwritten), opacità 60%, colore grigio chiaro. Il tratto dello studente resta sopra, completamente visibile |
| P4-11 | Le **connessioni errate (gialle)** mostrano un alone e un "?" — ma NON dicono qual è la connessione corretta | Socratic §20 | L'alone giallo + "?" è l'unico feedback. Lo studente deve capire da solo perché la connessione è sbagliata |
| P4-12 | Le **connessioni mancanti (blu)** mostrano la linea punteggiata tra i nodi ma con un'**etichetta opzionale** che descrive il tipo di relazione (es. "causa", "prerequisito", "contrasto") | Concept Mapping §27, Elaborazione §6 | L'etichetta è un indizio relazionale, non un contenuto. Max 2 parole |
| P4-13 | I **nodi corretti (verdi)** ricevono solo un bordo verde discreto — nessun feedback eccessivo | Growth Mindset §12 | Il verde è conferma, non celebrazione. Non deve distrarre dall'attenzione sulle lacune |
| P4-14 | Gli elementi overlay sono **navigabili** in sequenza (es. "prossimo nodo rosso", "prossima connessione gialla") con un gesto o bottone | Metacognition T1 | Navigazione: swipe o pulsante "→" per tipologia. Ordine: rossi → gialli → blu |

---

### 4.3 — Il Workflow di Correzione (Lo Studente Agisce)

Questa è la fase in cui lo studente corregge il proprio canvas, guidato dall'overlay. Ogni correzione è un atto motorio e cognitivo.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-15 | Tutte le correzioni avvengono **scrivendo a mano** sul canvas — mai copiando, mai incollando, mai accettando un "fix" automatico | Generation §3, Embodied §23 | 0 azioni di "accetta correzione" automatiche nell'UI |
| P4-16 | Quando lo studente **scrive** dentro una sagoma rossa, il tratto resta come contenuto permanente del canvas. La sagoma rossa scompare gradualmente (fade-out 500ms) | Spatial Cognition §22, Extended Mind §29 | La sagoma era un placeholder. Il contenuto dello studente la sostituisce |
| P4-17 | Quando lo studente **cancella** una connessione errata (gialla) con la gomma e la ridisegna, l'alone giallo scompare e viene sostituito dal tratto corretto | Ipercorrezione §4 | Rilevamento: la vecchia freccia è stata cancellata → l'alone si dissolve |
| P4-18 | Quando lo studente **traccia** con la penna su una connessione mancante (blu punteggiata), la linea punteggiata diventa il tratto solido dello studente. L'overlay blu scompare | Concept Mapping §27 | Il tratto dello studente sovrascrive visualmente la linea punteggiata. Transizione fluida |
| P4-19 | Per ogni correzione, il sistema **registra** l'azione nel metadato: quale nodo/connessione è stato corretto, il tentativo dello studente vs. la risposta dell'IA, il tempo impiegato | Spacing §1, Metacognition T1 | Schema: `{type: node|connection, studentAttempt: blob, aiReference: text, timeTaken_ms, corrected: bool}` |
| P4-20 | Lo studente può **ignorare** elementi dell'overlay che ritiene irrilevanti o troppo avanzati — non è obbligato a correggere tutto | Autonomy T2, ZPD §19 | Gesto di dismiss per singolo elemento. Stato: "dismissed" nel metadato |

---

### 4.4 — Integrazione con i Dati del Passo 3 (Ipercorrezione Amplificata)

Il Passo 4 ha accesso ai dati di confidenza del Passo 3. Questo permette un feedback emotivamente calibrato:

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-21 | I nodi che nel Passo 3 erano segnati come **ipercorrezione** (errore ad alta confidenza) devono avere un **trattamento visivo speciale** nell'overlay: sagoma rossa con bordo ondulato + icona "⚡" | Ipercorrezione §4 — queste sono le lacune più importanti perché lo studente ERA sicuro | Doppia segnalazione visiva: rosso + bordo ondulato + "⚡". Questi nodi appaiono per primi nella navigazione |
| P4-22 | I nodi marcati **fuori-ZPD** nel Passo 3 (grigio scuro) appaiono nell'overlay come sagome **grigie** (non rosse) — con un'etichetta "Da approfondire" | ZPD §19 | Questi nodi non richiedono correzione immediata. Colore: grigio (#888). Label: "Da approfondire in una prossima sessione" |
| P4-23 | I nodi a cui lo studente ha **risposto correttamente con alta confidenza** nel Passo 3 ricevono un bordo verde **più marcato** nell'overlay — un riconoscimento del proprio successo | Growth Mindset §12, Self-Determination T2 | Bordo: #00C853, 3px, opacità 80%. Leggermente più brillante del verde standard |

---

### 4.5 — Dismissal dell'Overlay e Risultato Finale

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-24 | Lo studente può **rimuovere l'overlay** in qualsiasi momento con un gesto (es. swipe a due dita verso l'alto, o bottone "Chiudi confronto") | Autonomy T2 | Animazione di dismiss: fade-out overlay 500ms. Il canvas torna a mostrare solo il lavoro dello studente |
| P4-25 | Dopo il dismiss, il canvas mostra il lavoro dello studente **arricchito** dalle correzioni del Passo 4: nuovi nodi scritti a mano, connessioni ridisegnate, lacune colmate | Extended Mind §29, Spatial Cognition §22 | Il canvas prima e dopo il Passo 4 è visivamente diverso: più denso, più connesso |
| P4-26 | Il sistema salva un **snapshot "prima/dopo"** del canvas che lo studente può rivedere in futuro per visualizzare la propria crescita | Growth Mindset §12, Metacognition T1 | Snapshot: viewport state + lista modifiche. Accessibile dalla cronologia del canvas |
| P4-27 | Mostrare un **sommario finale** del Confronto: "Hai colmato 5 lacune, corretto 2 connessioni, tracciato 3 nuovi link. Il tuo canvas è cresciuto del 40%." | Growth Mindset §12 | Testo positivo. La crescita è quantificata come dato motivazionale |
| P4-28 | L'overlay è **richiamabile** dopo il dismiss: lo studente può riattivare la Ghost Map per rivedere il confronto | Metacognition T1 | Bottone "Rimostra confronto". L'overlay si riattiva con le stesse informazioni |

---

### 4.6 — Stato dell'IA durante il Passo 4

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 🔍 CENTAURO                       │
│                                                  │
│  • Modulo IA: ATTIVO (generazione Ghost Map)     │
│  • Genera: STRUTTURA di riferimento (overlay)    │
│  • Modifica canvas studente: MAI                 │
│  • Scrive sul canvas: MAI                        │
│  • Posiziona overlay: SÌ (livello separato)      │
│  • Rivela risposte: SOLO dopo tentativo studente │
│  • Rimuove elementi: MAI (solo lo studente)      │
│                                                  │
│  L'IA è uno SPECCHIO CRITICO.                    │
│  Mostra la distanza tra dove sei e dove          │
│  dovresti essere — ma il cammino lo fai tu.      │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!CAUTION]
> ### La Regola Suprema del Passo 4
> **L'overlay è un ospite, mai un padrone.** L'IA genera una mappa di riferimento, la sovrappone al canvas, e aspetta. Non sposta nodi. Non cancella errori. Non scrive correzioni. Non "migliora" il layout. Ogni pixel che cambia sul canvas dello studente è cambiato dalla **mano dello studente**. L'overlay è un suggerimento visivo — la correzione è un atto motorio.

---

### 4.7 — Edge Case: Lo Studente Ha un Canvas Quasi Perfetto

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P4-29 | Se l'overlay mostra **≤2 differenze** rispetto al canvas dello studente, l'IA comunica: "Il tuo canvas è quasi completo! Solo qualche dettaglio da aggiungere." | Il messaggio è celebrativo. Lo studente ha fatto un lavoro eccellente |
| P4-30 | In questo caso, l'IA può proporre **domande di Transfer (Tipo D)** in aggiunta all'overlay: "Il tuo canvas è solido. Vuoi esplorare connessioni con altre materie?" | Serve a stimolare lo studente oltre il dominio corrente |

---

### 4.8 — Edge Case: Lo Studente Ha un Canvas Molto Incompleto

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P4-31 | Se l'overlay mostra **>15 nodi mancanti**, l'IA **non mostra tutti** contemporaneamente — mostra solo i 5 più fondamentali (prerequisiti degli altri) | Il sovraccarico visivo di 15+ sagome rosse è paralizzante. Lo scaffolding è graduale |
| P4-32 | Dopo che lo studente ha colmato i primi 5, l'IA rivela i **prossimi 5**, e così via | Chunking §9 — le lacune vengono servite in blocchi gestibili |
| P4-33 | L'IA comunica: "Ho trovato diverse aree da esplorare. Iniziamo dalle basi." | Il tono è gentile e graduale, non intimidatorio. Mai "ti mancano 15 concetti" |

---

### 4.9 — Edge Case: Connessioni Cross-Dominio

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P4-34 | Se l'IA rileva una connessione possibile tra un concetto **nel canvas corrente** e un concetto in **un'altra zona/materia** del canvas, la mostra come linea punteggiata blu che attraversa lo spazio | Interleaving §10, Transfer T3 |
| P4-35 | Le connessioni cross-dominio sono mostrate **solo dopo** che le lacune intra-dominio sono state affrontate | ZPD §19 — prima consolidare la base, poi espandere |
| P4-36 | Le connessioni cross-dominio sono **sempre opzionali** — mai obbligatorie | Autonomy T2 | Lo studente decide se il collegamento è rilevante per il suo studio |

---

### 4.10 — Dati Generati dal Passo 4

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "zone": "canvas_zone_id",
  "ghostMap": {
    "missingNodes": 8,
    "filledByStudent": 5,
    "dismissed": 1,
    "belowZPD": 2,
    "wrongConnections": 3,
    "correctedByStudent": 2,
    "missingConnections": 4,
    "tracedByStudent": 3,
    "correctNodes": 15,
    "hypercorrectionNodes": 3
  },
  "canvasGrowth": {
    "nodesBefore": 15,
    "nodesAfter": 20,
    "connectionsBefore": 8,
    "connectionsAfter": 13,
    "growthPercentage": 33
  },
  "corrections": [
    {
      "type": "missingNode",
      "nodeId": "ghost_123",
      "studentAttemptCorrect": true,
      "timeTaken_ms": 30000,
      "wasHypercorrection": true
    }
  ]
}
```

Questo dataset alimenta:
- **Passo 6-8** — l'SRS sa quali nodi sono stati scoperti per la prima volta al Passo 4 (recall più debole)
- **Passo 10** — i nodi ipercorrettivi scoperti al Passo 4 diventano zone ad alta priorità nella Fog of War
- **Cronologia crescita** — il `canvasGrowth` diventa il grafico di progresso visibile allo studente

---

### 4.11 — Transizione verso il Passo 5

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P4-37 | Dopo il dismiss dell'overlay, mostrare un messaggio: **"Il tuo canvas è cresciuto. Adesso riposati — il sonno consolidarà tutto."** | Consolidamento §14, Sleep Consolidation | Il messaggio comunica il valore del sonno nell'apprendimento. Tono: cura, non ordine |
| P4-38 | Permettere di **continuare a scrivere** sul canvas dopo il confronto — lo studente può avere insight post-confronto che vuole annotare | Extended Mind §29, Generation §3 | Il canvas torna a modalità scrittura pura (IA dormiente) dopo il dismiss dell'overlay |
| P4-39 | Salvare il **dataset completo** del Passo 4 per i Passi successivi | Spacing §1 | Persistenza: database locale. Payload disponibile per Passi 6-10 |

---

### 4.12 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-66:** Attivazione Confronto: solo su invocazione esplicita, 0 attivazioni automatiche
- [ ] **CA-67:** Generazione Ghost Map: ≤8s per canvas con ≤50 nodi
- [ ] **CA-68:** Overlay a 4 colori: rosso/giallo/verde/blu chiaramente distinguibili
- [ ] **CA-69:** Nodi mancanti (rossi): contenuto nascosto, solo sagoma + posizione
- [ ] **CA-70:** Tentativo obbligatorio: la sagoma non si rivela senza almeno un tratto nell'area (min 10s)
- [ ] **CA-71:** Rivelazione: testo IA sotto il tratto dello studente, opacità 60%, fade-in 1s
- [ ] **CA-72:** Connessioni errate (gialle): alone + "?", 0 indicazioni sulla correzione corretta
- [ ] **CA-73:** Connessioni mancanti (blu): linea punteggiata + etichetta relazionale ≤2 parole
- [ ] **CA-74:** Nodi corretti (verdi): bordo discreto 2px, opacità 50%, 0 animazioni
- [ ] **CA-75:** Navigazione overlay: swipe/"→" per tipologia (rossi→gialli→blu)
- [ ] **CA-76:** Correzioni tutte scritte a mano: 0 azioni "accetta fix" automatiche
- [ ] **CA-77:** Sagoma rossa fade-out dopo scrittura studente: 500ms
- [ ] **CA-78:** Overlay dismissable: fade-out 500ms, canvas torna a stato puro
- [ ] **CA-79:** Overlay richiamabile dopo dismiss
- [ ] **CA-80:** Nodi ipercorrettivi: bordo ondulato + "⚡", mostrati per primi nella navigazione
- [ ] **CA-81:** Canvas molto incompleto: max 5 sagome rosse alla volta, poi progressivo
- [ ] **CA-82:** Snapshot prima/dopo salvato e accessibile dalla cronologia
- [ ] **CA-83:** Dataset JSON completo e persistito con growth percentage

---
---

## PASSO 5 — La Notte: Il Consolidamento Offline

### Contesto

Il Passo 5 è il passo in cui il **software fa meno** ma il **cervello lavora di più**. Durante il sonno, l'ippocampo riproduce le esperienze del giorno (replay neurale) e consolida le tracce mnestiche. I nodi scritti a mano, le posizioni spaziali, i colori, gli shock delle ipercorrezioni — tutto viene trasferito dalla memoria a breve termine a quella a lungo termine.

Il ruolo del software è: (1) NON interferire, (2) calcolare in background gli intervalli SRS ottimali, (3) preparare il canvas per il Passo 6.

**📅 Quando:** La notte tra il Giorno 0 e il Giorno 1.

**Principi attivati:** Spacing (§1), Consolidamento durante il sonno (neuroscienze di base)

---

### 5.1 — Cosa Fa il Software Mentre lo Studente Dorme

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P5-01 | Calcolare in background gli **intervalli SRS** per ogni nodo, basandosi sui dati dei Passi 2-4: recall level, confidenza, ipercorrezioni, breadcrumb usati, nodi fuori-ZPD | Spacing §1 | Algoritmo SRS: SM-2 modificato o FSRS. Input: recall level (1-5), confidence (1-5), hypercorrection (bool), hintsUsed (0-3). Output: next_review_date per ogni nodo |
| P5-02 | Calcolare il **livello di blur** per ogni nodo per il Passo 6, proporzionale inversamente alla forza del recall | Spacing §1, Active Recall §2 | Nodi con recall 5 + alta confidenza → blur forte (devono sforzarsi). Nodi con recall 1-2 → blur leggero (sono già stati faticosi) |
| P5-03 | Preparare l'**ordine di navigazione** suggerito per il Passo 6: quali nodi visitare per primi, con che percorso | Interleaving §10 | L'ordine NON è sequenziale — è interleaved: alterna nodi di sotto-argomenti diversi |
| P5-04 | Tutti i calcoli avvengono **localmente e silenziosamente** — nessuna connessione internet necessaria | Autonomy T2 | Calcolo offline. 0 richieste di rete |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P5-05 | Mandare **notifiche push** tipo "È ora di ripassare!" o "Non hai ancora aperto il canvas oggi!" | Autonomy T2 | Le notifiche push trasformano lo studente in un esecutore di ordini. L'agency sulla disciplina temporale è dello studente |
| P5-06 | Mandare **email o messaggi** con riassunti dello studio del giorno precedente | Active Recall §2, Cognitive Offloading §15 | Leggere un riassunto è relettura passiva — l'opposto del recall attivo |
| P5-07 | Mostrare un **badge** o contatore di "streak" (giorni consecutivi di studio) | Growth Mindset §12 | Le streak sono gamification che sposta la motivazione dall'apprendimento alla performance del contatore |
| P5-08 | Modificare il canvas in qualsiasi modo durante la notte (riorganizzare, aggiungere contenuti, "ottimizzare") | Extended Mind §29, Spatial Cognition §22 | Il canvas deve essere identico a come lo studente l'ha lasciato |

---

### 5.2 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-84:** Intervalli SRS calcolati per ogni nodo al termine della sessione Passi 2-4
- [ ] **CA-85:** Livelli di blur pre-calcolati e pronti per il Passo 6
- [ ] **CA-86:** 0 notifiche push generate dal sistema
- [ ] **CA-87:** 0 modifiche al canvas durante la notte
- [ ] **CA-88:** Calcolo SRS: completamente offline, 0 richieste di rete

---
---

## PASSO 6 — Il Primo Ritorno: Active Recall Spaziale con Blur

### Contesto

Il Passo 6 è il primo vero test di ritenzione. Sono passate **24 ore** dal giorno di studio. Il sonno ha consolidato le tracce. Adesso lo studente torna al canvas e scopre: cosa è rimasto?

Il canvas si apre con i nodi **sfumati** (blur gaussiano). Lo studente naviga nello spazio e per ogni nodo tenta di ricordare il contenuto prima di toccarlo per rivelarlo. È Active Recall puro, potenziato dalla Cognizione Spaziale.

**📅 Quando:** Giorno 1 (24 ore dopo il Passo 1).

**Principi attivati:** Spacing (§1), Active Recall (§2), Spatial Cognition (§22), Zoom Semantico (§26), Interleaving (§10), Embodied Cognition (§23), Ipercorrezione (§4)

---

### 6.1 — Apertura del Canvas al Ritorno

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P6-01 | Aprire il canvas **esattamente nella posizione e zoom** dell'ultima sessione | Spatial Cognition §22 — la posizione è parte della memoria | Posizione e zoom restaurati pixel-perfect dal database locale |
| P6-02 | I nodi sono **sfumati** con blur gaussiano **proporzionale inverso alla forza del recall**: nodi con recall forte (alta confidenza, 0 errori) → blur più intenso (devono sforzarsi per ricordare); nodi con recall debole → blur più leggero | Active Recall §2, Desirable Difficulties §5 | Blur radius: recall 5 → 30px, recall 4 → 22px, recall 3 → 15px, recall 2 → 10px, recall 1 → 5px. Il principio: chi sa di più deve sforzarsi di più |
| P6-03 | I nodi marcati **"padroneggiato"** (3 recall corretti, stella dorata) sono quasi completamente illeggibili — il blur è massimo | Desirable Difficulties §5 | Blur radius: 40px. Se lo studente ricorda anche con blur 40px → il nodo è veramente consolidato |
| P6-04 | I nodi marcati **fuori-ZPD** dal Passo 3 sono senza blur — visibili normalmente, con un'etichetta "Da rivedere" | ZPD §19 | Questi nodi NON vengono testati — lo studente deve prima rivederli e riscriverli |
| P6-05 | I nodi con **ipercorrezione** (bordo rosso dal Passo 3) hanno un **blur medio** + il bordo rosso visibile attraverso il blur — un promemoria visivo dello shock | Ipercorrezione §4 | Blur: 18px. Il bordo rosso (3px) è visibile anche attraverso il blur |
| P6-06 | Le **frecce/connessioni** tra nodi sono **anch'esse sfumate** — lo studente deve ricordare sia i nodi che le relazioni | Concept Mapping §27 | Le frecce usano lo stesso livello di blur degli endpoint. Se entrambi i nodi collegati sono a blur 30px, la freccia è a blur 30px |

---

### 6.2 — Il Meccanismo di Reveal (Navigazione + Rivelazione)

Lo studente naviga nel canvas sfumato e tenta di ricordare ogni nodo. La sequenza per ogni nodo è:

```
1. Lo studente NAVIGA verso il nodo blurrato
        ↓
2. Si FERMA e tenta di ricordare il contenuto
   (mentalmente o scrivendo accanto)
        ↓
3. TOCCA il nodo per rivelarlo
        ↓
4. Il blur si dissolve (animazione 500ms)
        ↓
5. Risultato:
   → Se ricordava → ✅ pulse verde + haptic positivo
   → Se non ricordava → 🔴 pulse rosso + prompt "Riscrivilo"
```

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P6-07 | Il nodo si rivela **solo al tocco** — mai automaticamente, mai su proximity | Active Recall §2 | Tocco diretto (tap) sul nodo. No reveal su hover o avvicinamento |
| P6-08 | Prima del tocco, lo studente può **scrivere a mano** accanto al nodo ciò che crede sia il contenuto — creando un "tentativo" confrontabile | Generation §3, Ipercorrezione §4 | Area di scrittura libera accanto al nodo blurrato. I tratti vengono salvati come "recall attempt" |
| P6-09 | Al tocco, il blur si dissolve con **animazione graduale** (500ms, ease-out) | Embodied §23 | Il reveal è un momento significativo — non un flash |
| P6-10 | Lo studente **auto-valuta** il recall: "Ricordavo?" (verde) o "Non ricordavo?" (rosso) con un gesto rapido dopo il reveal | Metacognition T1 | 2 bottoni: ✅ / ❌. Gesto: swipe destra = verde, swipe sinistra = rosso |
| P6-11 | Se recall **corretto** (verde): pulse verde 500ms + haptic leggero. L'intervallo SRS per quel nodo si **allunga** | Spacing §1 | Nuovo intervallo: il precedente × fattore di facilità (SM-2). Il nodo diventa più trasparente al prossimo ritorno |
| P6-12 | Se recall **errato** (rosso): pulse rosso 500ms + haptic medio. L'intervallo SRS si **accorcia** (ripasso più frequente) | Spacing §1, Ipercorrezione §4 | Nuovo intervallo: reset a 1 giorno. Il nodo tornerà più opaco al prossimo ritorno |
| P6-13 | Se recall errato, lo studente **DEVE riscrivere** il nodo a mano (non rileggere — riscrivere) in una zona adiacente prima di procedere al prossimo nodo | Generation §3, Embodied §23 | Prompt: "Riscrivilo con le tue parole." Area di riscrittura evidenziata. Il nodo non è "completato" finché lo studente non ha scritto |
| P6-14 | La riscrittura viene salvata come **nuovo layer** sul nodo — lo studente vede il suo "tentativo di oggi" accanto al "nodo originale" | Metacognition T1 | I diversi strati di riscrittura sono la storia visiva della comprensione |

---

### 6.3 — Navigazione Suggerita (Percorsi Interleaving)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P6-15 | L'IA suggerisce un **percorso di navigazione** che attraversa sotto-argomenti diversi in ordine imprevedibile (interleaving spaziale) | Interleaving §10 | Il percorso è visualizzato come una linea sottile punteggiata (sentiero luminoso) che collega i nodi in ordine di revisione |
| P6-16 | Il percorso è un **suggerimento**, non un obbligo — lo studente può navigare liberamente e ignorare il percorso | Autonomy T2 | Il sentiero è dismissable con un gesto. Lo studente può toccare qualsiasi nodo in qualsiasi ordine |
| P6-17 | Il percorso **alterna** nodi di argomenti diversi: mai 3 nodi consecutivi dello stesso sotto-argomento | Interleaving §10 | Algoritmo: shuffle vincolato con max 2 nodi consecutivi dello stesso cluster |
| P6-18 | Il percorso **priorizza** i nodi con SRS scaduto (la cui data di revisione è oggi o nel passato) | Spacing §1 | I nodi "urgenti" (overdue) appaiono per primi nel percorso |

---

### 6.4 — Zoom-Out Progressivo (Piani del Palazzo)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P6-19 | Ad ogni ritorno successivo (Passo 6 ripetuto, Passo 8), il canvas si apre a un **livello di zoom leggermente più ampio** rispetto alla sessione precedente | Zoom Semantico §26, Desirable Difficulties §5 | Zoom out progressivo: sessione 1 = zoom normale, sessione 2 = 90%, sessione 3 = 80%, etc. Min: 50% |
| P6-20 | A zoom più ampio, grazie al LOD, i nodi mostrano solo i **titoli** (non il contenuto) — lo studente deve ricostruire mentalmente i dettagli dalla posizione e dal titolo prima di zoomare in | Zoom Semantico §26, Active Recall §2 | Il LOD a zoom out mostra: blob colorato + titolo (se presente). Nessun dettaglio |
| P6-21 | Lo studente può **zoomare in** su un nodo per leggerlo in dettaglio, ma il sistema registra il zoom-in come "ha avuto bisogno di aiuto" per quel nodo | Metacognition T1 | Tag: `neededZoomIn: true`. Questo dato informa l'SRS |

---

### 6.5 — Stato dell'IA durante il Passo 6

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 📊 TRACKER SILENZIOSO             │
│                                                  │
│  • Modulo IA: ATTIVO (tracking only)             │
│  • Analisi contenuto: NO                         │
│  • Genera domande: NO (solo su invocazione)      │
│  • Registra: SÌ (recall, timing, zoom-in)        │
│  • Calcola: SÌ (aggiorna intervalli SRS)         │
│  • Suggerisce percorso: SÌ (opzionale)           │
│  • Modifica canvas: MAI                          │
│                                                  │
│  L'IA è un OSSERVATORE SILENZIOSO.               │
│  Registra. Calibra. Non interferisce.            │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> ### Il Principio del Passo 6
> **Il Primo Ritorno è il test più onesto.** Lo studente non sta performando per un'IA o per un voto — sta scoprendo cosa il proprio cervello ha trattenuto dopo una notte di sonno. Il verde e il rosso non sono giudizi — sono dati. Il canvas sfumato è uno specchio fedele della propria memoria.

---

### 6.6 — Dati Generati dal Passo 6

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "zone": "canvas_zone_id",
  "daysSinceLastSession": 1,
  "nodesReviewed": 15,
  "recallResults": [
    {
      "nodeId": "node_123",
      "blurLevel": 30,
      "recalledCorrectly": true,
      "wroteAttemptBefore": true,
      "neededZoomIn": false,
      "timeTaken_ms": 8000,
      "newSRS_interval_days": 3
    }
  ],
  "rewrittenNodes": 4,
  "pathFollowed": true,
  "zoomOutLevel": 0.9
}
```

---

### 6.7 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-89:** Canvas aperto alla posizione e zoom della sessione precedente (pixel-perfect)
- [ ] **CA-90:** Blur proporzionale inverso al recall: recall 5 → 30px, recall 1 → 5px
- [ ] **CA-91:** Nodi "padroneggiato": blur 40px, quasi illeggibili
- [ ] **CA-92:** Nodi fuori-ZPD: 0 blur, etichetta "Da rivedere"
- [ ] **CA-93:** Nodi ipercorrettivi: blur 18px + bordo rosso visibile attraverso il blur
- [ ] **CA-94:** Frecce sfumate con lo stesso blur dei nodi endpoint
- [ ] **CA-95:** Reveal solo su tap: 0 reveal automatici o su proximity
- [ ] **CA-96:** Animazione reveal: blur dissolve in 500ms, ease-out
- [ ] **CA-97:** Auto-valutazione post-reveal: 2 bottoni (✅/❌) o swipe
- [ ] **CA-98:** Recall corretto: pulse verde + haptic + intervallo SRS allungato
- [ ] **CA-99:** Recall errato: pulse rosso + haptic + prompt "Riscrivilo" + intervallo reset a 1g
- [ ] **CA-100:** Riscrittura obbligatoria per nodi errati: il nodo non è "completato" senza tratto
- [ ] **CA-101:** Percorso interleaving: max 2 nodi consecutivi dello stesso sotto-argomento
- [ ] **CA-102:** Percorso dismissable con gesto, navigazione libera sempre possibile
- [ ] **CA-103:** Zoom-out progressivo: sessione N+1 apre a zoom leggermente più ampio di N
- [ ] **CA-104:** LOD a zoom out: solo blob colorato + titolo, 0 dettagli
- [ ] **CA-105:** Dataset JSON completo con SRS interval aggiornato per ogni nodo

---
---

## PASSO 7 — L'Apprendimento Solidale: Il Confronto tra Pari

### Contesto

Il Passo 7 è il **primo passo sociale**: lo studente esce dall'isolamento e confronta il proprio canvas con quello di un compagno. NON è collaborazione generica — è collaborazione strutturata in 3 sotto-modalità, ciascuna con un obiettivo cognitivo diverso.

La regola fondamentale: **ognuno lavora sul PROPRIO canvas**. Non si copia, non si fonde. Si osserva, si insegna, si compete — e poi si torna a casa propria e si rielabora con le proprie mani.

**📅 Quando:** Giorno 2-3 (dopo almeno un ciclo individuale completo: Passi 1-6).

**Principi attivati:** Peer Instruction (Mazur), Protégé Effect (§8), Conflitto Socio-Cognitivo (Doise & Mugny), Active Recall (§2), Spatial Cognition (§22), Generation (§3)

> [!WARNING]
> ### Prerequisito: Ciclo Individuale Completato
> Il Passo 7 si attiva **solo dopo** che lo studente ha completato almeno i Passi 1-6 sulla zona in questione. Se lo studente non ha ancora fatto il proprio recall e confronto, la collaborazione diventa copia — il compagno "riempie" le lacune che lo studente non ha nemmeno scoperto. L'ordine è: prima solo, poi insieme.

---

### 7.1 — Prerequisiti e Connessione

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P7-01 | Il Passo 7 richiede che lo studente abbia completato **almeno i Passi 1-4** (e preferibilmente il 6) sulla zona in questione | Productive Failure T4 — prima la fatica individuale, poi il confronto | Il sistema mostra un avviso se lo studente tenta il Passo 7 senza aver completato i Passi 1-4. L'avviso è dismissable (non bloccante) |
| P7-02 | La connessione tra due studenti avviene tramite **invito esplicito** (link, QR code, vicinanza Bluetooth) | Autonomy T2 | Nessuna lobby pubblica. Nessun matchmaking. Lo studente sceglie con chi collaborare |
| P7-03 | Entrambi gli studenti devono avere la **stessa zona/materia** nel proprio canvas per attivare le sotto-modalità 7b e 7c | Peer Instruction (Mazur) | Matching basato su tag materia/argomento. La visita reciproca (7a) non richiede la stessa materia |
| P7-04 | La connessione è **peer-to-peer** o via server relay — ma i canvas restano sui dispositivi rispettivi. Nessun canvas viene "caricato" sul dispositivo dell'altro | Extended Mind §29, Privacy | Solo viewport e posizione cursore vengono trasmessi, non i dati completi del canvas |

---

### 7.2 — Modalità 7a: La Visita Reciproca (Sola Lettura)

Lo studente entra nel canvas del compagno come **ospite in sola lettura**. Osserva la diversa organizzazione spaziale, i diversi nodi, le diverse connessioni. Non può toccare nulla.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P7-05 | L'ospite vede il canvas dell'altro con un **cursore-fantasma** (ghost cursor) che mostra dove sta guardando. Il proprietario vede il cursore dell'ospite nel proprio canvas | Spatial Cognition §22 — la presenza dell'altro è spaziale | Cursore fantasma: cerchio semi-trasparente (opacità 30%), colore distinto dal proprietario |
| P7-06 | L'ospite è in **sola lettura completa**: non può scrivere, disegnare, spostare, cancellare o modificare nulla nel canvas dell'altro | Extended Mind §29 | 0 azioni di modifica disponibili. La toolbar mostra solo strumenti di navigazione (pan, zoom) |
| P7-07 | L'ospite può **navigare liberamente** (pan, zoom) nel canvas dell'altro — non è vincolato alla posizione del proprietario | Autonomy T2 | Pan e zoom indipendenti. Bottone "Segui" opzionale per sincronizzare la vista con il proprietario |
| P7-08 | L'ospite può **piazzare marker temporanei** (puntini colorati con "!" o "?") che il proprietario vedrà. I marker scompaiono al termine della sessione | Peer Instruction (Mazur) | Marker: tap lungo su un punto del canvas dell'altro → crea un puntino colorato. Max 10 marker per sessione |
| P7-09 | Dopo la visita, l'ospite torna al **PROPRIO canvas** e può annotare ciò che ha osservato dall'altro — riscrivendolo a mano, non copiandolo | Generation §3 | Il sistema NON offre "importa dal canvas dell'altro". Lo studente deve generare il contenuto da sé |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P7-10 | Permettere il **copia-incolla** dal canvas dell'altro al proprio | Generation §3, Embodied §23 | Copiare è il contrario di generare. Lo studente deve RISCRIVERE con la propria mano |
| P7-11 | Mostrare un **confronto automatico** tra i due canvas ("Ecco le differenze") | Active Recall §2, Metacognition T1 | Lo studente deve notare le differenze DA SOLO — il confronto automatico uccide l'osservazione attiva |
| P7-12 | Permettere all'ospite di **scrivere** nel canvas dell'altro (annotazioni permanenti, correzioni) | Extended Mind §29, Generation §3 | Il canvas è sacro. Solo il proprietario ci scrive |

---

### 7.3 — Modalità 7b: L'Insegnamento Reciproco (Protégé Effect)

A turno, ciascuno studente **guida l'altro** nel proprio canvas, spiegando a voce i concetti. Chi ascolta poi torna al PROPRIO canvas e ricostruisce ciò che ha appreso.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P7-13 | Il proprietario guida la navigazione — l'ospite **segue** il viewport del proprietario (modalità "Follow") | Protégé Effect §8 — chi insegna sta navigando il proprio Palazzo della Memoria | Sync viewport: l'ospite vede lo stesso viewport del proprietario, con un leggero ritardo (100ms) per smoothness |
| P7-14 | Il sistema offre un **canale vocale** integrato (voce in-app) per la spiegazione | Peer Instruction (Mazur) | Audio peer-to-peer, bassa latenza (≤200ms). Nessuna chat testuale durante l'insegnamento — la spiegazione è orale |
| P7-15 | Il proprietario può usare un **puntatore laser** virtuale (tratto temporaneo luminoso) per indicare concetti mentre spiega | Spatial Cognition §22, Embodied §23 | Tratto luminoso che scompare dopo 2s. Colore: giallo brillante. Non viene salvato nel canvas |
| P7-16 | Dopo il turno di insegnamento, l'ospite torna al **PROPRIO canvas** e riceve un prompt: "Adesso riscrivi con le tue parole ciò che hai appreso" | Generation §3, Protégé §8 | Il prompt è un suggerimento gentile. L'area di riscrittura è evidenziata nel proprio canvas |
| P7-17 | Chi ha insegnato riceve un **feedback metacognitivo**: "Hai spiegato 6 nodi. Ci sono zone del tuo canvas che hai faticato a spiegare?" | Metacognition T1, Protégé §8 — la difficoltà a spiegare rivela lacune proprie | Domanda opzionale dopo la sessione. Lo studente può segnare i nodi "faticosi" |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P7-18 | Permettere la **registrazione audio** della spiegazione per riascolto successivo | Active Recall §2, Cognitive Offloading §15 | Riascoltare è passivo. Lo studente deve rielaborare ciò che ha sentito, non riprodurlo |
| P7-19 | Permettere **screenshot** del canvas dell'altro | Generation §3 | Lo screenshot è una copia passiva. La rielaborazione deve avvenire a mano |
| P7-20 | Generare un **riassunto IA** di ciò che il compagno ha insegnato | Cognitive Offloading §15, Generation §3 | Il riassunto IA sostituisce l'elaborazione autonoma |

---

### 7.4 — Modalità 7c: Il Duello di Richiamo

Entrambi gli studenti attivano **simultaneamente** il Recall Mode (Passo 2) sulla stessa zona. Ognuno nel proprio canvas. Alla fine, confrontano i risultati.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P7-21 | Entrambi attivano il Recall Mode **contemporaneamente** — un countdown sincronizzato ("3... 2... 1... Via!") | Motivazione sociale, Active Recall §2 | Countdown visivo e sonoro. Entrambi iniziano nello stesso istante |
| P7-22 | Ciascuno ricostruisce nel **proprio canvas**, senza vedere il canvas dell'altro durante il richiamo | Active Recall §2 | Durante il recall, i canvas sono isolati. 0 visibilità sul lavoro dell'altro |
| P7-23 | Al termine del recall (quando entrambi premono "Ho finito"), il sistema mostra una **split-view**: i due canvas fianco a fianco | Peer Instruction (Mazur), Metacognition T1 | Split-view: 50/50 orizzontale o verticale (adattivo allo schermo). Pan e zoom sincronizzati |
| P7-24 | La split-view evidenzia le **differenze**: nodi presenti nel canvas A ma non nel B (e viceversa) con un colore distinto | Conflitto Socio-Cognitivo (Doise & Mugny) | Colore: nodi unici di A = blu chiaro, nodi unici di B = arancione chiaro |
| P7-25 | Le zone **rosse** (nodi dimenticati) di uno studente che sono **verdi** nell'altro diventano il **piano di studio reciproco**: "Tu sai X, io no. Insegnamelo." | Peer Instruction (Mazur), Protégé §8 | Il sistema non fa questa assegnazione automaticamente — mostra solo la differenza. Lo studente decide cosa imparare dall'altro |
| P7-26 | Dopo la split-view, ciascuno torna al **PROPRIO canvas** e può riscrivere a mano ciò che ha appreso dal confronto | Generation §3 | Il sistema non trasferisce nodi. Lo studente deve generare |
| P7-27 | Il sistema **NON mostra un "vincitore"** — non c'è punteggio, non c'è classifica, non c'è chi ha "vinto" il duello | Growth Mindset §12, Cooperazione vs. competizione | 0 punteggi comparativi. La split-view mostra differenze, non ranking |

---

### 7.5 — Guardrail Emotivi e Anti-Confronto Tossico

> [!CAUTION]
> Il confronto tra pari è potentissimo ma anche pericoloso. Può facilmente degenerare in **confronto tossico** ("Lui ha capito meglio di me"), **copia passiva** ("Il suo canvas è migliore, copio il suo"), o **ansia sociale** ("Non voglio mostrare il mio canvas imperfetto").

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P7-28 | Il sistema deve comunicare **prima** di ogni sessione sociale: "Il tuo canvas è unico — è il TUO palazzo della memoria. Le differenze con gli altri non sono errori, sono prospettive diverse." | Growth Mindset §12, Self-Determination T2 | Messaggio mostrato 1 volta per sessione, dismissable. Tono: rassicurante e normalizzante |
| P7-29 | Il linguaggio dell'UI deve evitare **ogni forma di confronto quantitativo**: mai "Lui ha 15 nodi, tu ne hai 10", mai "Il suo recall è dell'87%, il tuo del 63%" | Growth Mindset §12 | 0 numeri comparativi. Le differenze sono mostrate visivamente (colori) non numericamente |
| P7-30 | Lo studente può **rifiutare** di mostrare il proprio canvas in qualsiasi momento — la partecipazione è volontaria | Autonomy T2 | Bottone "Esci dalla sessione" sempre visibile. Uscita istantanea senza penalità |
| P7-31 | Il sistema deve offrire la possibilità di **sfuocare selettivamente** parti del proprio canvas che lo studente non vuole mostrare (es. annotazioni personali, zone deboli) | Autonomy T2, Privacy | Gesto: selezione area + "Nascondi all'ospite". Le aree nascoste appaiono come bloc opachi neutri all'ospite |

---

### 7.6 — Stato dell'IA durante il Passo 7

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: ⚖️ ARBITRO NEUTRALE               │
│                                                  │
│  • Modulo IA: ATTIVO (monitoraggio)              │
│  • Genera domande: SÌ (a entrambi, su conflitti) │
│  • Dà risposte: MAI                             │
│  • Dichiara vincitori: MAI                       │
│  • Confronta i canvas: SOLO visivamente          │
│  • Copia contenuti tra canvas: MAI               │
│  • Modifica canvas: MAI                          │
│                                                  │
│  L'IA è un ARBITRO — non un giudice.             │
│  Facilita il dialogo, non esprime verdetti.      │
│                                                  │
└──────────────────────────────────────────────────┘
```

#### Il Ruolo dell'IA come Arbitro

| ID | Regola | Dettaglio |
|----|--------|-----------|
| P7-32 | Se durante l'insegnamento reciproco (7b) i due studenti sono in **disaccordo** su un concetto, l'IA può intervenire (su invocazione) come **arbitro neutrale** — ponendo domande a ENTRAMBI | "Voi dite cose diverse. Studente A, perché credi X? Studente B, perché credi Y? Trovate la differenza." |
| P7-33 | L'IA non dice chi ha ragione — pone **domande socratiche** che guidano entrambi verso la risposta | Socratic §20, Generation §3 |
| P7-34 | Se il conflitto non si risolve, l'IA suggerisce: "Questo è un punto interessante. Ognuno annoti la propria ipotesi e la verifichi nel materiale." | Il conflitto irrisolto non è un problema — è **tensione Zeigarnik** (§7) che stimolerà ulteriore ricerca |

---

### 7.7 — Dati Generati dal Passo 7

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "mode": "7a|7b|7c",
  "participants": ["student_A_id", "student_B_id"],
  "zone": "canvas_zone_id",
  "7a_data": {
    "markersPlaced": 4,
    "nodesDifferent": 7,
    "viewDuration_ms": 300000
  },
  "7b_data": {
    "whoTaught": "student_A_id",
    "nodesExplained": 6,
    "nodesHardToExplain": 2,
    "rewrittenAfter": 3
  },
  "7c_data": {
    "nodesRecalledA": 10,
    "nodesRecalledB": 8,
    "uniqueToA": 3,
    "uniqueToB": 1,
    "rewrittenAfter": 2
  }
}
```

---

### 7.8 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-106:** Prerequisito: avviso (dismissable) se Passi 1-4 non completati sulla zona
- [ ] **CA-107:** Connessione peer: invito esplicito (link/QR). 0 lobby pubbliche, 0 matchmaking
- [ ] **CA-108:** 7a — Sola lettura: 0 azioni di modifica disponibili all'ospite
- [ ] **CA-109:** 7a — Ghost cursor: cerchio semi-trasparente, latenza ≤100ms
- [ ] **CA-110:** 7a — Marker temporanei: max 10, scompaiono a fine sessione
- [ ] **CA-111:** 7a — 0 funzioni copia-incolla tra canvas
- [ ] **CA-112:** 7b — Follow viewport: sync con ritardo ≤100ms
- [ ] **CA-113:** 7b — Canale vocale: latenza ≤200ms, peer-to-peer
- [ ] **CA-114:** 7b — Puntatore laser: tratto luminoso, scompare dopo 2s, non salvato
- [ ] **CA-115:** 7b — Prompt "riscrivi" mostrato all'ospite dopo il turno
- [ ] **CA-116:** 7b — 0 registrazioni audio, 0 screenshot permessi
- [ ] **CA-117:** 7c — Countdown sincronizzato, canvas isolati durante il recall
- [ ] **CA-118:** 7c — Split-view post-duello: 50/50, differenze colorate (blu/arancione)
- [ ] **CA-119:** 7c — 0 punteggi comparativi, 0 classifiche, 0 "vincitori"
- [ ] **CA-120:** Messaggio rassicurante pre-sessione mostrato 1 volta
- [ ] **CA-121:** 0 confronti quantitativi nell'UI ("Lui ha N, tu hai M")
- [ ] **CA-122:** Uscita dalla sessione: sempre possibile, istantanea, 0 penalità
- [ ] **CA-123:** Sfuocatura selettiva: aree nascoste appaiono come blocchi opachi all'ospite
- [ ] **CA-124:** IA arbitro: domande a entrambi su conflitti, 0 verdetti, 0 risposte dirette

---
---

## PASSO 8 — I Ritorni SRS: Il Ripasso a Intervalli Crescenti

### Contesto

Il Passo 8 non è un passo singolo — è un **ciclo** che si ripete nel tempo. Lo studente torna al canvas a intervalli crescenti (giorni 3, 7, 14, 30, 60...) guidati dall'algoritmo SRS. Ad ogni ritorno, il canvas è leggermente diverso: più sfumato, più zoomato fuori, con percorsi interleaving più complessi.

Il Passo 6 era il primo ritorno. Il Passo 8 è il **motore di tutti i ritorni successivi** — la macchina che appiattisce la curva dell'oblio di Ebbinghaus.

**📅 Quando:** Giorni 3, 7, 14, 30, 60, 120...

**Principi attivati:** Spacing (§1), Interleaving (§10), Zeigarnik (§7), Zoom Semantico (§26), Active Recall (§2), Desirable Difficulties (§5)

---

### 8.1 — L'Algoritmo SRS Spaziale

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P8-01 | L'algoritmo SRS calcola un **intervallo personalizzato per ogni nodo** del canvas, non un intervallo uniforme per tutta la zona | Spacing §1 | Ogni nodo ha il proprio `next_review_date`. Due nodi adiacenti possono avere date di ripasso diverse |
| P8-02 | L'algoritmo usa come input **tutti i dati** accumulati nei Passi precedenti: recall level (1-5), confidenza (1-5), ipercorrezione (bool), breadcrumb usati (0-3), fuori-ZPD (bool), peek count, tempo di risposta, zoom-in necessari | Spacing §1, Metacognition T1 | Algoritmo: SM-2 modificato o FSRS (Free Spaced Repetition Scheduler). I pesi dei parametri sono configurabili |
| P8-03 | I nodi con **ipercorrezione** hanno un **bonus di ritenzione**: l'intervallo si allunga più velocemente del normale perché lo shock cognitivo ha creato una traccia mnestica forte | Ipercorrezione §4 | Bonus: fattore di facilità × 1.3 per nodi con `hypercorrection: true` |
| P8-04 | I nodi con **peek** o **breadcrumb** hanno un **malus di ritenzione**: l'intervallo si accorcia perché il recall non era puro | Active Recall §2 | Malus: fattore di facilità × 0.8 per nodi con `peeked: true` o `hintsUsed > 0` |
| P8-05 | L'algoritmo tiene conto del **tempo di risposta**: un recall corretto ma lento (>15s) è meno robusto di un recall corretto e rapido (<5s) | Desirable Difficulties §5 | Tempo di risposta influenza il fattore di facilità: <5s → +0.1, 5-15s → +0.0, >15s → -0.1 |

---

### 8.2 — I 5 Stadi Visivi dell'Invecchiamento del Canvas

Ad ogni ritorno, l'aspetto visivo dei nodi cambia in base alla loro maturità SRS:

| Stadio | Nome | Aspetto | Significato | Intervallo SRS tipico |
|--------|------|---------|-------------|----------------------|
| **1 — Fragile** | Nodo giovane | Blur leggero (5-10px), colori vivaci, bordo visibile | Il nodo è stato appreso di recente, la traccia è instabile | 1-3 giorni |
| **2 — In crescita** | Nodo in consolidamento | Blur medio (15-20px), colori leggermente desaturati | Il nodo è stato ricordato 2-3 volte, sta diventando stabile | 7-14 giorni |
| **3 — Solido** | Nodo consolidato | Blur forte (25-30px), colori pastello, bordo sottile | Lo studente ricorda consistentemente. Il test è più difficile | 30-60 giorni |
| **4 — Padroneggiato** | Nodo stella dorata | Blur massimo (35-40px), quasi trasparente, stella dorata visibile | 3+ recall corretti. Il cervello lo "possiede" | 90-180 giorni |
| **5 — Integrato** | Nodo fantasma | Quasi invisibile (opacità 10-15%), solo titolo leggibile a zoom-in | Il nodo è diventato conoscenza integrata — non serve più testarlo attivamente | 365+ giorni |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P8-06 | Il **blur e l'opacità** di ogni nodo evolve automaticamente in base al suo stadio SRS | Desirable Difficulties §5 — più il nodo è consolidato, più il test è arduo | I valori della tabella sono default. Lo studente può calibrare la scala |
| P8-07 | Lo stadio del nodo è **calcolato automaticamente** dall'SRS — lo studente non deve assegnarlo manualmente | Cognitive Load §9 | Lo stadio è derivato: numero di recall corretti + intervallo corrente → stadio |
| P8-08 | I nodi allo **Stadio 5 (Integrato)** non vengono più proposti per il ripasso a meno che lo studente non fallisca un recall casuale | Spacing §1 | Questi nodi escono dalla coda SRS attiva. Vengono testati solo in Fog of War (Passo 10) o su richiesta |
| P8-09 | Lo studente può vedere un **indicatore di stadio** opzionale per ogni nodo (icona piccola nell'angolo) | Metacognition T1 | Icona: 🌱 (fragile) → 🌿 (crescita) → 🌳 (solido) → ⭐ (padroneggiato) → 👻 (integrato) |

---

### 8.3 — Navigazione Interleaving Avanzata

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P8-10 | Ad ogni ritorno SRS, l'IA genera un **percorso interleaving** che attraversa sotto-argomenti diversi | Interleaving §10 | Il percorso è un "sentiero luminoso" che collega i nodi da rivedere in ordine interleaved |
| P8-11 | Il percorso rispetta la regola: **mai 2 nodi consecutivi dello stesso sotto-argomento** (più restrittivo del Passo 6 che permetteva 2) | Interleaving §10 | Algoritmo: shuffle con vincolo di non-contiguità per cluster |
| P8-12 | Il percorso può attraversare **zone diverse** del canvas (non solo la zona corrente) — proponendo ritorni cross-materia | Interleaving §10, Transfer T3 | Se lo studente ha studiato Biologia e Chimica, il percorso può alternare nodi tra le due |
| P8-13 | I nodi **Zeigarnik** (incompleti, contorno tratteggiato) pulsano ad ogni ritorno fino a quando non vengono completati | Zeigarnik §7 | Glow pulsante: 2s periodo, colore ambra, opacità 30-60%. Ogni ritorno rinnova il pulse |
| P8-14 | L'IA può suggerire **connessioni cross-zona** durante la navigazione: "Il concetto X nella zona Biologia è collegato al concetto Y nella zona Chimica — vuoi navigare lì?" | Interleaving §10, Transfer T3 | Suggerimento: bolla discreta ancorata al nodo. Dismissable. Tocco → navigazione automatica alla zona suggerita |

---

### 8.4 — Due Tipi di Sessione di Ripasso

Non tutti i ritorni sono uguali. Il sistema supporta due tipi:

| Tipo | Nome | Durata | Cosa succede | Quando |
|------|------|--------|-------------|--------|
| **Micro-Review** | "Ripasso veloce" | 3-5 minuti | Solo i nodi con SRS scaduto. Tap → reveal → verde/rosso. Nessuna riscrittura | Quando lo studente ha poco tempo |
| **Deep-Review** | "Ripasso profondo" | 15-30 minuti | SRS + riscrittura obbligatoria per nodi errati + navigazione interleaving + domande Socratiche opzionali | Quando lo studente vuole una sessione completa |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P8-15 | All'apertura del canvas per ripasso, offrire la scelta: **"Ripasso veloce"** vs **"Ripasso profondo"** | Autonomy T2 | 2 bottoni chiari. Tempo stimato mostrato: "~ 5 min" vs "~ 20 min" |
| P8-16 | Nel **Micro-Review**, la sequenza è semplificata: navigate → tap → reveal → ✅/❌ → next. Nessuna riscrittura, nessun breadcrumb | Cognitive Load §9 | Sessione ottimizzata per velocità. I dati SRS vengono comunque aggiornati |
| P8-17 | Nel **Deep-Review**, tutte le regole del Passo 6 (reveal, riscrittura, interleaving) sono attive. In più, l'IA può generare domande Socratiche (Passo 3 light) su invocazione | ZPD §19, Active Recall §2 | Le domande sono facoltative: bottone "Mettimi alla prova su questo nodo" |
| P8-18 | Lo studente può **passare** da Micro a Deep durante la sessione (es. inizia veloce, poi decide di approfondire) ma NON viceversa | Desirable Difficulties §5 | Passaggio unidirezionale: Micro → Deep ✅, Deep → Micro ❌ |

---

### 8.5 — L'Autonomia dello Studente sul Calendario SRS

> [!IMPORTANT]
> L'SRS suggerisce quando ripassare, ma lo studente **decide**. Fluera non è un taskmaster.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P8-19 | Il sistema mostra un **indicatore visivo discreto** nella galleria o nella home del canvas: "Questa zona ha 8 nodi da rivedere" | Metacognition T1 | Badge numerico piccolo (non allarmante), aggiornato quotidianamente |
| P8-20 | Lo studente può **ignorare** gli intervalli SRS senza penalità o popup | Autonomy T2 | 0 notifiche "Non hai ripassato!", 0 popup di colpa, 0 streak rotte |
| P8-21 | Se lo studente non ripassa per un periodo lungo (es. 2 settimane oltre l'intervallo SRS), l'algoritmo **adatta** gli intervalli senza drammatizzare: i nodi tornano a Stadio 1-2 silenziosamente | Spacing §1 | Nessun messaggio "Hai perso i tuoi progressi!" — solo un ricalcolo silenzioso del blur |
| P8-22 | Lo studente può **anticipare** un ripasso (ripassare prima della data SRS) — il sistema registra il risultato ma non sovrascrive l'intervallo pianificato | Autonomy T2 | I ripassi anticipati sono "extra practice". L'SRS successivo viene comunque calcolato sulla data pianificata |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P8-23 | Mandare notifiche push di ripasso | Autonomy T2 | Vedi P5-05. La disciplina temporale è dello studente |
| P8-24 | Mostrare "streak" o "giorni consecutivi" di ripasso | Growth Mindset §12 | Gamification che sposta la motivazione |
| P8-25 | Mostrare "percentuale di completamento" globale ("Hai padroneggiato il 73% del corso") | Growth Mindset §12 | La percentuale crea ansia e falsa precisione. Lo studente vede la mappa visiva, non un numero |
| P8-26 | Penalizzare lo studente che non ripassa nei tempi SRS (es. perdere "punti", regredire artificialmente) | Autonomy T2, Growth Mindset §12 | L'oblio naturale è già la penalità. Aggiungerne un'altra è punitivo |

---

### 8.6 — Stato dell'IA durante il Passo 8

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 📊 CALIBRATORE SRS                │
│                                                  │
│  • Modulo IA: ATTIVO (calcolo + tracking)        │
│  • Calcola intervalli: SÌ (per ogni nodo)        │
│  • Genera percorsi interleaving: SÌ              │
│  • Suggerisce connessioni cross-zona: SÌ         │
│  • Domande Socratiche: SOLO su invocazione       │
│  •   (Deep-Review)                               │
│  • Modifica canvas: MAI                          │
│  • Notifiche: MAI                                │
│                                                  │
│  L'IA è un CUSTODE SILENZIOSO del tempo.         │
│  Tiene il ritmo — ma lo studente decide          │
│  quando ballare.                                 │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

### 8.7 — Dati Generati dal Passo 8

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "sessionType": "micro|deep",
  "zone": "canvas_zone_id",
  "daysSinceLastReview": 7,
  "nodesScheduled": 12,
  "nodesReviewed": 10,
  "nodesSkipped": 2,
  "recallResults": [
    {
      "nodeId": "node_123",
      "stage": 3,
      "blurLevel": 25,
      "recalledCorrectly": true,
      "responseTime_ms": 6000,
      "rewritten": false,
      "newInterval_days": 21,
      "newStage": 3
    }
  ],
  "interleavingPath": {
    "followed": true,
    "crossZoneJumps": 2
  },
  "zeigarnikNodesStillOpen": 1
}
```

---

### 8.8 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-125:** SRS per nodo: ogni nodo ha il proprio intervallo indipendente
- [ ] **CA-126:** Algoritmo SRS: usa recall level, confidenza, ipercorrezione, peek, breadcrumb, tempo di risposta
- [ ] **CA-127:** Bonus ipercorrezione: fattore × 1.3 per nodi con shock cognitivo
- [ ] **CA-128:** Malus peek/breadcrumb: fattore × 0.8 per nodi con aiuto esterno
- [ ] **CA-129:** 5 stadi visivi: blur e opacità evolvono correttamente per stadio
- [ ] **CA-130:** Icone stadio: 🌱→🌿→🌳→⭐→👻 mostrate correttamente (opzionale)
- [ ] **CA-131:** Stadio 5 (Integrato): nodo esce dalla coda SRS attiva
- [ ] **CA-132:** Interleaving: mai 2 nodi consecutivi dello stesso sotto-argomento
- [ ] **CA-133:** Nodi Zeigarnik: pulse ambra vivo ad ogni ritorno
- [ ] **CA-134:** Connessioni cross-zona: suggerimento dismissable con navigazione automatica
- [ ] **CA-135:** Micro-Review: sessione ≤5min, 0 riscrittura, SRS aggiornato
- [ ] **CA-136:** Deep-Review: riscrittura obbligatoria per nodi errati, domande Socratiche opzionali
- [ ] **CA-137:** Passaggio Micro→Deep funzionante; Deep→Micro bloccato
- [ ] **CA-138:** Badge "nodi da rivedere" in galleria: discreto, non allarmante
- [ ] **CA-139:** 0 notifiche push, 0 streak, 0 percentuali globali
- [ ] **CA-140:** Assenza ripasso: ricalcolo SRS silenzioso, 0 messaggi di colpa
- [ ] **CA-141:** Ripasso anticipato: registrato come extra, 0 sovrascrittura intervallo pianificato

---
---

## PASSO 9 — I Ponti Cross-Dominio: La Nascita del Pensiero Sistemico

### Contesto

Il Passo 9 è dove lo studente smette di essere un "conoscitore di fatti" e inizia a diventare un **pensatore sistemico**. Dopo settimane o mesi di studio su più argomenti nello stesso canvas infinito, lo studente zooma fuori e vede il "continente" della conoscenza — e inizia a riconoscere **pattern che attraversano le materie**.

Non è un passo che avviene in un giorno specifico — emerge naturalmente quando il canvas contiene almeno 2-3 zone/materie studiate con i Passi 1-8. Il software deve **abilitare** questa visione panoramica, non forzarla.

**📅 Quando:** Dopo settimane/mesi di studio su più argomenti nello stesso canvas.

**Principi attivati:** Interleaving (§10), Concept Mapping (§27), Zoom Semantico (§26), Elaborazione Profonda (§6), Transfer (T3), Spatial Cognition (§22)

---

### 9.1 — La Visione Panoramica (Zoom-Out Continentale)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P9-01 | Il canvas deve supportare un **zoom-out sufficiente** a mostrare l'intero "continente" della conoscenza dello studente — tutte le zone di tutte le materie visibili contemporaneamente | Spatial Cognition §22, Zoom Semantico §26 | Zoom minimo: tale da contenere tutte le zone nel viewport. LOD attivo: a questo zoom, solo i nodi-monumento (titoli principali) sono leggibili |
| P9-02 | A zoom panoramico, il LOD mostra le **zone come "quartieri"** del Palazzo: blob colorati per materia, nomi delle zone leggibili, dettagli interni nascosti | Zoom Semantico §26 | Le zone sono visivamente distinguibili per colore/bordo. I nomi delle zone sono l'unico testo leggibile |
| P9-03 | Le **connessioni esistenti** (frecce all'interno delle zone) sono semplificate visivamente a zoom-out: diventano linee sottili di colore zona | Cognitive Load §9 | Le frecce intra-zona si fondono in un "texture" visiva. Solo le frecce cross-zona (lunghe) restano distinte |
| P9-04 | Lo studente può **tracciare frecce a lunga distanza** che attraversano l'intero canvas, collegando nodi in zone diverse | Concept Mapping §27, Transfer T3 | Le frecce cross-zona sono tracciate con la penna come qualsiasi altra freccia. Il rendering supporta frecce lunghe senza degradamento di performance |

---

### 9.2 — I 3 Tipi di Ponte Cross-Dominio

| Tipo | Nome | Esempio | Come si manifesta |
|------|------|---------|-------------------|
| **A — Analogia Strutturale** | "Queste due cose hanno la stessa forma" | La stessa equazione differenziale governa la crescita batterica (Biologia) e l'interesse composto (Economia) | Due nodi in zone diverse condividono una struttura matematica o logica identica |
| **B — Meccanismo Condiviso** | "Queste due cose funzionano allo stesso modo" | Il feedback negativo nella regolazione ormonale (Biologia) e nel termostato (Fisica/Ingegneria) | Due processi in domini diversi usano lo stesso principio causale |
| **C — Prospettiva Complementare** | "Queste due cose illuminano la stessa cosa da angoli diversi" | L'entropia in Termodinamica e il disordine in Teoria dell'Informazione | Due concetti in domini diversi descrivono lo stesso fenomeno con linguaggi diversi |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P9-05 | Le frecce cross-zona devono avere un **aspetto visivo distinto** dalle frecce intra-zona: più spesse, colore diverso (es. dorato), con un'etichetta che descrive il tipo di ponte (A/B/C) | Concept Mapping §27, Spatial Cognition §22 | Freccia cross-zona: 3px spessore, colore #FFD700 (dorato), etichetta opzionale |
| P9-06 | Lo studente può **annotare** ogni ponte con una spiegazione scritta a mano: "Questo e quello sono la stessa cosa perché..." | Generation §3, Elaborazione §6 | L'annotazione è un nodo-ponte: un piccolo nodo posizionato a metà della freccia cross-zona, con il testo scritto a mano |
| P9-07 | I ponti tracciati dallo studente sono **permanenti** — diventano parte della struttura del canvas e vengono mostrati a zoom-out come linee dorate prominenti | Extended Mind §29 | I ponti formano visivamente una "rete" a zoom panoramico — più ponti = rete più densa = pensiero più sistemico |

---

### 9.3 — Il Ruolo dell'IA: Suggeritrice di Ponti, Mai Costruttrice

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P9-08 | Su invocazione esplicita ("Suggeriscimi connessioni"), l'IA analizza le zone del canvas e **suggerisce possibili ponti** tra concetti di domini diversi | Transfer T3, Interleaving §10 | L'IA mostra i suggerimenti come linee punteggiate dorate tra i nodi candidati. Max 3-5 suggerimenti alla volta |
| P9-09 | I suggerimenti sono formulati come **domande**, non come affermazioni: "Hai notato che X in Biologia e Y in Economia condividono la stessa struttura? Cosa hanno in comune?" | Socratic §20, Generation §3 | La bolla-suggerimento contiene una domanda, mai un'asserzione |
| P9-10 | Lo studente decide se il ponte è **rilevante**: se sì, lo traccia con la penna (la linea punteggiata diventa solida). Se no, lo dismissega | Autonomy T2 | Gesto: tracciare sulla linea punteggiata = accetta. Swipe via = dismissega |
| P9-11 | L'IA **non traccia mai** ponti autonomamente — aspetta sempre che sia lo studente a completare la connessione | Generation §3 | 0 frecce create dall'IA nel canvas dello studente |
| P9-12 | I ponti **scoperti autonomamente** dallo studente (senza suggerimento IA) vengono marcati con un'icona distinta (💡) rispetto a quelli suggeriti dall'IA (🤖) | Metacognition T1 | Lo studente vede quanti ponti ha scoperto da solo vs. quanti con aiuto — nella cronologia del canvas |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P9-13 | Tracciare automaticamente connessioni cross-zona basate su keyword matching o similarità semantica | Generation §3, Transfer T3 | Il valore del ponte è nell'ATTO di scoprirlo. La scoperta automatica elimina l'insight |
| P9-14 | Suggerire connessioni cross-zona **prima** che lo studente abbia consolidato le singole zone (Passi 1-8) | ZPD §19 | Prima consolidare la base, poi espandere. I ponti prematuri sono superficiali |
| P9-15 | Mostrare un "punteggio di interconnessione" ("Il tuo canvas ha 12 ponti — obiettivo: 20") | Growth Mindset §12 | I ponti emergono naturalmente quando la conoscenza è matura. Quantificarli li trasforma in un target da raggiungere |

---

### 9.4 — La Navigazione Cross-Zona

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P9-16 | Toccando un ponte (freccia cross-zona), il canvas **zooma fluentemente** dal nodo sorgente al nodo destinazione, attraversando lo spazio intermedio | Spatial Cognition §22, Embodied §23 | Animazione: zoom-out → pan → zoom-in al nodo destinazione. Durata: 1-2s. Il viaggio è visivamente "sentito" |
| P9-17 | Il viaggio cross-zona deve mostrare il **percorso spaziale** tra le due zone — lo studente "vede" la distanza sul canvas | Spatial Cognition §22 | Nessun taglio o teletrasporto. Il canvas si muove fluidamente. Lo studente percepisce la distanza tra i domini |
| P9-18 | A zoom panoramico, i ponti formano una **rete visiva** — il canvas mostra la "topografia della conoscenza" con le connessioni dorate come strade principali | Concept Mapping §27 | I ponti sono visibili a qualsiasi livello di zoom. A zoom-out estremo sono gli elementi più prominenti |

---

### 9.5 — Stato dell'IA durante il Passo 9

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 🌉 SUGGERITRICE DI PONTI          │
│                                                  │
│  • Modulo IA: ATTIVO (su invocazione)            │
│  • Analizza cross-zona: SÌ                      │
│  • Suggerisce ponti: SÌ (come domande)           │
│  • Traccia ponti: MAI (solo lo studente)         │
│  • Modifica canvas: MAI                          │
│                                                  │
│  L'IA è una GUIDA che indica l'orizzonte —       │
│  ma il sentiero lo traccia lo studente.           │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> ### Il Significato del Passo 9
> I ponti cross-dominio sono ciò che distingue lo **studente** dall'**esperto**. Lo studente conosce i fatti dentro le materie. L'esperto vede i pattern CHE ATTRAVERSANO le materie. Il canvas infinito di Fluera rende questo visivamente possibile: zoomando fuori, i ponti dorati formano la rete che trasforma la conoscenza frammentaria in comprensione sistemica.

---

### 9.6 — Dati Generati dal Passo 9

```json
{
  "bridges": [
    {
      "bridgeId": "bridge_001",
      "sourceNode": "bio_node_42",
      "sourceZone": "biologia",
      "targetNode": "eco_node_17",
      "targetZone": "economia",
      "bridgeType": "A|B|C",
      "discoveredBy": "student|ai_suggested",
      "annotation": "blob_handwritten",
      "timestamp": "ISO-8601"
    }
  ],
  "totalBridges": 5,
  "studentDiscovered": 3,
  "aiSuggested": 2,
  "zonesConnected": ["biologia", "economia", "chimica"]
}
```

---

### 9.7 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-142:** Zoom panoramico: tutte le zone visibili simultaneamente con LOD
- [ ] **CA-143:** LOD a zoom-out: zone come "quartieri" con nomi leggibili, dettagli nascosti
- [ ] **CA-144:** Frecce cross-zona: 3px, dorate (#FFD700), distinguibili dalle frecce intra-zona
- [ ] **CA-145:** Frecce lunghe: rendering senza degradamento di performance
- [ ] **CA-146:** Nodo-ponte: annotazione scritto a mano posizionato a metà della freccia
- [ ] **CA-147:** IA suggerisce ponti: solo su invocazione, come domande, max 3-5 alla volta
- [ ] **CA-148:** Ponte accettato: traccia su linea punteggiata → diventa solido
- [ ] **CA-149:** Ponte dismissato: swipe via, la linea punteggiata scompare
- [ ] **CA-150:** 0 ponti creati automaticamente dall'IA
- [ ] **CA-151:** Icona 💡 per ponti autonomi, 🤖 per ponti suggeriti dall'IA
- [ ] **CA-152:** Navigazione cross-zona: zoom-out→pan→zoom-in fluido (1-2s), 0 tagli
- [ ] **CA-153:** Rete di ponti visibile a zoom panoramico come strade dorate prominenti
- [ ] **CA-154:** 0 punteggi di interconnessione, 0 obiettivi di ponti da raggiungere

---
---

## PASSO 10 — La Fog of War: Preparazione all'Esame

### Contesto

Il Passo 10 è la **simulazione d'esame** — l'esperienza di recall più intensa dell'intero framework. L'intero canvas (o una zona selezionata) viene avvolto in una "nebbia" opaca. Lo studente naviga alla cieca nel proprio Palazzo della Memoria, toccando nodi per tentare di ricordare il contenuto. Alla fine, la nebbia si alza e rivela la **mappa di padronanza** — un heatmap che mostra esattamente cosa sa e cosa no.

Non è un esame con voto. È uno **strumento diagnostico** che elimina l'ansia dell'ignoto: dopo il Passo 10, lo studente sa esattamente dove concentrare il ripasso nei giorni restanti.

**📅 Quando:** 7-14 giorni prima dell'esame.

**Principi attivati:** Active Recall (§2), Desirable Difficulties (§5), Spatial Cognition (§22), Metacognition (T1), tutti i precedenti cristallizzati

---

### 10.1 — Attivazione della Fog of War

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-01 | La Fog of War si attiva su **invocazione esplicita** dello studente: bottone "Modalità Esame" o gesto dedicato | Autonomy T2 | Mai automatica. Mai suggerita proattivamente ("L'esame è tra 10 giorni, vuoi provare?") |
| P10-02 | Lo studente seleziona la **zona** da coprire con la nebbia (un argomento, una materia intera, o tutto il canvas) | Autonomy T2 | Selezione area: come nel Passo 2 (gesto di area). Opzione "tutta la zona" con un toggle |
| P10-03 | Lo studente sceglie la **densità della nebbia** tra 3 livelli | Desirable Difficulties §5, ZPD §19 | 3 opzioni chiare al momento dell'attivazione |

#### I 3 Livelli di Nebbia

| Livello | Nome | Cosa vede lo studente | Difficoltà | Quando usarla |
|---------|------|----------------------|------------|---------------|
| **1 — Nebbia Leggera** | "Posso orientarmi" | Struttura spaziale visibile: posizioni dei nodi come sagome sfuocate, connessioni come linee grigie. 0 contenuto testuale | Media | Prima simulazione. Lo studente usa la memoria spaziale come aiuto |
| **2 — Nebbia Media** | "So solo dove sono" | Solo la posizione corrente dello studente nel canvas. I nodi sono completamente invisibili finché non vengono toccati | Alta | Simulazione avanzata. Lo studente deve ricordare sia posizione che contenuto |
| **3 — Nebbia Totale** | "Buio completo" | Canvas completamente nero/vuoto. Lo studente non vede nulla — deve navigare dalla memoria pura, ricordando dove si trovano i nodi | Massima | Simulazione finale. Solo la memoria spaziale pura guida la navigazione |

---

### 10.2 — Comportamento Durante la Fog of War

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-04 | Lo studente **naviga** nel canvas coperto dalla nebbia usando pan e zoom | Spatial Cognition §22 | La navigazione funziona normalmente. Solo il contenuto è nascosto |
| P10-05 | In **Nebbia Leggera**, le sagome dei nodi sono vagamente visibili — lo studente vede dove sono ma non cosa contengono | Spatial Cognition §22, Desirable Difficulties §5 | Sagome: opacità 15%, colori desaturati, 0 testo |
| P10-06 | In **Nebbia Media**, i nodi appaiono solo quando lo studente si avvicina (zoom-in) a una distanza predefinita — un "raggio di visibilità" centrato sulla posizione corrente | Desirable Difficulties §5 | Raggio: 300px dal centro del viewport. I nodi fuori dal raggio sono completamente invisibili |
| P10-07 | In **Nebbia Totale**, il canvas è nero. I nodi appaiono **solo** quando lo studente tocca esattamente la posizione dove erano | Active Recall §2 | Tolleranza tocco: 50px dalla posizione reale del nodo. Se tocca e non c'è nulla: nessun feedback |
| P10-08 | Ad ogni nodo toccato/raggiunto, si attiva la **sequenza di recall** (come nel Passo 6): lo studente tenta di ricordare → tocca → reveal → auto-valutazione ✅/❌ | Active Recall §2 | Stessa sequenza del Passo 6. Le regole P6-07 → P6-14 si applicano integralmente |
| P10-09 | I nodi già rivelati restano **visibili** anche dopo il reveal — la nebbia si alza progressivamente mentre lo studente avanza | Metacognition T1 | Il "svelamento" è permanente per la sessione. Lo studente vede il terreno conquistato |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P10-10 | Mostrare un **timer** o conto alla rovescia ("Hai 30 minuti") | Flow §24, Autonomy T2 | La simulazione non ha un tempo limite. La pressione temporale produce ansia, non apprendimento |
| P10-11 | Mostrare un **contatore** dei nodi rimanenti ("12 nodi su 30 visitati") | Active Recall §2 | Lo studente non deve sapere quanti nodi ci sono — la consapevolezza della quantità è parte del test |
| P10-12 | Dare feedback **durante** l'esplorazione su quanto sta andando bene/male | Active Recall §2, Productive Failure T4 | Il feedback arriva ALLA FINE, non durante. La Fog of War è un'esperienza senza rete |

---

### 10.3 — L'IA come Esaminatore (Opzionale)

Lo studente può scegliere di attivare l'IA come **esaminatore aggiuntivo** durante la Fog of War, per simulare un esame orale o scritto.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-13 | L'IA esaminatrice è **opzionale** — lo studente la attiva con un toggle prima di iniziare | Autonomy T2 | Default: OFF. Lo studente sceglie se vuole solo il recall spaziale o anche le domande IA |
| P10-14 | Se attivata, l'IA genera domande **di tipo diverso** dai Passi 3: domande **applicative** ("Risolvi questo problema usando il concetto X"), **scenari ipotetici** ("Cosa succederebbe se Y cambiasse?"), **connettive** ("Come si collega X a Y?") | Desirable Difficulties §5, Transfer T3 | Le domande del Passo 10 sono più difficili e più "da esame" rispetto al Passo 3 (che era socratico/esplorativo) |
| P10-15 | Le domande IA appaiono come bolle **nella nebbia** — ancorate alla posizione del nodo rilevante ma senza rivelare il contenuto del nodo | Active Recall §2, Spatial Cognition §22 | Bolla: sfondo nero 80%, bordo ambra, testo bianco. Ancorata alla posizione ma il nodo sottostante resta nella nebbia |
| P10-16 | Lo studente risponde **scrivendo a mano** sul canvas (come nel Passo 3). Le regole P3-17→P3-23 (confidenza→risposta→rivelazione) si applicano | Generation §3, Embodied §23 | Stessa meccanica del Passo 3 ma in contesto d'esame |
| P10-17 | L'IA NON dà la risposta dopo un errore — rimanda al nodo corrispondente una volta che la nebbia si alzerà | Socratic §20, Generation §3 | 0 risposte nel Passo 10. Lo studente scoprirà la risposta quando il nodo sarà rivelato |

---

### 10.4 — La Mappa di Padronanza (Il Reveal Finale)

Quando lo studente decide di terminare la Fog of War, la nebbia si alza e rivela la **mappa di padronanza** — il momento di verità.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-18 | Al termine, la nebbia si alza con un'**animazione cinematografica** (dissolve graduale, 2-3 secondi) — il momento deve essere emotivamente significativo | Embodied §23, Metacognition T1 | Animazione: nebbia dissolve dal centro verso i bordi, ease-out, 2-3s |
| P10-19 | L'overlay **heatmap** colora ogni nodo in base al risultato: 🟢 verde = ricordato correttamente, 🔴 rosso = dimenticato, ⬜ grigio = non visitato (punti ciechi) | Metacognition T1, Ipercorrezione §4 | 3 colori distinti. Opacità overlay: 30%. Sotto, il canvas originale resta visibile |
| P10-20 | I **punti ciechi** (nodi non visitati, grigi) sono altrettanto importanti dei nodi rossi — rappresentano concetti che lo studente non sa nemmeno di non sapere | Metacognition T1 | I nodi grigi hanno un bordo punteggiato + icona "👁‍🗨". Il sistema li segnala: "Questi nodi non li hai cercati" |
| P10-21 | La mappa di padronanza è **navigabile**: lo studente può toccare i nodi rossi e grigi per rivelare il contenuto e scoprire cosa aveva dimenticato | Active Recall §2 | Tocco su nodo rosso → rivela contenuto + pulse rosso. Tocco su nodo grigio → rivela contenuto + messaggio "Non sapevi che c'era" |
| P10-22 | Mostrare un **sommario positivo ma onesto**: "Hai ricostruito 18 nodi su 30. 4 dimenticati. 8 non visitati. Le zone rossa e grigia sono il tuo piano di studio." | Growth Mindset §12, Metacognition T1 | Testo neutro e costruttivo. La formulazione è "piano di studio", non "fallimenti" |

---

### 10.5 — Il Piano di Studio Chirurgico

Il risultato del Passo 10 non è solo una mappa visiva — è un **piano d'azione**.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-23 | I nodi rossi e grigi vengono automaticamente **promossi a priorità massima** nella coda SRS | Spacing §1 | Gli intervalli SRS dei nodi rossi/grigi vengono resettati a 1 giorno — devono essere ripassati domani |
| P10-24 | Il sistema genera un **percorso di ripasso mirato** che copre solo i nodi rossi e grigi — non spreca tempo su quelli verdi | Spacing §1, Metacognition T1 | Percorso: sentiero luminoso che collega solo i nodi critici. Simile al Passo 6 ma ristretto |
| P10-25 | Lo studente può **ripetere** la Fog of War più volte nei giorni successivi — ogni volta la mappa di padronanza mostrerà il progresso | Growth Mindset §12 | Cronologia: "Fog of War 1: 18/30 · Fog of War 2: 24/30 · Fog of War 3: 28/30" |
| P10-26 | I nodi verdi (ricordati) **non vengono ripassati** nel piano mirato — il tempo prima dell'esame è limitato, va investito sulle lacune | Spacing §1 | I nodi verdi mantengono il loro intervallo SRS normale. 0 "ripasso di tutto" obbligatorio |

---

### 10.6 — Fog of War Ripetuta: Evoluzione tra Sessioni

| Sessione | Cosa cambia |
|----------|------------|
| **Fog of War 1** | Mappa iniziale. Identifica le lacune. Lo studente scopre la verità |
| **Fog of War 2** (1-3 giorni dopo) | I nodi rossi della sessione 1 sono stati ripassati (Passi 6/8). Ora si testano di nuovo. I grigi sono stati esplorati. La mappa dovrebbe mostrare più verde |
| **Fog of War 3** (2-3 giorni prima dell'esame) | Test finale. La densità della nebbia può essere aumentata (da Leggera a Media, o da Media a Totale). Se la mappa è prevalentemente verde → lo studente è pronto |

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P10-27 | Ad ogni Fog of War ripetuta, mostrare la **delta rispetto alla sessione precedente**: "+6 nodi ricordati, -2 punti ciechi" | Growth Mindset §12, Metacognition T1 | Delta evidenziato in verde (miglioramenti) e discreto per peggioramenti |
| P10-28 | Suggerire di **aumentare la densità** della nebbia se la sessione precedente ha dato >80% verde | Desirable Difficulties §5 | Suggerimento gentile: "La volta scorsa hai ricordato quasi tutto. Vuoi provare con nebbia più densa?" |
| P10-29 | Se 3 Fog of War consecutive mostrano >90% verde, comunicare: **"Sei pronto per l'esame. Il tuo Palazzo della Memoria è solido."** | Growth Mindset §12, Self-Determination T2 | Il messaggio è celebrativo e fiducioso. Il canvas ha fatto il suo lavoro |

---

### 10.7 — Stato dell'IA durante il Passo 10

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: ⚔️ ESAMINATORE (opzionale)        │
│                                                  │
│  • Modulo IA: ATTIVO (se toggle ON)              │
│  • Genera domande applicative: SÌ                │
│  • Genera scenari ipotetici: SÌ                  │
│  • Dà risposte: MAI                             │
│  • Feedback durante l'esplorazione: MAI          │
│  • Calcola mappa padronanza: SÌ (locale)         │
│  • Modifica canvas: MAI                          │
│                                                  │
│  L'IA è un SIMULATORE D'ESAME.                   │
│  Testa. Registra. Rivela alla fine.              │
│  Non aiuta. Non consola. Non giudica.            │
│                                                  │
└──────────────────────────────────────────────────┘
```

> [!CAUTION]
> ### La Fog of War NON è un Esame
> La Fog of War è uno strumento **diagnostico**, non valutativo. Non c'è un voto. Non c'è un "superato/non superato". C'è una mappa che mostra verde, rosso e grigio — e un piano d'azione per trasformare il rosso e il grigio in verde nei giorni restanti. Lo studente che esce dalla Fog of War sa ESATTAMENTE cosa studiare. L'ansia dell'ignoto ("Non so cosa non so") è eliminata.

---

### 10.8 — Dati Generati dal Passo 10

```json
{
  "sessionId": "uuid",
  "timestamp": "ISO-8601",
  "fogLevel": "light|medium|total",
  "zone": "canvas_zone_id",
  "aiExaminer": true,
  "totalNodes": 30,
  "results": {
    "recalled": 18,
    "forgotten": 4,
    "blind_spots": 8
  },
  "nodeResults": [
    {
      "nodeId": "node_123",
      "status": "recalled|forgotten|blind_spot",
      "responseTime_ms": 5000,
      "confidence": 4,
      "aiQuestionAsked": true,
      "aiQuestionCorrect": false
    }
  ],
  "comparedToPrevious": {
    "previousRecalled": 14,
    "delta": "+4"
  },
  "surgicalPlan": {
    "nodesForImmedateReview": ["node_456", "node_789"],
    "blindSpotNodes": ["node_111", "node_222"]
  }
}
```

---

### 10.9 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-155:** Attivazione Fog of War: solo su invocazione esplicita, 0 suggerimenti proattivi
- [ ] **CA-156:** 3 livelli di nebbia: leggera (sagome), media (raggio visibilità), totale (buio)
- [ ] **CA-157:** Nebbia Leggera: sagome visibili opacità 15%, 0 testo
- [ ] **CA-158:** Nebbia Media: raggio visibilità 300px, nodi fuori raggio invisibili
- [ ] **CA-159:** Nebbia Totale: canvas nero, nodi appaiono solo su tocco (tolleranza 50px)
- [ ] **CA-160:** Nodi rivelati: restano visibili per il resto della sessione
- [ ] **CA-161:** 0 timer, 0 contatori nodi rimanenti, 0 feedback durante l'esplorazione
- [ ] **CA-162:** IA esaminatrice: opzionale (default OFF), domande applicative/scenari
- [ ] **CA-163:** IA esaminatrice: 0 risposte fornite, rimanda al nodo per la scoperta
- [ ] **CA-164:** Reveal finale: animazione cinematografica 2-3s, nebbia dissolve dal centro
- [ ] **CA-165:** Heatmap: 3 colori (verde/rosso/grigio), opacità 30%
- [ ] **CA-166:** Punti ciechi (grigi): icona "👁‍🗨" + "Non sapevi che c'era"
- [ ] **CA-167:** Sommario: "X su Y ricostruiti. Z non visitati." Tono costruttivo
- [ ] **CA-168:** Nodi rossi/grigi: SRS reset a 1 giorno
- [ ] **CA-169:** Percorso chirurgico: sentiero che copre solo nodi rossi e grigi
- [ ] **CA-170:** Fog of War ripetuta: delta rispetto a sessione precedente mostrato
- [ ] **CA-171:** Suggerimento aumento densità se >80% verde nella sessione precedente
- [ ] **CA-172:** Messaggio "Sei pronto" dopo 3 sessioni consecutive >90% verde

---
---

## PASSO 11 — L'Esame: Il Canvas nella Testa

### Contesto

Il Passo 11 è il momento della verità — e il momento in cui il software **non serve più**. Lo studente chiude Fluera, posa il tablet, entra nell'aula d'esame. Il canvas non è più sullo schermo — è **nella testa**.

Se i Passi 1-10 hanno funzionato, lo studente può chiudere gli occhi e navigare mentalmente il proprio Palazzo della Memoria: "In alto a sinistra c'era la termodinamica. La freccia scendeva verso la cinetica. A destra c'erano gli esempi..." Le Place Cells, i gesti motori, i colori, gli shock delle ipercorrezioni — tutto è codificato nella memoria a lungo termine.

**📅 Quando:** il giorno dell'esame.

**Principi attivati:** Tutti i precedenti, cristallizzati nella memoria a lungo termine.

---

### 11.1 — Cosa il Software NON Fa il Giorno dell'Esame

Il software non ha quasi nessun ruolo il giorno dell'esame. Ma ci sono importanti regole su ciò che NON deve fare:

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| P11-01 | Mandare **notifiche** il giorno dell'esame ("In bocca al lupo!", "Ripassa queste ultime cose!") | Autonomy T2 | Lo studente non ha bisogno di promemoria. L'ansia pre-esame non va alimentata |
| P11-02 | Suggerire un **"ultimo ripasso"** la mattina dell'esame | Spacing §1, Cognitive Overload §9 | L'ultimo ripasso dell'ultimo minuto è cramming — l'opposto di tutto il framework |
| P11-03 | Mostrare statistiche sulla **preparazione** ("Sei pronto al 87%") il giorno dell'esame | Growth Mindset §12 | I numeri creano ansia. Lo studente sa già dove sta — l'ha visto nella Fog of War |
| P11-04 | Richiedere login, sync, o qualsiasi **interazione** il giorno dell'esame | Autonomy T2 | L'app deve essere silenziosa. Lo studente non ha bisogno che l'app gli parli |

---

### 11.2 — La Visualizzazione di Navigazione Mentale (Opzionale)

Se lo studente vuole, il giorno prima dell'esame o la mattina stessa, può fare un **ultimo esercizio di navigazione mentale** — senza recall, senza test, solo navigazione.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P11-05 | Offrire una modalità **"Passeggiata nel Palazzo"**: il canvas si apre senza blur, senza nebbia, senza test. Lo studente naviga liberamente per rinfrescare la mappa spaziale | Spatial Cognition §22, Embodied §23 | Modalità attivabile con un bottone "Passeggiata". Canvas completamente visibile, 0 meccaniche di test |
| P11-06 | Durante la Passeggiata, l'IA è **completamente dormiente** — 0 domande, 0 suggerimenti, 0 analisi | Autonomy T2 | L'IA è nello stesso stato del Passo 1: dormiente al 100% |
| P11-07 | La Passeggiata non genera **nessun dato** — non aggiorna l'SRS, non registra performance, non modifica metadati | Flow §24 | È un momento di contemplazione, non di misurazione. 0 tracking |

---

### 11.3 — Il Ritorno Post-Esame (Retrospettiva)

Dopo l'esame, lo studente può tornare al canvas per una **retrospettiva** — un momento di riflessione.

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P11-08 | Dopo l'esame, lo studente può annotare sul canvas le **domande dell'esame** e le proprie risposte — aggiungendo nodi "domanda d'esame" nella zona corrispondente | Metacognition T1, Extended Mind §29 | Nodo speciale: bordo dorato, icona 📝, posizionato accanto ai nodi rilevanti |
| P11-09 | Lo studente può segnare i nodi che gli hanno **salvato l'esame** (ricordo cruciale) con un'icona speciale (🏆) | Growth Mindset §12 | Tag "salvavita": icona 🏆 apposta manualmente dallo studente |
| P11-10 | Lo studente può segnare i nodi che **non ricordava** durante l'esame — alimentando un futuro ciclo (se c'è un esame successivo) | Metacognition T1, Spacing §1 | Tag "mancato all'esame": icona ❌ rossa. Il nodo entra nella coda SRS con priorità massima se c'è un esame futuro |

> [!IMPORTANT]
> ### Il Test del Passo 11
> Se lo studente ha bisogno del canvas per rispondere all'esame, **la fase di codifica non è completa** — deve tornare ai Passi 8-10. Il canvas è un mezzo di codifica, non un fine. Il successo del Passo 11 è quando lo studente risponde all'esame ricostruendo il Palazzo della Memoria nella propria testa — senza schermo, senza penna, senza app.

---

### 11.4 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-173:** 0 notifiche il giorno dell'esame
- [ ] **CA-174:** 0 suggerimenti "ultimo ripasso"
- [ ] **CA-175:** 0 statistiche di preparazione mostrate il giorno dell'esame
- [ ] **CA-176:** Modalità "Passeggiata nel Palazzo": canvas visibile, 0 test, 0 blur, 0 nebbia
- [ ] **CA-177:** Passeggiata: IA dormiente, 0 dati generati, 0 tracking
- [ ] **CA-178:** Post-esame: nodi "domanda d'esame" (📝) creabili e posizionabili
- [ ] **CA-179:** Post-esame: tag 🏆 (salvavita) e ❌ (mancato) applicabili manualmente

---
---

## PASSO 12 — Il Canvas Resta e Cresce: L'Infrastruttura Permanente

### Contesto

Il Passo 12 non è un passo da implementare in senso stretto — è una **filosofia** che guida l'architettura del software. Il canvas di una materia non si cancella dopo l'esame. Resta per sempre, accanto alle altre materie, e diventa parte di un "continente della conoscenza" che cresce anno dopo anno.

Il Passo 12 è la promessa che Fluera non è un'app per passare esami — è un'app per costruire il **patrimonio intellettuale** di una vita.

**📅 Quando:** Dopo l'esame, per sempre.

**Principi attivati:** Growth Mindset (§12), Spacing (§1), Spatial Cognition (§22), il canvas come autoritratto cognitivo

---

### 12.1 — Il Canvas come Patrimonio Permanente

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P12-01 | I canvas **non vengono mai cancellati automaticamente** — nessun "archivia dopo l'esame", nessun "vuoi eliminare questa materia?" | Extended Mind §29 | 0 prompt di cancellazione automatici. L'eliminazione è possibile solo su azione esplicita dell'utente, con doppia conferma |
| P12-02 | Le zone di materie diverse **coesistono** nel canvas infinito — lo studente può navigare dalla Matematica del primo anno alla Fisica del terzo anno in un unico spazio | Spatial Cognition §22, Interleaving §10 | Il canvas infinito supporta zone illimitate. La performance non degrada sotto le 1000 zone |
| P12-03 | I nodi del primo anno e i nodi dell'ultimo anno sono **visivamente diversi** — il tratto è diverso, lo stile è diverso, la densità è diversa. Questa differenza è la prova tangibile della crescita | Growth Mindset §12, Metacognition T1 | Il sistema non altera i tratti originali. La differenza emerge naturalmente dall'evoluzione dello studente |
| P12-04 | L'SRS a lungo termine mantiene le zone **vive**: anche dopo l'esame, i nodi più importanti vengono periodicamente suggeriti per un ripasso light | Spacing §1 | Intervalli post-esame: 6 mesi, 1 anno, 2 anni. Solo i nodi allo Stadio 4-5 (Padroneggiato/Integrato). Completamente opzionale |

---

### 12.2 — La Cronologia della Crescita

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P12-05 | Lo studente può accedere a una **timeline visiva** del proprio canvas: "Ottobre 2025 → il primo nodo. Giugno 2026 → 500 nodi, 12 zone, 8 ponti cross-dominio" | Growth Mindset §12 | Timeline: linea orizzontale con milestone. Navigabile con swipe. Ogni milestone porta alla versione del canvas di quel momento |
| P12-06 | La timeline mostra **metriche di crescita** nel tempo: numero di nodi, zone, ponti, richiami riusciti — mai confrontati con altri studenti | Metacognition T1 | Metriche solo proprie. 0 classifiche. 0 "media degli studenti". 0 confronti |
| P12-07 | Lo studente può **navigare** le versioni precedenti del canvas in modalità "time travel" — vedendo come le zone sono cresciute nel tempo | Spatial Cognition §22, Growth Mindset §12 | Slider temporale: trascina a sinistra per tornare indietro. Il canvas mostra i nodi come erano a quella data |
| P12-08 | L'IA può generare un **sommario annuale** su richiesta: "Quest'anno hai studiato 5 materie, costruito 230 nodi, scoperto 15 ponti cross-dominio, e padroneggiato il 78% dei concetti." | Metacognition T1, Growth Mindset §12 | Sommario: testo + infografica visiva. Solo su richiesta, mai automatico |

---

### 12.3 — L'Identità Cognitiva dello Studente

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| P12-09 | Il canvas è il **"ritratto cognitivo"** dello studente — l'app deve trattarlo come tale: con rispetto, con cura, con permanenza | Extended Mind §29, Identity | Il canvas non è un documento — è un luogo. Il linguaggio dell'UI lo riflette: "Il tuo Palazzo", "Le tue zone", "I tuoi ponti" |
| P12-10 | Il sistema deve supportare l'**esportazione** del canvas come immagine ad alta risoluzione che lo studente può condividere o stampare | Extended Mind §29 | Export: PNG/PDF ad alta risoluzione. Lo studente può "appendere al muro" il proprio Palazzo della Memoria |
| P12-11 | Il canvas è il **prodotto del lavoro dello studente**, non dell'IA. I crediti appartengono allo studente. L'IA non ha mai scritto un singolo nodo sul canvas | Generation §3, Extended Mind §29 | L'overlay Ghost Map era un livello separato. I suggerimenti erano punteggiati. Tutto ciò che è solido e permanente nel canvas è stato scritto dalla mano dello studente |

---

### 12.4 — Stato dell'IA durante il Passo 12

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  🤖 STATO IA: 🏛️ CUSTODE DEL PALAZZO            │
│                                                  │
│  • Modulo IA: DORMIENTE (attivo su invocazione)  │
│  • SRS long-term: SÌ (opzionale, a intervalli    │
│    lunghi: 6 mesi, 1 anno)                       │
│  • Sommario annuale: SÌ (su richiesta)           │
│  • Suggerimenti cross-dominio: SÌ (su richiesta) │
│  • Modifica canvas: MAI                          │
│  • Notifiche: MAI                                │
│                                                  │
│  L'IA è il CUSTODE di un palazzo che lo           │
│  studente ha costruito con le proprie mani.       │
│  Lo mantiene. Non lo modifica. Mai.              │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

### 12.5 — Criteri di Accettazione (QA Checklist)

- [ ] **CA-180:** Canvas permanenti: 0 prompt di cancellazione automatici, doppia conferma per eliminazione manuale
- [ ] **CA-181:** Zone illimitate nel canvas infinito: performance stabile sotto 1000 zone
- [ ] **CA-182:** SRS post-esame: intervalli 6m/1a/2a, completamente opzionale
- [ ] **CA-183:** Timeline visiva: milestone navigabili, swipe, metriche solo proprie
- [ ] **CA-184:** Time travel: slider temporale che mostra il canvas a date precedenti
- [ ] **CA-185:** Sommario annuale: solo su richiesta, mai automatico
- [ ] **CA-186:** Export: PNG/PDF ad alta risoluzione del canvas completo

---
---

## Riepilogo Completo: I 12 Passi — Regole e Criteri

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   📖 SPECIFICA IMPLEMENTATIVA COMPLETA — FLUERA COGNITIVE ENGINE            │
│                                                                             │
│   12 Passi · dall'Ignoranza alla Padronanza                                │
│                                                                             │
│   ┌────────┬────────────────────────────────┬────────┬──────┐              │
│   │ Passo  │ Nome                           │ Regole │  QA  │              │
│   ├────────┼────────────────────────────────┼────────┼──────┤              │
│   │   1    │ Appunti a Mano                 │   48   │  15  │              │
│   │   2    │ Elaborazione Solitaria         │   70   │  28  │              │
│   │   3    │ Interrogazione Socratica       │   50   │  22  │              │
│   │   4    │ Confronto Centauro             │   39   │  18  │              │
│   │   5    │ Consolidamento Notturno        │    8   │   5  │              │
│   │   6    │ Primo Ritorno (Blur + Recall)  │   21   │  17  │              │
│   │   7    │ Apprendimento Solidale         │   34   │  19  │              │
│   │   8    │ Ritorni SRS                    │   26   │  17  │              │
│   │   9    │ Ponti Cross-Dominio            │   18   │  13  │              │
│   │  10    │ Fog of War                     │   29   │  18  │              │
│   │  11    │ L'Esame                        │   10   │   7  │              │
│   │  12    │ Infrastruttura Permanente      │   11   │   7  │              │
│   ├────────┼────────────────────────────────┼────────┼──────┤              │
│   │ TOTALE │                                │  364   │ 186  │              │
│   └────────┴────────────────────────────────┴────────┴──────┘              │
│                                                                             │
│   🔑 L'Unica Regola che Governa Tutti i 12 Passi:                          │
│                                                                             │
│   Lo studente deve SEMPRE generare prima di ricevere.                      │
│   In ogni passo — dalla prima riga di appunti all'ultimo                   │
│   ripasso prima dell'esame — lo sforzo cognitivo viene                     │
│   PRIMA, e il feedback viene DOPO.                                         │
│   Invertire quest'ordine annulla il valore di tutto                        │
│   il percorso.                                                             │
│                                                                             │
│   La fatica è il prezzo. La memoria è il premio.                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---
---

# APPENDICI TRASVERSALI — Specifiche Infrastrutturali

> Queste appendici specificano i sistemi trasversali che servono a più Passi contemporaneamente e che nella specifica principale erano referenziati ma non dettagliati.

---

## APPENDICE A1 — Il Motore HTR (Handwriting Recognition Pipeline)

### Contesto

Ogni interazione IA nei Passi 3, 4, 6, 9 e 10 dipende dalla capacità del sistema di **leggere il contenuto scritto a mano** dallo studente. Senza un motore HTR robusto, l'IA è cieca. Questa appendice specifica l'intera pipeline dal tratto alla semantica.

**Passi che dipendono dall'HTR:** Passo 3 (P3-02), Passo 4 (P4-02), Passo 6 (P6-08 valutazione tentativo), Passo 9 (P9-08 analisi cross-zona), Passo 10 (P10-14 valutazione risposte).

---

### A1.1 — Architettura a 3 Livelli

La pipeline HTR opera su **3 livelli** distinti, ciascuno con un modello diverso:

| Livello | Nome | Input | Output | Modello | Dove Gira |
|---------|------|-------|--------|---------|-----------|
| **L1 — Classificazione Tratto** | Stroke Classifier | Tratti raw (punti touch) | Tipo: `text` · `drawing` · `arrow` · `formula` · `symbol` | CNN leggera (MobileNet-based) | On-device (Core ML / TFLite) |
| **L2 — Riconoscimento Testuale** | Text Recognizer | Tratti classificati come `text` | Testo UTF-8 con confidenza per carattere | Transformer encoder-decoder (TrOCR-small o custom ONNX) | On-device (ONNX Runtime) |
| **L3 — Riconoscimento Formule** | Formula Recognizer | Tratti classificati come `formula` | LaTeX string | Modello HME-ATT (già presente nel progetto: `hme_attn_onnx/`) | On-device (ONNX Runtime) |

> [!IMPORTANT]
> **Tutto gira on-device.** Nessun tratto dello studente viene mai inviato a server esterni per il riconoscimento. Il canvas è sacro (Parte VI della teoria) — questo include la privacy dei contenuti scritti.

---

### A1.2 — Livello 1: Classificazione del Tratto

#### Scopo
Distinguere automaticamente i 5 tipi di contenuto sul canvas prima di invocare il riconoscitore appropriato.

#### Tipi di Contenuto

| Tipo | Caratteristiche del Tratto | Azione Successiva |
|------|---------------------------|-------------------|
| **`text`** | Tratti corti, raggruppati orizzontalmente, con curvature tipiche della calligrafia | → Livello 2 (Text Recognizer) |
| **`drawing`** | Tratti lunghi e irregolari, non lineari, senza pattern calligrafici | → Nessun riconoscimento testuale. Salvato come `drawing_node` nel grafo semantico |
| **`arrow`** | Tratto lungo con direzione dominante e terminazione a punta | → Estratta come connessione: `{from: nodeA, to: nodeB, direction}` |
| **`formula`** | Tratti con pattern matematici: frazioni (linea orizzontale con testo sopra/sotto), esponenti (tratti piccoli in alto a destra), simboli (∫, Σ, √) | → Livello 3 (Formula Recognizer) |
| **`symbol`** | Tratto singolo che corrisponde a un simbolo comune: ?, !, ✓, ✗, ★ | → Mappato a tag semantico (es. `?` → `incomplete_node`, `✓` → `verified`) |

#### Specifiche Tecniche

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A1-01 | La classificazione avviene **offline** (non durante la scrittura) — alla fine del Passo 1 o su invocazione IA | Trigger: Passo 3 invocato, o pausa >30s. Mai durante il Flow |
| A1-02 | Accuratezza di classificazione: **≥90%** su dataset misto (calligrafia + disegni + formule) | Validato su corpus interno di 500+ campioni multi-studente |
| A1-03 | Il risultato della classificazione è **correggibile** dallo studente: se il sistema classifica un disegno come testo, lo studente può correggerlo | UI: long-press su nodo → "Questo è un disegno / testo / formula" |
| A1-04 | Tempo di classificazione: **≤100ms per nodo** | Batch processing: tutti i nodi di una zona classificati in ≤2s |
| A1-05 | La classificazione è **salvata come metadato** del nodo: `{nodeId, contentType: text|drawing|arrow|formula|symbol, confidence}` | Persistito nel database locale |

---

### A1.3 — Livello 2: Riconoscimento Testuale

#### Specifiche Tecniche

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A1-06 | Modello: **TrOCR-small** (ONNX) o modello custom fine-tunato su calligrafia scolastica | Dimensione modello: ≤50MB. Caricamento: ≤1s |
| A1-07 | Accuratezza: **≥85% CER** (Character Error Rate) su calligrafia "media" di studente universitario | Testato su corpus multilingue (IT, EN, DE, FR, ES) |
| A1-08 | Lingue supportate al lancio: **Italiano, Inglese** — con architettura estendibile per altre lingue | Il modello è multi-script (latino). L'aggiunta di lingue non-latine (cinese, arabo, giapponese) richiede modelli separati |
| A1-09 | L'output è **testo UTF-8 con confidenza per parola**: `[{word: "entropia", confidence: 0.92}, ...]` | Le parole con confidenza <0.5 sono marcate come `uncertain` |
| A1-10 | Il testo riconosciuto è **invisibile all'utente** — non viene mai mostrato sullo schermo come sostituto del tratto | Il tratto originale resta sacro. Il testo HTR è metadato interno, usato solo dall'IA |
| A1-11 | Il riconoscimento è **incrementale**: se lo studente aggiunge tratti a un nodo esistente, solo i nuovi tratti vengono riprocessati | Cache: il risultato HTR per ogni nodo è salvato. Rielaborazione solo su modifica |
| A1-12 | **Fallback**: se il CER medio di un nodo è <50% (calligrafia illeggibile), il nodo viene marcato come `unreadable` e l'IA lo tratta come `drawing` (nessuna interpretazione testuale) | L'IA non genera domande su nodi `unreadable` — li segnala come "Non riesco a leggere questo nodo. Vuoi riscriverlo più chiaramente?" |

---

### A1.4 — Livello 3: Riconoscimento Formule

#### Specifiche Tecniche

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A1-13 | Modello: **HME-ATT** (già presente nel progetto: `hme_attn_onnx/`, vocabolario: `hme_attn_vocab.json`) | Il modello è già integrato nel progetto Fluera — riutilizzare l'infrastruttura esistente |
| A1-14 | Output: **LaTeX string** (es. `\frac{\partial^2 u}{\partial t^2} = c^2 \nabla^2 u`) | L'output LaTeX è usato dall'IA per la comprensione semantica delle formule |
| A1-15 | Accuratezza: **≥80% ExpRate** (Expression Recognition Rate) su formule universitarie standard | Testato su dataset CROHME + corpus interno |
| A1-16 | Supporto per formule **multi-linea** (sistemi di equazioni, matrici) | Il sistema raggruppa tratti verticalmente allineati come formula multi-linea |
| A1-17 | **Fallback**: se la formula non viene riconosciuta, viene trattata come testo generico e l'IA la ignora semanticamente | Nodo marcato come `formula_unrecognized`. L'IA non fa domande sulla formula specifica |

---

### A1.5 — Integrazione con il Grafo Semantico

L'output della pipeline HTR alimenta un **Grafo Semantico Interno** che l'IA usa per generare domande e confronti:

```json
{
  "nodes": [
    {
      "nodeId": "node_001",
      "contentType": "text",
      "htrText": "Il secondo principio della termodinamica afferma che l'entropia di un sistema isolato non può diminuire",
      "htrConfidence": 0.88,
      "spatialPosition": {"x": 1200, "y": -400, "zoom": 1.0},
      "cluster": "termodinamica",
      "connections": ["node_002", "node_005"],
      "recallHistory": {...}
    },
    {
      "nodeId": "node_002",
      "contentType": "formula",
      "htrLatex": "\\Delta S \\geq 0",
      "htrConfidence": 0.91,
      "spatialPosition": {"x": 1350, "y": -380, "zoom": 1.0},
      "cluster": "termodinamica",
      "connections": ["node_001"]
    }
  ]
}
```

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A1-18 | Il Grafo Semantico è costruito **automaticamente** dalla pipeline HTR + segmentazione nodi (Appendice A6) | Costruzione: ≤5s per canvas con ≤50 nodi |
| A1-19 | Il Grafo Semantico è il **payload** che viene passato al LLM nei Passi 3, 4, 9 | Il LLM non vede mai i tratti raw — vede solo il grafo semantico |
| A1-20 | Il Grafo è **aggiornato incrementalmente** ad ogni invocazione IA — non ricostruito da zero | Solo i nodi modificati dall'ultima invocazione vengono rielaborati |

---

### A1.6 — Criteri di Accettazione HTR

- [ ] **CA-A1-01:** Classificazione tratti: ≥90% accuratezza su dataset misto (500+ campioni)
- [ ] **CA-A1-02:** HTR testuale: ≥85% CER su calligrafia media, lingue IT+EN
- [ ] **CA-A1-03:** HTR formule: ≥80% ExpRate su formule universitarie standard
- [ ] **CA-A1-04:** Tutto on-device: 0 richieste di rete per HTR
- [ ] **CA-A1-05:** Testo HTR invisibile all'utente: 0 rendering del testo riconosciuto
- [ ] **CA-A1-06:** Classificazione ≤100ms per nodo, riconoscimento ≤2s per zona (≤50 nodi)
- [ ] **CA-A1-07:** Fallback calligrafia illeggibile: messaggio "non riesco a leggere" gentile
- [ ] **CA-A1-08:** Grafo Semantico: costruzione ≤5s, aggiornamento incrementale
- [ ] **CA-A1-09:** Correzione manuale della classificazione: funzionante con ≤2 gesti

---
---

## APPENDICE A2 — Prompt Engineering del Tutor Socratico

### Contesto

Il Tutor Socratico è il cuore dell'IA di Fluera. Il suo compito è **generare domande, mai risposte** — e resistere alla naturale tendenza dei LLM a "spiegare tutto". Questa appendice specifica l'architettura di prompting, i guardrail, e la pipeline di valutazione delle risposte dello studente.

**Passi che dipendono da questo sistema:** Passo 3 (interrogazione), Passo 4 (Ghost Map — parzialmente), Passo 7 (arbitro), Passo 8 (Deep Review), Passo 9 (ponti), Passo 10 (esaminatore).

---

### A2.1 — Selezione del Modello LLM

| Scenario | Modello | Dove Gira | Latenza Target | Razionale |
|----------|---------|-----------|----------------|-----------|
| **Interrogazione Socratica (Passo 3)** | Modello locale small (~3B-7B parametri) | On-device (Core ML / llama.cpp) | ≤3s per domanda | L'interrogazione deve funzionare offline. Le domande socratiche non richiedono conoscenza enciclopedica — richiedono struttura logica |
| **Ghost Map (Passo 4)** | Modello cloud large (GPT-4o / Claude) | Cloud (API) | ≤8s per mappa | La generazione della concept map richiede conoscenza disciplinare ampia. L'unico step che necessita cloud |
| **Esaminatore (Passo 10)** | Modello locale medium (~7B-13B) o cloud | On-device preferibilmente | ≤5s per domanda | Le domande applicative richiedono più sofisticazione delle domande socratiche base |
| **Ponti Cross-Dominio (Passo 9)** | Modello cloud large | Cloud (API) | ≤10s per batch di suggerimenti | L'analisi cross-dominio richiede conoscenza vasta per identificare analogie |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A2-01 | Il sistema deve supportare **almeno** un modello locale (offline) per le funzioni base (Passo 3) | Il Passo 3 deve funzionare senza internet. Il Passo 4 può richiedere internet |
| A2-02 | Il fallback se il cloud non è disponibile per Passo 4: **degradare** a modello locale con messaggio "La verifica sarà più approssimativa offline" | Mai bloccare lo studente. Degradare graziosamente |
| A2-03 | La scelta del modello è **trasparente** allo studente ma configurabile nelle impostazioni: "IA locale (più veloce, offline)" vs "IA cloud (più precisa)" | Default: locale per Passo 3, cloud per Passo 4 |

---

### A2.2 — Il System Prompt Socratico (Passo 3)

```
SYSTEM PROMPT — SOCRATIC TUTOR MODE

You are a Socratic tutor integrated into a handwriting-based learning canvas.

ABSOLUTE RULES (NEVER VIOLATE):
1. You MUST generate ONLY questions. NEVER provide answers, explanations, 
   definitions, or solutions — not even partial ones.
2. If asked "what is X?", respond with "What do YOU think X is?"
3. If the student begs for the answer, respond with a QUESTION that guides 
   them toward discovering it themselves.
4. You NEVER say "The answer is...", "Actually...", "The correct answer...", 
   "Let me explain...", or any variant.
5. Your output is ALWAYS a single question. Maximum 2 sentences.
6. You NEVER use bullet points, lists, or structured explanations.

CONTEXT:
- You are examining a student's handwritten canvas about: {subject}
- The student's knowledge graph (from HTR): {semantic_graph_json}
- The recall gap map from Step 2: {gap_map_json}
- Previous questions and responses in this session: {session_history}

QUESTION TYPES (use the appropriate type based on context):
- Type A (Gap): Ask about concepts that are MISSING from the canvas
- Type B (Challenge): Question a connection or claim that seems wrong
- Type C (Depth): Ask WHY something is true, not just WHAT it is
- Type D (Transfer): Ask if a concept reminds them of something in another domain

ADAPTIVE DIFFICULTY:
- Current difficulty level: {difficulty_level} (1-5)
- If last 3 answers were correct: increase difficulty
- If last 2 answers were wrong: decrease difficulty
- For recall level 1-2 nodes: use Type A/B questions only
- For recall level 4-5 nodes: use Type C/D questions only

TONE: Curious, encouraging, never judgmental. You are a wise friend who 
asks good questions, not a teacher who tests for grades.

OUTPUT FORMAT:
{
  "question": "Your single Socratic question here",
  "type": "A|B|C|D",
  "targetNodeId": "node_xxx",
  "difficultyLevel": 1-5
}
```

---

### A2.3 — Guardrail Anti-Risposta

Il problema più critico: i LLM tendono a rispondere anche quando gli si dice di non farlo. Servono guardrail a 3 livelli:

| Livello | Nome | Meccanismo | Esempio |
|---------|------|------------|---------|
| **G1 — Prompt-Level** | Istruzioni nel system prompt | Le regole ABSOLUTE nel system prompt sopra | "NEVER provide answers" |
| **G2 — Output Filter** | Post-processing regex sull'output del LLM | Scansione dell'output per pattern proibiti **prima** di mostrarlo allo studente | Se l'output contiene "The answer is" o "Perché X è Y" → rigenera |
| **G3 — Structural** | Il formato JSON obbliga un singolo campo "question" | Il LLM non può inserire spiegazioni se l'output è vincolato a un campo "question" | Il parsing JSON rifiuta output non conformi |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A2-04 | **Output Filter (G2)**: ogni output del LLM viene scansionato per **pattern proibiti** prima di essere mostrato | Pattern proibiti: dichiarazioni ("X è Y"), spiegazioni ("perché X succede è che"), definizioni ("X significa"). Regex configurabile |
| A2-05 | Se l'output filter rileva una risposta mascherata, il LLM viene **ri-invocato** con un prompt aggiuntivo: "Riformula come domanda pura. Non dare informazioni." | Max 2 retry. Al 3° fallimento: domanda generica di fallback ("Puoi spiegare questo concetto con le tue parole?") |
| A2-06 | Il campo "question" dell'output JSON viene **validato sintatticamente**: deve terminare con "?" | Se non termina con "?", il sistema aggiunge "?" o rigenera |
| A2-07 | **Log di violazioni**: ogni violazione dei guardrail viene loggata per migliorare il fine-tuning del modello locale | Log: `{timestamp, violation_type, original_output, corrected_output}` |

---

### A2.4 — Il Sistema di Breadcrumb (Prompt per Indizi Graduali)

Quando lo studente chiede un indizio (P3-24), il LLM genera breadcrumb a 3 livelli progressivi usando prompt diversi:

```
BREADCRUMB PROMPT — LEVEL {level}

The student cannot answer the question: "{original_question}"
about node: "{node_content}"

Generate a HINT at level {level}/3:
- Level 1 (Distant Echo): A vague directional hint. Do NOT mention the 
  answer. Just indicate the DOMAIN. Max 10 words.
- Level 2 (Path): A more specific hint that narrows the search space. 
  Mention a RELATED concept but NOT the answer itself. Max 15 words.  
- Level 3 (Threshold): The maximum hint — the answer is one step away. 
  Give the STRUCTURE of the answer without filling it in. Max 20 words.

ABSOLUTE RULE: Even at Level 3, the student must make the final 
cognitive leap themselves. NEVER give the complete answer.

OUTPUT: {"hint": "your hint here", "level": {level}}
```

---

### A2.5 — Valutazione delle Risposte dello Studente

Quando lo studente risponde scrivendo a mano (P3-18), il sistema deve valutare se la risposta è corretta. La pipeline è:

```
Tratti risposta → HTR Pipeline (A1) → Testo risposta
                                           ↓
              Confronto semantico con il contenuto del nodo originale
                                           ↓
                                    Verdetto: correct / incorrect / partial
```

#### Il Prompt di Valutazione

```
EVALUATION PROMPT

You are evaluating a student's handwritten answer to a Socratic question.

Question asked: "{question}"
Expected concept (from reference): "{reference_content}"
Student's answer (from HTR, may contain recognition errors): "{student_answer_htr}"
HTR confidence: {confidence}%

RULES:
1. Be LENIENT with spelling and wording — the HTR may have errors
2. Evaluate SEMANTIC correctness, not lexical match
3. A concept explained in different words but correctly is CORRECT
4. A partially correct answer is PARTIAL (specify what's missing)
5. Account for HTR confidence: if confidence <60%, flag as "low_confidence" 
   and lean toward PARTIAL rather than INCORRECT

OUTPUT:
{
  "verdict": "correct|incorrect|partial",
  "confidence_in_verdict": 0.0-1.0,
  "missing_elements": ["element1", "element2"],
  "htr_quality": "good|acceptable|poor"
}
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A2-08 | La valutazione è **semantica**, non lessicale: "l'entropia cresce" e "il disordine aumenta" sono la stessa risposta | Embedding similarity o LLM-as-judge, non string matching |
| A2-09 | L'HTR confidence influenza la severità: se <60% il verdetto propende per PARTIAL anziché INCORRECT | Soglia configurabile. Il sistema non penalizza lo studente per calligrafia difficile |
| A2-10 | Il verdetto "incorrect" ad alta confidenza dello studente (≥4) triggera l'**Ipercorrezione** (P3-21) | Solo se verdict=incorrect AND student_confidence≥4 → effetto shock |
| A2-11 | Il verdetto "partial" genera un **follow-up** socratico: "Ci sei quasi. Cosa manca?" | Il follow-up è una domanda, non una spiegazione |

---

### A2.6 — Prompt per il Passo 10 (Esaminatore)

Il Passo 10 usa un prompt diverso — più simile a un esaminatore accademico:

```
SYSTEM PROMPT — EXAM MODE

You are simulating an academic examiner. Generate exam-style questions 
that test APPLICATION and TRANSFER, not recall.

Question types for exam mode:
1. APPLICATION: "Given [scenario], use [concept] to solve/predict..."
2. HYPOTHETICAL: "What would happen if [variable] changed?"  
3. CONNECTIVE: "How does [concept A] relate to [concept B]?"
4. CRITICAL: "What are the limitations of [model/theory]?"

NEVER test pure recall ("What is X?") — that's Step 3's job.

The student's knowledge graph: {semantic_graph_json}
Focus on nodes with recall level ≥3 (the student knows these — 
test if they can USE them).

OUTPUT: Same JSON format as Socratic mode.
```

---

### A2.7 — Temperature e Parametri di Generazione

| Parametro | Passo 3 (Socratico) | Passo 4 (Ghost Map) | Passo 10 (Esaminatore) |
|-----------|---------------------|---------------------|------------------------|
| **Temperature** | 0.7 (creativo ma controllato) | 0.3 (preciso e fattuale) | 0.6 (bilanciato) |
| **Top-p** | 0.9 | 0.85 | 0.9 |
| **Max tokens** | 80 (una domanda breve) | 2000 (concept map intera) | 100 (domanda applicativa) |
| **Frequency penalty** | 0.3 (evita domande ripetitive) | 0.0 | 0.4 (alta varietà) |
| **Stop sequences** | `["\n\n", "Answer:", "The answer"]` | `["\n\n\n"]` | `["\n\n", "Answer:"]` |

---

### A2.8 — Criteri di Accettazione Prompt Engineering

- [ ] **CA-A2-01:** Modello locale funzionante offline per Passo 3: domande generate in ≤3s
- [ ] **CA-A2-02:** Guardrail G1+G2+G3: 0 risposte dirette mostrate allo studente su 100 sessioni di test
- [ ] **CA-A2-03:** Output filter: rileva e blocca ≥95% delle risposte mascherate
- [ ] **CA-A2-04:** Breadcrumb a 3 livelli: progressione corretta, livello 3 non rivela la risposta
- [ ] **CA-A2-05:** Valutazione semantica risposte: ≥85% concordanza con giudizio umano
- [ ] **CA-A2-06:** HTR confidence integrata nella valutazione: studente con calligrafia difficile non penalizzato
- [ ] **CA-A2-07:** Domande esaminatore (Passo 10): 0 domande di puro recall, 100% applicative/connettive
- [ ] **CA-A2-08:** Fallback cloud→locale: degradazione graceful con messaggio, mai blocco

---
---

## APPENDICE A3 — Generazione e Allineamento della Ghost Map

### Contesto

La Ghost Map (Passo 4) è il confronto visivo tra il canvas dello studente e una mappa di riferimento generata dall'IA. È la feature più ambiziosa del framework perché richiede: (1) generare una concept map corretta per l'argomento, (2) allinearla spazialmente al canvas, (3) classificare ogni nodo come corretto/mancante/errato. Un errore in qualsiasi step produce feedback pedagogicamente dannoso.

---

### A3.1 — La Pipeline di Generazione in 4 Fasi

```
Fase 1: ESTRAZIONE        Fase 2: GENERAZIONE       Fase 3: MATCHING        Fase 4: OVERLAY
─────────────────         ──────────────────        ─────────────────       ─────────────
Canvas studente   ──→    Concept Map IA    ──→    Allineamento      ──→   Ghost Map
(Grafo Semantico         (Mappa Riferimento)      Semantico-Spaziale       a 4 Colori
 da Appendice A1)
```

---

### A3.2 — Fase 1: Estrazione del Grafo Studente

Il Grafo Semantico prodotto dalla pipeline HTR (Appendice A1) viene **arricchito** con metadati strutturali:

```json
{
  "studentGraph": {
    "nodes": [
      {
        "nodeId": "n1",
        "content": "Secondo principio termodinamica",
        "contentType": "text",
        "position": {"x": 100, "y": 200},
        "boundingBox": {"w": 300, "h": 80},
        "cluster": "termodinamica",
        "confidence": 0.88
      }
    ],
    "edges": [
      {
        "from": "n1", "to": "n2",
        "label": null,
        "direction": "down"
      }
    ],
    "clusters": [
      {
        "id": "termodinamica",
        "centroid": {"x": 200, "y": 300},
        "nodeCount": 5,
        "boundingBox": {"x": 0, "y": 50, "w": 500, "h": 600}
      }
    ]
  }
}
```

---

### A3.3 — Fase 2: Generazione della Concept Map di Riferimento

#### Il Prompt di Generazione

```
SYSTEM PROMPT — GHOST MAP GENERATION

You are generating a REFERENCE concept map to compare against a student's 
handwritten canvas.

CONTEXT:
- Subject: {subject} (e.g., "Termodinamica - Capitolo 3")
- Student level: {level} (e.g., "Primo anno ingegneria")
- Student's current nodes (from HTR): {student_graph_nodes}
- Student's current connections: {student_graph_edges}

YOUR TASK:
Generate a COMPLETE concept map for this subject at this level.
Include ONLY concepts that a student at this level should know.
Do NOT include advanced concepts beyond their curriculum.

OUTPUT FORMAT:
{
  "referenceNodes": [
    {
      "refId": "ref_001",
      "concept": "Short concept title",
      "description": "Brief description (1 sentence)",
      "importance": "core|supporting|advanced",
      "prerequisites": ["ref_002"],
      "relatedStudentNode": null
    }
  ],
  "referenceEdges": [
    {
      "from": "ref_001",
      "to": "ref_002",
      "relationType": "causes|requires|contrasts|exemplifies|contains",
      "label": "max 2 words"
    }
  ]
}

RULES:
1. Include 15-40 nodes depending on topic breadth
2. Mark each node as "core" (essential), "supporting" (important), 
   or "advanced" (nice to have)
3. If you recognize a student node that matches a reference concept, 
   set "relatedStudentNode" to hint at the match
4. Edges must have a relationType from the fixed vocabulary
5. Be PRECISE: wrong information in the reference map will cause the 
   student to correct something that was actually right
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A3-01 | La mappa di riferimento include **solo** concetti al livello dello studente (P4-03) | Il prompt contiene il livello e il curriculum. L'IA non genera concetti avanzati |
| A3-02 | La mappa è generata con **temperature 0.3** per massima accuratezza fattuale | Nessuna creatività nella mappa di riferimento — deve essere corretta |
| A3-03 | Tempo di generazione: **≤8s** per mappa con ≤40 nodi di riferimento | Timeout: 12s. Se supera → messaggio "Sto preparando il confronto..." |
| A3-04 | La mappa è **cacheable**: se lo studente richiede il confronto sulla stessa zona senza aver modificato il canvas, la mappa precedente viene riutilizzata | Cache key: hash del grafo semantico studente + subject + level |

---

### A3.4 — Fase 3: Matching Semantico-Spaziale

L'algoritmo di matching collega i nodi dello studente ai nodi di riferimento:

#### Algoritmo di Matching (3 passaggi)

**Passaggio 1 — Matching Semantico:**
Per ogni nodo di riferimento, calcola la **similarità semantica** con ogni nodo dello studente (embedding cosine similarity o LLM-based matching).

```
Per ogni refNode in referenceNodes:
  Per ogni studentNode in studentNodes:
    similarity = semantic_similarity(refNode.concept, studentNode.htrText)
    se similarity > 0.75: candidato_match
```

**Passaggio 2 — Risoluzione Conflitti:**
Se più nodi studente matchano lo stesso nodo di riferimento, scegliere quello con similarità più alta. Se più nodi di riferimento matchano lo stesso nodo studente, verificare se lo studente ha combinato concetti.

**Passaggio 3 — Classificazione:**

| Match | Classificazione | Colore Ghost Map |
|-------|----------------|-------------------|
| refNode ha match studente con similarity ≥0.75 | **Corretto** (✅) | 🟢 Verde |
| refNode NON ha match studente | **Mancante** | 🔴 Rosso |
| studentEdge non presente in referenceEdges | **Connessione errata** | 🟡 Giallo |
| referenceEdge non presente in studentEdges | **Connessione mancante** | 🔵 Blu |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A3-05 | La soglia di similarità per "match" è **configurabile** e default a 0.75 | Range: 0.60 (permissivo) — 0.90 (rigoroso). Lo studente non vede la soglia |
| A3-06 | Il matching è **semantico**, non lessicale: "2° principio" e "secondo principio della termodinamica" devono matchare | Embedding-based (sentence-transformers) o LLM-as-judge per ciascun nodo |
| A3-07 | I nodi di riferimento marcati come **"advanced"** vengono esclusi dallo scoring e mostrati come sagome grigie (fuori-ZPD) | Coerenza con P4-22 (nodi fuori-ZPD grigi) |
| A3-08 | Falsi positivi (nodo marcato "mancante" ma lo studente l'ha scritto con parole diverse): tasso accettabile **≤10%** | Test su corpus di 50+ canvas studente reali |
| A3-09 | Falsi negativi (nodo marcato "corretto" ma lo studente ha scritto qualcosa di sbagliato): tasso accettabile **≤5%** | Più grave del falso positivo — lo studente non corregge un errore |

---

### A3.5 — Fase 4: Allineamento Spaziale dell'Overlay

L'overlay Ghost Map deve essere posizionato **in modo coerente** con il layout del canvas dello studente:

#### Strategia di Posizionamento

| Tipo di Elemento | Come viene posizionato |
|-------------------|----------------------|
| **Nodo corretto (verde)** | Posizionato esattamente **sul** nodo studente corrispondente (bordo verde attorno al bounding box del nodo) |
| **Nodo mancante (rosso)** | Posizionato **vicino ai nodi correlati** (prerequisiti o concetti adiacenti nel grafo di riferimento). Algoritmo: trovare il cluster studente più affine → posizionare la sagoma nel baricentro dello spazio vuoto adiacente |
| **Connessione errata (giallo)** | L'alone giallo appare **sulla freccia esistente** dello studente — posizionamento pixel-perfect |
| **Connessione mancante (blu)** | La linea punteggiata collega i **due nodi studente** tra cui manca la connessione | 

#### Algoritmo di Posizionamento Nodi Mancanti

```
Per ogni refNode mancante:
  1. Trovare i refNode collegati che HANNO un match studente
  2. Calcolare il baricentro delle posizioni dei match studente
  3. Calcolare un offset (150-200px) nella direzione con più spazio libero
  4. Posizionare la sagoma rossa a quel punto
  5. Se conflitto (sovrapposizione con altro nodo): spostare con force-directed repulsion
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A3-10 | I nodi mancanti (rossi) sono posizionati a **≤200px** dal cluster studente più affine | Se non ci sono nodi affini, posizionare ai bordi del canvas visibile |
| A3-11 | **0 sovrapposizioni** tra elementi overlay e nodi studente | Anti-collision: ogni sagoma ha un padding di 30px dai nodi esistenti |
| A3-12 | Le dimensioni della sagoma rossa sono **proporzionali** alla complessità del concetto mancante (P4-08) | Concetto "core": sagoma grande (200×60px). "Supporting": media (150×50px). "Advanced": piccola (100×40px, grigia) |
| A3-13 | L'intero overlay è un **layer separato** che non modifica la struttura dati del canvas studente | L'overlay esiste in un render layer dedicato. Zero impatto sulla persistenza del canvas |

---

### A3.6 — Gestione dell'Ambiguità

Quando un argomento ammette **più organizzazioni concettuali valide**, l'IA deve gestirlo:

| Scenario | Strategia |
|----------|-----------|
| Lo studente ha organizzato i concetti in ordine diverso ma valido | L'IA confronta **relazioni**, non ordine. Se le connessioni sono semanticamente corrette anche se posizionate diversamente → 🟢 Verde |
| Lo studente ha incluso un concetto corretto ma non nel grafo di riferimento | L'IA NON marca il nodo come "errato". Lo ignora (nessun colore) con nota interna: "extra_node" |
| Lo studente ha creato una connessione originale valida ma non prevista | L'IA NON marca la connessione come errata. La ignora. L'IA è conservativa: marca giallo SOLO quando è sicura che la connessione è sbagliata |
| L'argomento è opinabile (filosofia, scienze sociali) | L'IA riduce i nodi "mancanti" ai soli concetti fattuali universalmente accettati. I concetti opinabili non generano sagome rosse |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A3-14 | L'IA è **conservativa** nel marcare errori: meglio un falso negativo (non segnalare un errore) che un falso positivo (segnalare errore dove non c'è) | In dubbio → 🟢 Verde o nessun colore. Mai 🔴 Rosso o 🟡 Giallo per incertezza |
| A3-15 | I nodi "extra" dello studente (corretti ma non nel riferimento) non ricevono nessun colore overlay | Non sono né rossi né verdi — sono semplicemente non valutati |
| A3-16 | Per materie opinabili, il sistema mostra un avviso: "Questo confronto si basa su un'interpretazione standard. La tua organizzazione potrebbe essere altrettanto valida." | Messaggio pre-overlay, dismissable |

---

### A3.7 — Criteri di Accettazione Ghost Map

- [ ] **CA-A3-01:** Generazione concept map: ≤8s per materie universitarie standard
- [ ] **CA-A3-02:** Matching semantico: ≥90% concordanza con matching umano su 50 canvas test
- [ ] **CA-A3-03:** Falsi positivi (mancante ma presente): ≤10%
- [ ] **CA-A3-04:** Falsi negativi (corretto ma errato): ≤5%
- [ ] **CA-A3-05:** 0 sovrapposizioni tra overlay e nodi studente
- [ ] **CA-A3-06:** Layer overlay separato: 0 modifiche alla struttura dati del canvas
- [ ] **CA-A3-07:** Nodi extra studente: 0 colore assegnato (né rosso né verde)
- [ ] **CA-A3-08:** Cache concept map: riutilizzo se canvas non modificato


---
---

## APPENDICE A4 — Infrastruttura Network per l'Apprendimento Solidale (Passo 7)

### Contesto

Il Passo 7 richiede interazione real-time tra due studenti (ghost cursor, viewport sync, canale vocale, split-view). Questa appendice specifica l'architettura di rete, i protocolli, e la gestione degli edge case.

---

### A4.1 — Architettura di Rete

| Funzione | Protocollo | Razionale |
|----------|-----------|-----------|
| **Signaling** (handshake iniziale) | Firebase Realtime Database | Entrambi gli studenti usano già Firebase. Il signaling è low-bandwidth (pochi messaggi) |
| **Canvas Data Stream** (cursor, viewport, marker) | **WebRTC DataChannel** (peer-to-peer) | Bassa latenza (≤100ms), nessun server relay per i dati, crittografia E2E |
| **Audio** (canale vocale 7b) | **WebRTC Audio** (peer-to-peer) | Standard audio real-time, opus codec, ≤200ms latenza |
| **Split-View Sync** (7c post-duello) | WebRTC DataChannel | I canvas restano locali — si trasmettono solo snapshot viewport |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A4-01 | La connessione P2P è stabilita tramite **WebRTC** con Firebase come signaling server | ICE candidates scambiati via Realtime Database. STUN/TURN servers: Google STUN gratuito + Twilio TURN come fallback |
| A4-02 | **Nessun canvas completo** viene mai trasmesso all'altro peer — solo metadati visivi | Dati trasmessi: `{cursorPosition, viewportRect, zoomLevel, markers[], laserPath[]}`. Dimensione: ≤1KB per frame |
| A4-03 | Frame rate dei metadati: **15fps** per ghost cursor, **5fps** per viewport sync | Il cursor ha bisogno di smoothness, il viewport no |
| A4-04 | Latenza ghost cursor: **≤100ms end-to-end** | WebRTC DataChannel reliable-unordered per minimizzare la latenza |
| A4-05 | Latenza audio: **≤200ms** end-to-end | WebRTC Audio con opus codec, bitrate 24kbps (sufficiente per voce) |

---

### A4.2 — Flusso di Connessione

```
Studente A                    Firebase                    Studente B
    │                            │                            │
    │── Crea sessione ──────────→│                            │
    │   (genera roomId)          │                            │
    │                            │                            │
    │   Link/QR con roomId ─────────────────────────────────→ │
    │                            │                            │
    │                            │←── Join (roomId) ──────────│
    │                            │                            │
    │←── ICE Offer ──────────────│                            │
    │                            │                            │
    │── ICE Answer ─────────────→│──────────────────────────→ │
    │                            │                            │
    │←═══════════════ WebRTC P2P ═══════════════════════════→ │
    │                            │                            │
    │   (Firebase non serve più  │                            │
    │    dopo il P2P handshake)  │                            │
```

#### Metodi di Invito

| Metodo | Come Funziona | Quando |
|--------|--------------|--------|
| **Link condivisibile** | URL con roomId crittografato: `fluera://collab/{roomId}` | Default — lo studente invia via messaggio |
| **QR Code** | QR che codifica lo stesso link — scannerizzabile con la fotocamera | In presenza — due studenti vicini |
| **Nearby (futuro)** | Bluetooth LE / Multipeer Connectivity per scoperta locale | V2 — richiede permessi aggiuntivi |

---

### A4.3 — Gestione Offline e Disconnessione

| Scenario | Comportamento |
|----------|--------------|
| **Disconnessione momentanea** (<10s) | Il sistema mostra "Connessione instabile..." + ghost cursor congelato. Buffer dei dati in coda. Al ricollegamento: flush del buffer |
| **Disconnessione prolungata** (>10s) | Il sistema mostra "Compagno disconnesso". La sessione resta attiva per 60s (possibilità di riconnessione). Dopo 60s: sessione terminata graziosamente |
| **Disconnessione durante Duello (7c)** | Il duello viene sospeso. Entrambi possono continuare il recall individualmente. La split-view non sarà disponibile |
| **Nessun internet all'inizio** | Il Passo 7 **non è disponibile** senza connessione. Messaggio: "La collaborazione richiede una connessione internet." |

---

### A4.4 — Sicurezza e Privacy

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A4-06 | I dati trasmessi via WebRTC sono **crittografati E2E** (DTLS-SRTP) | Standard WebRTC — crittografia integrata nel protocollo |
| A4-07 | **Nessun contenuto scritto** dallo studente viene trasmesso — solo posizioni, viewport e marker | Il peer vede il canvas dell'altro tramite il rendering locale (come un "screen share" renderizzato dal mittente), non tramite dati raw |
| A4-08 | Il canvas dell'altro è **renderizzato come immagine rasterizzata** e trasmesso come stream video a bassa risoluzione | Risoluzione: 720p, framerate: 10fps. Sufficiente per la vista d'insieme. L'ospite non può estrarre i tratti raw |
| A4-09 | Le aree "nascoste" dallo studente (P7-31) sono **nere nel raster** — il peer non può aggirare la sfuocatura selettiva | Il raster viene generato DOPO l'applicazione delle aree nascoste |

---

### A4.5 — Criteri di Accettazione Network

- [ ] **CA-A4-01:** WebRTC P2P stabilito ≤5s dopo il join
- [ ] **CA-A4-02:** Ghost cursor latenza ≤100ms end-to-end
- [ ] **CA-A4-03:** Audio latenza ≤200ms, qualità accettabile a 24kbps
- [ ] **CA-A4-04:** 0 canvas raw trasmessi — solo viewport metadata + raster stream
- [ ] **CA-A4-05:** Disconnessione graceful: freeze cursor + messaggio, 60s timeout
- [ ] **CA-A4-06:** Aree nascoste: nero nel raster, 0 data leak
- [ ] **CA-A4-07:** Invito: link + QR funzionanti, deeplink `fluera://collab/{id}`
- [ ] **CA-A4-08:** Crittografia E2E: DTLS-SRTP standard WebRTC attiva

---
---

## APPENDICE A5 — Algoritmo SRS Spaziale (Formula Concreta)

### Contesto

I Passi 5, 6, 8, e 10 dipendono da un algoritmo SRS che calcola l'intervallo ottimo di ripasso per ogni nodo. Questa appendice specifica l'algoritmo esatto, i parametri, e le formule.

---

### A5.1 — Algoritmo Base: FSRS Modificato

L'algoritmo scelto è **FSRS (Free Spaced Repetition Scheduler)** — una versione moderna e open-source dell'SM-2, con migliore adattamento ai dati reali. FSRS è stato scelto su SM-2 perché:

- Modella esplicitamente la **stabilità** (quanto a lungo la memoria durerà) e la **difficoltà** (quanto è intrinsecamente difficile il concetto)
- È stato validato su dataset di milioni di carte (Anki community)
- È open-source e configurabile

### A5.2 — Parametri per Nodo

Ogni nodo mantiene i seguenti parametri SRS:

```json
{
  "nodeId": "node_123",
  "srs": {
    "stability": 1.0,
    "difficulty": 0.5,
    "elapsed_days": 0,
    "scheduled_days": 1,
    "reps": 0,
    "lapses": 0,
    "state": "new|learning|review|relearning",
    "last_review": "ISO-8601",
    "next_review": "ISO-8601",
    "stage": 1
  }
}
```

| Parametro | Tipo | Significato | Range |
|-----------|------|-------------|-------|
| **stability** (S) | float | Giorni dopo i quali la probabilità di recall scende al 90% | 0.1 → ∞ |
| **difficulty** (D) | float | Difficoltà intrinseca del concetto | 0.0 (facile) → 1.0 (difficile) |
| **elapsed_days** | int | Giorni dall'ultimo ripasso | 0 → ∞ |
| **scheduled_days** | int | Intervallo pianificato dall'ultimo ripasso alla prossima review | 1 → 365 |
| **reps** | int | Numero di review corrette consecutive | 0 → ∞ |
| **lapses** | int | Numero di volte che lo studente ha dimenticato il nodo | 0 → ∞ |
| **state** | enum | Stato corrente nella macchina a stati FSRS | 4 stati possibili |
| **stage** | int | Stadio visivo (1-5 dalla tabella P8-06) | 1 → 5 |

---

### A5.3 — La Formula di Scheduling

#### Calcolo dell'Intervallo al Prossimo Ripasso

```
Dopo un recall:
  Se recall == correcte:
    new_stability = S * (1 + e^(w[0]) * D^(-w[1]) * (S^w[2] - 1) * e^(w[3] * (1 - R)))
    new_interval = new_stability * ln(desired_retention) / ln(0.9)
  
  Se recall == incorrect:
    new_stability = w[4] * D^(-w[5]) * (S^w[6] + 1) * e^(w[7] * (1 - R))
    new_interval = max(1, new_stability)
```

#### Pesi Default (w[0]..w[7])

| Peso | Valore Default | Significato |
|------|---------------|-------------|
| w[0] | 0.40 | Fattore base di crescita stabilità |
| w[1] | 0.60 | Impatto della difficoltà sulla crescita |
| w[2] | 2.40 | Impatto della stabilità corrente sulla crescita |
| w[3] | 0.10 | Impatto della retrievability sulla crescita |
| w[4] | 5.00 | Fattore base di decadimento dopo lapse |
| w[5] | 0.10 | Impatto della difficoltà sul decadimento |
| w[6] | 0.80 | Impatto della stabilità sul decadimento |
| w[7] | 0.20 | Impatto della retrievability sul decadimento |

> [!TIP]
> I pesi sono **calibrabili per studente**: dopo 100+ review, il sistema può usare gradient descent sui dati reali dello studente per ottimizzare i pesi. Fino ad allora, si usano i default sopra.

---

### A5.4 — Modificatori Fluera (Bonus e Malus)

I parametri base dell'FSRS vengono modificati dai segnali pedagogici raccolti nei Passi 2-4:

| Segnale | Modificatore | Formula | Razionale |
|---------|-------------|---------|-----------|
| **Ipercorrezione** (errore ad alta confidenza) | Bonus stabilità ×1.3 | `new_stability *= 1.3` | Lo shock cognitivo crea traccia mnestica forte (§4) |
| **Peek** (lo studente ha sbirciato, Passo 2) | Malus stabilità ×0.8 | `new_stability *= 0.8` | Il recall non era puro — la traccia è più debole |
| **Breadcrumb** (indizio usato, Passo 3) | Malus stabilità ×0.85 per livello | `new_stability *= 0.85^hints_used` | Ogni indizio riduce la purezza del recall |
| **Zoom-in necessario** (Passo 6) | Malus stabilità ×0.9 | `new_stability *= 0.9` | Lo studente ha avuto bisogno di avvicinarsi — la memoria spaziale non era sufficiente |
| **Tempo di risposta rapido** (<5s) | Bonus stabilità ×1.1 | `new_stability *= 1.1` | Recall rapido = recupero automatico, traccia forte |
| **Tempo di risposta lento** (>15s) | Malus stabilità ×0.9 | `new_stability *= 0.9` | Recall lento = recupero effortful, traccia fragile |
| **Nodo scoperto in Ghost Map** (Passo 4) | Malus iniziale: stabilità partenza = 0.5 | `initial_stability = 0.5` | Il nodo non è stato generato dallo studente — il recall sarà più debole |

---

### A5.5 — Floor e Ceiling degli Intervalli

| Parametro | Valore | Razionale |
|-----------|--------|-----------|
| **Intervallo minimo** | 1 giorno | Non si ripassa più di una volta al giorno sullo stesso nodo |
| **Intervallo massimo** | 365 giorni | Anche un nodo Stadio 5 torna almeno una volta l'anno |
| **Stabilità floor** | 0.1 | Una stabilità <0.1 è trattata come 0.1 (non si scende sotto 1 giorno) |
| **Desired retention** | 0.90 (90%) | Il target è ricordare il 90% dei nodi a ogni review — calibrabile dallo studente nell'intervallo [0.80, 0.97] |

---

### A5.6 — Prioritizzazione dei Nodi per Sessione

Quando lo studente apre una sessione di ripasso, il sistema seleziona i nodi da ripassare con il seguente algoritmo di priorità:

```
Per ogni nodo con next_review ≤ oggi:
  overdue_days = oggi - next_review
  urgency = overdue_days / scheduled_days  // Quanto è "scaduto" in proporzione
  
  priority = urgency * (1 + 0.3 * is_hypercorrection) * (1 + 0.5 * from_ghost_map)

Ordinare i nodi per priority (decrescente).

Per Micro-Review: selezionare top-N (N = nodi revisionabili in 5 min, ~10-15)
Per Deep-Review: selezionare tutti
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A5-01 | L'algoritmo FSRS calcola **un intervallo per nodo**, non per zona | Ogni nodo ha il proprio `next_review` indipendente |
| A5-02 | I modificatori Fluera si applicano **dopo** il calcolo FSRS base | L'ordine è: FSRS base → applicare bonus/malus → clamp a floor/ceiling |
| A5-03 | La prioritizzazione è **proporzionale** all'urgenza relativa, non assoluta | Un nodo con intervallo 30 giorni scaduto di 5 giorni è meno urgente di un nodo con intervallo 3 giorni scaduto di 3 giorni |
| A5-04 | Il desired retention è **configurabile** dallo studente: 80-97% | Default: 90%. Slider nelle impostazioni con spiegazione |
| A5-05 | Il calcolo SRS avviene **offline** e silenziosamente (P5-04) | 0 richieste di rete. Tutti i calcoli locali |
| A5-06 | I pesi FSRS diventano **personalizzati** dopo 100+ review dello studente | Auto-calibrazione: gradient descent sui dati reali. Fino a 100 review: pesi default |

---

### A5.7 — Mapping Stadio Visivo ← SRS

| Stadio | Condizione | Blur (px) | Icona |
|--------|-----------|-----------|-------|
| **1 — Fragile** | reps < 2 AND stability < 3 | 5-10 | 🌱 |
| **2 — In crescita** | reps ≥ 2 AND stability ∈ [3, 14] | 15-20 | 🌿 |
| **3 — Solido** | reps ≥ 4 AND stability ∈ [14, 60] | 25-30 | 🌳 |
| **4 — Padroneggiato** | reps ≥ 6 AND stability ∈ [60, 180] AND lapses = 0 negli ultimi 3 reps | 35-40 | ⭐ |
| **5 — Integrato** | reps ≥ 10 AND stability > 180 AND lapses = 0 negli ultimi 5 reps | Quasi invisibile | 👻 |

---

### A5.8 — Criteri di Accettazione SRS

- [ ] **CA-A5-01:** Intervallo calcolato per-nodo: due nodi nella stessa zona possono avere date di review diverse
- [ ] **CA-A5-02:** FSRS base: formula implementata correttamente, validata con test unitari su 100+ scenari
- [ ] **CA-A5-03:** Modificatori Fluera: bonus ipercorrezione ×1.3, malus peek ×0.8, ecc. applicati correttamente
- [ ] **CA-A5-04:** Floor/ceiling respettati: min 1g, max 365g, stability ≥0.1
- [ ] **CA-A5-05:** Prioritizzazione: nodi overdue ordinati per urgenza relativa, non assoluta
- [ ] **CA-A5-06:** 5 stadi visivi: blur e icona coerenti con tabella mapping
- [ ] **CA-A5-07:** Desired retention: configurabile 80-97%, default 90%
- [ ] **CA-A5-08:** Calcolo completamente offline: 0 richieste di rete

---
---

## APPENDICE A6 — Segmentazione dei Nodi (Algoritmo Concreto)

### Contesto

La segmentazione trasforma tratti raw (ink strokes) in **nodi semantici** — le unità atomiche del canvas che l'SRS traccia, l'IA legge, e il recall testa. Senza una segmentazione precisa, tutto il framework crolla.

---

### A6.1 — Algoritmo: DBSCAN Spazio-Temporale

L'algoritmo scelto è **DBSCAN** (Density-Based Spatial Clustering of Applications with Noise), modificato per includere la dimensione temporale:

```
Input: lista di tratti [stroke_1, stroke_2, ..., stroke_N]
       Ogni stroke ha: bounding_box, timestamp, contentType (da A1 L1)

1. FILTRAGGIO PER TIPO:
   - Separare i tratti classificati come "arrow" → pool connessioni
   - Separare i tratti classificati come "symbol" → pool tag
   - Rimanenti (text, drawing, formula) → pool nodi

2. CLUSTERING DBSCAN:
   Per il pool nodi:
   - Distanza: distanza minima tra bounding box di due tratti
   - eps (raggio): 100px (default, adattivo alla dimensione media della calligrafia)
   - min_samples: 1 (anche un singolo tratto è un nodo valido)
   - Bonus temporale: tratti scritti entro 5s l'uno dall'altro 
     hanno eps raddoppiato (200px) — tendono ad appartenere allo stesso nodo

3. POST-PROCESSING:
   - Cluster con bounding box > 600×400px → tentare split 
     (probabilmente due nodi adiacenti fusi)
   - Cluster con un singolo micro-tratto (<20px) → classificare come rumore 
     (punto accidentale)

4. OUTPUT: lista di nodi, ciascuno con:
   {nodeId, strokes[], boundingBox, centroid, contentType, 
    createdAt, lastModifiedAt}
```

---

### A6.2 — Gestione Tipi Specifici

| Tipo di Contenuto | Come si Segmenta |
|-------------------|-----------------|
| **Testo multi-riga** | Il DBSCAN raggruppa righe vicine (<100px verticalmente) come un singolo nodo. Se la distanza verticale tra righe supera 150px → due nodi separati |
| **Formule** | Tratti classificati come `formula` sono raggruppati con eps più largo (150px) per catturare frazioni, esponenti, pedici |
| **Disegni** | Tratti classificati come `drawing` usano eps standard (100px). Un grande diagramma può essere un singolo nodo |
| **Frecce** | Tratti classificati come `arrow` NON sono nodi — sono **connessioni** tra nodi. L'endpoint più vicino a un nodo diventa l'origine, l'altro diventa la destinazione |
| **Simboli** | Tratti classificati come `symbol` diventano **tag** del nodo più vicino (entro 80px). Se isolati → nodo autonomo di tipo `symbol_node` |

---

### A6.3 — Adattamento alla Calligrafia

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A6-01 | Il parametro `eps` è **adattivo**: si calibra sulla dimensione media della calligrafia dello studente | Calibrazione: media dell'altezza dei tratti classificati come `text` nei primi 20 tratti. eps = media_altezza × 1.5 |
| A6-02 | La segmentazione è **ricalcolata** quando lo studente aggiunge nuovi tratti vicino a nodi esistenti | Trigger: nuovo tratto con bounding box che interseca o è entro eps da un nodo esistente → merge o re-segment |
| A6-03 | Lo studente può **unire** manualmente due nodi o **dividere** un nodo in due | UI: long-press su due nodi → "Unisci". Long-press su un nodo → "Dividi qui" con linea di taglio |
| A6-04 | La tolleranza d'errore è **≤15%** misurata come percentuale di nodi segmentati erroneamente | Metrica: su 20 nodi, ≤3 hanno segmentazione sbagliata (troppi tratti o troppo pochi) |
| A6-05 | Il 15% viene valutato tramite **test umano**: 5 canvas campione giudicati da 3 valutatori | Concordanza inter-valutatore ≥80% definisce la ground truth |

---

### A6.6 — Criteri di Accettazione Segmentazione

- [ ] **CA-A6-01:** DBSCAN implementato con parametro eps adattivo alla calligrafia
- [ ] **CA-A6-02:** Frecce classificate come connessioni, non nodi: origin/destination corretti
- [ ] **CA-A6-03:** Testo multi-riga: righe entro 100px verticali → stesso nodo
- [ ] **CA-A6-04:** Merge/split manuale funzionante con ≤2 gesti
- [ ] **CA-A6-05:** Errore di segmentazione ≤15% su 5 canvas campione
- [ ] **CA-A6-06:** Segmentazione incrementale: aggiunta tratti non ricalcola tutto

---
---

## APPENDICE A7 — IA Cross-Dominio: Metodo per la Scoperta di Ponti (Passo 9)

### Contesto

Il Passo 9 richiede che l'IA suggerisca connessioni tra concetti di zone/materie diverse. Questa appendice specifica come l'IA identifica somiglianze cross-dominio in modo scalabile e accurato.

---

### A7.1 — Pipeline a 2 Passaggi

```
Passaggio 1: CANDIDATE GENERATION (veloce, locale)
──────────────────────────────────────────────────
Per ogni nodo di ogni zona:
  Calcolare embedding del contenuto HTR (sentence-transformer, on-device)
  
Per ogni coppia di zone (z1, z2):
  Per ogni nodo n1 in z1:
    Per ogni nodo n2 in z2:
      sim = cosine_similarity(embedding(n1), embedding(n2))
      se sim > 0.60: candidato ponte
      
Filtrare: max 10 candidati, ordinati per similarità

Passaggio 2: VERIFICATION + QUESTION (LLM, cloud)
──────────────────────────────────────────────────
Per ogni candidato ponte:
  Prompt al LLM:
    "Il concetto '{n1.content}' in {z1.subject} e il concetto 
     '{n2.content}' in {z2.subject} hanno una similarità 
     embedding di {sim}. È una connessione significativa?
     Se sì, formulala come DOMANDA (non affermazione).
     Se no, rispondi 'NO_BRIDGE'.
     Se sì, classifica: A (analogia) / B (meccanismo) / C (prospettiva)."
     
  Se output ≠ "NO_BRIDGE": aggiungere alla lista suggerimenti
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A7-01 | Il Passaggio 1 (embedding) gira **on-device** — il filtraggio è locale e veloce | Modello: sentence-transformer small (MiniLM, ~30MB). Tempo: ≤2s per 100 nodi |
| A7-02 | Il Passaggio 2 (LLM verification) gira su **cloud** perché richiede ragionamento cross-dominio | Il LLM elimina le false analogie lessicali (es. "cellula" in biologia vs. "cellula" in telefonia) |
| A7-03 | I suggerimenti sono limitati a **3-5 per invocazione** (P9-08) | Se ci sono >5 candidati validi, mostrare i top 5 per similarità |
| A7-04 | **Mai suggerire ponti banali** (stessa parola in due contesti ovvi) | Il LLM è istruito a rifiutare ponti che uno studente scoprirebbe da solo |
| A7-05 | Scalabilità: funziona per canvas con **≤500 nodi** in **≤10 zone** | Complessità tempo Passaggio 1: O(N² per coppia di zone) — ma con pruning per cluster, ~O(N log N) |

---

### A7.2 — Criteri di Accettazione Cross-Dominio

- [ ] **CA-A7-01:** Embedding on-device: ≤2s per 100 nodi
- [ ] **CA-A7-02:** LLM verification: elimina ≥80% delle false analogie lessicali
- [ ] **CA-A7-03:** Suggerimenti formulati come domande, 0 affermazioni
- [ ] **CA-A7-04:** 3-5 suggerimenti max per invocazione
- [ ] **CA-A7-05:** Scalabile ≤500 nodi, ≤10 zone senza timeout

---
---

## APPENDICE A8 — Time Travel e Versionamento del Canvas

### Contesto

Il Passo 12 promette che lo studente possa "navigare nel tempo" e vedere le versioni precedenti del canvas. Questa appendice specifica il sistema di versionamento.

---

### A8.1 — Architettura: Event Sourcing

Il canvas NON viene salvato come snapshot — viene salvato come **sequenza di eventi**:

```json
{
  "events": [
    {
      "eventId": "evt_001",
      "timestamp": "2025-10-15T14:30:00Z",
      "type": "stroke_added",
      "data": {"strokeId": "s_001", "points": [...], "tool": "pen", "color": "#000"}
    },
    {
      "eventId": "evt_002", 
      "timestamp": "2025-10-15T14:30:05Z",
      "type": "stroke_erased",
      "data": {"strokeId": "s_001"}
    },
    {
      "eventId": "evt_003",
      "timestamp": "2025-10-15T14:31:00Z",
      "type": "srs_review",
      "data": {"nodeId": "n_001", "result": "correct", "newStability": 3.2}
    }
  ]
}
```

#### Vantaggi dell'Event Sourcing

| Vantaggio | Dettaglio |
|-----------|----------|
| **Spazio** | Molto più efficiente degli snapshot: un tratto occupa ~200 byte, uno snapshot PNG di canvas occupa ~5MB |
| **Granularità** | Si può ricostruire il canvas a *qualsiasi* istante, non solo a intervalli predefiniti |
| **Cronologia** | La timeline (P12-05) si costruisce filtrando gli eventi per data |
| **Undo/Redo** | Già integrato nel transaction system esistente del progetto Fluera |

---

### A8.2 — Snapshot Periodici (Checkpoints)

Per evitare di dover riprodurre migliaia di eventi per ricostruire un canvas vecchio di anni:

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A8-01 | Il sistema crea uno **snapshot automatico** ogni 500 eventi o ogni sessione conclusa | Lo snapshot è lo stato completo del canvas (tratti + metadati SRS + layout) serializzato come binary blob |
| A8-02 | Per navigare a una data, il sistema trova lo **snapshot più vicino precedente** e riproduce gli eventi fino alla data richiesta | Tempo max di ricostruzione: ≤3s per qualsiasi data con ≤500 eventi di delta |
| A8-03 | Gli snapshot **non sostituiscono** gli eventi — convivono. La timeline usa gli eventi per la granularità fine | Lo snapshot è un acceleratore, gli eventi sono la verità |
| A8-04 | Lo storage totale per un canvas di 1 anno con uso intenso: **≤50MB** | Budget: ~1000 eventi/mese × 200 byte = 200KB eventi + 2MB snapshot/mese × 12 = 24MB snapshot. Totale: ~25MB. Sotto il budget |

---

### A8.3 — Timeline UI (P12-05, P12-07)

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A8-05 | La timeline è una **linea orizzontale** con milestone (date delle sessioni) | Milestone: punti sulla linea, etichettati con data e metriche (nodi aggiunti, review fatti) |
| A8-06 | Lo studente **trascina** uno slider sulla timeline per navigare nel tempo | L'anteprima si aggiorna in tempo reale mentre lo slider si muove (30fps minimo) |
| A8-07 | La timeline mostra solo **macro-eventi**: sessioni di studio (Passo 1), confronti (Passo 4), Fog of War (Passo 10) | Non mostrare ogni singolo tratto — è rumore. Mostrare le sessioni |
| A8-08 | In modalità time travel, il canvas è **in sola lettura** — lo studente non può modificare il passato | Toolbar disabilitata. Messaggio: "Stai guardando il canvas come era il {data}. Tocca 'Torna al presente' per modificare." |

---

### A8.4 — Criteri di Accettazione Time Travel

- [ ] **CA-A8-01:** Event sourcing: ogni azione sul canvas genera un evento persistito
- [ ] **CA-A8-02:** Snapshot automatici ogni 500 eventi o fine sessione
- [ ] **CA-A8-03:** Ricostruzione canvas a qualsiasi data ≤3s
- [ ] **CA-A8-04:** Storage ≤50MB per canvas di 1 anno
- [ ] **CA-A8-05:** Timeline UI: slider navigabile con anteprima 30fps
- [ ] **CA-A8-06:** Modalità time travel: sola lettura, 0 modifiche permesse

---
---

## APPENDICE A9 — Meccanismo Pull per i Ritorni (Passo 5→6)

### Contesto

Il framework vieta le notifiche push (P5-05) e le streak (P5-07). Ma lo studente deve sapere quando tornare a ripassare. La soluzione è un meccanismo **pull** — lo studente controlla attivamente, il sistema non lo insegue.

---

### A9.1 — Indicatori di Ripasso nella Galleria

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A9-01 | Nella galleria dei canvas, ogni zona mostra un **badge discreto** con il numero di nodi scaduti: "6 nodi da rivedere" | Badge: piccolo cerchio con numero, colore neutro (grigio scuro, non rosso allarmante). Posizione: angolo in basso a destra della card della zona |
| A9-02 | Il badge è calcolato in background all'apertura dell'app (non richiede connessione) | Calcolo SRS locale. Aggiornamento: ≤500ms all'apertura della galleria |
| A9-03 | Il badge **non pulsa, non anima, non ha suono** — è un dato statico | Nessuna urgenza comunicata visivamente. È un'informazione, non un allarme |
| A9-04 | Se 0 nodi sono scaduti: il badge **non appare** (non mostrare "0 nodi") | Lo spazio è pulito quando non serve azione |
| A9-05 | Tocco sul badge → apre direttamente la selezione "Ripasso veloce" o "Ripasso profondo" (P8-15) | Shortcut: dal badge al ripasso in 1 tap |

---

### A9.2 — Il Calendario "Prossimi Ritorni" (Opzionale)

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A9-06 | Nelle impostazioni della zona, lo studente può vedere un **mini-calendario** che mostra le prossime date di ripasso SRS | Calendario: vista mensile, con punti colorati nei giorni con review programmate. Colori: grigio (poche review), giallo (moderate), blu (molte) |
| A9-07 | Il calendario è **informativo**, mai imperativo — non dice "devi", dice "ecco quando" | Tono: "Hai 5 nodi programmati per martedì prossimo." |
| A9-08 | Il calendario è **nascosto** per default — lo studente deve cercarlo nelle impostazioni | Non deve essere nella schermata principale. L'informazione SRS è disponibile solo a chi la cerca |

---

### A9.3 — Criteri di Accettazione

- [ ] **CA-A9-01:** Badge nodi scaduti: discreto, grigio scuro, non pulsante, ≤500ms aggiornamento
- [ ] **CA-A9-02:** 0 nodi scaduti → 0 badge (non mostrare "0")
- [ ] **CA-A9-03:** Tap su badge → selezione tipo ripasso in 1 tap
- [ ] **CA-A9-04:** Mini-calendario: nascosto per default, solo su richiesta

---
---

## APPENDICE A10 — Passeggiata nel Palazzo (UX Completa per Passo 11)

### Contesto

La "Passeggiata nel Palazzo" (P11-05) è la modalità contemplativa pre-esame. Serve una specifica UX dettagliata per distinguerla dalla semplice apertura del canvas.

---

### A10.1 — Attivazione e Interfaccia

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A10-01 | La Passeggiata si attiva tramite un bottone **dedicato** nella toolbar: icona 🚶 o "Passeggiata" | Non confondibile con l'apertura normale del canvas |
| A10-02 | All'attivazione, l'UI cambia **atmosfera**: la toolbar si minimizza, i bordi dello schermo si oscurano leggermente (vignetta 10%), e un'animazione di apertura lenta (1s) simula l'"ingresso nel Palazzo" | L'effetto è contemplativo: meno UI, più canvas |
| A10-03 | Il canvas mostra **tutto il contenuto** senza blur, senza nebbia, senza test | Il canvas è identico allo stato corrente ma ogni meccanica di test è disabilitata |
| A10-04 | Un **percorso guidato opzionale** (linea sottile punteggiata dorata) suggerisce un ordine di navigazione che attraversa l'intero canvas | Il percorso è il "tour del Palazzo" — tocca le zone in ordine logico. Dismissable con un gesto |
| A10-05 | Lo studente **può scrivere** durante la Passeggiata (annotazioni dell'ultimo minuto) | Il canvas non è in sola lettura — la Passeggiata non è il time travel |
| A10-06 | La Passeggiata **non genera dati SRS** — non aggiorna intervalli, non registra performance | Il flag `tracking: false` è attivo. Nessun metadato sulla sessione |
| A10-07 | Un bottone **"Torna"** chiude la modalità Passeggiata e ripristina la UI standard | Animazione di uscita: la vignetta si dissolve, la toolbar riappare |

---

### A10.2 — Criteri di Accettazione

- [ ] **CA-A10-01:** Bottone dedicato in toolbar, non confondibile con apertura normale
- [ ] **CA-A10-02:** Atmosfera: vignetta 10%, toolbar minimizzata, animazione 1s
- [ ] **CA-A10-03:** 0 blur, 0 nebbia, 0 test, 0 recall
- [ ] **CA-A10-04:** Percorso guidato opzionale, dismissable
- [ ] **CA-A10-05:** Scrittura permessa durante la Passeggiata
- [ ] **CA-A10-06:** 0 dati SRS generati, 0 tracking

---
---

## APPENDICE A11 — Accessibilità

### Contesto

Il framework usa colori (rosso/verde/giallo/blu) come canale informativo primario in più Passi. Senza adattamenti, ~8% degli studenti maschi con daltonismo non possono usare efficacemente la Ghost Map, la Fog of War, e il feedback di recall.

---

### A11.1 — Daltonismo

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A11-01 | Ogni informazione veicolata tramite colore è **ridondante** con un altro canale: forma, icona, pattern, o testo | Mai colore-solo. Il rosso ha "❌", il verde ha "✅", il giallo ha "?", il blu ha "---" (tratteggio) |
| A11-02 | Nelle impostazioni è disponibile una **modalità daltonico** che sostituisce rosso/giallo/verde/blu con una palette distinguibile | Palette alternativa: Rosso→Arancione #FF6B35, Verde→Ciano #00C9DB, Giallo→Magenta #FF00FF, Blu→Bianco #FFFFFF. Testata con simulatore di daltonismo deuteranopia/protanopia |
| A11-03 | In modalità daltonico, i nodi della Ghost Map usano anche **pattern di riempimento**: mancanti (tratteggio diagonale), errati (puntini), corretti (linee orizzontali) | I pattern funzionano anche in scala di grigi |

---

### A11.2 — Disabilità Motorie

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A11-04 | Per studenti che non possono scrivere a mano, il sistema offre una **modalità tastiera** per i Passi che richiedono input testuale (Passi 3, 6) | La modalità tastiera sostituisce la scrittura a mano con digitazione. Il principio di "generazione" resta intatto: lo studente scrive comunque da sé |
| A11-05 | La modalità tastiera **non disabilita** il principio motorio per chi può scrivere a mano — è un'opzione di accessibilità, non un shortcut | Toggle nelle impostazioni di accessibilità. L'app comunica: "Questa modalità è per chi ha difficoltà a scrivere a mano" |

---

### A11.3 — Contrasto e Leggibilità

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A11-06 | Tutti gli elementi UI rispettano un rapporto di contrasto **≥4.5:1** (WCAG AA) | Testato con strumenti di audit WCAG |
| A11-07 | Le bolle socratiche (Passo 3) e le etichette overlay (Passo 4) sono **ridimensionabili** con il sistema di accessibilità del sistema operativo | L'app rispetta `textScaleFactor` di iOS/Android. Testato fino a 200% |
| A11-08 | Il blur del Passo 6 ha un'**opzione a contrasto elevato**: invece di blur gaussiano, usa un overlay opaco solido (più facile da "indovinare" per chi ha problemi visivi) | Toggle nelle impostazioni di accessibilità |

---

### A11.4 — Criteri di Accettazione Accessibilità

- [ ] **CA-A11-01:** Ogni colore ha un canale ridondante (icona, forma, pattern)
- [ ] **CA-A11-02:** Modalità daltonico: palette alternativa funzionante per deuteranopia e protanopia
- [ ] **CA-A11-03:** Modalità tastiera: funzionante per i Passi 3 e 6
- [ ] **CA-A11-04:** Contrasto ≥4.5:1 su tutti gli elementi UI
- [ ] **CA-A11-05:** Text scale: funzionante fino a 200%
- [ ] **CA-A11-06:** Opzione blur ad alto contrasto (overlay opaco)

---
---

## APPENDICE A12 — Performance su Larga Scala

### Contesto

Un canvas che cresce per anni (Passo 12) può contenere migliaia di nodi. Senza una strategia di performance, l'app diventa inutilizzabile. Questa appendice specifica i vincoli di performance.

---

### A12.1 — Budget di Memoria

| Dimensione Canvas | Nodi | Tratti Totali | RAM Budget | Frame Target |
|-------------------|------|--------------|------------|--------------|
| **Piccolo** | ≤50 | ≤1.000 | ≤50MB | 60fps |
| **Medio** | 50-200 | 1.000-10.000 | ≤150MB | 60fps |
| **Grande** | 200-500 | 10.000-50.000 | ≤300MB | 60fps |
| **Enorme** | 500-2.000 | 50.000-200.000 | ≤500MB | ≥30fps |
| **Estremo** | 2.000+ | 200.000+ | ≤800MB | ≥30fps (con avviso) |

---

### A12.2 — Strategia di Culling e Paginazione

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A12-01 | **Viewport culling**: solo i nodi/tratti visibili nel viewport corrente vengono renderizzati | Il culling è basato sul bounding box: se il bounding box del nodo non interseca il viewport (con margine del 20%), il nodo NON viene disegnato |
| A12-02 | **Spatial indexing**: un R-Tree (o Quadtree) indicizza i nodi per posizione | La ricerca "quali nodi sono nel viewport" è O(log N), non O(N) |
| A12-03 | I tratti fuori viewport sono **scaricati dalla RAM** e caricati on-demand dal database | Background loading: quando lo studente fa pan, i tratti nella direzione di pan vengono pre-caricati 500ms prima di entrare nel viewport |
| A12-04 | A zoom-out estremo (**zoom <20%**), i nodi sono renderizzati come **blob colorati + titolo** senza i tratti dettagliati (LOD system già esistente nel progetto) | Il LOD è già implementato nel Fluera Engine. Questa è una conferma che deve funzionare anche per 2000+ nodi |
| A12-05 | Il rasterizatore dei nodi usa una **cache texture**: i nodi che non cambiano vengono renderizzati come sprite rasterizzati, non ri-disegnati frame per frame | Cache invalidation: solo sui nodi modificati. Il rendering di un nodo non modificato costa 0 draw calls |

---

### A12.3 — Persistenza

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A12-06 | Il database locale è **SQLite** (già in uso nel progetto) con tabelle separate per tratti, nodi, metadati SRS, e eventi (A8) | Schema: `strokes`, `nodes`, `srs_data`, `events`, `snapshots` |
| A12-07 | Il salvataggio è **incrementale** e **asincrono**: i tratti vengono salvati in background, mai nel thread UI | Ritardo massimo di persistenza: 2s dalla fine del tratto. In caso di crash, l'ultimo 2s di lavoro può andare perso (accettabile) |
| A12-08 | L'apertura del canvas carica **solo i tratti nel viewport iniziale** — il resto viene caricato on-demand | Tempo di apertura: ≤1.5s per canvas con ≤500 nodi, ≤3s per canvas con ≤2000 nodi |

---

### A12.4 — Sincronizzazione Cloud (se presente)

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A12-09 | La sincronizzazione cloud è **opzionale** (solo per utenti Plus/Pro) | Il canvas funziona completamente offline. Il sync è un backup, non un requisito |
| A12-10 | Il sync usa il **log degli eventi** (A8) come unità di sincronizzazione — non gli snapshot completi | Sync incrementale: solo i nuovi eventi vengono caricati. Bandwidth: ~50KB/sessione |
| A12-11 | Il conflict resolution in caso di modifica da due dispositivi: **last-write-wins** per i tratti, **merge** per i metadati SRS | I tratti sono immutabili (append-only). L'unico conflitto possibile è sull'SRS, risolvibile con merge |
| A12-12 | La prima sincronizzazione di un canvas grande (2000+ nodi) avviene in **background** con progress bar | Tempo stimato per upload completo: ~30s su WiFi. Lo studente può usare l'app durante il sync |

---

### A12.5 — Criteri di Accettazione Performance

- [ ] **CA-A12-01:** 60fps con ≤500 nodi, ≥30fps con ≤2000 nodi
- [ ] **CA-A12-02:** Viewport culling: 0 nodi fuori viewport renderizzati
- [ ] **CA-A12-03:** R-Tree/Quadtree: ricerca viewport O(log N)
- [ ] **CA-A12-04:** LOD a zoom-out: blob + titolo per zoom <20%
- [ ] **CA-A12-05:** Apertura canvas ≤1.5s per ≤500 nodi, ≤3s per ≤2000 nodi
- [ ] **CA-A12-06:** Persistenza incrementale: ritardo max 2s, async, mai su UI thread
- [ ] **CA-A12-07:** Sync cloud incrementale: ~50KB/sessione, background

---
---

## Riepilogo Finale con Appendici

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   📖 SPECIFICA IMPLEMENTATIVA COMPLETA — FLUERA COGNITIVE ENGINE            │
│                                                                             │
│   12 Passi + 12 Appendici Infrastrutturali                                 │
│                                                                             │
│   ┌────────┬────────────────────────────────────┬────────┬──────┐          │
│   │ Passo  │ Nome                               │ Regole │  QA  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │   1    │ Appunti a Mano                     │   48   │  15  │          │
│   │   2    │ Elaborazione Solitaria             │   70   │  28  │          │
│   │   3    │ Interrogazione Socratica           │   50   │  22  │          │
│   │   4    │ Confronto Centauro                 │   39   │  18  │          │
│   │   5    │ Consolidamento Notturno            │    8   │   5  │          │
│   │   6    │ Primo Ritorno (Blur + Recall)      │   21   │  17  │          │
│   │   7    │ Apprendimento Solidale             │   34   │  19  │          │
│   │   8    │ Ritorni SRS                        │   26   │  17  │          │
│   │   9    │ Ponti Cross-Dominio                │   18   │  13  │          │
│   │  10    │ Fog of War                         │   29   │  18  │          │
│   │  11    │ L'Esame                            │   10   │   7  │          │
│   │  12    │ Infrastruttura Permanente          │   11   │   7  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │  A1    │ HTR Pipeline                       │   20   │   9  │          │
│   │  A2    │ Prompt Engineering Socratico       │   11   │   8  │          │
│   │  A3    │ Ghost Map Generation               │   16   │   9  │          │
│   │  A4    │ Network P2P                        │    9   │   8  │          │
│   │  A5    │ Algoritmo SRS (FSRS)               │    6   │   8  │          │
│   │  A6    │ Segmentazione Nodi                 │    5   │   6  │          │
│   │  A7    │ IA Cross-Dominio                   │    5   │   5  │          │
│   │  A8    │ Time Travel                        │    8   │   6  │          │
│   │  A9    │ Meccanismo Pull Ritorni            │    8   │   4  │          │
│   │  A10   │ Passeggiata nel Palazzo            │    7   │   6  │          │
│   │  A11   │ Accessibilità                      │    8   │   6  │          │
│   │  A12   │ Performance su Larga Scala         │   12   │   7  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │ TOTALE │                                    │  479   │ 283  │          │
│   └────────┴────────────────────────────────────┴────────┴──────┘          │
│                                                                             │
│   🔑 L'Unica Regola che Governa Tutti i 12 Passi e le 12 Appendici:       │
│                                                                             │
│   Lo studente deve SEMPRE generare prima di ricevere.                      │
│   In ogni passo — dalla prima riga di appunti all'ultimo                   │
│   ripasso prima dell'esame — lo sforzo cognitivo viene                     │
│   PRIMA, e il feedback viene DOPO.                                         │
│   Invertire quest'ordine annulla il valore di tutto                        │
│   il percorso.                                                             │
│                                                                             │
│   La fatica è il prezzo. La memoria è il premio.                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---
---

## APPENDICE A13 — UX Comportamentale: Il Respiro del Canvas

### Filosofia

La specifica base definisce cosa il software *fa*. Questa appendice definisce **come lo fa sentire**. Ogni passo ha un'identità emotiva, un ritmo, un suono, un peso tattile. Lo studente non interagisce con un software — abita un luogo. Il Palazzo della Memoria deve *respirare*.

> [!IMPORTANT]
> La UX comportamentale non è decorazione. Ogni micro-animazione ha uno scopo cognitivo: ridurre il carico della memoria di lavoro, segnalare transizioni di stato, e creare **ancoraggi sensoriali** che rafforzano la codifica mnestica (Multimodal Encoding §28).

---

### A13.1 — L'Identità Emotiva di Ogni Passo

Ogni Passo ha una **temperatura emotiva** diversa. Il software la comunica tramite sottili cambiamenti ambientali:

| Passo | Emozione Dominante | Colore Ambientale | Intensità UI | Metafora |
|-------|--------------------|-------------------|--------------|----------|
| **1 — Appunti** | Concentrazione serena | Neutro (sfondo canvas puro) | Minima — solo penna e carta | "Stanza vuota, luce naturale" |
| **2 — Recall** | Tensione costruttiva | Leggera sfumatura calda (beige 5%) sullo sfondo dell'area recall | Bassa — blur + zona vuota | "Stanza con le luci abbassate" |
| **3 — Socratico** | Curiosità dialogica | Accent color sulle bolle IA: indaco morbido (#5C6BC0) | Media — bolle + canvas | "Conversazione con un mentore" |
| **4 — Ghost Map** | Scoperta e confronto | Overlay multi-colore (rosso/giallo/verde/blu) su canvas morbido | Alta — overlay a 4 colori | "Mappa del tesoro sovrapposta alla propria" |
| **5 — Notte** | Riposo (nessuna UI) | — | Zero | "Il Palazzo dorme" |
| **6 — Primo Ritorno** | Attesa e rivelazione | Canvas sfumato (blu-grigio desaturato) | Media — blur + reveal | "Nebbia mattutina nel Palazzo" |
| **7 — Solidale** | Eccitazione sociale | Accent color collaborazione: verde acqua (#26A69A) | Alta — split-view, cursori, voce | "Due esploratori nella stessa mappa" |
| **8 — SRS** | Routine rituale | Lo stesso colore del Passo 6 ma più saturo (familiarità crescente) | Media | "Passeggiata serale nel Palazzo" |
| **9 — Ponti** | Illuminazione | Accento dorato (#FFD700) per i ponti | Media-alta — frecce dorate, zoom panoramico | "Vista dall'alto, strade che si illuminano" |
| **10 — Fog of War** | Sfida e verità | Canvas scuro/nero con rivelazioni progressive | Alta — nebbia, reveal cinematografico | "Esplorazione notturna con torcia" |
| **11 — Esame** | Fiducia silenziosa | UI minima, toni caldi | Minima | "Il Palazzo vive nella testa" |
| **12 — Permanenza** | Orgoglio e appartenenza | Dorato per la timeline; colori vivi del canvas | Alta — timeline, time travel | "Il Palazzo completato" |

---

### A13.2 — Coreografia delle Transizioni tra Passi

Le transizioni tra un Passo e l'altro sono **momenti pedagogici** — non semplici cambi di schermata. Lo studente deve percepire che sta "avanzando nel percorso".

#### Transizione Passo 1 → Passo 2 (Concentrazione → Recall)

```
1. Lo studente attiva "Modalità Ricostruzione" (bottone o gesto)
2. ANIMAZIONE (800ms, ease-in-out):
   - I nodi del Passo 1 si sfumano gradualmente (blur 0 → 25px)
   - Lo sfondo dell'area recall cambia tono (neutro → beige 5%)
   - La toolbar si riorganizza: scompare l'icona IA, 
     appare il marker "non ricordo"
3. HAPTIC: vibrazione media singola — "stacco" dal materiale
4. SUONO: tono grave morbido (200Hz, 300ms) — "sipario che scende"
5. Lo studente è nella zona recall. Il Palazzo del Passo 1 è una sagoma.
```

#### Transizione Passo 2 → Passo 3 (Recall → Dialogo Socratico)

```
1. Lo studente invoca l'IA (bottone "Interrogami")
2. ANIMAZIONE (600ms):
   - Una linea sottile luminosa appare dal bordo destro del canvas 
     → si espande in un pannello laterale semi-trasparente
   - Il canvas si comprime leggermente a sinistra (5%) 
     per fare spazio al pannello
3. HAPTIC: doppio tap leggero — "qualcuno bussa alla porta"
4. SUONO: due note ascendenti morbide (DO-MI, 200ms ciascuna) — 
   "il mentore è arrivato"
5. La prima domanda appare con typing animation (carattere per carattere, 
   30ms/char) — l'IA "sta parlando", non "mostrando"
```

#### Transizione Passo 3 → Passo 4 (Dialogo → Ghost Map)

```
1. Lo studente invoca "Verifica il mio canvas"
2. ANIMAZIONE (1200ms, 3 fasi):
   Fase 1 (0-400ms): il pannello socratico si dissolve
   Fase 2 (400-800ms): un'onda luminosa circolare parte dal centro 
       del canvas e si espande verso i bordi — "scanning"
   Fase 3 (800-1200ms): gli elementi dell'overlay (rosso/giallo/verde/blu)
       appaiono uno per uno con fade-in scaglionato (50ms tra ciascuno)
3. HAPTIC: vibrazione crescente durante l'onda di scanning
4. SUONO: sweep ascendente (200→800Hz, 1s) + "ping" per ogni 
   elemento overlay che appare
5. Lo studente vede la Ghost Map costruirsi gradualmente — 
   non appare tutto insieme
```

#### Transizione Passo 6 — Ritorno (Apertura Canvas Blurrato)

```
1. Lo studente apre il canvas il giorno dopo
2. ANIMAZIONE (1500ms):
   - Il canvas appare completamente blurrato (blur massimo)
   - Il blur si attenua gradualmente al livello calcolato per 
     ogni nodo (differenziale)
   - I nodi emergono come "fantasmi nella nebbia" — prima le sagome, 
     poi i colori, poi il blur calibrato
3. HAPTIC: pulse lento e profondo — "risveglio"
4. SUONO: nota grave bassa che sale lentamente (100→400Hz, 1.5s) — 
   "il Palazzo si sveglia dalla notte"
5. Il percorso interleaving (sentiero luminoso) appare con 
   trail animation (testa→coda, 2s)
```

#### Transizione Passo 10 — Reveal Finale Fog of War

```
1. Lo studente preme "Termina Fog of War"
2. ANIMAZIONE CINEMATOGRAFICA (3000ms):
   Fase 1 (0-500ms): pausa drammatica — lo schermo si ferma
   Fase 2 (500-2500ms): la nebbia si dissolve dal CENTRO verso 
       i BORDI con effetto radiale — come un sole che sorge
   Fase 3 (2500-3000ms): l'heatmap (verde/rosso/grigio) 
       appare in dissolvenza
3. HAPTIC: crescendo vibrazionale parallelo alla dissoluzione 
   (leggero → medio → forte al momento dell'heatmap)
4. SUONO: accordo musicale che si "apre" (triade minore → maggiore, 
   3s) — dal dubbio alla rivelazione
5. Pausa di 2s dopo la completa rivelazione — lo studente GUARDA 
   prima che il sommario appaia
```

---

### A13.3 — Sistema Haptic Unificato

Un vocabolario tattile coerente in tutta l'app. Lo studente impara a "sentire" cosa sta succedendo:

| Pattern Haptic | Nome | Quando si Usa | Implementazione |
|----------------|------|--------------|-----------------|
| **Tap leggero singolo** | "Conferma" | Primo tratto su zona vergine (P1-05), selezione opzione, navigazione | `UIImpactFeedbackGenerator(.light)` |
| **Tap medio singolo** | "Azione" | Attivazione Recall Mode, invocazione IA, dismiss overlay | `UIImpactFeedbackGenerator(.medium)` |
| **Doppio tap leggero** | "Arrivo" | L'IA ha generato la domanda, la Ghost Map è pronta | `.light` × 2 con 100ms gap |
| **Vibrazione crescente** | "Scanning" | Onda di analisi nella Ghost Map, elaborazione in corso | Rampa da `.light` a `.heavy` su 1s |
| **Pulse lento** | "Risveglio" | Apertura canvas blurrato (Passo 6), ritorno SRS | `.medium` lento: 500ms on, 500ms off, × 2 |
| **Buzz breve** | "Errore dolce" | Recall sbagliato, tentativo di peek esaurito | `UINotificationFeedbackGenerator(.error)` ma attenuato |
| **Tap triplo rapido** | "Successo" | Recall corretto, nodo padroneggiato, Fog of War >90% verde | `.light` × 3 con 50ms gap |
| **Nessun haptic** | "Silenzio" | Passo 1 scrittura pura, Passeggiata nel Palazzo, Passo 11 | Il silenzio tattile è intenzionale |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-01 | Gli haptic sono **sempre disabilitabili** nelle impostazioni | Toggle globale: "Feedback tattile: On/Off". Default: On |
| A13-02 | Gli haptic non si attivano MAI durante la **scrittura attiva** (tratto in corso) | Nessun haptic dal touchdown al touchup della penna. Solo tra i tratti |
| A13-03 | Il vocabolario haptic è **coerente**: lo stesso pattern significa sempre la stessa cosa | Mai usare "Successo" per un'azione neutra, mai "Errore" per un feedback positivo |

---

### A13.4 — Sound Design

Il suono in Fluera è **quasi assente** — ma precisamente calibrato nei pochi momenti dove appare:

| Momento | Suono | Durata | Volume | Rationale |
|---------|-------|--------|--------|-----------|
| **Cambio strumento** (P1-20) | Click meccanico morbido — diverso per ogni strumento (penna: "click", gomma: "swish", evidenziatore: "pop") | 100ms | 20% del volume sistema | Feedback senza distrazione — lo studente sa quale strumento ha senza guardare |
| **Attivazione Recall Mode** | Tono basso singolo (200Hz sinusoide, attack lento) | 300ms | 15% | "Sipario che scende" — cambio di stato |
| **IA arriva** (Passo 3) | Due note ascendenti (DO4-MI4, piano morbido) | 400ms | 15% | "Il mentore arriva" — non una notifica, una presenza |
| **Reveal nodo** (Passo 6) | Nota singola variabile: DO per ricordato, LA♭ per dimenticato | 200ms | 20% | Feedback tonale del risultato — il verde ha un suono "aperto", il rosso ha un suono "chiuso" |
| **Ghost Map scanning** | Sweep ascendente (synth pad, 200→800Hz) | 1000ms | 10% | Sottofondo durante l'analisi — "l'IA sta esplorando" |
| **Fog of War reveal** | Accordo musicale che si apre (Am → C, strings) | 3000ms | 25% | Il momento più "musicale" dell'app — rivelazione cinematografica |
| **Messaggio "Sei pronto"** (P10-29) | Triade maggiore piena (DO-MI-SOL) con riverbero | 2000ms | 30% | Il punto culminante dell'intero percorso — merita un suono che lo studente ricorderà |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-04 | I suoni sono **sempre disabilitabili** e **rispettano la modalità silenziosa** del dispositivo | Toggle: "Effetti sonori: On/Off". In modalità silenziosa: 0 suoni |
| A13-05 | **Nessun suono** durante la scrittura attiva — stessa regola degli haptic | Il Flow non viene mai interrotto da suoni generati dall'app |
| A13-06 | I suoni sono **tutti pre-caricati** all'avvio — nessun ritardo al primo trigger | Cache audio: tutti i sample caricati in RAM all'avvio (budget: ≤2MB) |
| A13-07 | L'intensità dei suoni è **proporzionale** all'importanza del momento | Il click del cambio strumento è quasi inudibile. Il reveal della Fog of War è l'unico momento "forte" |

---

### A13.5 — Animazioni di Caricamento (IA Thinking)

Quando l'IA elabora (Passo 3: domanda, Passo 4: Ghost Map, Passo 9: ponti), il sistema mostra stati di caricamento che comunicano "attesa attiva" senza creare ansia:

| Passo | Stato di Caricamento | Aspetto | Durata Max |
|-------|---------------------|---------|------------|
| **3** — Domanda socratica | **3 punti pulsanti** disposti orizzontalmente nella bolla IA, con un ritmo lento e "respirante" | I punti oscillano in opacità (30%→100%→30%) in sequenza, come un'onda. Colore: indaco morbido | 3s |
| **4** — Ghost Map | **Onda radiale** che parte dal centro del canvas e si espande verso i bordi, ripetendosi | L'onda è semi-trasparente (opacità 15%), colore dorato. Comunica "scanning in corso" spazialmente | 8s |
| **9** — Ponti cross-dominio | **Linee punteggiate esplorative** che si disegnano tra le zone e poi svaniscono, come se l'IA stesse "cercando connessioni" | Le linee appaiono e scompaiono randomicamente tra zona e zona. Colore: dorato tenue | 10s |
| **10** — Domanda esaminatore | Stessi **3 punti** del Passo 3 ma con colore ambra (contesto "esame") | Pattern identico al Passo 3 ma colore ambra distingue il contesto | 5s |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-08 | Gli stati di caricamento sono **sempre interrompibili** — lo studente può annullare in qualsiasi momento | Bottone "✕" discreto accanto all'animazione. Annullamento in ≤200ms |
| A13-09 | Le animazioni di caricamento sono **non-bloccanti** — lo studente può continuare a navigare/scrivere sul canvas | L'animazione è un layer overlay. Il canvas resta interattivo sotto |
| A13-10 | Se il caricamento supera il tempo massimo previsto, mostrare un messaggio gentile: "Ci vuole un po' più del solito..." | Mai "Errore". Mai "Timeout". Il tono è paziente |

---

### A13.6 — Onboarding per Passo (Prima Volta)

La prima volta che lo studente attiva un Passo nuovo, il sistema offre un **micro-onboarding** — non un tutorial, ma una singola frase contestuale:

| Passo | Prima Volta — Messaggio | Dove Appare | Comportamento |
|-------|------------------------|-------------|---------------|
| **1** | *Nessuno.* Il canvas vuoto È il messaggio. | — | P1-09 vieta l'onboarding al Passo 1 |
| **2** | "I tuoi appunti sono nascosti. Prova a ricostruire dalla memoria — le lacune sono il punto di partenza." | Toast in alto, opacità 80%, auto-dismiss 5s | Mostrato 1 volta in assoluto. Mai più |
| **3** | "L'IA ti farà solo domande — mai risposte. Più fatichi a rispondere, più il concetto si consoliderà." | Dentro la prima bolla IA, come prefazione | Mostrato 1 volta. La domanda vera segue sotto |
| **4** | "Questa mappa è un confronto, non un giudizio. Ogni nodo rosso è un'opportunità di crescita." | Banner sopra l'overlay, dismissable | Mostrato 1 volta |
| **6** | "Il blur è proporzionale alla tua forza. Più sai, più è sfumato. Prova a ricordare prima di toccare." | Toast in alto, auto-dismiss 5s | 1 volta |
| **7** | "Il tuo canvas è unico — è il TUO palazzo della memoria. Le differenze con gli altri non sono errori." | Toast pre-sessione, P7-28 | 1 volta per sessione sociale |
| **10** | "Questa non è un esame. È una mappa che mostra cosa sai e cosa no — e un piano per colmare le lacune." | Banner pre-Fog of War, dismissable | 1 volta |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-11 | Ogni messaggio di onboarding appare **una sola volta** in tutta la vita dell'app (per quell'utente) | Flag persistente: `onboarding_{step}_shown: true`. Mai ri-mostrare |
| A13-12 | I messaggi sono **dismissable** con un tap o si auto-dismettono in 5s | Non bloccano. Non richiedono azione |
| A13-13 | Il tono è **caldo e rassicurante**, mai didattico o paternalistico | Nessun "Dovresti...", "È importante che...", "Ricorda di...". Solo frasi descrittive |
| A13-14 | Il Passo 1 **non ha onboarding** — il vuoto è pedagogico | Nessun messaggio, toast, o tooltip nella prima sessione di scrittura |

---

### A13.7 — Gestione degli Errori e Stati Vuoti

| Scenario | Comportamento | Tono |
|----------|--------------|------|
| **HTR fallisce** su un nodo (calligrafia illeggibile) | Il nodo appare con un leggero contorno arancione pulsante + icona "✏️" piccola. Al tap: "Non riesco a leggere questo nodo. Vuoi riscriverlo più chiaramente?" | Gentile, non colpevolizzante. "Non riesco a leggere" è colpa dell'IA, non dello studente |
| **LLM non risponde** (timeout cloud) | L'animazione di caricamento si dissolve → messaggio: "L'IA è momentaneamente lenta. Vuoi riprovare o continuare senza?" | Mai "Errore". Mai codici. Due opzioni chiare |
| **Ghost Map ha pochi nodi** (materia troppo semplice o troppo avanzata) | Messaggio: "Ho trovato solo poche differenze. Il tuo canvas è già molto completo, o questo argomento potrebbe richiedere più dettaglio." | Ambiguità onesta — non finge che il risultato sia preciso |
| **Nessun nodo da ripassare** (SRS up to date) | Badge assente nella galleria. Se lo studente apre comunque: "Tutti i nodi sono in ordine. Il prossimo ripasso è previsto per {data}. Vuoi fare una Passeggiata?" | Il suggerimento della Passeggiata è un redirect gentile |
| **Canvas vuoto** al Passo 2 (lo studente non ha scritto nulla al Passo 1) | Il Recall Mode si attiva ma con 0 nodi da blurrare. Messaggio: "Non ci sono ancora appunti in questa zona. Inizia con il Passo 1: scrivi i tuoi appunti." | Redirect costruttivo, non errore |
| **Primo avvio** in assoluto | Il canvas si apre vuoto. Nessun messaggio. Dopo 10s senza azione, un'icona penna sottile (opacità 20%) appare brevemente al centro e svanisce in 2s — l'unico "invito" a iniziare | L'icona è quasi subliminale. Non è un suggerimento, è una "presenza" |

---

### A13.8 — Celebrazioni e Traguardi

Le celebrazioni in Fluera sono **discrete e mai gamificate** — rispettano il Growth Mindset (§12):

| Traguardo | Celebrazione | Cosa NON Fare |
|-----------|-------------|---------------|
| **Primo recall corretto** (Passo 6) | Pulse verde 500ms + haptic "Successo" + niente altro | Niente coriandoli, niente "Bravo!", niente punteggi |
| **Nodo raggiunge Stadio 4 (Padroneggiato)** | La stella dorata appare con un fade-in lento (1s) + haptic leggero + micro-suono (nota alta e breve) | Niente notifica popup. La stella è la celebrazione — silenziosa e permanente |
| **10 nodi padroneggiati** | Il contatore nel sommario cambia colore (grigio → dorato) discretamente | Niente "Achievement unlocked". 0 badge |
| **Primo ponte cross-dominio** (Passo 9) | La freccia dorata appare con un'animazione luminosa (glow pulse 2s) + suono lieve | Niente "Hai scoperto una connessione!". L'azione parla da sé |
| **Fog of War >90% verde** (Passo 10) | Messaggio "Sei pronto per l'esame." + accordo musicale + haptic forte | L'unico momento di celebrazione "forte" di tutta l'app — perché è il traguardo finale |
| **1 anno di canvas** (Passo 12) | Nella timeline appare un'icona 🎂 sulla milestone anniversario. Al tap: metriche dell'anno | L'anniversario è discreto. Lo studente lo scopre solo se naviga la timeline |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-15 | **Zero celebrazioni con testo esclamativo** ("Fantastico!", "Incredibile!", "Wow!") | Il tono è adulto e sobrio. Le parole celebrative più forti consentite: "Solido.", "Pronto.", "Cresciuto." |
| A13-16 | **Zero animazioni celebrative che coprono il canvas** (confetti, fuochi d'artificio, modale a schermo intero) | La celebrazione è sempre nel contesto del canvas — mai sopra di esso |
| A13-17 | La celebrazione più intensa dell'app è il **messaggio "Sei pronto"** del Passo 10. Tutto il resto è più sobrio | Gerarchia celebrativa rispettata: quotidiano < occasionale < traguardo finale |

---

### A13.9 — Il Respiro del Canvas (Micro-Animazioni Ambientali)

Il canvas non è un foglio morto — è un ambiente che reagisce sottilmente alla presenza dello studente:

| Animazione | Dove | Comportamento | Scopo Cognitivo |
|-----------|------|---------------|-----------------|
| **Nodo Zeigarnik pulsante** | Nodi incompleti ("?" o bordo tratteggiato rosso) | Glow pulsante lentissimo: opacità 30%→60%→30%, periodo 4s | §7 — il nodo incompleto "chiama" l'attenzione subconscia |
| **Sentiero luminoso** (Passo 6, 8) | Percorso interleaving tra nodi | Trail animation: la "testa" del sentiero avanza lentamente (1px/s), lasciando una scia che sfuma in 3s | Guida spaziale non verbale — lo studente vede dove andare senza testo |
| **Stella dorata** (Stadio 4) | Nodi padroneggiati | La stella ha un leggero shimmer (variazione luminosità ±10%, periodo 6s) — come un oggetto prezioso | Ancoraggio visivo: i nodi padroneggiati "brillano" sottilmente nel panorama |
| **Ponti dorati** (Passo 9) | Frecce cross-zona | Le frecce dorate hanno particelle che scorrono lungo di esse (velocità 5px/s, opacità 20%) | Dinamismo: le connessioni cross-dominio "vivono" — sono strade con traffico |
| **Nebbia trasparente** (Passo 10) | Canvas in Fog of War | La nebbia ha una texture animata lentissima (noise Perlin, 0.5Hz) — non è un blocco statico, è una nebbia vera | Immersione: la nebbia è un ambiente, non un filtro CSS |

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-18 | Le micro-animazioni ambientali sono **disabilitabili** globalmente ("Animazioni ambientali: On/Off") | Default: On. Gli studenti con bassa tolleranza alle distrazioni possono disabilitarle |
| A13-19 | Le animazioni ambientali usano **≤5% GPU** addizionale | Non devono degradare le performance. Se il frame rate scende sotto 50fps → disabilitazione automatica |
| A13-20 | Le animazioni ambientali **si fermano** quando lo studente sta scrivendo (penna a contatto) | Durante la scrittura: 0 animazioni ambientali. Si riattivano 2s dopo il touchup |
| A13-21 | Le animazioni hanno velocità **molto bassa** (periodi 4-6s) — devono essere percepite subconsciamente, non osservate coscientemente | Se uno studente "nota" l'animazione attivamente, è troppo veloce |

---

### A13.10 — Densità dell'Interfaccia e Spazio Negativo

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A13-22 | Il canvas occupa **≥90% dello schermo** in qualsiasi momento durante i Passi 1-2 | La toolbar e i controlli non occupano mai più del 10% dell'area visiva |
| A13-23 | Le bolle socratiche (Passo 3) occupano **≤30% della larghezza** dello schermo | Il canvas resta dominante anche durante il dialogo IA |
| A13-24 | L'overlay Ghost Map (Passo 4) è a **opacità ≤50%** — il canvas dello studente è sempre il layer primario | L'overlay è un "ospite" visivo, mai il protagonista |
| A13-25 | I messaggi di onboarding, errore e celebrazione sono **sempre** sul bordo superiore o inferiore — mai al centro del canvas | Il centro del canvas è dello studente. Il sistema parla dai margini |
| A13-26 | Tra ogni elemento UI interattivo c'è **almeno 12px di spazio negativo** | L'interfaccia non deve mai sembrare "affollata". Lo spazio vuoto è parte del design |

---

### A13.11 — Transizioni di Modalità (Micro-Feedback)

Quando lo studente entra/esce da una modalità, il canvas comunica il cambio con un **micro-feedback multisensoriale**:

| Transizione | Visivo | Haptic | Suono |
|-------------|--------|--------|-------|
| **Scrittura → Pan/Zoom** | — (fluido, nessun segnale) | — | — |
| **Canvas → Recall Mode** | Blur graduale 800ms | Tap medio | Tono basso 300ms |
| **Recall Mode → Canvas** | De-blur graduale 500ms | Tap leggero | — (silenzio = "libero") |
| **Canvas → Socratico** | Pannello laterale slide-in 600ms | Doppio tap leggero | Due note ascendenti |
| **Socratico → Canvas** | Pannello slide-out 400ms | Tap leggero | — |
| **Canvas → Ghost Map** | Onda radiale + overlay fade-in 1200ms | Vibrazione crescente | Sweep ascendente |
| **Ghost Map → Canvas** | Overlay fade-out 500ms | Tap medio | — |
| **Canvas → Fog of War** | Nebbia animata che copre 1500ms | Pulse lento | Tono grave |
| **Fog of War → Reveal** | Dissoluzione cinematografica 3000ms | Crescendo | Accordo musicale |
| **Canvas → Passeggiata** | Vignetta 10%, toolbar minimizza 1000ms | — (silenzio intenzionale) | — |

---

### A13.12 — Criteri di Accettazione UX Comportamentale

- [ ] **CA-A13-01:** Ogni Passo ha un'identità emotiva distinguibile (colore ambientale, intensità UI)
- [ ] **CA-A13-02:** Transizioni Passo 1→2, 2→3, 3→4, 6 apertura, 10 reveal: animate con tempi specificati
- [ ] **CA-A13-03:** Vocabolario haptic coerente: 8 pattern, nessuna ambiguità d'uso
- [ ] **CA-A13-04:** Haptic e suoni disabilitabili: toggle globale, rispetto modalità silenziosa
- [ ] **CA-A13-05:** 0 haptic e 0 suoni durante scrittura attiva (penna a contatto)
- [ ] **CA-A13-06:** Suoni pre-caricati: 0 ritardo al primo trigger, budget ≤2MB
- [ ] **CA-A13-07:** Loading states: tutti interrompibili, non-bloccanti, gentili nel timeout
- [ ] **CA-A13-08:** Onboarding per Passo: 1 volta sola per messaggio, dismissable, 0 al Passo 1
- [ ] **CA-A13-09:** Errori: tono gentile, 0 codici tecnici, redirect costruttivo
- [ ] **CA-A13-10:** Celebrazioni: 0 testo esclamativo, 0 animazioni a schermo intero, gerarchia rispettata
- [ ] **CA-A13-11:** Micro-animazioni: disabilitabili, ≤5% GPU, si fermano durante la scrittura
- [ ] **CA-A13-12:** Canvas ≥90% schermo durante Passi 1-2, ≥70% durante tutti gli altri
- [ ] **CA-A13-13:** Messaggi di sistema: sempre sui bordi, mai al centro del canvas
- [ ] **CA-A13-14:** Primo avvio: solo icona penna subliminale dopo 10s, nessun altro elemento

---
---

## APPENDICE A14 — Data Model Unificato (Schema SQLite)

### Contesto

I dati del canvas sono referenziati in 8 appendici diverse. Senza uno schema unificato, ogni sviluppatore interpreta la struttura a modo suo. Questa appendice definisce lo schema SQLite **definitivo** — la singola fonte di verità per la persistenza.

---

### A14.1 — Schema delle Tabelle

```sql
-- ═══════════════════════════════════════════════════════════════
-- FLUERA COGNITIVE ENGINE — DATABASE SCHEMA v1.0
-- ═══════════════════════════════════════════════════════════════

-- ─── ZONE (materie / aree del canvas) ───
CREATE TABLE zones (
  zone_id       TEXT PRIMARY KEY,           -- UUID
  title         TEXT,                        -- es. "Termodinamica"
  subject       TEXT,                        -- es. "Fisica"
  level         TEXT,                        -- es. "Primo anno ingegneria"
  created_at    TEXT NOT NULL,               -- ISO-8601
  last_opened   TEXT NOT NULL,               -- ISO-8601
  viewport_x    REAL NOT NULL DEFAULT 0,     -- ultima posizione viewport
  viewport_y    REAL NOT NULL DEFAULT 0,
  viewport_zoom REAL NOT NULL DEFAULT 1.0,
  color_tag     TEXT                          -- colore della zona nella galleria
);

-- ─── TRATTI (ink strokes raw) ───
CREATE TABLE strokes (
  stroke_id     TEXT PRIMARY KEY,            -- UUID
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  node_id       TEXT REFERENCES nodes(node_id),  -- NULL finché non segmentato
  points        BLOB NOT NULL,               -- array binario di {x, y, pressure, tilt, timestamp}
  tool          TEXT NOT NULL,               -- 'pen' | 'highlighter' | 'eraser'
  color         TEXT NOT NULL,               -- hex es. '#000000'
  thickness     REAL NOT NULL,
  bounding_x    REAL NOT NULL,               -- bounding box
  bounding_y    REAL NOT NULL,
  bounding_w    REAL NOT NULL,
  bounding_h    REAL NOT NULL,
  created_at    TEXT NOT NULL,               -- ISO-8601
  is_deleted    INTEGER NOT NULL DEFAULT 0   -- soft delete per event sourcing
);
CREATE INDEX idx_strokes_zone ON strokes(zone_id);
CREATE INDEX idx_strokes_node ON strokes(node_id);

-- ─── NODI (unità semantiche segmentate) ───
CREATE TABLE nodes (
  node_id       TEXT PRIMARY KEY,            -- UUID
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  content_type  TEXT NOT NULL,               -- 'text' | 'drawing' | 'formula' | 'symbol'
  htr_text      TEXT,                        -- output HTR (NULL se drawing/non ancora elaborato)
  htr_latex     TEXT,                        -- output formula (NULL se non formula)
  htr_confidence REAL,                       -- 0.0-1.0
  centroid_x    REAL NOT NULL,
  centroid_y    REAL NOT NULL,
  bounding_x    REAL NOT NULL,
  bounding_y    REAL NOT NULL,
  bounding_w    REAL NOT NULL,
  bounding_h    REAL NOT NULL,
  cluster       TEXT,                        -- nome cluster semantico
  is_ghost      INTEGER NOT NULL DEFAULT 0,  -- 1 se scoperto via Ghost Map (non generato dallo studente)
  tags          TEXT,                        -- JSON array: ["incomplete", "peeked", "verified"]
  created_at    TEXT NOT NULL,
  last_modified TEXT NOT NULL
);
CREATE INDEX idx_nodes_zone ON nodes(zone_id);
CREATE INDEX idx_nodes_cluster ON nodes(cluster);

-- ─── CONNESSIONI (frecce tra nodi) ───
CREATE TABLE connections (
  connection_id TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  from_node_id  TEXT NOT NULL REFERENCES nodes(node_id),
  to_node_id    TEXT NOT NULL REFERENCES nodes(node_id),
  stroke_id     TEXT REFERENCES strokes(stroke_id),  -- tratto freccia originale
  label_htr     TEXT,                        -- etichetta scritta a mano (HTR)
  relation_type TEXT,                        -- 'causes' | 'requires' | 'contrasts' | etc.
  is_cross_zone INTEGER NOT NULL DEFAULT 0,  -- 1 se ponte cross-dominio (Passo 9)
  created_at    TEXT NOT NULL
);

-- ─── SRS DATA (per nodo) ───
CREATE TABLE srs_data (
  node_id         TEXT PRIMARY KEY REFERENCES nodes(node_id),
  stability       REAL NOT NULL DEFAULT 1.0,
  difficulty      REAL NOT NULL DEFAULT 0.5,
  elapsed_days    INTEGER NOT NULL DEFAULT 0,
  scheduled_days  INTEGER NOT NULL DEFAULT 1,
  reps            INTEGER NOT NULL DEFAULT 0,
  lapses          INTEGER NOT NULL DEFAULT 0,
  state           TEXT NOT NULL DEFAULT 'new',  -- 'new'|'learning'|'review'|'relearning'
  stage           INTEGER NOT NULL DEFAULT 1,   -- stadio visivo 1-5
  last_review     TEXT,                         -- ISO-8601
  next_review     TEXT,                         -- ISO-8601
  desired_retention REAL NOT NULL DEFAULT 0.90,
  is_hypercorrection INTEGER NOT NULL DEFAULT 0,
  peek_count      INTEGER NOT NULL DEFAULT 0,
  hint_count      INTEGER NOT NULL DEFAULT 0
);

-- ─── REVIEW HISTORY (log di ogni ripasso) ───
CREATE TABLE review_history (
  review_id     TEXT PRIMARY KEY,
  node_id       TEXT NOT NULL REFERENCES nodes(node_id),
  reviewed_at   TEXT NOT NULL,               -- ISO-8601
  verdict       TEXT NOT NULL,               -- 'correct' | 'incorrect' | 'partial'
  response_time_ms INTEGER,                  -- tempo di risposta in ms
  confidence    INTEGER,                     -- 1-5 confidenza auto-valutata
  was_peeked    INTEGER NOT NULL DEFAULT 0,
  hints_used    INTEGER NOT NULL DEFAULT 0,
  zoom_needed   INTEGER NOT NULL DEFAULT 0,  -- 1 se ha dovuto zoomare (malus)
  old_stability REAL,
  new_stability REAL,
  old_stage     INTEGER,
  new_stage     INTEGER
);
CREATE INDEX idx_reviews_node ON review_history(node_id);

-- ─── EVENTI (event sourcing per Time Travel) ───
CREATE TABLE events (
  event_id      TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  timestamp     TEXT NOT NULL,               -- ISO-8601
  event_type    TEXT NOT NULL,               -- 'stroke_added' | 'stroke_erased' | 'node_created'
                                             -- | 'connection_added' | 'srs_review' | 'ghost_map'
                                             -- | 'session_start' | 'session_end' | 'step_changed'
  data          TEXT NOT NULL                -- JSON payload specifico per evento
);
CREATE INDEX idx_events_zone_time ON events(zone_id, timestamp);

-- ─── SNAPSHOT (checkpoint periodici) ───
CREATE TABLE snapshots (
  snapshot_id   TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  created_at    TEXT NOT NULL,
  event_count   INTEGER NOT NULL,            -- quanti eventi sono inclusi
  data          BLOB NOT NULL                -- stato completo serializzato (binary)
);
CREATE INDEX idx_snapshots_zone ON snapshots(zone_id);

-- ─── SESSIONI (tracciamento sessioni di studio) ───
CREATE TABLE sessions (
  session_id    TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  step          INTEGER NOT NULL,            -- 1-12 passo corrente
  started_at    TEXT NOT NULL,
  ended_at      TEXT,
  duration_ms   INTEGER,
  nodes_created INTEGER NOT NULL DEFAULT 0,
  nodes_recalled INTEGER NOT NULL DEFAULT 0,
  nodes_forgotten INTEGER NOT NULL DEFAULT 0,
  tracking      INTEGER NOT NULL DEFAULT 1   -- 0 per Passeggiata (A10)
);

-- ─── ONBOARDING FLAGS ───
CREATE TABLE onboarding (
  key           TEXT PRIMARY KEY,            -- es. 'step_2_shown', 'step_3_shown'
  shown_at      TEXT NOT NULL                -- ISO-8601
);

-- ─── MODELLI IA (versioning) ───
CREATE TABLE ai_models (
  model_id      TEXT PRIMARY KEY,            -- es. 'htr_text_v1', 'stroke_classifier_v2'
  model_type    TEXT NOT NULL,               -- 'stroke_classifier' | 'text_recognizer' | 'formula_recognizer' | 'embeddings'
  version       TEXT NOT NULL,
  file_path     TEXT NOT NULL,               -- path locale al modello
  file_size     INTEGER NOT NULL,
  installed_at  TEXT NOT NULL,
  is_active     INTEGER NOT NULL DEFAULT 1   -- solo 1 modello attivo per tipo
);
```

---

### A14.2 — Relazioni tra Tabelle

```
zones ──┬── strokes ──── nodes ──── srs_data
        │                  │              │
        │                  ├── connections │
        │                  │              │
        ├── events         └── review_history
        │
        ├── snapshots
        │
        └── sessions
```

---

### A14.3 — Regole di Integrità

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A14-01 | Ogni stroke appartiene a **esattamente una zona** | FK zone_id NOT NULL |
| A14-02 | Un nodo può avere **0 o più strokes** (un nodo Ghost Map non ha strokes) | node_id nullable su strokes |
| A14-03 | Ogni nodo ha **esattamente un record SRS** (creato alla segmentazione) | 1:1 tra nodes e srs_data |
| A14-04 | Le connessioni cross-zona hanno `is_cross_zone = 1` e collegano nodi di zone diverse | Validazione: `from_node.zone_id ≠ to_node.zone_id` se `is_cross_zone = 1` |
| A14-05 | I soft-delete (`is_deleted = 1`) non vengono mai eliminati fisicamente — servono per il Time Travel | Il garbage collector elimina solo strokes più vecchi di 2 anni |
| A14-06 | Le transazioni di scrittura usano **WAL mode** per non bloccare le letture | `PRAGMA journal_mode = WAL;` all'apertura |

---

### A14.4 — Criteri di Accettazione

- [ ] **CA-A14-01:** Schema creato correttamente su primo avvio
- [ ] **CA-A14-02:** Ogni tabella ha gli indici specificati
- [ ] **CA-A14-03:** FK constraints attive (`PRAGMA foreign_keys = ON`)
- [ ] **CA-A14-04:** WAL mode: letture e scritture concorrenti senza lock
- [ ] **CA-A14-05:** Migrazione schema: versionamento DB con `PRAGMA user_version`

---
---

## APPENDICE A15 — State Machine dei Passi (Prerequisiti e Gate)

### Contesto

La specifica assume una sequenza lineare 1→12, ma nella realtà lo studente può tentare di saltare passi. Questa appendice definisce la **macchina a stati** che governa quali passi sono disponibili.

---

### A15.1 — Filosofia: Gating Morbido, Mai Bloccante

> [!IMPORTANT]
> Fluera **non blocca mai** lo studente. Se un passo non è "pronto", il sistema lo segnala con un messaggio informativo ma permette comunque l'accesso. La filosofia è: **il sistema consiglia, lo studente decide** (Autonomy T2).

---

### A15.2 — Matrice dei Prerequisiti

| Passo | Prerequisito | Se non soddisfatto | Gate Type |
|-------|-------------|---------------------|-----------|
| **1** | Nessuno | — | 🟢 Sempre disponibile |
| **2** | Zona con ≥5 nodi dal Passo 1 | "Questa zona ha pochi appunti. Vuoi prima scrivere di più?" | 🟡 Soft (consigliato) |
| **3** | Passo 2 completato almeno 1 volta nella zona | "Ti consiglio prima di provare a ricostruire dalla memoria (Passo 2). Vuoi procedere comunque?" | 🟡 Soft |
| **4** | Passo 3 con ≥3 domande risposte | "L'IA non ti ha ancora interrogato su questa zona. Il confronto sarà più utile dopo l'interrogazione. Procedere?" | 🟡 Soft |
| **5** | Automatico (non è un'azione — è il passare del tempo) | — | ⚪ Automatico |
| **6** | ≥24h dall'ultimo Passo 1 o 2 nella zona | "Sono passate solo {N}h. Il ripasso è più efficace dopo almeno 24h di pausa. Vuoi procedere comunque?" | 🟡 Soft |
| **7** | ≥1 sessione di Passo 2 completata + connessione internet | "La collaborazione richiede che tu abbia già fatto almeno un ripasso." / "Connessione internet necessaria." | 🟡 Soft / 🔴 Hard (internet) |
| **8** | ≥1 nodo con `next_review ≤ oggi` | "Non ci sono nodi da ripassare oggi. Il prossimo ripasso è previsto per {data}." | 🔴 Hard (niente da ripassare) |
| **9** | ≥2 zone con ≥10 nodi ciascuna | "I ponti richiedono almeno 2 materie con contenuto sufficiente." | 🟡 Soft |
| **10** | ≥50% dei nodi della zona a Stadio ≥2 | "Troppi nodi sono ancora fragili. Continua con i ripassi SRS prima della Fog of War." | 🟡 Soft |
| **11** | Nessuno (lo studente decide quando è pronto per l'esame) | — | 🟢 Sempre disponibile |
| **12** | Automatico (la timeline esiste dal primo evento) | — | 🟢 Sempre disponibile |

---

### A15.3 — Tipi di Gate

| Tipo | Comportamento | Bypass |
|------|---------------|--------|
| 🟢 **Sempre disponibile** | Nessun messaggio, nessun gate | — |
| 🟡 **Soft (consigliato)** | Messaggio informativo + bottone "Procedi comunque" | Lo studente può sempre procedere. Il messaggio appare **1 volta per sessione** |
| 🔴 **Hard (bloccante)** | Il passo non è attivabile. Messaggio spiega perché | Solo per prerequisiti oggettivi (niente internet, 0 nodi da ripassare) |
| ⚪ **Automatico** | Il passo non richiede azione — il sistema lo gestisce in background | — |

---

### A15.4 — La Macchina a Stati per Zona

Ogni zona mantiene il proprio stato indipendente:

```json
{
  "zoneId": "zone_123",
  "stepHistory": {
    "step_1": {"completedCount": 3, "lastCompleted": "2025-10-15"},
    "step_2": {"completedCount": 2, "lastCompleted": "2025-10-15"},
    "step_3": {"completedCount": 1, "lastCompleted": "2025-10-15"},
    "step_4": {"completedCount": 0},
    "step_6": {"completedCount": 5, "lastCompleted": "2025-11-01"}
  },
  "currentAvailableSteps": [1, 2, 3, 4, 6, 8, 11, 12],
  "suggestedNextStep": 4
}
```

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A15-01 | Ogni zona ha la propria **macchina a stati indipendente** | Lo studente può essere al Passo 8 in Termodinamica e al Passo 2 in Analisi |
| A15-02 | I gate soft mostrano il messaggio **1 volta per sessione** — non ad ogni tap | Flag: `gate_shown_{step}_{session_id}` |
| A15-03 | I passi non si "sbloccano" come livelli di un gioco — sono **tutti visibili** dalla toolbar con indicazione di disponibilità | Icone: piena (disponibile), sfumata (soft gate), grigia con lucchetto (hard gate) |
| A15-04 | Il "passo suggerito" è calcolato automaticamente: il prossimo passo logico nel percorso 1→12 | Suggerimento discreto (highlight leggero sull'icona). Mai popup |
| A15-05 | Lo studente può **ripetere** qualsiasi passo quante volte vuole | Il Passo 2 può essere fatto 100 volte. Non c'è un concetto di "completamento finale" |

---

### A15.5 — Criteri di Accettazione

- [ ] **CA-A15-01:** Gate soft: messaggio informativo + "Procedi comunque", 1 volta per sessione
- [ ] **CA-A15-02:** Gate hard: passo non attivabile, messaggio chiaro del motivo
- [ ] **CA-A15-03:** Stato per zona: zone diverse possono essere a passi diversi
- [ ] **CA-A15-04:** Tutti i passi visibili in toolbar: disponibili, soft gate, hard gate distinguibili
- [ ] **CA-A15-05:** Ripetibilità: 0 limiti sul numero di volte che un passo può essere ripetuto

---
---

## APPENDICE A16 — Privacy, Sicurezza e GDPR

### Contesto

Il canvas contiene la "radiografia cognitiva" dello studente — cosa sa, cosa non sa, dove sbaglia, quanto tempo impiega. Questi sono **dati sensibili** (educational records). Fluera deve trattarli con lo stesso rigore di un'app sanitaria.

---

### A16.1 — Crittografia

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A16-01 | Il database SQLite locale è crittografato **at-rest** con SQLCipher (AES-256) | La chiave è derivata dal passcode del dispositivo o da un secret keychain. Se il dispositivo viene rubato, i dati sono inaccessibili |
| A16-02 | I modelli IA locali **non sono crittografati** (sono file pubblici, non contengono dati studente) | Solo i dati personali sono crittografati, non i pesi dei modelli |
| A16-03 | Le comunicazioni cloud (Ghost Map, ponti, sync) usano **TLS 1.3** | HTTPS obbligatorio. Certificate pinning per le API Fluera |
| A16-04 | I dati inviati al LLM cloud (Passo 4, 9) contengono **solo il grafo semantico anonimizzato** — mai metadati identificativi | Il payload non include: nome studente, email, device ID, zone_id. Solo contenuti concettuali |

---

### A16.2 — Diritti GDPR dello Studente

| ID | Diritto | Implementazione | Soglia Tecnica |
|----|---------|-----------------|----------------|
| A16-05 | **Esportazione dati** (Art. 20 — Portabilità) | Bottone "Esporta i miei dati" nelle impostazioni → genera un archivio ZIP con: tutti i canvas (PDF/SVG), dati SRS (JSON), cronologia review (CSV) | Generazione: ≤30s. Formato leggibile senza Fluera |
| A16-06 | **Cancellazione account** (Art. 17 — Diritto all'oblio) | Bottone "Elimina il mio account" → elimina tutti i dati locali + richiede cancellazione server-side se sync attivo | Cancellazione irreversibile dopo conferma a 2 step. Completata in ≤24h per i dati cloud |
| A16-07 | **Accesso ai dati** (Art. 15) | L'esportazione (A16-05) soddisfa questo requisito | Stessa implementazione |
| A16-08 | **Consenso esplicito** per la sincronizzazione cloud | Prima di attivare il sync, mostrare: "I tuoi appunti verranno salvati sui server Fluera. Puoi disattivare in qualsiasi momento." + checkbox | Consenso opt-in, non opt-out. Revocabile |
| A16-09 | **Consenso esplicito** per l'invio dati al LLM cloud | Prima del primo Passo 4 o 9, mostrare: "Per generare il confronto, i concetti del tuo canvas (non i tuoi appunti originali) verranno elaborati dal nostro servizio IA." + checkbox | Distinguere dal consenso sync. Revocabile. Se revocato: solo modelli locali |

---

### A16.3 — Retention e Cancellazione

| Dato | Retention | Cancellazione |
|------|-----------|--------------|
| Canvas locale | Illimitata (è dello studente) | Solo su richiesta esplicita dell'utente |
| Dati SRS locali | Illimitata | Con il canvas |
| Log eventi (Time Travel) | 2 anni — poi garbage collected | Prima degli eventi, dopo i 2 anni |
| Dati cloud (sync) | Finché l'account esiste | Entro 24h dalla cancellazione account |
| Log API LLM (server-side) | **0 retention** — i payload vengono elaborati e scartati | Le API sono configurate con `no_log: true` — nessun dato studente persiste sui server LLM |
| Analytics anonimizzate (A19) | 1 anno | Aggregate, non ricollegabili all'utente |

---

### A16.4 — Criteri di Accettazione

- [ ] **CA-A16-01:** SQLCipher attivo: database inaccessibile senza chiave
- [ ] **CA-A16-02:** Payload LLM: 0 metadati identificativi (email, nome, device ID)
- [ ] **CA-A16-03:** Esportazione dati: ZIP con PDF + JSON + CSV in ≤30s
- [ ] **CA-A16-04:** Cancellazione account: irreversibile, completata ≤24h cloud
- [ ] **CA-A16-05:** Consensi: 2 consensi separati (sync + LLM), entrambi opt-in e revocabili
- [ ] **CA-A16-06:** Log API LLM: 0 retention server-side verificato

---
---

## APPENDICE A17 — Mapping Tier Abbonamento (Free / Plus / Pro)

### Contesto

La specifica non definisce quali feature cognitive sono disponibili gratuitamente e quali richiedono un abbonamento. Questa appendice mappa ogni funzionalità al suo tier.

---

### A17.1 — Filosofia di Monetizzazione

> [!IMPORTANT]
> **I 12 Passi sono il cuore pedagogico.** Rendere i passi fondamentali (1-6) a pagamento significherebbe vendere l'apprendimento. La monetizzazione si concentra sulle feature **avanzate, collaborative e cloud** — non sulla pedagogia base.

---

### A17.2 — Matrice Feature/Tier

| Feature | Free | Plus | Pro |
|---------|------|------|-----|
| **Passo 1** — Appunti a mano (canvas infinito) | ✅ | ✅ | ✅ |
| **Passo 2** — Recall Mode (blur + ricostruzione) | ✅ | ✅ | ✅ |
| **Passo 3** — Interrogazione Socratica (modello locale) | ✅ (5/giorno) | ✅ (illimitato) | ✅ (illimitato) |
| **Passo 4** — Ghost Map (richiede cloud) | ❌ | ✅ (3/settimana) | ✅ (illimitato) |
| **Passo 5** — Consolidamento notturno | ✅ | ✅ | ✅ |
| **Passo 6** — Primo Ritorno (blur + recall SRS) | ✅ | ✅ | ✅ |
| **Passo 7** — Apprendimento Solidale (P2P) | ❌ | ✅ | ✅ |
| **Passo 8** — Ritorni SRS (micro + deep review) | ✅ | ✅ | ✅ |
| **Passo 9** — Ponti Cross-Dominio (richiede cloud) | ❌ | ❌ | ✅ |
| **Passo 10** — Fog of War | ✅ (1/zona) | ✅ (illimitato) | ✅ (illimitato) |
| **Passo 11** — Passeggiata nel Palazzo | ✅ | ✅ | ✅ |
| **Passo 12** — Time Travel (timeline) | ✅ (30 giorni) | ✅ (1 anno) | ✅ (illimitato) |
| **Sync Cloud** | ❌ | ✅ | ✅ |
| **Esportazione PDF/SVG** | ✅ (1 zona) | ✅ (tutte) | ✅ (tutte) |
| **Modello IA locale avanzato** (7B→13B) | ❌ | ❌ | ✅ |
| **Calibrazione SRS personalizzata** (pesi FSRS custom) | ❌ | ✅ | ✅ |
| **Modalità daltonico + accessibilità avanzata** | ✅ | ✅ | ✅ |
| **Zone** | Max 5 | Max 20 | Illimitate |

---

### A17.3 — Principi di Gating

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A17-01 | Le feature **pedagogiche fondamentali** (Passi 1, 2, 5, 6, 8, 11) sono **sempre gratuite** | Lo studente può apprendere efficacemente senza pagare. I passi a pagamento sono potenziamenti, non prerequisiti |
| A17-02 | Il gate per le feature a pagamento è **trasparente**: lo studente vede cosa potrebbe fare, non viene bloccato silenziosamente | Messaggio: "Questa funzione è disponibile con Plus. [Scopri di più] [Non ora]" |
| A17-03 | Il Passo 3 free è limitato a **5 domande/giorno** — sufficienti per una sessione, non per un uso intensivo | Contatore locale. Reset a mezzanotte. Messaggio: "Hai usato le 5 domande gratuite di oggi. Torneranno domani." |
| A17-04 | La **Fog of War** free è limitata a **1 sessione per zona** — un assaggio che mostra il valore | Dopo la prima: "Per sessioni illimitate di Fog of War, passa a Plus." |
| A17-05 | L'**accessibilità** non è mai a pagamento | Modalità daltonico, tastiera, contrasto: sempre free. L'accessibilità non è un premium |
| A17-06 | Il Passo 3 free usa il **modello locale small** (3B). Plus/Pro possono scegliere tra locale e cloud | Il modello locale è sufficiente per domande socratiche. Il cloud è un upgrade di qualità, non un requisito |

---

### A17.4 — Criteri di Accettazione

- [ ] **CA-A17-01:** Passi 1, 2, 5, 6, 8, 11: funzionanti al 100% senza abbonamento
- [ ] **CA-A17-02:** Gate feature premium: messaggio trasparente, mai blocco silenzioso
- [ ] **CA-A17-03:** Passo 3 free: 5 domande/giorno, contatore visibile, reset a mezzanotte
- [ ] **CA-A17-04:** Accessibilità: 0 feature di accessibilità dietro paywall
- [ ] **CA-A17-05:** Zone free: max 5, messaggio chiaro al raggiungimento del limite

---
---

## APPENDICE A18 — AI Model Lifecycle (Aggiornamento e Migrazione)

### Contesto

I modelli IA (HTR, classificatore, embeddings, LLM locale) sono bundled con l'app. Quando migliorano, devono essere aggiornati senza rompere i dati dello studente.

---

### A18.1 — Strategia di Distribuzione

| Modello | Dimensione | Come si aggiorna | Frequenza |
|---------|-----------|------------------|-----------|
| **Stroke Classifier** (CNN, TFLite) | ~5MB | Bundled con l'app (update app store) | Ogni 2-3 release |
| **Text Recognizer** (TrOCR, ONNX) | ~50MB | Download separato on-demand al primo uso | Ogni 3-6 mesi |
| **Formula Recognizer** (HME-ATT, ONNX) | ~30MB | Bundled con l'app | Ogni 6 mesi |
| **Sentence Embeddings** (MiniLM, ONNX) | ~30MB | Download separato on-demand | Ogni 6 mesi |
| **LLM Locale** (3B-13B, GGUF) | 2-8GB | Download separato, opzionale | Quando disponibile un modello migliore |

---

### A18.2 — Regole di Aggiornamento

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A18-01 | L'aggiornamento modelli avviene **in background** su WiFi — mai su rete cellulare senza consenso | Check: `NetworkInfo.isWifi`. Se cellulare: "Nuovo modello disponibile. Vuoi scaricarlo ora (Xmb)?" |
| A18-02 | Il vecchio modello resta attivo **finché il download del nuovo non è completo** | Swap atomico: vecchio → nuovo solo a download completato e validato |
| A18-03 | Dopo l'aggiornamento di un modello HTR, tutti i nodi vengono **ri-processati in background** | Re-HTR incrementale: rielabora i nodi con il nuovo modello, aggiornando htr_text e htr_confidence |
| A18-04 | Se il re-HTR cambia significativamente il contenuto di un nodo (edit distance >30%), il nodo viene **flaggato** per revisione dallo studente | Messaggio: "Ho migliorato il riconoscimento di alcuni nodi. Vuoi verificarli?" Non modificare automaticamente i dati SRS basati sul vecchio HTR |
| A18-05 | La tabella `ai_models` (A14) traccia versioni e consente **rollback** | Se il nuovo modello degrada le performance, l'utente può tornare al precedente nelle impostazioni avanzate |
| A18-06 | I modelli LLM locali sono **opzionali**: lo studente sceglie se scaricarli | "Modello IA avanzato disponibile (2.1GB). Le domande socratiche saranno più precise. [Scarica]" |

---

### A18.3 — Criteri di Accettazione

- [ ] **CA-A18-01:** Download modelli: solo su WiFi di default, consenso per cellulare
- [ ] **CA-A18-02:** Swap atomico: 0 downtime durante l'aggiornamento
- [ ] **CA-A18-03:** Re-HTR post-update: background, nodi con cambiamento >30% flaggati
- [ ] **CA-A18-04:** Rollback: funzionante da impostazioni avanzate
- [ ] **CA-A18-05:** LLM locale: download opzionale, mai obbligatorio

---
---

## APPENDICE A19 — Metriche di Validazione della Metodologia

### Contesto

Il framework fa promesse scientifiche forti ("apprendimento permanente in 12 passi"). Senza metriche, non sapremo mai se funziona. Questa appendice definisce la telemetria anonimizzata per validare la metodologia.

---

### A19.1 — Filosofia: Misurare senza Sorvegliare

> [!IMPORTANT]
> Le metriche sono **opt-in** e **completamente anonimizzate**. Non raccogliamo: chi è lo studente, cosa studia, cosa scrive. Raccogliamo solo: pattern di apprendimento aggregati. Lo studente può disattivare la telemetria in qualsiasi momento.

---

### A19.2 — Metriche Raccolte

| Metrica | Cosa Misura | Come si Calcola | Granularità |
|---------|------------|-----------------|-------------|
| **Retention Rate** | % di nodi richiamati correttamente al Passo 6/8 | `nodi_corretti / nodi_totali_testati` per sessione | Per sessione, aggregata settimanale |
| **Spacing Effect** | Migliora il recall con intervalli crescenti? | Confronto retention rate tra review a 1g, 3g, 7g, 14g, 30g | Aggregata per bucket temporale |
| **Hypercorrection Effectt** | Il bonus ipercorrezione funziona? | Retention rate dei nodi con `is_hypercorrection=1` vs nodi normali | Aggregata globale |
| **Ghost Map Impact** | La Ghost Map migliora il canvas? | % nodi mancanti riempiti dallo studente dopo il Passo 4 | Per sessione |
| **Socratic Depth** | Quanti livelli di profondità raggiunge il dialogo? | Media domande per sessione socratica, distribuzione tipi (A/B/C/D) | Per sessione |
| **Step Completion** | Quanti studenti completano tutti i 12 passi? | Funnel: % che raggiunge passo N per ciascun N | Aggregata mensile |
| **Stage Distribution** | Come si distribuiscono i nodi sui 5 stadi? | Istogramma stadi (1-5) per utente anonimizzato | Aggregata mensile |
| **Time-to-Mastery** | Quanto tempo serve per portare un nodo da Stadio 1 a Stadio 4? | Mediana giorni `first_review → stage_4` | Aggregata globale |
| **FSRS Accuracy** | L'algoritmo prevede correttamente il recall? | % nodi previsti "ricordati" (R>0.9) che sono effettivamente ricordati | Aggregata per bucket di R |
| **Peek Rate** | Quanto spesso lo studente sbircia? | `peek_count / total_recall_attempts` per sessione | Per sessione |

---

### A19.3 — Formato dei Dati Anonimi

```json
{
  "telemetry_batch": {
    "app_version": "1.2.0",
    "os": "iOS 18",
    "device_class": "tablet",
    "anonymous_id": "sha256(device_id + salt)",
    "events": [
      {
        "type": "review_session",
        "data": {
          "nodes_tested": 15,
          "nodes_correct": 11,
          "nodes_partial": 2,
          "nodes_incorrect": 2,
          "avg_response_ms": 4200,
          "peek_count": 1,
          "hint_count": 3,
          "session_duration_ms": 420000,
          "step": 8
        }
      }
    ]
  }
}
```

**Non contiene:** contenuto dei nodi, testo HTR, posizioni spaziali, nomi di materie, email, nome, device_id raw.

---

### A19.4 — Dashboard di Validazione (Interna)

| Domanda di Ricerca | Metrica Chiave | Target |
|---------------------|----------------|--------|
| "La Productive Failure funziona?" | Retention rate Passo 6 vs baseline (recall senza Passo 2) | ≥15% miglioramento |
| "I Passi 1→6 sono sufficienti senza cloud?" | Retention rate utenti Free vs utenti Plus | Free ≥80% della performance Plus |
| "L'ipercorrezione ha un effetto misurabile?" | Retention nodi ipercorretti vs normali a 30 giorni | ≥20% miglioramento |
| "L'FSRS prevede bene?" | Correlazione tra R previsto e recall effettivo | r ≥ 0.75 |
| "Quanto ci mette per padroneggiare?" | Mediana Time-to-Mastery | ≤45 giorni |
| "Quanti completano il percorso?" | Funnel Step Completion | ≥30% raggiunge Passo 10 |

---

### A19.5 — Regole Etiche

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A19-01 | La telemetria è **opt-in**: disabilitata per default, attivata solo su consenso esplicito | Al primo avvio: "Vuoi aiutarci a migliorare Fluera condividendo statistiche anonime di utilizzo? [Sì] [No]" |
| A19-02 | Lo studente può **disattivare** la telemetria in qualsiasi momento | Toggle nelle impostazioni: "Condividi statistiche anonime: On/Off" |
| A19-03 | I dati sono **aggregati server-side** e non ricollegabili all'utente | L'anonymous_id è un hash di device_id + salt che cambia ogni 90 giorni. Nessun join possibile dopo il cambio |
| A19-04 | **Nessun contenuto** dello studente viene mai trasmesso — solo contatori e metriche | Il payload non contiene: testo, formule, posizioni, nomi di zone |
| A19-05 | I dati aggregati sono usati **solo** per migliorare l'algoritmo e validare la metodologia — mai per profilazione o pubblicità | Policy interna: 0 condivisione con terze parti |

---

### A19.6 — Criteri di Accettazione

- [ ] **CA-A19-01:** Telemetria opt-in: disabilitata di default, consenso esplicito
- [ ] **CA-A19-02:** Toggle disattivazione: funzionante, 0 invii dopo disattivazione
- [ ] **CA-A19-03:** Payload: 0 contenuti studente, 0 testo, 0 posizioni
- [ ] **CA-A19-04:** Anonymous ID: hash con salt rotante ogni 90 giorni
- [ ] **CA-A19-05:** Dashboard interna: retention rate, spacing effect, FSRS accuracy visualizzabili

---
---

## APPENDICE A20 — Edge Case del Mondo Reale (Traduzione della Parte XI)

> Questa appendice traduce le 7 sezioni della **Parte XI** della Teoria Cognitiva dell'Apprendimento ("Il Metodo Incontra il Mondo Reale") in regole implementative concrete con soglie tecniche. Ogni sezione della Parte XI diventa una sotto-appendice con tabelle ✅ DEVE / ❌ NON DEVE e Criteri di Accettazione.

---

### A20.1 — Onboarding: Meta-Apprendimento Esperienziale (da XI.1)

#### Contesto

Lo studente che apre Fluera per la prima volta senza conoscere Ghost Map, slider di confidenza o Fog of War non può usare il sistema. L'onboarding è un **micro-ciclo dei 12 Passi** applicato all'argomento "Come funziona la memoria?". Lo studente impara il metodo *usando* il metodo — non leggendolo.

---

#### A20.1.1 — Il Primo Canvas Guidato

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-01 | Al primo avvio in assoluto, il canvas contiene un **singolo nodo seed al centro**, scritto in stile handwriting (non font digitale): *"Come funziona la memoria?"* | Scaffolding §19 — il seed guida senza strutturare | Il nodo è un'immagine rasterizzata che sembra scritta a mano. Positioned al centro del viewport iniziale. Dimensione: ~300×60px |
| A20-02 | Un **overlay discreto** appare sopra il nodo seed: *"Scrivi tutto quello che sai su come funziona la memoria. Usa la penna. Non c'è una risposta giusta."* | Productive Failure T4 — lo studente scopre di sapere poco | Overlay: sfondo scuro al 60%, testo bianco, dismissable con tap O con il primo tratto di penna. Auto-dismiss al primo touchdown della penna |
| A20-03 | L'overlay **scompare per sempre** al primo tratto di penna — il canvas si comporta come al Passo 1 (silenzioso, reattivo) | Flow §24 — entrare immediatamente nel flusso di scrittura | Flag: `onboarding_overlay_dismissed: true`. Mai ri-mostrato |
| A20-04 | Dopo che lo studente ha scritto (≥3 tratti O ≥30s dall'ultimo tratto), un **secondo indicatore discreto** pulsa nel bordo: *"Vuoi vedere quanto ne sai davvero? Tocca per attivare il test."* | Metacognition T1 — transizione al Passo 3 miniatura | Indicatore: punto luminoso ambra (8px), pulse 2s. Posizione: bordo laterale del canvas. Tocco → attiva il micro Passo 3 |
| A20-05 | L'IA Socratica pone **3-5 domande semplici** sul contenuto scritto dallo studente, usando la meccanica del Passo 3 (bolle ancorate, slider confidenza, risposta a mano) | ZPD §19 — domande al livello dello studente principiante | Le domande sono pre-generate per il topic "memoria": "Hai scritto che ripetere aiuta — ma quale tipo di ripetizione? Rileggere o provare a ricordare?" Max 5 domande |
| A20-06 | Dopo le domande, l'IA mostra una **Ghost Map miniatura** del topic "memoria": sagome rosse per concetti mancanti (Active Recall, Spacing, Generation Effect — semplificati) | Centauro §16 — il primo incontro con la Ghost Map | Max 4-5 sagome rosse. I concetti sono versioni semplificate adatte a qualsiasi studente. Tutto il meccanismo del Passo 4 è attivo |
| A20-07 | Lo studente scrive nelle sagome, tocca per rivelare — scopre la meccanica della Ghost Map organicamente | Generation §3 — l'apprendimento è pratico, non istruttivo | Le sagome funzionano identicamente al Passo 4 (P4-08 → P4-18). Nessuna semplificazione della meccanica |
| A20-08 | Un **overlay finale** appare: *"Quello che hai appena fatto — scrivere, essere interrogato, confrontare, correggere — è il ciclo di Fluera. Da qui in poi, il canvas è tuo. Nessuna guida. Buon viaggio."* | Fading §19 — lo scaffolding si dissolve | Overlay: sfondo scuro al 60%, testo caldo, dismiss con tap. Flag: `onboarding_complete: true`. Da questo momento, il canvas è come descritto nella specifica dei Passi 1-12 |
| A20-09 | L'intero onboarding dura **5-10 minuti**. Nessuna parte è skippable fino al primo overlay (A20-02), ma le fasi successive (Socratica, Ghost Map) sono skippabili | ZPD §19 — non sopraffare al primo contatto | Timer stimato: writing 2-3min, Socratica 2-3min, Ghost Map 2-3min. Bottone "Salta" visibile da A20-04 in poi |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-10 | Mostrare un **tutorial video** o una sequenza di schermate esplicative | Generation §3, Scaffolding §19 | Guardare un video è passivo. Lo studente deve scoprire le feature *usandole* |
| A20-11 | Mostrare **template** o layout pre-costruiti come opzioni di partenza | Desirable Difficulties §5 | I template eliminano la difficoltà desiderabile di organizzare lo spazio |
| A20-12 | Mostrare **tutte le feature** al primo lancio (Fog of War, Ponti, etc.) | Cognitive Load §9 | 3 feature alla volta è il massimo. Le altre emergono progressivamente |
| A20-13 | Rendere l'onboarding **ripetibile** o ri-accessibile dalla UI | Fading §19 | L'onboarding è usa-e-getta. Lo studente non deve poterlo rivivere — il canvas dopo è il suo spazio |

---

#### A20.1.2 — Feature Scoperte Progressivamente (Fading)

Le feature non mostrate nell'onboarding appaiono **quando il contesto le rende rilevanti**:

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-14 | **Fog of War**: appare come opzione la prima volta che lo studente torna a un canvas dopo ≥3 giorni di assenza | Spacing §1, ZPD §19 | Toast: "Vuoi testare la tua memoria su questa zona?" Auto-dismiss 5s. Mostrato 1 volta in assoluto |
| A20-15 | **Blur SRS**: si attiva automaticamente dopo il primo ritorno completato (Passo 6) | Spacing §1 | Nessun messaggio — i nodi si sfumano, lo studente li scopre. Il messaggio di onboarding del Passo 6 (A13-12) spiega |
| A20-16 | **Apprendimento Solidale**: indicatore discreto appare quando lo studente ha ≥1 canvas con ≥20 nodi | Peer Instruction (Mazur) | Indicatore nella toolbar o galleria: "Invita un compagno a visitare". Dismissable, 1 volta |
| A20-17 | **Ponti Cross-Dominio**: disponibili quando esistono ≥2 zone-materia con ≥10 nodi ciascuna | Transfer T3, Interleaving §10 | L'opzione "Suggeriscimi connessioni" appare nella toolbar a zoom panoramico. 1 toast di scoperta |
| A20-18 | **Modalità Esame**: appare 2+ settimane prima di una data esame impostata dallo studente | Spacing §1 | Se lo studente ha impostato una data esame nelle impostazioni della zona, l'opzione "Fog of War" si arricchisce del contesto esame |
| A20-19 | Ogni feature viene presentata con **una singola frase di contesto** e poi diventa silenziosamente disponibile per sempre | Fading §19 | Flag persistente `feature_{name}_discovered: true`. 0 tutorial, 0 video, 0 popup ripetuti |

---

### A20.2 — Flessibilità Temporale: Compressione e Recupero (da XI.2)

#### Contesto

I 12 Passi presuppongono tempo e cadenza ideali. La realtà impone: 5 lezioni consecutive, lavoro part-time, assenze prolungate. Il software deve classificare i passi per criticità temporale e supportare la compressione senza abbandono.

---

#### A20.2.1 — Gerarchia di Criticità Temporale

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-20 | Il sistema classifica ogni passo come 🔴 **Time-Critical**, 🟡 **Semi-Critical** o 🟢 **Flessibile** | Spacing §1, Consolidamento §14 | Classificazione hardcoded nel state machine (A15): Passi 1,2,5 = 🔴; Passi 3,6,8 = 🟡; Passi 4,7,9,10 = 🟢 |
| A20-21 | Quando lo studente tenta un passo **oltre** la finestra temporale accettabile, il sistema mostra un messaggio informativo (non bloccante): *"Questo passo è più efficace entro {X} ore dalla lezione. Vuoi procedere comunque?"* | Spacing §1, Autonomy T2 | Gate soft (🟡 da A15). 1 volta per sessione. Bottone "Procedi comunque" sempre presente |
| A20-22 | Il sistema **non blocca mai** un passo per motivi temporali (tranne Passo 8 se 0 nodi SRS scaduti) | Autonomy T2 | Solo gate soft. Mai hard gate per timing |
| A20-23 | Se lo studente esegue il Passo 2 dopo \>24h (invece che entro la giornata), l'IA SRS adatta automaticamente la curva di oblio — il recall sarà più basso, ma l'esperienza è comunque utile | Spacing §1 | Il parametro `elapsed_days` viene aggiornato. L'SRS non "punisce" — ricalcola |

---

#### A20.2.2 — Compressione dei Passi

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-24 | Il sistema supporta **Micro-Passi**: versioni compresse da 10 minuti dei Passi 2, 3, 6, 8 | ZPD §19, Cognitive Load §9 | Micro-Passo 2: ricostruzione dei soli nodi-chiave (≤10). Micro-Passo 3: 3-5 domande anziché 8-12. Micro-6/8: già definiti come Micro-Review (P8-15) |
| A20-25 | La scelta tra versione completa e versione compressa è dello **studente** — il sistema non auto-comprime | Autonomy T2 | Al momento dell'attivazione: "Sessione completa (~20min)" vs "Sessione rapida (~10min)" |
| A20-26 | I Micro-Passi generano comunque dati SRS validi — la qualità dei dati è proporzionale alla sessione, non degradata | Spacing §1 | I metadati (recall level, confidenza, timing) sono identici alla versione completa |

---

#### A20.2.3 — Recupero dopo Assenza Prolungata

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-27 | Al ritorno dopo un'assenza (≥14 giorni senza apertura), il canvas si apre **senza commenti** — esattamente dove l'aveva lasciato | Growth Mindset §12, Autonomy T2 | 0 messaggi tipo "Sono passati X giorni", 0 badge "Streak rotta", 0 popup di colpa |
| A20-28 | L'SRS **ricalcola silenziosamente** gli intervalli: i nodi decaduti tornano a stabilità bassa e vengono riproposti progressivamente | Spacing §1 | Algoritmo: per ogni nodo con `elapsed_days > scheduled_days * 3`: reset stability a max(0.5, stability * 0.3). Nessun messaggio all'utente |
| A20-29 | Il badge nella galleria mostra il numero di nodi da rivedere come dato **neutro** (non allarmante, non rosso, non con esclamazioni) | Growth Mindset §12 | Badge: numero + "nodi da rivedere". Colore: grigio scuro. Mai rosso. Mai "!" |
| A20-30 | Il sistema propone un **Micro-Review** come primo passo di rientro — 5-10 nodi facili dalla zona comfort dello studente | ZPD §19 | Il primo ritorno dopo assenza è calibrato per il successo: nodi con recall storico ≥3 (più facili). Lo studente rientra con un'esperienza positiva |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-31 | Mostrare **"Sono passati X giorni dalla tua ultima sessione"** | Growth Mindset §12 | Il contatore è un giudizio implicito che genera colpa |
| A20-32 | Mostrare un **"piano di recupero"** automatico (es. "Devi rivedere 150 nodi questa settimana") | Autonomy T2, Cognitive Load §9 | Un piano di recupero massiccio è paralizzante. Il rientro deve essere gentile |
| A20-33 | Richiedere un **"reonboarding"** o tutorial di rientro | Fading §19 | Lo studente sa già come funziona Fluera. Il rientro è: apri, scrivi, ripassa |
| A20-34 | Mostrare **confronti con la performance precedente** (es. "Prima sapevi l'80%, ora il 40%") | Growth Mindset §12 | Il confronto con il sé passato è distruttivo dopo un'assenza |

---

### A20.3 — Contenuti Esterni: Tassonomia a 3 Categorie (da XI.3)

#### Contesto

Lo studente importa foto di libri, PDF di slide, immagini dal web. Ogni contenuto sul canvas appartiene a una di 3 categorie con trattamento visivo e cognitivo distinto.

---

#### A20.3.1 — Le 3 Categorie di Contenuto

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-35 | Il sistema distingue automaticamente **3 categorie** di contenuto: 🟢 Generato (a mano), 🔵 Riferimento (importato dall'esterno), 🔴 IA (output dell'IA) | Generation §3, Levels of Processing §6 | Classificazione basata sull'origine: `inputMethod: handwriting|import|ai` salvato per ogni nodo/tratto |
| A20-36 | Il contenuto **🟢 Generato** (scritto a mano) ha aspetto standard — nessuna distinzione visiva speciale | Generation §3 | È il contenuto "nativo" del canvas. Tutti i principi dei Passi 1-12 si applicano integralmente |
| A20-37 | Il contenuto **🔵 Riferimento** (foto importate, PDF, immagini) ha un aspetto visivamente distinto: **opacità 85%**, **bordo blu sottile** (1px, colore #007AFF opacità 40%), e un piccolo indicatore 📎 nell'angolo | Multimodal Encoding §28 | La distinzione visiva è sottile ma inconfondibile: il contenuto importato è "di supporto", non "il lavoro dello studente" |
| A20-38 | Il contenuto **🔵 Riferimento** **non conta come nodo nel Knowledge Flow e SRS** — l'IA Socratica non lo interroga come se lo studente lo avesse prodotto | Active Recall §2, Generation §3 | Tag: `isReference: true`. L'IA lo usa come contesto ma non genera domande su di esso. L'SRS lo ignora |
| A20-39 | Il contenuto **🔴 IA** segue la Regola d'Oro: l'overlay Ghost Map scompare al dismiss. Solo ciò che lo studente **riscrive a mano** resta come contenuto permanente | Generation §3 | Il contenuto IA non persiste sul canvas. Il tratto dello studente che lo sostituisce diventa 🟢 Generato |
| A20-40 | Il contenuto **incollato** (paste da clipboard) è automaticamente classificato come **🔵 Riferimento** e riceve la stessa distinzione visiva | Generation §3 | Il paste detection è basato su `ClipboardData` / InputEvent type. Il contenuto incollato diventa nodo con `isReference: true` e indicatore visivo |
| A20-41 | L'IA può segnalare **su invocazione** la percentuale di contenuto 🟢 vs 🔵 nella zona: *"Il tuo canvas ha l'80% di materiale importato e il 20% di elaborazione tua — vuoi lavorare sulle zone non elaborate?"* | Metacognition T1 | Disponibile solo su invocazione esplicita. Tono: suggerimento, non giudizio. Mostra la ratio come dato neutro |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-42 | **Impedire** l'importazione di foto, PDF o immagini | Autonomy T2 | Lo studente deve poter organizzare il proprio spazio. L'importazione è legittima come àncora contestuale |
| A20-43 | **Impedire** il paste da clipboard | Autonomy T2 | La libertà di sbagliare è una Difficoltà Desiderabile metacognitiva (vedi XI.4) |
| A20-44 | Trattare il contenuto importato come equivalente al contenuto scritto a mano per l'SRS | Active Recall §2, Generation §3 | Il contenuto importato non ha attivato i canali motorio/propriocettivo — il recall sarà più debole |

---

#### A20.3.2 — Contenuti Speciali: Formule e Testo Digitale

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-45 | Le **formule LaTeX** inserite tramite editor digitale sono classificate come **contenuto ibrido**: la formula digitale è 🔵 Riferimento, ma le annotazioni a mano attorno (diagrammi esplicativi, casi speciali, "cosa significa ogni simbolo") sono 🟢 Generato | Elaborazione §6 | Il nodo-formula ha `contentType: formula_hybrid`. L'SRS traccia solo le annotazioni 🟢 attorno alla formula, non la formula stessa |
| A20-46 | Il **testo digitale** (definizioni verbatim, citazioni) è classificato come 🔵 Riferimento. L'elaborazione a mano attorno è 🟢 Generato | Generation §3 | Il testo digitale è un "segnaposto di precisione" — la comprensione avviene nella rielaborazione a mano |

---

### A20.4 — Stati di Crisi: Il Sistema Protegge, Mai Punisce (da XI.4)

#### Contesto

Il sistema è progettato per sfidare, ma la sfida ha un punto di rottura. Tre scenari critici: il Muro Rosso (troppi nodi dimenticati), l'Abbandono Silenzioso (mesi senza aprire l'app), e il Cheating (copia da ChatGPT).

---

#### A20.4.1 — Gestione del Muro Rosso (>70% nodi rossi)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-47 | Quando la percentuale di nodi rossi in una sessione supera il **70%**, il sistema attiva una **risposta protettiva** | ZPD §19, Growth Mindset §12 | Soglia: `forgotten_nodes / total_nodes > 0.70`. Attivazione per Passi 6, 8, 10 |
| A20-48 | **Riformulazione visiva**: i pochi nodi verdi ricevono un pulse celebrativo discreto. I nodi rossi appaiono con contorno **grigio sfumato** anziché rosso vivo | Growth Mindset §12 | Nodi verdi: pulse verde 500ms (come P2-57). Nodi rossi: colore #888 (grigio) anziché #FF3B30 (rosso). Solo quando protettiva è attiva |
| A20-49 | Il messaggio di sommario è **metacognitivo**, non motivazionale: *"Hai identificato esattamente le {N} zone da rafforzare. Ora sai dove lavorare — la maggior parte degli studenti non lo sa."* | Metacognition T1 | Il messaggio enfatizza il valore diagnostico del fallimento, non il fallimento stesso. 0 parole "fallimento", "errore", "sbagliato" |
| A20-50 | L'SRS **riduce automaticamente** il volume proposto nella prossima sessione: da N nodi a max(10, N×0.3) — i più accessibili (ZPD bassa) | ZPD §19 | Lo studente può espandere manualmente ("Mostra altri nodi") ma il default è gentile |
| A20-51 | Il sistema garantisce che ogni sessione si concluda con **almeno 1 nodo verde** — se necessario, proponendo un nodo dalla zona comfort | ZPD §19, Self-Determination T2 (competence) | Se 0 nodi ricordati: il sistema propone 1 nodo con recall storico ≥4 (facilissimo). Non è falsificazione — è calibrazione della ZPD |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-52 | Mostrare *"Hai sbagliato {N} nodi su {M}"* con enfasi sul numero di errori | Growth Mindset §12 | Focalizzazione sul fallimento. La formulazione corretta è "Hai identificato {N} zone da rafforzare" |
| A20-53 | Mostrare *"Non mollare, ce la puoi fare!"* o motivazione generica | Growth Mindset §12 | Lo studente percepisce la condiscendenza. Il feedback deve essere informativo, non cheerleading |
| A20-54 | Proporre di **abbassare il livello** esplicitamente: "Forse dovresti tornare indietro" | Growth Mindset §12 | L'adattamento è automatico e silenzioso. Non si chiede allo studente di giudicarsi |

---

#### A20.4.2 — Gestione dell'Abbandono Silenzioso

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-55 | Il canvas si riapre dopo qualsiasi assenza **esattamente dove lo studente l'aveva lasciato**, senza commenti | Spatial Cognition §22, Growth Mindset §12 | Viewport position e zoom restaurati. 0 prompt di rientro. Il canvas è l'unico "messaggio" |
| A20-56 | **0 notifiche push** di richiamo — mai, in nessun caso, per nessun motivo | Autonomy T2 | Vedi P5-05, P8-23. La disciplina temporale è dello studente |
| A20-57 | Il canvas come **àncora motivazionale**: il lavoro passato è visibile. La memoria spaziale (§22) riattiva parzialmente i ricordi | Spatial Cognition §22, Extended Mind §29 | Il canvas dopo l'assenza è un Palazzo temporaneamente sfocato — ma il palazzo è ancora in piedi. Più efficace di qualsiasi notifica |

---

#### A20.4.3 — Gestione del Cheating (Copia da IA Esterna)

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-58 | Il contenuto **incollato** (paste) riceve automaticamente una **distinzione visiva sottile**: bordo leggermente diverso (tratteggiato 1px), opacità 90% | Generation §3 | Rilevamento: `ClipboardData.paste`. Non è un "bollino di vergogna" — è una distinzione funzionale. Colore bordo: grigio neutro |
| A20-59 | L'IA Socratica (Passo 3) **ignora** i nodi con `inputMethod: paste` e concentra le domande sui nodi scritti a mano | Active Recall §2 | Flag: `isPasted: true`. L'IA non li interroga. Comunicazione implicita: "l'IA sa che non sono tuoi" |
| A20-60 | Al ripasso SRS (Passi 6, 8, 10), i nodi incollati saranno sistematicamente **rossi** — lo studente non li ricorderà perché non li ha generati | Active Recall §2, Ipercorrezione §4 | I nodi incollati sono nel flusso SRS ma con `initial_stability: 0.3` (molto bassa). Il risultato naturale è il fallimento al recall |
| A20-61 | Il sistema **non mostra mai** un messaggio tipo "Te l'avevo detto" o "Questo nodo era incollato, per questo non lo ricordi" | Autonomy T2 | I nodi rossi parlano da soli. Lo studente trarrà la conclusione autonomamente (Generation Effect applicato alla metacognizione) |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-62 | **Impedire** il copia-incolla o mostrare un popup "Sei sicuro di voler incollare?" | Autonomy T2 | Impedire il paste è paternalistico. La libertà di sbagliare è una Difficoltà Desiderabile metacognitiva |
| A20-63 | **Marcare in rosso o con icone di warning** il contenuto incollato al momento del paste | Growth Mindset §12 | La distinzione è funzionale (bordo diverso), non punitiva (allarme rosso) |

---

### A20.5 — Navigazione a Scala Estrema (da XI.5)

#### Contesto

Un canvas con migliaia di nodi (triennale intera) richiede strumenti di navigazione che non violano la Sovranità Cognitiva — assistono la navigazione senza alterare il contenuto.

---

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-64 | **Minimap**: miniatura always-available (angolo dello schermo) che mostra l'intero canvas a zoom minimo. Le zone-materia sono visibili come regioni colorate | Spatial Cognition §22 | Attivabile con gesto (tap sull'angolo o long-press). Posizione: angolo in basso a destra. Dimensione: ~150×100px. Semi-trasparente (opacità 60%) |
| A20-65 | La minimap è **generata dal canvas** dello studente (non dal sistema): le regioni colorate corrispondono ai cluster di nodi rilevati dalla segmentazione (A6) | Extended Mind §29, Spatial Cognition §22 | I colori sono derivati dai colori prevalenti dei tratti in ogni cluster. I nodi-monumento sono visibili come punti luminosi |
| A20-66 | Tocco sulla minimap → il canvas **naviga istantaneamente** alla posizione corrispondente | Spatial Cognition §22 | Animazione: zoom-out → pan → zoom-in fluido (≤500ms). Touch-to-navigate |
| A20-67 | **Ricerca Spaziale**: lo studente cerca un termine e i risultati appaiono come **punti luminosi nelle posizioni reali** sul canvas — non come lista testuale | Spatial Cognition §22, Extended Mind §29 | Input: campo di ricerca in toolbar. HTR matching: cerca nei `htr_text` dei nodi. Risultati: glow pulsante (#FFD700, opacità 80%, pulse 2s) sulle posizioni dei nodi matching. Max 20 risultati visivi |
| A20-68 | La ricerca offre **navigazione rapida**: tocco su un risultato → il canvas naviga alla posizione del nodo. L'highlight scompare dopo 5s | Spatial Cognition §22 | Navigazione fluida. L'highlight è temporaneo — non altera il canvas |
| A20-69 | **Segnalibri Spaziali**: lo studente può piazzare segnalibri in punti specifici del canvas (posizioni di navigazione rapida) | Spatial Cognition §22, Extended Mind §29 | Gesto: long-press su canvas + "Aggiungi segnalibro" O bottone dedicato. Max 50 segnalibri. Icona: 📍 piccolo, opacità 40%, visibile a qualsiasi zoom |
| A20-70 | I segnalibri sono visibili sulla **minimap** come icone dedicate. Menu rapido mostra lista segnalibri con anteprima | Spatial Cognition §22 | Gesto: tap su icona segnalibro nella toolbar → lista con nome + thumbnail della zona. Tocco → navigazione istantanea |
| A20-71 | Tutti gli strumenti di navigazione **non alterano il canvas** — non riorganizzano, non spostano, non raggruppano automaticamente | Extended Mind §29, Spatial Cognition §22 | Lo spazio resta sacro. Gli strumenti sono "lenti" attraverso cui guardare, non architetti che ristrutturano |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-72 | **Riorganizzare automaticamente** i nodi per "migliorare" il layout a scala | Spatial Cognition §22, Extended Mind §29 | La posizione è un locus nel Palazzo della Memoria — spostarla è come riarredare la casa di qualcuno mentre dorme |
| A20-73 | Mostrare i risultati della ricerca come **lista testuale separata** dal canvas | Spatial Cognition §22 | I risultati devono vivere nel contesto spaziale — non estratti dal contesto |
| A20-74 | **Proporre segnalibri** automaticamente (es. "Vuoi un segnalibro qui?") | Autonomy T2 | I segnalibri sono dello studente. Il sistema non li suggerisce |

---

### A20.6 — Tipi di Conoscenza Diversi (da XI.6)

#### Contesto

Il flusso dei 12 Passi è ideale per conoscenza dichiarativa-concettuale. Questa sezione specifica gli adattamenti per conoscenza procedurale, lingue straniere e matematica pura. Il principio: **il metodo non cambia nei principi — cambia nella forma dei nodi**.

---

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-75 | Il sistema riconosce **3 pattern di organizzazione** dei nodi (non impone — riconosce): Concettuale (grafo), Procedurale (catena sequenziale), Misto | Concept Mapping §27, Levels of Processing §6 | Riconoscimento basato sulla struttura delle connessioni: se \>70% delle connessioni sono sequenziali (from→to in linea), il cluster è "procedurale". Altrimenti "concettuale" |
| A20-76 | Per cluster **procedurali** (programmazione, laboratorio), l'IA Socratica adatta le domande: anziché "spiega cos'è X", chiede *"cosa succede se il passo 3 fallisce?"* o *"in che ordine esegui questi passaggi?"* | Elaborazione §6, Transfer T3 | Il prompt del Passo 3 (A2.2) riceve il `clusterType: procedural` e adatta il tipo di domande |
| A20-77 | Per cluster **procedurali**, la Fog of War chiede allo studente di ricostruire la **sequenza corretta** dei passi — non solo il contenuto dei nodi | Active Recall §2 | La nebbia nasconde i nodi E le frecce sequenziali. Lo studente deve ricostruire sia i passi che l'ordine |
| A20-78 | Per **lingue straniere**, i nodi-vocabolo contengono: la parola nella lingua target + un disegno/associazione visiva (non la traduzione) + frase d'esempio | Generation §3, Multimodal Encoding §28 | L'IA Socratica può condurre micro-dialoghi nella lingua target (Passo 3 adattato). Le domande sono nella lingua studiata |
| A20-79 | Per **matematica**, le dimostrazioni si scrivono linearmente (verticalmente) all'interno di una zona — il canvas non forza la bidimensionalità. Il contesto (teorema sopra, lemmi laterali, applicazioni sotto) è spaziale | Spatial Cognition §22, Elaborazione §6 | L'IA Socratica in matematica chiede: "Quale proprietà stai usando in questo passaggio?" — costringendo l'articolazione del ragionamento implicito |
| A20-80 | La **Ghost Map procedurale** (Passo 4) mostra passi mancanti O passi nell'ordine errato — con sagome rosse posizionate nella sequenza corretta | Centauro §16 | La Ghost Map per cluster procedurali include un campo `order_position` per ogni nodo di riferimento. I nodi in ordine errato ricevono un alone giallo con freccia che indica la posizione corretta |

---

### A20.7 — Modalità Degradata: Device e Contesti Diversi (da XI.7)

#### Contesto

Il setup ideale è tablet + penna + canvas infinito. Ma lo studente studia anche in treno (smartphone), in biblioteca (laptop), e su carta. Il principio: **Genera nel contesto ideale, Richiama in qualsiasi contesto.**

---

#### A20.7.1 — Le 4 Modalità di Utilizzo

#### ✅ DEVE

| ID | Regola | Principio Scientifico | Soglia Tecnica |
|----|--------|----------------------|----------------|
| A20-81 | Il sistema rileva automaticamente il **tipo di device** e adatta la UI: 🖊️ Tablet+Penna, 👆 Tablet/Smartphone touch, ⌨️ Laptop desktop, 📄 Offline (carta → riscrittura) | Embodied Cognition §23 | Detection: `hasStylusSupport` (API platform). Il tipo di device determina quali Passi sono a piena potenza e quali degradati |
| A20-82 | In **Modalità Tattile** (senza penna): i Passi di recall e revisione funzionano pienamente (6, 8, 10). I Passi di generazione (1, 2) mostrano un messaggio discreto: *"La scrittura con il dito funziona, ma la penna è più efficace per la codifica. Vuoi procedere?"* | Embodied Cognition §23, Autonomy T2 | Messaggio: toast 1 volta per sessione. Lo studente può procedere con il dito. I dati SRS sono validi ma con tag `inputMode: touch` (nessun malus ancora — potenzialmente in futuro) |
| A20-83 | In **Modalità Desktop** (tastiera/mouse): la navigazione (pan/zoom), il recall spaziale, la Fog of War, l'IA Socratica funzionano. Le risposte sono digitate anziché scritte a mano | Spatial Cognition §22, Active Recall §2 | Tag: `inputMode: keyboard`. L'IA valuta le risposte digitate con la stessa pipeline HTR-free (testo diretto, no HTR necessario). Il canale motorio è perso ma tutti gli altri principi restano attivi |
| A20-84 | In **Modalità Smartphone**: i Passi di recall SRS (6, 8) funzionano in versione compatta: la navigazione è semplificata (swipe tra nodi anziché pan/zoom granulare). Il Passo 10 è in versione "scroll" | Spacing §1, Active Recall §2 | UI adattiva per schermo piccolo: nodi presentati uno alla volta in modalità card (swipe). Blur + reveal + ✅/❌ funzionano identicamente. Il layout spaziale è preservato nella logica ma linearizzato nella presentazione |
| A20-85 | Il sistema **non blocca** nessun Passo su nessun device. Su device degradato, segnala la perdita di qualità con un messaggio discreto ma permette l'accesso | Autonomy T2 | Gate soft: "Il Passo 1 è più efficace con tablet+penna. Vuoi procedere comunque?" 1 volta per sessione |
| A20-86 | I dati generati in **qualsiasi modalità** sono validi e contribuiscono all'SRS — il recall dal treno con lo smartphone conta come recall | Spacing §1 | Tutti i `inputMode` (pen, touch, keyboard) generano metadati compatibili. L'SRS non discrimina per device |

#### ❌ NON DEVE

| ID | Anti-Pattern | Principio Violato | Perché è Dannoso |
|----|-------------|-------------------|------------------|
| A20-87 | **Bloccare** il Passo 1 su smartphone con messaggio "Usa il tablet" | Autonomy T2 | Meglio 3 righe di appunti con il dito che 0 righe. L'approssimazione funziona (La Regola dell'Imperfetto) |
| A20-88 | **Degradare la qualità SRS** per i recall fatti su dispositivi non ideali | Spacing §1 | Un recall è un recall. Il device cambia la codifica, non il valore del retrieval |
| A20-89 | **Richiedere** di trasferire il lavoro da smartphone a tablet (es. "Completa su tablet") | Autonomy T2, Extended Mind §29 | Il lavoro fatto su un device è completo su quel device. Il sync è automatico e trasparente |

---

### A20.8 — Dati Generati dai Sistemi A20

```json
{
  "onboarding": {
    "completed": true,
    "completedAt": "ISO-8601",
    "microCycleDuration_ms": 420000,
    "socialQuestions": 4,
    "ghostMapNodesRevealed": 3,
    "skipped": false
  },
  "contentTaxonomy": {
    "zone_id": "zone_123",
    "generatedNodes": 45,
    "referenceNodes": 8,
    "pastedNodes": 2,
    "aiNodes": 0,
    "generatedRatio": 0.82
  },
  "crisisEvents": [
    {
      "type": "red_wall",
      "timestamp": "ISO-8601",
      "forgottenRatio": 0.75,
      "protectiveActivated": true,
      "reducedVolume": 10
    }
  ],
  "deviceModes": {
    "pen_sessions": 15,
    "touch_sessions": 8,
    "keyboard_sessions": 3,
    "smartphone_sessions": 12
  }
}
```

---

### A20.9 — Criteri di Accettazione Edge Case Mondo Reale

#### Onboarding (A20.1)
- [ ] **CA-A20-01:** Primo avvio: nodo seed "Come funziona la memoria?" visibile al centro
- [ ] **CA-A20-02:** Primo overlay: scompare al primo tratto di penna, mai riappare
- [ ] **CA-A20-03:** Micro Passo 3: 3-5 domande socratiche funzionanti sul topic "memoria"
- [ ] **CA-A20-04:** Micro Ghost Map: 4-5 sagome rosse con meccanica completa del Passo 4
- [ ] **CA-A20-05:** Overlay finale: messaggio di chiusura, flag `onboarding_complete: true`
- [ ] **CA-A20-06:** Durata totale onboarding: 5-10 minuti, 0 tutorial video
- [ ] **CA-A20-07:** Feature progressive: Fog of War, Blur, Solidale, Ponti appaiono al momento giusto, 1 sola volta

#### Flessibilità Temporale (A20.2)
- [ ] **CA-A20-08:** Gate temporali: soft, dismissable, 1 volta per sessione
- [ ] **CA-A20-09:** Micro-Passi: versioni compresse da ~10min per Passi 2, 3, 6, 8
- [ ] **CA-A20-10:** Rientro dopo assenza: 0 messaggi di colpa, canvas identico, SRS ricalcolato silenziosamente
- [ ] **CA-A20-11:** Primo ripasso post-assenza: calibrato per il successo (nodi facili)

#### Contenuti Esterni (A20.3)
- [ ] **CA-A20-12:** 3 categorie visivamente distinguibili: 🟢 Generato, 🔵 Riferimento (bordo blu, opacità 85%), 🔴 IA (non persiste)
- [ ] **CA-A20-13:** Contenuto incollato: classificato automaticamente come Riferimento
- [ ] **CA-A20-14:** Nodi Riferimento: esclusi dall'IA Socratica e dall'SRS
- [ ] **CA-A20-15:** Ratio generato/importato: disponibile su invocazione, tono neutro

#### Stati di Crisi (A20.4)
- [ ] **CA-A20-16:** Muro Rosso (\>70% rossi): risposta protettiva attivata (grigio anziché rosso, volume ridotto, 1 nodo verde garantito)
- [ ] **CA-A20-17:** 0 messaggi motivazionali generici ("Non mollare!"). Solo feedback metacognitivo
- [ ] **CA-A20-18:** Cheating detection: bordo distinto per contenuto incollato, IA ignora nodi paste, SRS con stabilità bassa
- [ ] **CA-A20-19:** 0 blocchi del paste, 0 popup conferma, 0 "te l'avevo detto"

#### Navigazione a Scala (A20.5)
- [ ] **CA-A20-20:** Minimap: ~150×100px, opacità 60%, touch-to-navigate ≤500ms
- [ ] **CA-A20-21:** Ricerca spaziale: risultati come punti luminosi sulle posizioni canvas, max 20
- [ ] **CA-A20-22:** Segnalibri: max 50, creazione manuale, visibili su minimap, navigazione 1 tap
- [ ] **CA-A20-23:** 0 riorganizzazioni automatiche del layout

#### Tipi di Conoscenza (A20.6)
- [ ] **CA-A20-24:** Cluster procedurali riconosciuti: IA adatta le domande (sequenza, error case)
- [ ] **CA-A20-25:** Ghost Map procedurale: mostra passi mancanti O in ordine errato
- [ ] **CA-A20-26:** Lingue: nodi-vocabolo con disegno, IA in lingua target

#### Modalità Degradata (A20.7)
- [ ] **CA-A20-27:** Detection device automatica: pen, touch, keyboard, smartphone
- [ ] **CA-A20-28:** 0 Passi bloccati su nessun device (solo gate soft)
- [ ] **CA-A20-29:** Smartphone: UI card-based (swipe tra nodi), recall SRS funzionante
- [ ] **CA-A20-30:** Dati da tutti i device contribuiscono all'SRS (0 discriminazione per device)

---

### A20.10 — Schema Database Addizionale

```sql
-- ─── ONBOARDING STATE ───
ALTER TABLE onboarding ADD COLUMN onboarding_complete INTEGER NOT NULL DEFAULT 0;
ALTER TABLE onboarding ADD COLUMN onboarding_completed_at TEXT;

-- ─── CONTENT TAXONOMY (estensione tabella nodes) ───
ALTER TABLE nodes ADD COLUMN input_method TEXT NOT NULL DEFAULT 'handwriting';
  -- 'handwriting' | 'import' | 'paste' | 'ai_generated'
ALTER TABLE nodes ADD COLUMN is_reference INTEGER NOT NULL DEFAULT 0;
ALTER TABLE nodes ADD COLUMN is_pasted INTEGER NOT NULL DEFAULT 0;

-- ─── CRISIS EVENTS ───
CREATE TABLE crisis_events (
  event_id      TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  event_type    TEXT NOT NULL,  -- 'red_wall' | 'absence_return'
  timestamp     TEXT NOT NULL,
  data          TEXT NOT NULL   -- JSON payload
);

-- ─── BOOKMARKS (segnalibri spaziali) ───
CREATE TABLE bookmarks (
  bookmark_id   TEXT PRIMARY KEY,
  zone_id       TEXT NOT NULL REFERENCES zones(zone_id),
  name          TEXT,
  position_x    REAL NOT NULL,
  position_y    REAL NOT NULL,
  zoom          REAL NOT NULL DEFAULT 1.0,
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_bookmarks_zone ON bookmarks(zone_id);

-- ─── DEVICE SESSIONS (tracking modalità device) ───
ALTER TABLE sessions ADD COLUMN input_mode TEXT NOT NULL DEFAULT 'pen';
  -- 'pen' | 'touch' | 'keyboard' | 'smartphone'
ALTER TABLE sessions ADD COLUMN device_class TEXT;
  -- 'tablet_stylus' | 'tablet_touch' | 'phone' | 'desktop'

-- ─── FEATURE DISCOVERY (progressive fading) ───
CREATE TABLE feature_discovery (
  feature_name  TEXT PRIMARY KEY,  -- 'fog_of_war' | 'blur_srs' | 'peer_learning' | 'bridges' | 'exam_mode'
  discovered_at TEXT NOT NULL,
  zone_id       TEXT               -- zona in cui è stata scoperta (se applicabile)
);
```

---
---

## APPENDICE A21 — Integrazione Dizionari Linguistici con il Cognitive Engine

### Contesto

Fluera dispone di un sistema di dizionari multilingua production-grade (**45 lingue**, **916.000+ parole**, **12 sistemi di scrittura**, supporto RTL) composto da 4 servizi:

| Servizio | File | Funzione |
|----------|------|----------|
| `WordCompletionDictionary` | `word_completion_dictionary.dart` | Predizione parole via Trie O(k), frequenza, decay temporale, context canvas, fuzzy matching, ghost suffix |
| `DictionaryLookupService` | `dictionary_lookup_service.dart` | Definizioni, sinonimi, antonimi, etimologia, IPA via Free Dictionary API con cache 3 livelli |
| `PersonalDictionaryService` | `personal_dictionary_service.dart` | Vocabolario personale dello studente con cloud sync |
| `DictionaryLookupSheet` | `dictionary_lookup_sheet.dart` | UI bottom sheet per consultazione definizioni |

Questa appendice specifica come questi servizi — **già implementati** — si integrano con i 12 Passi e le appendici architetturali.

---

### A21.1 — Integrazione con la Pipeline HTR (Estensione di A1)

> Il dizionario diventa il **verificatore post-HTR**: dopo che il modello riconosce il testo, il dizionario conferma o corregge.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-01 | Dopo il riconoscimento HTR (A1.3), ogni parola viene verificata contro il `WordCompletionDictionary` della lingua attiva. Se la parola **non esiste** nel dizionario ma un match fuzzy (edit distance ≤2) esiste, l'HTR propone la correzione | Candidato: `fuzzyMatches(htrWord, limit: 3)`. Se il miglior match ha editDistance ≤2: `htr_text` aggiornato con il match, `htr_confidence` aumenta di +0.15 |
| A21-02 | Se la parola esiste nel `PersonalDictionaryService` (vocabolario custom dello studente), viene **sempre accettata** anche se non esiste nel dizionario standard | Check: `PersonalDictionaryService.instance.contains(word)` → skip correzione. Priorità: Personale > Standard |
| A21-03 | La correzione post-HTR è **silenziosa**: il testo corretto viene salvato nel nodo senza notificare lo studente. Solo se la correzione cambia il significato (edit distance ≥3), viene ignorata — meglio una parola sconosciuta che una correzione errata | Soglia conservativa: edit distance 1 → correggi sempre. Edit distance 2 → correggi solo se confidence HTR <0.7. Edit distance ≥3 → non correggere |
| A21-04 | Le parole specialistiche (termine tecnico non nel dizionario) identificate dal contesto del canvas (`_canvasContext`) vengono suggerite come completamento anche se non nel dizionario standard | Il `WordCompletionDictionary.updateCanvasContext()` già scansiona il canvas e boost le parole presenti. Parole ripetute ≥3 volte sul canvas sono considerate "vocabolario della zona" |

---

### A21.2 — Integrazione con il Matching Ghost Map (Estensione di A3)

> I sinonimi del dizionario arricchiscono il matching semantico senza bisogno del LLM.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-05 | Il Matching Semantico-Spaziale (A3.4) usa i **sinonimi dal DictionaryLookupService** come canale di matching supplementare prima degli embedding vectors | Pipeline di matching ampliata: (1) Match esatto → score 1.0, (2) Match sinonimi dizionario → score 0.85, (3) Match embedding cosine → score variabile. I sinonimi sono un "fast path" on-device che evita la chiamata embedding per parole comuni |
| A21-06 | Quando un nodo dello studente contiene una parola e il nodo di riferimento contiene un suo **sinonimo** (da `result.allSynonyms`), il matching li considera equivalenti con score 0.85 | Esempio: nodo studente "velocità" ↔ nodo ref "rapidità" → match via sinonimo. Nodo studente "calore" ↔ nodo ref "temperatura" → non sinonimi nel dizionario, serve embedding |
| A21-07 | Il matching per sinonimi è **on-device e gratuito** — non richiede cloud, non conta verso i limiti di rate del LLM, funziona offline | I risultati `DictionaryLookupService` sono cached su disco (max 500 voci). Il costo è 1 HTTP call per parola mai cercata prima — successivamente tutto è locale |
| A21-08 | Per ogni nodo mancante nella Ghost Map, se il concetto ha **antonimi** nel dizionario, l'IA può generare domande contrastive migliori: "Hai parlato di X — e il suo opposto?" | Gli antonimi (`result.allAntonyms`) arricchiscono il prompt del Passo 3 (A2.2) quando disponibili. Il tutor li usa come suggerimenti impliciti, non come risposte |

---

### A21.3 — Integrazione con il Tutor Socratico (Estensione di A2)

> Il dizionario fornisce al tutor definizioni formali per sfidare le definizioni imprecise dello studente.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-09 | Quando l'IA Socratica (Passo 3) valuta la risposta (A2.5) e lo studente usa un termine-chiave in modo impreciso, il tutor può far riferimento alla **definizione formale dal dizionario** per generare una domanda di approfondimento | Esempio: lo studente scrive "l'entropia è il disordine". Il tutor (arricchito dalla definizione): "Quando dici 'disordine', cosa intendi esattamente? E come si relaziona con il numero di microstati?" |
| A21-10 | La definizione formale **non viene mai mostrata direttamente** allo studente — viene usata dal LLM come contesto nel prompt per generare domande migliori | Il prompt del Passo 3 include: `[DICT_CONTEXT]: definizione formale di "{termineChiave}": "{definizione}". Usa questa informazione solo per generare domande, MAI per fornire la risposta.` |
| A21-11 | Il `DictionaryLookupSheet` è accessibile dallo studente come azione **esplicita** (long-press su una parola HTR riconosciuta → "Cerca nel dizionario") | Flusso: long-press su nodo → menu contestuale → "📖 Definizione" → apre DictionaryLookupSheet. Disponibile in tutti i Passi. Non è un'azione dell'IA — è un tool dello studente |
| A21-12 | L'**etimologia** (`result.origin`) disponibile dal dizionario è particolarmente utile per le lingue straniere (Passo 7 adattato per lingue, A20.6 A20-78) | Per i nodi-vocabolo in lingua straniera, l'etimologia appare come sezione "Origine" nel DictionaryLookupSheet. L'IA può usarla per creare connessioni: "Sai che 'democracy' viene dal greco δῆμος (demos)?" |

---

### A21.4 — Integrazione con i Ponti Cross-Dominio (Estensione di A7)

> I sinonimi e le polisemie rivelano connessioni lessicali tra zone diverse.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-13 | Il sistema di scoperta ponti (A7) usa i **sinonimi condivisi** come segnale di possibile ponte cross-dominio: se la stessa parola O un suo sinonimo appare in 2+ zone diverse, è un candidato ponte | Algoritmo: per ogni nodo in zona A, per ogni nodo in zona B, se `htr_text_A ∈ allSynonyms(htr_text_B)` → candidato ponte con score = 0.6 (inferiore all'embedding ma complementare) |
| A21-14 | Le **polisemie** (stessa parola, significati diversi) sono segnalate come ponti particolarmente interessanti: "equilibrio" in Fisica (forze) vs "equilibrio" in Economia (mercato) | Il DictionaryLookupService restituisce definizioni multiple per partOfSpeech diversi. Se un termine ha ≥2 `partOfSpeech` distinti E appare in zone di materie diverse → ponte polisemico con score bonus +0.2 |
| A21-15 | Il dizionario funge da **filtro di rumore** per i ponti: parole funzionali ("quindi", "perché", "ogni") che appaiono in tutte le zone sono automaticamente escluse dal matching cross-dominio | Blacklist: le top-100 parole per frequenza nel dizionario corrente (`_frequency.entries.sorted().take(100)`) sono escluse dal matching ponti |

---

### A21.5 — Integrazione con l'Ink Prediction (Passo 1)

> Il ghost suffix predice la parola mentre lo studente scrive a mano — senza violare il Generation Effect.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-16 | Durante il Passo 1 (scrittura), il `WordCompletionDictionary` offre completamenti **ghost suffix** — la parte rimanente della parola appare come testo grigio semitrasparente dopo l'ultimo tratto | Ghost suffix: opacità 20%, colore #888. Non è un suggerimento di contenuto (violerebbe il Generation Effect) — è un completamento ortografico della parola che lo studente sta già scrivendo |
| A21-17 | Il ghost suffix si basa sulla lingua del canvas (auto-detected da `LanguageDetectionService`) e i candidati sono **rankati per frequenza** con boost dal canvas context | Ranking: `effectiveFreq = baseFreq + learnedBoost + canvasContextBoost`. Le parole che lo studente usa spesso e che sono pertinenti al topic corrente appaiono per prime |
| A21-18 | L'accettazione del ghost suffix (tap o continuazione della scrittura in linea) fa un **boost()** nel dizionario — la parola accettata sale di frequenza per le sessioni future | `WordCompletionDictionary.instance.boost(acceptedWord)`. Frequency +3 con timestamp per decay temporale |
| A21-19 | Il ghost suffix è **disattivabile** nelle impostazioni e si disattiva automaticamente durante i Passi 2, 6, 10 (recall/test) | Durante recall: il completamento violerebbe l'Active Recall. Il sistema spegne l'InkPredictionBubble quando `currentStep ∈ {2, 6, 10}` |
| A21-20 | Per le lingue **RTL** (arabo, ebraico, persiano, urdu), il ghost suffix appare a **sinistra** del cursore, non a destra | `WordCompletionDictionary.instance.isRtl` → `TextDirection.rtl` nel `GhostInkPainter`. Il posizionamento x è invertito |

---

### A21.6 — Dizionario Personale e Apprendimento Continuo

> Il dizionario personale è l'estensione del Palazzo della Memoria a livello lessicale.

#### ✅ DEVE

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-21 | Ogni parola che lo studente scrive ≥5 volte e che non esiste nel dizionario standard viene **automaticamente suggerita** per l'aggiunta al `PersonalDictionaryService` | Toast discreto: "Aggiungi '{parola}' al tuo dizionario?" [Sì] [No]. Mostrato 1 volta per parola. La parola aggiunta non verrà più segnalata come errore dall'HTR |
| A21-22 | Il dizionario personale si **sincronizza** tra dispositivi tramite il cloud adapter | `PersonalDictionaryService.setCloudAdapter(adapter, userId)`. Merge union: le parole di entrambi i device sono unite. Nessuna parola viene persa |
| A21-23 | Nella schermata "Esporta i miei dati" (A16-05), il dizionario personale è incluso come **file separato** (`personal_dictionary.json`) | Il file contiene la lista di parole. È un dato dello studente che rientra nella portabilità GDPR |

---

### A21.7 — Performance e Architettura

| ID | Regola | Soglia Tecnica |
|----|--------|----------------|
| A21-24 | I dizionari inline (.dart) forniscono **~50 parole** per avvio istantaneo (0 jank). I dizionari espansi (.txt, fino a 25K parole) vengono caricati in background su **Isolate** | Avvio: ≤1ms (parole inline). Asset loading: ~200ms su isolate (non blocca il main thread). Trie building: ~50ms per 25K parole |
| A21-25 | I Trie non attivi vengono **evicted** dalla RAM dopo 5 minuti di inattività per la lingua | `_evictStaleTries()`: rimuove dalla `_trieCache` le lingue con `lastAccess > 5min`. Risparmio: ~2-8MB RAM per lingua evicted |
| A21-26 | La cache del `DictionaryLookupService` è a **3 livelli**: RAM (64 voci) → Disco (500 voci, JSON) → API (timeout 5s) | Lookup successivi alla stessa parola: ≤1ms (RAM), ~5ms (disco), ~200-500ms (API). 95% dei lookup sono serviti dalla cache |

---

### A21.8 — Schema Database Addizionale

```sql
-- ─── PERSONAL DICTIONARY (già gestito via JSON file, ma referenziato qui) ───
-- Il PersonalDictionaryService usa un file JSON standalone (.fluera_personal_dict.json)
-- Non è in SQLite per semplicità e portabilità.
-- Se in futuro serve query avanzata, migrare a:

-- CREATE TABLE personal_dictionary (
--   word        TEXT PRIMARY KEY,
--   added_at    TEXT NOT NULL,
--   source      TEXT NOT NULL DEFAULT 'manual'  -- 'manual' | 'auto_suggested' | 'cloud_sync'
-- );

-- ─── DICTIONARY CACHE (già gestito via JSON file) ───
-- Il DictionaryLookupService usa un file JSON standalone (dictionary_cache.json)
-- Max 500 voci. Eviction FIFO.

-- ─── ESTENSIONE TABELLA nodes (per tracking sinonimi matching) ───
ALTER TABLE nodes ADD COLUMN synonym_match_source TEXT;
  -- NULL se il nodo non è stato matchato via sinonimo
  -- 'dictionary' se il matching è avvenuto via DictionaryLookupService
  -- 'embedding' se il matching è avvenuto via embedding vectors
```

---

### A21.9 — Criteri di Accettazione Integrazione Dizionari

#### HTR Post-Processing (A21.1)
- [ ] **CA-A21-01:** Correzione post-HTR: parola non in dizionario + fuzzy match (ed ≤2) → correzione silenziosa
- [ ] **CA-A21-02:** Dizionario personale: parole custom accettate dall'HTR senza correzione
- [ ] **CA-A21-03:** Soglia conservativa: ed=1 → correggi sempre, ed=2 → solo se confidence <0.7, ed≥3 → mai
- [ ] **CA-A21-04:** Canvas context: parole ripetute ≥3 volte trattate come vocabolario della zona

#### Ghost Map Matching (A21.2)
- [ ] **CA-A21-05:** Sinonimi dizionario come canale supplementare: score 0.85
- [ ] **CA-A21-06:** Matching on-device: 0 chiamate cloud per match via sinonimi
- [ ] **CA-A21-07:** Antonimi: disponibili come contesto per il tutor, mai come risposta

#### Tutor Socratico (A21.3)
- [ ] **CA-A21-08:** Definizione formale: usata nel prompt, mai mostrata direttamente
- [ ] **CA-A21-09:** Long-press parola → "📖 Definizione" → DictionaryLookupSheet funzionante
- [ ] **CA-A21-10:** Etimologia: visibile nel lookup sheet, usabile dall'IA per connessioni

#### Ponti Cross-Dominio (A21.4)
- [ ] **CA-A21-11:** Sinonimi condivisi tra zone: candidati ponte con score 0.6
- [ ] **CA-A21-12:** Polisemie: bonus score +0.2 per parole con ≥2 partOfSpeech in zone diverse
- [ ] **CA-A21-13:** Filtro rumore: top-100 parole funzionali escluse dal matching ponti

#### Ink Prediction (A21.5)
- [ ] **CA-A21-14:** Ghost suffix: opacità 20%, colore #888, disattivabile
- [ ] **CA-A21-15:** Ghost suffix OFF durante Passi 2, 6, 10 (recall)
- [ ] **CA-A21-16:** RTL: ghost suffix a sinistra per ar, he, fa, ur
- [ ] **CA-A21-17:** Boost su accettazione: frequenza +3 con timestamp

#### Dizionario Personale (A21.6)
- [ ] **CA-A21-18:** Auto-suggest: parola scritta ≥5 volte + non in dizionario → toast 1 volta
- [ ] **CA-A21-19:** Sync cloud: merge union tra dispositivi
- [ ] **CA-A21-20:** Incluso nell'esportazione GDPR (A16-05)

#### Performance (A21.7)
- [ ] **CA-A21-21:** Avvio Trie: ≤1ms (inline), asset loading su Isolate (0 jank main thread)
- [ ] **CA-A21-22:** Eviction Trie inattivi: dopo 5min, ~2-8MB RAM liberati per lingua
- [ ] **CA-A21-23:** Cache lookup: 95% hit rate (RAM + disco), timeout API 5s

---
---

## Riepilogo Finale Aggiornato con Appendici A1-A21

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   📖 SPECIFICA IMPLEMENTATIVA COMPLETA — FLUERA COGNITIVE ENGINE            │
│                                                                             │
│   12 Passi + 21 Appendici Infrastrutturali                                 │
│                                                                             │
│   ┌────────┬────────────────────────────────────┬────────┬──────┐          │
│   │ Passo  │ Nome                               │ Regole │  QA  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │   1    │ Appunti a Mano                     │   48   │  15  │          │
│   │   2    │ Elaborazione Solitaria             │   70   │  28  │          │
│   │   3    │ Interrogazione Socratica           │   50   │  22  │          │
│   │   4    │ Confronto Centauro                 │   39   │  18  │          │
│   │   5    │ Consolidamento Notturno            │    8   │   5  │          │
│   │   6    │ Primo Ritorno (Blur + Recall)      │   21   │  17  │          │
│   │   7    │ Apprendimento Solidale             │   34   │  19  │          │
│   │   8    │ Ritorni SRS                        │   26   │  17  │          │
│   │   9    │ Ponti Cross-Dominio                │   18   │  13  │          │
│   │  10    │ Fog of War                         │   29   │  18  │          │
│   │  11    │ L'Esame                            │   10   │   7  │          │
│   │  12    │ Infrastruttura Permanente          │   11   │   7  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │  A1    │ HTR Pipeline                       │   20   │   9  │          │
│   │  A2    │ Prompt Engineering Socratico       │   11   │   8  │          │
│   │  A3    │ Ghost Map Generation               │   16   │   9  │          │
│   │  A4    │ Network P2P                        │    9   │   8  │          │
│   │  A5    │ Algoritmo SRS (FSRS)               │    6   │   8  │          │
│   │  A6    │ Segmentazione Nodi                 │    5   │   6  │          │
│   │  A7    │ IA Cross-Dominio                   │    5   │   5  │          │
│   │  A8    │ Time Travel                        │    8   │   6  │          │
│   │  A9    │ Meccanismo Pull Ritorni            │    8   │   4  │          │
│   │  A10   │ Passeggiata nel Palazzo            │    7   │   6  │          │
│   │  A11   │ Accessibilità                      │    8   │   6  │          │
│   │  A12   │ Performance su Larga Scala         │   12   │   7  │          │
│   │  A13   │ UX Comportamentale                 │   21   │  14  │          │
│   │  A14   │ Data Model (SQLite)                │    6   │   5  │          │
│   │  A15   │ State Machine dei Passi            │    5   │   5  │          │
│   │  A16   │ Privacy, Sicurezza, GDPR           │    9   │   6  │          │
│   │  A17   │ Tier Abbonamento                   │    6   │   5  │          │
│   │  A18   │ AI Model Lifecycle                 │    6   │   5  │          │
│   │  A19   │ Metriche di Validazione            │    5   │   5  │          │
│   │  A20   │ Edge Case Mondo Reale              │   89   │  30  │          │
│   │  A21   │ Integrazione Dizionari Linguistici │   26   │  23  │          │
│   ├────────┼────────────────────────────────────┼────────┼──────┤          │
│   │ TOTALE │                                    │  594   │ 336  │          │
│   └────────┴────────────────────────────────────┴────────┴──────┘          │
│                                                                             │
│   🔑 L'Unica Regola che Governa Tutti i 12 Passi e le 21 Appendici:       │
│                                                                             │
│   Lo studente deve SEMPRE generare prima di ricevere.                      │
│   In ogni passo — dalla prima riga di appunti all'ultimo                   │
│   ripasso prima dell'esame — lo sforzo cognitivo viene                     │
│   PRIMA, e il feedback viene DOPO.                                         │
│   Invertire quest'ordine annulla il valore di tutto                        │
│   il percorso.                                                             │
│                                                                             │
│   La fatica è il prezzo. La memoria è il premio.                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

