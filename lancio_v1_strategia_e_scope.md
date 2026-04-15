# Fluera v1.0 — Master Plan Completo

**Il paradigma:** Fluera NON è un'app di appunti migliore. È **l'app che ti dice cosa non sai.**

**Il progetto:** 981 file Dart, 403.032 righe di codice, 6 piattaforme native (iOS, Android, macOS, Windows, Linux, Web), GPU rendering Vulkan+WebGPU, 11 shader brush, FSRS, IA Socratica, Ghost Map, Recall Mode, Fog of War, PDF Reader completo, CRDT Collaboration, P2P WebRTC, LaTeX ONNX, Time Travel, GDPR, Enterprise RBAC.

---

## 1. Posizionamento

### Chi è il target

Lo studente nel momento di **massima vulnerabilità**: ha studiato 40 ore, ha preso un voto basso, è pronto ad ammettere che il suo metodo non funziona.

| Target primario | Perché |
|---|---|
| **Studenti di medicina italiani** | Volume enorme di memorizzazione, Anki dominante ma odiato, pagano per tool, parlano tra loro (viral), mercato abbastanza piccolo da non attirare la risposta di GoodNotes |
| **Studenti STEM** | Canvas spaziale perfetto per diagrammi e formule |
| **Studenti di giurisprudenza** | Concettuale + memorizzazione, poche app dedicate |

### La frase

> **"L'app che ti dice cosa non sai."**

### Il posizionamento vs GoodNotes

Non sostituire GoodNotes. Affiancargliti:

> **GoodNotes è dove scrivi. Fluera è dove impari.**

Lo studente tiene GoodNotes per prendere appunti in classe. Poi importa una foto/PDF dei suoi appunti in Fluera e li ricostruisce da zero sul canvas. Switching cost = zero.

---

## 2. Il Gancio Virale (Video 30 Secondi TikTok/Reel)

```
[0-3s]   "Ho preso 18 all'esame di anatomia studiando 40 ore."
[3-5s]   "Poi ho provato questa app."
[5-10s]  Lo studente scrive a mano sul canvas. Veloce, fluido.
[10-15s] Preme 🧠. L'IA fa una domanda. "Sicuro al 90%."
[15-18s] La risposta è SBAGLIATA. Shock rosso. Nodo che pulsa.
[18-22s] "L'app mi ha fatto vedere tutto quello che NON sapevo."
[22-25s] Fast-forward: canvas completo, Fog of War, nodi verdi.
[25-28s] "Stesso esame. 28."
[28-30s] Logo Fluera. "Il tuo voto, costruito con le tue mani."
```

Nessuna menzione di Active Recall o neuroscienze. Solo il **18 che diventa 28**.

### Il viral loop

```
Studente A usa Fluera → Prende voto alto
→ Compagno B chiede "come hai studiato?"
→ A mostra il canvas (visivamente impressionante)
→ B installa Fluera
→ B prende voto alto → C chiede...
```

Acceleratori:
- Condivisione canvas read-only ("guarda cosa ho costruito")
- Statistiche condivisibili ("78% ricostruito da solo dopo 3 sessioni")
- Referral: "Invita un compagno, entrambi 1 mese Pro"

---

## 3. Modello di Business: Il "Taste Model"

### Regola d'oro

Tutto ciò che costa zero (gira in locale) è GRATIS. L'unico paywall è sull'IA (che ha costo API reale).

**MAI paywallare il canvas o la penna.** Il canvas free è il tavolo da gioco — senza tavolo nessuno si siede.

### Tabella Free vs Pro

| Feature | FREE | PRO |
|---|---|---|
| Canvas + penna (3 base) | ✅ Illimitato | ✅ Illimitato |
| PDF/Image import (reference-only 📎) | ✅ Illimitato | ✅ Illimitato |
| Registrazione audio sync | ✅ Illimitato | ✅ Illimitato |
| Recall Mode (Passo 2) | ✅ Illimitato | ✅ Illimitato |
| **FSRS + Fog of War + Notifiche** | **✅ Illimitato** | ✅ Illimitato |
| IA Socratica (Passo 3) | ⚠️ **3 sessioni/settimana** | ✅ Illimitata |
| Ghost Map (Passo 4) | ⚠️ **1 confronto/settimana** | ✅ Illimitata |
| Pennelli | 3 base (pencil, pen, marker) | Tutti gli 11 shader |
| Export | PNG solo | PNG + PDF HD + SVG |

