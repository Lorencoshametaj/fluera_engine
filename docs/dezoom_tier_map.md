# Dezoom Tier Map — Canvas Fluera

> Mappa completa del comportamento visivo, pedagogico e tecnico del canvas
> Fluera al variare del livello di zoom. Companion implementativo di
> [teoria_cognitiva_apprendimento.md](../teoria_cognitiva_apprendimento.md):
> ciò che la teoria descrive in prosa, qui è mappato come sistemi, soglie,
> file, e contratti.
>
> Aggiornato: 2026-05-16 — post Fase 1+2+3+4 (mappamondo + ritorno +
> monument nudge + FSRS heat-map + pulizia visiva). Status: **Wired up**
> end-to-end; **device-validated Xiaomi** pending (vedi §11).

---

## 1. Indice

1. [Range zoom + tier overview](#2-range-zoom--tier-overview)
2. [Tier per scala (cosa accade ad ogni soglia)](#3-tier-per-scala)
3. [Layer di rendering (z-order)](#4-layer-di-rendering)
4. [Sistemi paralleli](#5-sistemi-paralleli)
5. [Costanti soglia](#6-costanti-soglia-tabella)
6. [Palette colori](#7-palette-colori)
7. [Animation periods](#8-animation-periods)
8. [Toggle utente (Settings)](#9-toggle-utente)
9. [Mappa pedagogia → implementazione](#10-mappa-pedagogia--implementazione)
10. [Status & verifica](#11-status--verifica)
11. [File map (referenza rapida)](#12-file-map)

---

## 2. Range zoom + tier overview

```
500% ═══════════════════════════════════════════════════════════════════
       TIER 0 — STUDIO MODE
       • LOD 0 KnowledgeFlowPainter (clean connections + badges)
       • DrawingPainter Tier 0 (full quality per-node)
       • Image LOD: full resolution
       • Tutti i decorator ON (glow, halos, network stats)

 50% ─── _lodLevel1Max ─────────────────────────────────────────────────
       TIER 1 — CHUNKING MODE
       • LOD 1 KnowledgeFlowPainter (glassmorphic cluster bubbles + OCR)
       • DrawingPainter Tier mid (polyline simplification 4-step)
       • Image LOD: medium 1024px
       • 🏛️ MONUMENT STROKE PRESERVATION attiva (bypass simplificazione)

 35% ─── aiPreloadScale ────────────────────────────────────────────────
       TIER 2 — PREVIEW WINDOW
       • 🔮 Early title preview: pill flottanti AI/OCR sopra cluster
       • AI title fetch in background (_scheduleSemanticOcr)
       • Super-nodes Union-Find computati
       • Image LOD: thumb 512px

 30% ─── morphStartScale ─── (= COACHMARK TRIGGER mappamondo) ──────────
       TIER 3 — MAPPAMONDO TRANSITION
       • ✨ Semantic morph smoothstep 0→1 (ink fade-out)
       • 🟦 Semantic nodes (glassmorphic circles)
       • 🏛️ Monument boost: +20% padding, +20% glow (NO star badge)
       • 🎨 Zone tints: blob colorati per super-node (hash su zoneLabel)
       • 📍 Monument pills XXL sopra cluster monumenti
       • 🗺️ Zone labels: nomi macro-regioni auto-derivati
       • 🛣️ Cross-zone bridges: strokeW × (1 + 2×morphT) = ~3× a fine
       • 👁️ Signal: notifyMappamondoDezoom() (1×/process)

 25% ─── FsrsHeatMapPainter.kActivationScale ───────────────────────────
       TIER 3.5 — STAGE OVERLAY ENTRY
       • 🌡️ FSRS heat-map ring inizia fade-in (smoothstep 0.30→0.10)
       • Ring colorato per stage (rosso/arancio/verde/amber/azzurro)
       • Cluster monumenti: ring SUPPRESSED (eccetto untouched grigio)

 18% ─── morphEndScale ─────────────────────────────────────────────────
       TIER 4 — FULL SEMANTIC
       • morphProgress = 1.0 (ink completamente sparito)
       • DrawingPainter Tier raster (bounding-box thumbnails batched)
       • Monument strokes ANCORA preservati (full quality on top)

 16% ─── godViewStartScale ─────────────────────────────────────────────
       TIER 5 — GOD VIEW EMERGING
       • 🌍 Super-nodi (Union-Find ≤ 400px merge) fondono cluster vicini
       • Zone tints attenuati 50% (cedono palco ai super-nodi)

 15% ─── _lodLevel1Min ─────────────────────────────────────────────────
       • Image LOD: micro 256px
       • LOD 2 satellite mode in KnowledgeFlowPainter

 10% ═══ godViewEndScale = _minScale (CLAMP UTENTE) ════════════════════
       TIER 6 — MAPPAMONDO FINALE
       • Piena god view: super-nodi tematici dominanti
       • Zone tints + monument pills + cross-zone bridges enfatizzati
       • FSRS ring colorato pieno (alpha 1.0)

  8% ─── _isLowZoom gate (non raggiungibile) ─────────────────────────
       • Sopprime glow/halos/badge/network stats (cosmetic sub-pixel)

Sotto 10% non accessibile via pinch. Solo via bottone 🌍 → fitAllContent.
```

---

## 3. Tier per scala (dettaglio)

### Tier 0 — Studio mode (`scale > 0.50`)

**Cosa vede l'utente:** vista naturale di scrittura. Ogni stroke renderizzato in full quality, connessioni con underline puliti, badge connessioni numerici, network glow ambient.

**Cosa fa il sistema:**
- `DrawingPainter` Tier 0: per-node render via delegate
- `KnowledgeFlowPainter` LOD 0: clean connections + word underlines + connection badges
- Image LOD: piena risoluzione

**Pedagogia:** zona scrittura/elaborazione attiva. Nessuna distrazione di mappamondo.

---

### Tier 1 — Chunking mode (`0.30 < scale ≤ 0.50`)

**Cosa vede l'utente:** zoom medio; i cluster iniziano a diventare visibili come gruppi. Cluster bubbles glassmorphic con testo OCR riconosciuto. Connessioni come linee curve eleganti.

**Cosa fa il sistema:**
- `DrawingPainter` Tier mid: polyline simplification, decimazione 4-step
- `KnowledgeFlowPainter` LOD 1: glassmorphic cluster bubbles
- **🏛️ Monument stroke preservation**: stroke dentro `monumentBounds` saltano la simplificazione, restano full quality (perché monumenti sono landmark riconoscibili anche a basso zoom)

**Pedagogia:** chunking spaziale (§22.8) — il cervello inizia a percepire raggruppamenti naturali.

---

### Tier 2 — Preview window (`0.305 ≤ scale ≤ 0.35`)

**Cosa vede l'utente:** ink ancora visibile, **pill flottanti scuri** appaiono sopra i cluster con il titolo AI/OCR del cluster (in light blue `0xFFB0D4FF`). Smoothstep fade-in da 0.35 (alpha 0) a 0.30 (alpha 1).

**Cosa fa il sistema:**
- `KnowledgeFlowPainter._paintEarlyTitlePreview()`: per ogni cluster con `_clusterTextCache[id]` non vuoto, disegna piccola pill sopra il cluster
- AI title fetch parte in background (`_scheduleSemanticOcr`) se non già pronto
- Super-nodes computati via Union-Find (≤400px merge radius) per essere pronti al morph

**Pedagogia:** "qualcosa sta per cambiare" — affordance pre-morph che riduce il perceptual cliff (§26 zoom semantico).

**Pulizia visiva (Fase 4 Fix 3):** gate `>= morphStartScale + 0.005 = 0.305` invece di `> morphStartScale - 0.001 = 0.299` → preview pill scompare PRIMA che monument pill nasca (no double-pill).

---

### Tier 3 — Mappamondo transition (`0.18 ≤ scale < 0.30`)

**Cosa vede l'utente:** transizione morbida. L'ink sbiadisce progressivamente, al suo posto emergono:
- Nodi semantici glassmorphic con titolo AI (cerchi/RRect colorati)
- Pill scuri XXL con label monumenti sopra i cluster importanti
- Zone tints colorati semi-trasparenti dietro tutto
- Cross-zone bridges (frecce inter-zona) si ingrandiscono fino a ~3× lo spessore normale

**Cosa fa il sistema:**
- `SemanticMorphController.morphProgress` smoothstep da 0 (a 0.30) → 1 (a 0.18)
- `_paintSemanticNodes` con monumenti: `monBoost = 1.20` su padding + glow
- `_paintZoneTints` via Picture cache (replay con saveLayer alpha modulato da `0.08 × morphT × (1 − 0.5 × godT)`)
- `_paintMonumentLabels` rendering pill con `MonumentResolver.monumentIds`
- `_paintZoneLabels` con `ZoneLabel.label` testo
- `_paintConnections` con `crossZoneBonus = 1.0 + 2.0 × morphProgress` su strokeWidth

**Pedagogia:** §22 "Piani del Palazzo" + §26 zoom semantico — l'utente passa da scrittura a vista chunking a vista satellitare.

**Coachmark trigger:** primo dezoom < 0.30 → `CanvasCoachmarkSignals.notifyMappamondoDezoom()` → app-side `CoachmarkEngine.markMappamondoDezoom()` → coachmark "Il tuo Palazzo dall'alto" alla prossima apertura del canvas.

---

### Tier 3.5 — Stage overlay entry (`scale ≤ 0.25`)

**Cosa vede l'utente:** sui cluster normali appaiono **anelli colorati** che indicano lo stage di apprendimento FSRS:
- 🌱 **Rosso** (`0xFFF44336`) — fragile (da rivedere subito)
- 🌿 **Arancio** (`0xFFFF9800`) — growing (in apprendimento)
- 🌳 **Verde** (`0xFF4CAF50`) — solid (consolidato)
- ⭐ **Amber** (`0xFFFFB300`) — mastered (padroneggiato)
- 👻 **Azzurro** (`0xFF90CAF9`) — integrated (long-term memory)
- ⚪ **Grigio** (`0xFF9E9E9E`) — untouched (esiste ma mai studiato)

**Eccezione monumenti:** sui cluster monumento il ring colorato è **soppresso** (Fix 1 Fase 4) perché la pill XXL già comunica "importante". Solo il ring grigio "untouched" resta — letterale §1420 "monumento ma mai studiato = lacuna importante", con extra inflation per stare fuori del semantic node glow.

**Cosa fa il sistema:**
- `FsrsHeatMapPainter` mounted, gated `scale ≤ kActivationScale = 0.25`
- Fade alpha = `smoothstep(0.30, 0.10, scale)` — pieno a scale ≤ 0.10
- `_fsrsClusterStageList()` in canvas screen pre-calcola worst-of stage per cluster (cached con signature `_reviewScheduleStageHash()`)
- Matching: substring `clusterText.contains(concept.toLowerCase())`

**Pedagogia:** §1416-1420 "i nodi rossi vuoti sono la mappa delle lacune". §183 "i nodi verdi nel Confronto Centauro". Vista metacognitiva: le zone arancio/rosse diventano automaticamente il piano di studio della prossima sessione.

---

### Tier 4 — Full semantic (`0.16 ≤ scale < 0.18`)

**Cosa vede l'utente:** ink completamente sparito. Vista pulita di nodi semantici + monumenti + zone tints + ponti d'oro + ring FSRS.

**Cosa fa il sistema:**
- `morphProgress = 1.0` (smoothstep saturato)
- `DrawingPainter` Tier raster (bounding box thumbnails batched per colore)
- **Monument strokes ancora preservati** (DrawingPainter `monumentBounds` bypass)
- `godViewProgress = 0.0` (super-nodi ancora dormienti)

**Pedagogia:** lo studente vede l'**organizzazione spaziale** della sua conoscenza senza il rumore dei tratti individuali. Place cells §22 attivate al massimo.

---

### Tier 5 — God view emerging (`0.10 ≤ scale < 0.16`)

**Cosa vede l'utente:** cluster vicini iniziano a **fondersi** in super-nodi tematici. Zone tints si attenuano del 50% (cedono il palco). I super-nodi appaiono come label XXL tematici (chimica, fisica, biologia).

**Cosa fa il sistema:**
- `SemanticMorphController.godViewProgress` smoothstep da 0 (a 0.16) → 1 (a 0.10)
- `_paintGodView()` rendering super-nodi
- `superNodes = Union-Find merge` su radius 400px canvas-space
- Theme AI: `superNodeThemes` mappa async-fetched

**Pedagogia:** §1133-1138 "Continente della Conoscenza" — emerge la macro-geografia.

---

### Tier 6 — Mappamondo finale (`scale = 0.10`)

**Cosa vede l'utente:** vista satellite della triennale. Pochi super-nodi tematici colorati, monumenti come capitali, ponti oro che attraversano zone, ring FSRS che colorano l'intero canvas per stato apprendimento.

**Cosa fa il sistema:**
- `godViewProgress = 1.0` (clamp utente = limite zoom)
- FSRS ring fade = 1.0 (pieno)
- Tutto in stato semantico finale

**Pedagogia:** §1098 testuale: *"Lo zoom out massimo di Fluera mostra il 'mappamondo' della conoscenza dello studente. A questa scala, si vedono solo le macro-regioni con i loro nomi. È la vista satellite del Palazzo della Memoria. Lo studente può guardarla e sentire, fisicamente, il peso e l'ampiezza di ciò che ha costruito con le proprie mani."*

---

## 4. Layer di rendering (z-order)

A `scale ≤ 0.25` lo stack di mount in `_ui_canvas_layer.dart` è:

```
Z-ORDER STACK A DEZOOM (scale ≤ 0.25):
  0. BackgroundPainter          — paper + dot grid
  1. DrawingPainter Tier 1/2    — stroke raster + 🏛️ monument
                                  stroke preservation
  2. KnowledgeFlowPainter:
     2a. Zone tints (Picture)         — IDENTITY (regione)
     2b. Network glow                 — AMBIENT
     2c. Cluster dots + halos         — IDENTITY
     2d. Cross-zone bridges (gold)    — RELATION (autostrade)
     2e. Monument pills + zone labels — IDENTITY (testo)
     2f. Semantic nodes (morph)       — IDENTITY (concept)
     2g. Super-nodi (god view)        — IDENTITY (tema)
  3. FsrsHeatMapPainter         — STAGE signal
                                  (Fix 1: monuments suppressed)
  4. ReturnRitualBlurPainter    — transient on multi-day return
  5. SrsBlurOverlayPainter      — active review session
  6. FogOfWarOverlayPainter     — exam mode
```

**Gerarchia visiva**: IDENTITY (chi sei) > RELATION (chi connetti) > STAGE (cosa sai) > TRANSIENT (cosa stai facendo).

Layer 4-6 sono **transienti**: appaiono solo durante una specifica attività utente (ritorno dopo giorni, review session attiva, esame attivo).

---

## 5. Sistemi paralleli

| Sistema | Quando attivo | File | Note |
|---|---|---|---|
| **DrawingPainter LOD** | sempre, gated by `renderScale` | [drawing_painter.dart](../lib/src/rendering/canvas/drawing_painter.dart) | Tier 0 ≥0.50, Tier mid 0.20-0.50, Tier raster <0.20 |
| **🏛️ Monument stroke preservation** | sempre (Tier mid/raster) | [drawing_painter.dart](../lib/src/rendering/canvas/drawing_painter.dart) + [fluera_canvas_screen.dart](../lib/src/canvas/fluera_canvas_screen.dart) `_monumentBoundsList()` | Stroke con centroide in monumentBounds bypassa simplificazione |
| **🌍 Coachmark mappamondo** | one-shot per device, surfaced alla sessione *dopo* primo dezoom | [coachmark_signals.dart](../lib/src/canvas/coachmark_signals.dart) + [coachmark_engine.dart](../../Fluera/lib/onboarding/coachmark_engine.dart) | Fire callback `onFirstMappamondoDezoom` |
| **🔮 Early title preview** | scale ∈ [0.305, 0.35] | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) `_paintEarlyTitlePreview` | Gap di 0.005 prima del monument pill (Fix 3) |
| **🎨 Zone tints** | morphT > 0.05 (Picture cached) | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) `_paintZoneTints` | Sigma 80, color hash su zoneLabel testo |
| **🏛️ Monument labels + pills** | morphT > 0.01 | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) `_paintMonumentLabels` | Pill XXL inverse-scaled |
| **🗺️ Zone labels** | morphT > 0.01 + scale ≥ 0.08 | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) `_paintZoneLabels` | Auto-derivati da OCR |
| **🛣️ Cross-zone bridge emphasis** | sempre, ampiezza ramp con morphT | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) `_paintConnections` | `crossZoneBonus = 1.0 + 2.0×morphT` |
| **🌍 Bottone Mappamondo** | sempre visibile bottom-left | [_build_ui.dart](../lib/src/canvas/parts/ui/_build_ui.dart) `_MappamondoButton` | Tap → `CameraActions.fitAllContent()` |
| **🌡️ FSRS heat-map ring** | scale ≤ 0.25, fade smoothstep 0.30→0.10 | [fsrs_heat_map_painter.dart](../lib/src/rendering/canvas/fsrs_heat_map_painter.dart) | Suppressed sui monumenti, gray ring sui untouched monumenti |
| **🔁 Return ritual blur+zoom** | sessione successiva dopo 1+ gg gap | [return_ritual_blur_painter.dart](../lib/src/rendering/canvas/return_ritual_blur_painter.dart) + canvas screen | Opt-in setting, auto-dismiss 8s |
| **🏛️ Monument nudge** | one-shot per session quando nuovo monumento promosso | canvas screen `_detectAndNudgeNewMonuments` | SnackBar 8s |
| **Minimap HUD** | tap per toggle | [canvas_minimap.dart](../lib/src/canvas/navigation/canvas_minimap.dart) | Sempre disponibile |
| **Ghost Map overlay** | user-invoked (toolbar 🗺️) | [_ghost_map.dart](../lib/src/canvas/parts/_ghost_map.dart) | Step 4 learning cycle |
| **SRS Blur overlay** | sessione review attiva | [srs_blur_overlay_painter.dart](../lib/src/rendering/canvas/srs_blur_overlay_painter.dart) | Per-cluster blur+reveal, fase-shifted (Fix 6) |
| **Fog of War** | user-invoked (esame) | `_fog_of_war.dart` | Step 10 |

---

## 6. Costanti soglia (tabella)

| Costante | Valore | File | Linea | Significato |
|---|---|---|---|---|
| `_minScale` | **0.10** | [infinite_canvas_controller.dart](../lib/src/canvas/infinite_canvas_controller.dart) | 118 | Clamp utente (limite pinch) |
| `_maxScale` | **5.00** | infinite_canvas_controller.dart | 119 | Clamp utente max |
| `aiPreloadScale` | **0.35** | [semantic_morph_controller.dart](../lib/src/reflow/semantic_morph_controller.dart) | 248 | AI title fetch + preview pill start |
| `morphStartScale` | **0.30** | semantic_morph_controller.dart | 241 | Ink fade-in inizio (morphProgress=0→1) |
| `morphEndScale` | **0.18** | semantic_morph_controller.dart | 244 | Ink completamente sparito (morphProgress=1) |
| `godViewStartScale` | **0.16** | semantic_morph_controller.dart | 261 | Super-nodi emergenza |
| `godViewEndScale` | **0.10** | semantic_morph_controller.dart | 264 | God view pieno (= clamp utente) |
| `_isLowZoom` gate | **<0.08** | [knowledge_flow_painter.dart](../lib/src/rendering/canvas/knowledge_flow_painter.dart) | 230 | Sotto: skip cosmetic decorator |
| `_lodLevel1Max` | **0.50** | knowledge_flow_painter.dart | — | Sopra: LOD 0 (clean connections) |
| `_lodLevel1Min` | **0.15** | knowledge_flow_painter.dart | — | Sotto: LOD 2 (satellite mode) |
| `kActivationScale` (FSRS) | **0.25** | [fsrs_heat_map_painter.dart](../lib/src/rendering/canvas/fsrs_heat_map_painter.dart) | — | Soglia attivazione ring FSRS |
| `_superNodeMergeRadius` | **400px canvas** | semantic_morph_controller.dart | 282 | Union-Find radius |
| `MonumentResolver.monumentThreshold` | **0.45** | [monument_resolver.dart](../lib/src/reflow/monument_resolver.dart) | 37 | Importance ≥ → monument |
| `minDegreeEligibility` | **3** | monument_resolver.dart | 50 | Min connessioni per monument |
| `_kZoneTintBakedSigma` | **80.0** | knowledge_flow_painter.dart | — | Picture cache zone tints blur |
| `_kZoneTintBakedInflate` | **100.0** | knowledge_flow_painter.dart | — | Zone tint blob inflation |
| Cross-zone strokeW bonus | **1.0 + 2.0×morphT** | knowledge_flow_painter.dart | 1010 | A morphT=1 = ~3× spessi |
| Monument size boost | **×1.20** padding + glow | knowledge_flow_painter.dart | 4243 | Per cluster ∈ monumentIds |
| FSRS ring base inflation | **6.0 × inverseScale × 0.25** | fsrs_heat_map_painter.dart | — | Cluster normali |
| FSRS ring monument extra | **+8.0 × inverseScale × 0.20** | fsrs_heat_map_painter.dart | — | Solo monument untouched gray ring |
| `aiPreloadScale - morphStartScale` gap | **0.005** | knowledge_flow_painter.dart | 343 | Preview→monument pill handoff (Fix 3) |

---

## 7. Palette colori

Post-Fase 4 deconflict.

| Categoria | Color | Hex | Uso |
|---|---|---|---|
| **Stage FSRS — Fragile** | 🌱 | `0xFFF44336` | Ring rosso "da rivedere" |
| **Stage FSRS — Growing** | 🌿 | `0xFFFF9800` | Ring arancio "in apprendimento" |
| **Stage FSRS — Solid** | 🌳 | `0xFF4CAF50` | Ring verde "consolidato" |
| **Stage FSRS — Mastered** | ⭐ | `0xFFFFB300` (amber) | Ring oro-amber (Fix 2: era 0xFFFFD700, ora distinto dai gold di sotto) |
| **Stage FSRS — Integrated** | 👻 | `0xFF90CAF9` | Ring azzurro "long-term" |
| **Stage FSRS — Untouched** | ⚪ | `0xFF9E9E9E` | Ring grigio "non studiato" (§1420 lacuna) |
| **Cross-zone bridge** | 🛣️ | `0xFFFFD700` (puro gold) | Linee inter-zona, KnowledgeConnection.crossZoneColor |
| **Monument star (residual)** | ⭐ | `0xFFFFD700` | Solo per top-importance NON-monument (Fix 5 dedup) |
| **JARVIS HUD bg** | | `0xBB0A0E1A` / `0xFF1A1A2E` | ZoomLevelIndicator, monument pill base |
| **JARVIS HUD accent** | | `0xFF82C8FF` (cyan) | Monument pill border, mappamondo button |
| **JARVIS HUD text primary** | | `0xFFB0D4FF` | Preview titles, hud text |
| **Monument pill fill** | | lerp(zoneColor, `0xFF050812`, 0.65) | Pill XXL dark fill |
| **Flashcard selection** | | `0xFF00E5FF` (cyan A400) | Semantic node tap highlight |
| **Ghost cross-zone** | | `0xFF00E5FF` ghost + lerp gold quando audio-highlighted | Suggested bridges |

**Gold zones** (3 usage distinti, post-Fix 2):
- `0xFFFFD700` puro → cross-zone bridges + residual star badge
- `0xFFFFB300` amber → SrsStage.mastered (distinto, semantic preserva)
- Monument visual identity → niente gold dedicato (pill scuro + accent halo zone color)

---

## 8. Animation periods

Tutti i pulse hanno **per-cluster phase shift** post Fix 6 Fase 4: `(cluster.id.hashCode % 628) / 100.0 → 0..2π rad`. Due cluster vicini con stessi parametri non si sincronizzano più.

| Animazione | Periodo | File | Note |
|---|---|---|---|
| Monument breath | 10.5 s (slow heartbeat) | knowledge_flow_painter.dart `_paintMonumentLabels` | "Still landmark, exist" — dominante intenzionale |
| Semantic node connection pulse | π ≈ 3.14 s | knowledge_flow_painter.dart `_paintSemanticNodes` | + clusterPhase shift |
| SRS blur breathe (review) | π ≈ 3.14 s | srs_blur_overlay_painter.dart `_paintBlurOverlay` | + clusterPhase shift |
| Return ritual blur dissolve | 1.5 s once (AnimationController) | return_ritual_blur_painter.dart | One-shot fade, no loop |
| Auto-dismiss return ritual | 8 s timeout | return_ritual_blur_painter.dart `ReturnRitualBlurController` | Plus first-interaction trigger |
| Flashcard selection pulse | π ≈ 3.14 s | knowledge_flow_painter.dart | Cyan glow su tap |
| Connection birth animation | 1.5 s ease-out cubic | knowledge_flow_painter.dart `_paintConnections` | Solo su nuova connessione |
| Knowledge particle drift | ~16 ms tick (60fps) | KnowledgeFlowController `tickParticles` | Continuo, drift bassissimo |

---

## 9. Toggle utente

In `Settings → Cognitive features → Ritorno e landmark`:

| Toggle | Default | Persistence key | Effetto |
|---|---|---|---|
| **Ritorno con sfumatura** | OFF (opt-in) | `fluera_cognitive_return_ritual` | Apre canvas più zoomato + blur transitorio al ritorno dopo 1+ gg |
| **Suggerimento landmark** | ON (opt-out) | `fluera_cognitive_monument_nudge` | SnackBar quando nuovo monumento promosso |
| **Heat-map padronanza al dezoom** | ON (opt-out) | `fluera_cognitive_fsrs_heat_map` | Ring colorati FSRS a scale ≤ 0.25 |

**Bridge engine↔app**:
- `CanvasCoachmarkSignals.returnRitualEnabled` / `monumentNudgeEnabled` / `fsrsHeatMapEnabled` (engine-side statics)
- `CognitivePreferences` singleton app-side carica da SharedPreferences a init + bridge ai signal
- `revision: ValueNotifier<int>` per rebuild reattivo Settings UI

**Storage per-canvas (Return Ritual)**:
- `fluera_canvas_visit_count_<canvasId>` (int)
- `fluera_canvas_last_visited_ms_<canvasId>` (int ms epoch)
- Callbacks `CanvasCoachmarkSignals.loadCanvasVisitState` / `saveCanvasVisitState` registrati a app init

---

## 10. Mappa pedagogia → implementazione

Riferimenti diretti a [teoria_cognitiva_apprendimento.md](../teoria_cognitiva_apprendimento.md):

| § Teoria | Concetto | Implementazione |
|---|---|---|
| §1 + §8 (FSRS) | Curva oblio + Successive Relearning | [fsrs_scheduler.dart](../lib/src/canvas/ai/fsrs_scheduler.dart), 5 stage in `SrsStage` |
| §2 Active Recall | Test effect | `SrsBlurOverlayPainter` reveal mechanic + Atlas Exam |
| §22 Place Cells | Cognizione Spaziale | Zone tints persistenti (hash su zoneLabel testo, non superNode.id volatile) |
| §22.4 "Zoom come Piani del Palazzo" | 5 piani di dettaglio | 7 tier sopra (Studio → Mappamondo) |
| §22 §504-507 "Nodi-Monumento" | Landmark del Palazzo | `MonumentResolver` + boost +20% + pill XXL + stroke preservation |
| §22 §526-530 "Frecce = strade/autostrade" | Cross-domain bridges | Cross-zone bridges 3× spessi a fine morph |
| §26 Zoom Semantico (ZUI) | LOD per livello cognitivo, non solo qualità raster | 7 tier discreti con cambio di rappresentazione |
| §28 Codifica Multimodale | Più canali = più memoria | Posizione + colore + size + pill testo |
| §172 "Specchio Metacognitivo" | Studente vede oggettivato il proprio pensiero | FSRS heat-map ring per cluster |
| §183 "Nodi verdi del Centauro" | Confronto post-review | SrsStage.solid color (verde) |
| §504-507 Monument Elaboration | "Grandi, colorati, distintivi" | Monument nudge SnackBar quando promosso |
| §1047-1062 PASSO 6 Active Recall Spaziale | Ritorno con blur + zoom-out progressivo | Return Ritual: blur intensity da days-since, zoom factor da visit count |
| §1098 "Mappamondo / vista satellite" | Sentire il peso del Palazzo | Zoom 0.10 = vista finale + bottone 🌍 fitContent |
| §1133-1138 "Continente della Conoscenza" | Macro-geografia emergente | Super-nodi + zone tints + zone labels |
| §1145 "Ponti Cross-Dominio" | Connessioni cross-zone | KnowledgeConnection.isCrossZone + ghost suggestions P9 |
| §1156 "L'IA suggerisce ponti" | Discovery cross-domain | Cross-zone bridge controller (P9) |
| §1188 Cinematic Playback | Riesperienza della lezione | Time Travel V1 (scrubber + playback) — partial |
| §1416-1420 "Nodi rossi vuoti = lacune" | Mappa visiva delle lacune | FSRS heat-map ring grigio sui untouched |
| §1441 Pretesting Effect | Domande prima di studiare | Atlas Socratic V3 (parziale, Step 3+, manca Step 0) |
| T2 SDT Autonomy | Lo studente decide | Toggle opt-in/opt-out per ogni feature pedagogica |

---

## 11. Status & verifica

### Stato per fase

| Fase | Cosa | Status |
|---|---|---|
| **Fase 1** | Mappamondo tier (soglie, zone tints, monument preservation, cross-zone emphasis, bottone) | ✅ Shipped, **Wired up**, device test pending |
| **Fase 2** | Return ritual + Monument nudge | ✅ Shipped, **Wired up**, device test pending |
| **Fase 3** | FSRS Stage Heat-Map | ✅ Shipped, **Wired up**, device test pending |
| **Fase 4** | Pulizia visiva (6 fix) | ✅ Shipped, **Wired up**, device test pending |

### Test automatici (CI)

| Test file | Asserzioni | Status |
|---|---|---|
| `test/reflow/monument_resolver_test.dart` | 9 | ✅ verde |
| `test/rendering/return_ritual_blur_test.dart` | 5 | ✅ verde |
| `test/rendering/fsrs_heat_map_test.dart` | 12 | ✅ verde |

`flutter analyze --no-pub`: 15 issue, tutti pre-esistenti (deprecation/unnecessary_import in altri file).

### Device validation pending

Test script in conversazione (12 test step-by-step). Quando completato su Xiaomi 2107113SG:
1. Aggiornare questo doc §11 → "Validated 2026-05-XX"
2. Scrivere memoria `project_low_zoom_validated_2026_05_XX.md`
3. Promuovere status da Wired up → **Validated**

### Performance gate

- Frame time durante morph 0.30→0.10: ≤ 16ms target (60fps), ≤ 33ms accettabile su transition frame
- Picture cache zone tints: hit ratio > 90% durante normale pinch (rebuild solo a cluster set change)
- FSRS heat-map: ~100 drawRRect per frame (no maskFilter blur) → μs-range, non frame-budget-sensitive

---

## 12. File map

### Engine (`fluera_engine/lib/src/`)

| File | Ruolo |
|---|---|
| `canvas/coachmark_signals.dart` | Static toggle + callback hooks engine↔app (`CanvasCoachmarkSignals`) |
| `canvas/fluera_canvas_screen.dart` | State principale; helpers `_monumentBoundsList()`, `_fsrsClusterStageList()`, `_detectAndNudgeNewMonuments()`, `_resolveReturnRitualState()` |
| `canvas/infinite_canvas_controller.dart` | Camera; `_minScale=0.10`, `_maxScale=5.0`, `fitContent()` |
| `canvas/navigation/camera_actions.dart` | `CameraActions.fitAllContent` — usato dal bottone mappamondo |
| `canvas/parts/lifecycle/_lifecycle_helpers.dart` | Trigger su scale change: AI preload, super-nodes, coachmark mappamondo signal |
| `canvas/parts/ui/_ui_canvas_layer.dart` | Mount stack di tutti i painter; z-order documentato in commento |
| `canvas/parts/ui/_build_ui.dart` | `_MappamondoButton` bottom-left |
| `canvas/ai/fsrs_scheduler.dart` | FSRS state machine; `SrsCardData` |
| `canvas/ai/srs_stage_indicator.dart` | `SrsStage` enum + palette + `stageFromCard()` |
| `reflow/monument_resolver.dart` | Classifica cluster come monumenti (importance ≥ 0.45 + degree ≥ 3) |
| `reflow/semantic_morph_controller.dart` | Soglie morph + super-nodi Union-Find |
| `reflow/zone_labeler.dart` | `ZoneLabel` macro-region auto-derivata |
| `reflow/content_cluster.dart` | `ContentCluster` |
| `reflow/knowledge_connection.dart` | `KnowledgeConnection.crossZoneColor`, isCrossZone |
| `rendering/canvas/drawing_painter.dart` | Tier 0/mid/raster + `monumentBounds` bypass |
| `rendering/canvas/knowledge_flow_painter.dart` | Master painter: morph, zone tints, monument pills, zone labels, connections, semantic nodes, super-nodi, preview titles |
| `rendering/canvas/fsrs_heat_map_painter.dart` | Ring colorati per stage (Fase 3) |
| `rendering/canvas/srs_blur_overlay_painter.dart` | Blur reveal review session |
| `rendering/canvas/return_ritual_blur_painter.dart` | Blur transitorio al ritorno (Fase 2) |

### App (`Fluera/lib/`)

| File | Ruolo |
|---|---|
| `main.dart` | App init; carica `CognitivePreferences`, registra `CanvasCoachmarkSignals.onFirstMappamondoDezoom` |
| `services/cognitive_preferences.dart` | Singleton SharedPreferences bridge per i 3 toggle |
| `settings/screens/cognitive_features_screen.dart` | Settings UI con tile cognitivi |
| `onboarding/coachmark_engine.dart` | CoachmarkEngine session-paced + `mappamondo` spec (priorità #1) |

### Docs

| File | Ruolo |
|---|---|
| [teoria_cognitiva_apprendimento.md](../teoria_cognitiva_apprendimento.md) | Teoria pedagogica completa (3382 righe) |
| `docs/dezoom_tier_map.md` | Questo file — mappa implementativa |
| [/home/lorenzo/.claude/plans/perfetto-fai-un-piano-dreamy-kite.md](../../.claude/plans/perfetto-fai-un-piano-dreamy-kite.md) | Plan storici (Fase 1-2-3-4) |

### Test

| File | Coverage |
|---|---|
| `test/reflow/monument_resolver_test.dart` | MonumentResolver classification |
| `test/rendering/return_ritual_blur_test.dart` | Intensity curve + animation lifecycle |
| `test/rendering/fsrs_heat_map_test.dart` | Fade curve + palette + monument-aware behavior |

---

## Appendice: cheatsheet rapida

**Cosa vede l'utente a scale X?**

```
0.50+  → scrittura normale, ink dettagliato, badge connessioni
0.35   → preview pill flottanti sui cluster con titolo AI
0.30   → ink inizia a svanire, monument pills emergono, zone tint visibili
0.25   → FSRS ring colorati appaiono (rosso=fragile, verde=solid, etc.)
0.20   → tratti rasterizzati, ponti d'oro spessi, monumenti grandi
0.18   → ink completamente sparito, solo nodi+pills+zone
0.16   → super-nodi tematici iniziano a fondere cluster vicini
0.10   → vista satellite piena: quartieri colorati + monumenti capitali +
         autostrade oro + ring FSRS pieno colore = "mappamondo"
```

**Cosa fa il bottone 🌍?** `CameraActions.fitAllContent()` — camera spring-animation a inquadrare tutto il canvas, di solito atterra tra 0.10 e 0.30 a seconda della dimensione.

**Cosa NON vede l'utente?** Tutto sotto 0.10 (clamp). Super-God-View teorico a 0.04 (vecchie soglie) non più accessibile.