### Prezzi

| Tier | Prezzo |
|---|---|
| Free | €0 |
| Pro Mensile | €5.99/mese |
| Pro Annuale | €39.99/anno (€3.33/mese, sconto 44%) |
| Pro Studente (.edu) | €29.99/anno |

Confronto: GoodNotes Pro €11.99/anno, RemNote ~€96/anno, Anki iOS $24.99 una tantum.

### Il killer upsell moment

```
Lo studente ha finito le 3 sessioni Socratiche della settimana.
L'esame è tra 5 giorni. Vuole farne un'altra. Preme 🧠.

Messaggio: "Hai usato le 3 sessioni di questa settimana.
            Con Pro, l'IA è sempre pronta quando tu lo sei.
            €3.33/mese."
            [Prova 7 giorni gratis]
```

### Costi e margini

| | Costo stimato | Note |
|---|---|---|
| 1 sessione Socratica (~10 domande) | ~€0.02-0.05 | API LLM |
| 1 Ghost Map | ~€0.03-0.08 | API LLM |
| Costo mensile per utente Pro | ~€0.50-1.50 | |
| Ricavo mensile per utente Pro | €3.33-5.99 | |
| **Margine** | **~70-85%** | ✅ Sostenibile |

### Il flusso di conversione

```
1. Scrive appunti gratis (giorno 1)
2. L'FSRS lo fa tornare gratis (giorno 3, 7, 14...)
3. Usa la Socratica gratis — sente lo "shock"
4. Finisce le 3 sessioni la settimana dell'esame
5. Paga perché VUOLE essere interrogato ancora
```

---

## 4. I 12 Passi in v1

| Passo | Nome | v1? | Modulo nel codebase |
|---|---|---|---|
| **1** | Primo Contatto (scrivi) | ✅ | `tools/pen/`, `canvas/` |
| **2** | Ricostruzione (recall) | ✅ | `canvas/ai/recall/` (9 file, 145KB) |
| **3** | Socratica (IA interroga) | ✅ | `canvas/ai/socratic/` (3 file, 45KB) |
| **4** | Ghost Map (confronta) | ✅ | `ghost_map_controller.dart` (34KB) + cache + model |
| **5** | Sonno (consolidamento) | ✅ | Gap temporale naturale |
| **6** | Primo Ritorno (SRS) | ✅ | `fsrs_scheduler.dart` (24KB) + `fog_of_war/` (31KB) |
| **7** | Solidale (collaborazione) | ❌ v2 | `collaboration/`, `p2p/` — richiede infrastruttura server |
| **8** | Ritorni SRS | ✅ | `srs_review_session.dart` (13KB) + stage + pull |
| **9** | Ponti Cross-Dominio | ❌ v2 | `cross_zone_bridge_controller.dart` — troppo presto |
| **10** | Preparazione Esame | ❌ v2 | Non nel primo mese |
| **11** | Esame | ❌ v2 | `exam_session_controller.dart` |
| **12** | Post-Esame | ❌ v2 | Non nel primo mese |

**v1 = Passi 1-6 + 8.** Il ciclo completo che produce risultati.

---

## 5. Feature Matrix Completa

### ✅ SHIP — Presente e attivo in v1

| Modulo | Feature | File principali |
|---|---|---|
| Canvas | Canvas infinito, pan, zoom, pinch | `canvas/` |
| Pen Tool | Scrittura pressure-sensitive | `tools/pen/` (5 file, 100KB) |
| 3 Brush | Pencil, Fountain Pen, Marker | `shaders/pencil_pro.frag`, `fountain_pen_pro.frag`, `marker.frag` |
| Eraser | Gomma | `tools/eraser/`, `canvas/parts/eraser/` |
| Colors | Palette curata | `core/color/` |
| PDF Import | Reference-only (opacità 85%, bordo blu, 📎) | `tools/pdf/`, `native_pdf_provider.dart` |
| Image Import | Foto slide | `tools/image/` |
| PDF Reader | Viewer completo con bookmarks, ricerca, text | `canvas/pdf_reader/` (15 file, 152KB) |
| Audio | Registrazione vocale sincronizzata + tap-to-seek | `audio/` |
| Recall Mode | Passo 2 — ricostruzione da zero | `canvas/ai/recall/` (9 file, 145KB) |
| Socratic AI | Passo 3 — IA che interroga con slider confidenza | `canvas/ai/socratic/` (3 file, 45KB) |
| Ghost Map | Passo 4 — confronto visivo overlay | `ghost_map_controller.dart` + model + cache (47KB) |
| Fog of War | SRS visivo — nodi sfocati | `canvas/ai/fog_of_war/` (2 file, 31KB) |
| FSRS | Algoritmo scheduling best-in-class | `fsrs_scheduler.dart` + `fsrs_calibration.dart` (31KB) |
| SRS Session | Sessioni di ripasso strutturate | `srs_review_session.dart` + stage + pull + due (27KB) |
| Hypercorrection | Shock per errori ad alta confidenza | `hypercorrection_effect.dart` (4KB) |
| Celebration | Feedback visivo positivo | `celebration_controller.dart` + painters (20KB) |
| Step Gate | Orchestrazione dei passi | `step_gate_controller.dart` (19KB) |
| Step Transitions | Animazioni tra i passi | `step_transition_choreographer.dart` (13KB) |
| Learning Steps | Progresso nei passi | `learning_step_controller.dart` (12KB) |
| Onboarding | Walkthrough primo avvio 3 min | `onboarding_controller.dart` + step (14KB) |
| Sound Design | Suoni pedagogici discreti | Da verificare implementazione |
| Tier Gate | Free/Pro gating | `tier_gate_controller.dart` (10KB) |
| Storage | Salvataggio canvas persistente | `storage/` |
| Export | PNG/PDF del canvas | `export/` |
| L10n | Italiano + Inglese | `l10n/` |
| History | Undo/Redo | `history/` |
| Notifications | Ripasso SRS due | `native_notifications.dart` (23KB) |
| Degraded Mode | Fallback se IA non disponibile | `degraded_mode_controller.dart` (9KB) |
| Stylus Input | Nativo su tutte le piattaforme | `native_stylus_input.dart` (15KB) |
| GPU Rendering | Vulkan + WebGPU live stroke | `rendering/gpu/` (10 file) |
| Smart Guides | Allineamento nodi | `canvas/smart_guides/` |
| Scene Graph | Culling, LOD, traversal | `rendering/scene_graph/` |

### ⏳ DEFER — Nascondere dalla UI per v1, sbloccare in v1.5/v2

| Modulo | Perché non v1 |
|---|---|
| Collaboration CRDT + P2P | Passo 7 — richiede server, lo studente è solo al giorno 1 |
| Time Travel | Replay — impressionante ma non essenziale nel primo mese |
| Cross-Zone Bridges | Passo 9 — richiede mesi di canvas |
| Exam Session | Passo 10-11 — non nel primo mese |
| Interleaving Paths | Richiede più zone, troppo presto |
| Passeggiata | Modalità contemplativa — nice-to-have |
| Marketplace | Richiede massa critica utenti |
| Tabular | Tool avanzato |
| Multiview | Complessità UX non necessaria al day 1 |
| 8 Brush avanzati | Watercolor, charcoal, oil, spray, neon, ink wash, texture, stamp → Pro/v2 |
| LaTeX Recognition | ONNX — serve per STEM, non per tutti al lancio |
| Flood Fill | Tool artistico, non pedagogico |
| Enterprise RBAC | B2B è v2 |
| GDPR export/consent/deletion | Preparare per EU ma non è feature utente |
| Knowledge Type | Classificazione — troppo accademico per v1 |
| Content Taxonomy | Backend, non visibile |
| Pedagogical Telemetry | Analytics = v2 |
| Flow Guard | Raffinamento, non core |
| Red Wall | Complessità aggiuntiva |
| Design Comment | Feature collaboration |

---

## 6. Piattaforme e Priorità QA

| # | Piattaforma | Priorità | Device target | Note |
|---|---|---|---|---|
| 1 | **iPad (iOS)** | 🔴 P0 | iPad Air/Pro + Apple Pencil | Il dispositivo primario universale |
| 2 | **Android Tablet** | 🔴 P0 | Samsung Galaxy Tab S + S Pen, Xiaomi Pad | Mercato enorme che GoodNotes serviva male |
| 3 | **Web** | 🟡 P1 | Chrome/Firefox con mouse o touch | Per chi non ha tablet |
| 4 | **Windows** | 🟡 P1 | Surface Pro + penna | Mercato grande |
| 5 | **macOS** | 🟢 P2 | MacBook (trackpad, poca scrittura a mano) | Meno prioritario |
| 6 | **Linux** | 🟢 P2 | Desktop dev | Differenziatore vs GoodNotes (non ha Linux) |

**Vantaggio competitivo:** Live stroke ≤10ms nativo su TUTTE e 6 le piattaforme. GoodNotes ha Metal solo su Apple. Fluera ha Vulkan+WebGPU ovunque.

---

## 7. UI della v1

### Home Screen

```
┌──────────────────────────────────────────┐
│  FLUERA                         ⚙️        │
│                                           │
│  📋 I Tuoi Canvas                        │
│  ┌─────────────────────────────────────┐  │
│  │ 🔴 Anatomia - Lezione 3           │  │
│  │    5 nodi da ripassare oggi        │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ 🟢 Biochimica - Cap. 1            │  │
│  │    Tutto in ordine                 │  │
│  └─────────────────────────────────────┘  │
│  ┌─────────────────────────────────────┐  │
│  │ 🟡 Fisiologia - Lezione 1         │  │
│  │    Recall non ancora fatto         │  │
│  └─────────────────────────────────────┘  │
│                                           │
│              [ + Nuovo Canvas ]           │
│                                           │
│  📊 Questa settimana                     │
│  Nodi creati: 47  Recall: 78%  Streak: 5g│
└──────────────────────────────────────────┘
```

### Canvas Screen — 3 Bottoni Pedagogici

```
┌──────────────────────────────────────────┐
│ ←                        🎤  🧠  👻  ⋮   │
│                                           │
│                                           │
│         Il canvas infinito.               │
│         Lo studente scrive.               │
│                                           │
│                                           │
│ ┌────────────────────────────┐            │
│ │ ✏️ 🖋️ 🖍️ | 🎨 | ⬅️ ➡️  │            │
│ └────────────────────────────┘            │
└──────────────────────────────────────────┘

Header:  ←  |  🎤 Registra  |  🧠 Mettimi alla prova  |  👻 Cosa mi manca?  |  ⋮ Menu
Toolbar: 3 pennelli | colori | undo/redo
```

Lo studente non vede "Passo 2, Passo 3, Passo 4". Vede:
- 🧠 = "Mettimi alla prova" (Recall + Socratica combinati)
- 👻 = "Cosa mi manca?" (Ghost Map)
- 🎤 = "Registra la lezione"

---

## 8. Il Moat Competitivo

Dopo 3 mesi di utilizzo, lo studente ha costruito un **Palazzo della Memoria** — centinaia di nodi scritti a mano, posizionati, collegati, interrogati, revisionati. Questo è il lock-in più potente possibile:

1. **Non è esportabile.** Un canvas spaziale scritto a mano non si trasforma in card Anki o in un documento Word.
2. **È personale.** La calligrafia, le posizioni, i colori — sono del TUO cervello.
3. **Cresce nel tempo.** Più studi, più il canvas è grande, più è difficile lasciare.

| App | Il suo moat |
|---|---|
| GoodNotes | 200 PDF annotati |
| Anki | 5000 card flashcard |
| **Fluera** | **Il Palazzo della Memoria — il tuo cervello su tela** |

---

## 9. Confronto Diretto vs Competitor

| Feature | Fluera v1 | GoodNotes 6 | Anki | RemNote |
|---|---|---|---|---|
| Piattaforme | **6** | 5 (no Linux) | 4 | 3 |
| GPU Rendering | Vulkan+WebGPU | Metal (Apple only) | N/A | N/A |
| Live Stroke ≤10ms | **6 piattaforme** | Solo Apple | N/A | N/A |
| FSRS | ✅ | ❌ proprietario | ✅ | ✅ |
| IA Socratica | ✅ **UNICO** | ❌ | ❌ | ❌ |
| Ghost Map | ✅ **UNICO** | ❌ | ❌ | ❌ |
| Recall Mode | ✅ **UNICO** | ❌ | ❌ | ❌ |
| Fog of War SRS | ✅ **UNICO** | ❌ | ❌ | ❌ |
| PDF Reader | ✅ completo | ✅ | ❌ | ❌ |
| Anti-pattern by design | ✅ | ❌ ha evidenziatore | N/A | N/A |
| Framework pedagogico | 8332 righe | ❌ | ⚠️ SRS only | ❌ |

---

## 10. Timeline di Lancio

| Fase | Durata | Cosa | Output |
|---|---|---|---|
| **Feature Freeze + Taglio** | 2 settimane | Nascondere UI dei DEFER, implementare tier gate Free/Pro | Build pulita v1 |
| **Alpha interna** | 2 settimane | QA su iPad + Android Tablet, crash test, latenza Socratica | App stabile |
| **Beta chiusa** | 3-4 settimane | 10-20 studenti medicina italiani, canvas reali, esami reali | Feedback, testimonial, dati voti |
| **Asset marketing** | 1 settimana | Video TikTok 30s, landing page aggiornata, screenshot App Store | Materiale lancio |
| **Lancio Italia** | D-Day | App Store + Play Store + Web, marketing su canali università | Primi 1000 utenti |
| **Espansione** | 6-12 mesi | Localizzazione EN, target med students globali, sblocco v1.5 (collab, LaTeX) | 10K+ utenti |

---

## 11. Prossimi Passi Operativi (Checklist)

### Fase 1 — Feature Freeze + Taglio (2 settimane)

- [ ] Nascondere dalla UI: Time Travel
- [ ] Nascondere dalla UI: Collaboration / P2P
- [ ] Nascondere dalla UI: Cross-Zone Bridges
- [ ] Nascondere dalla UI: Exam Session
- [ ] Nascondere dalla UI: Marketplace
- [ ] Nascondere dalla UI: Passeggiata
- [ ] Nascondere dalla UI: LaTeX Recognition
- [ ] Nascondere dalla UI: 8 brush avanzati (lasciare in Pro)
- [ ] Nascondere dalla UI: Multiview
- [ ] Nascondere dalla UI: Tabular
- [ ] Configurare `tier_gate_controller.dart`: 3 Socratiche/settimana free
- [ ] Configurare `tier_gate_controller.dart`: 1 Ghost Map/settimana free
- [ ] Implementare messaggio upsell graceful al raggiungimento del limite
- [ ] Configurare pennelli: solo Pencil, Fountain Pen, Marker in free
- [ ] Verificare onboarding flow completo su tablet

### Fase 2 — QA e Stabilizzazione (2 settimane)

- [ ] Test iPad Pro + Apple Pencil: latenza stroke, Socratica, Ghost Map
- [ ] Test Samsung Galaxy Tab S + S Pen: stessa suite
- [ ] Test Web (Chrome): mouse + touch
- [ ] Test Windows Surface Pro: penna
- [ ] Crash test: canvas con 200+ nodi
- [ ] Stress test: FSRS scheduling con 30 giorni simulati
- [ ] Test Socratica: latenza risposta IA < 3 secondi
- [ ] Test Ghost Map: generazione < 5 secondi
- [ ] Test audio sync: tap-to-seek preciso
- [ ] Test PDF import: opacità 85%, bordo blu, non annotabile
- [ ] Test notifiche SRS: arrivano puntualmente
- [ ] Test Degraded Mode: cosa succede se l'API LLM è offline

### Fase 3 — Beta Chiusa (3-4 settimane)

- [ ] Reclutare 10-20 studenti medicina (università italiane)
- [ ] Fornire la v1 su iPad/Android
- [ ] Metriche da tracciare: crash rate, tempo di sessione, conversion free→pro
- [ ] Interviste dopo 2 settimane: "cos'è confuso? cos'è inutile?"
- [ ] Raccogliere testimonial: "prima prendevo X, ora prendo Y"
- [ ] Video testimonial per marketing

### Fase 4 — Lancio

- [ ] Video TikTok/Reel da 30s (script in §2)
- [ ] Aggiornare landing page `fluera-landing/`
- [ ] Screenshot App Store / Play Store
- [ ] Listing con keyword: "studio", "appunti", "esame", "memoria"
- [ ] Post su canali universitari italiani
- [ ] Lancio App Store + Play Store + Web

---

## 12. La Formula Finale

```
FLUERA = Canvas (scrivi) + IA (ti interroga) + FSRS (ti richiama)
       = L'app che ti dice cosa non sai
       = Il tuo voto, costruito con le tue mani
```
