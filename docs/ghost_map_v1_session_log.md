# 🗺️ Ghost Map V1 — Session Log

> **Data**: 6 Aprile 2026  
> **Sessione**: Finalizzazione, ottimizzazione, sicurezza e testing  
> **Status**: ✅ Production-ready

---

## Indice

- [1. Toolbar State Wiring](#1-toolbar-state-wiring)
- [2. Premium Visual Polish](#2-premium-visual-polish)
- [3. AI Model Hardening](#3-ai-model-hardening)
- [4. Performance Optimization](#4-performance-optimization)
- [5. UX Improvements](#5-ux-improvements)
- [6. Security Hardening](#6-security-hardening)
- [7. Unit Testing](#7-unit-testing)
- [8. Stato Finale](#8-stato-finale)
- [9. File Modificati](#9-file-modificati)
- [10. Roadmap V2](#10-roadmap-v2)

---

## 1. Toolbar State Wiring

### Problema
Il chip Ghost Map nella toolbar non aveva accesso allo stato attivo e al conteggio lacune perché `ToolbarState` non esponeva quei campi.

### Soluzione

| File | Modifica |
|------|----------|
| `_toolbar_state.dart` | Aggiunti campi `isGhostMapActive` e `ghostMapGapCount` alla classe, al costruttore, e a `copyWith()` |
| `_ui_toolbar.dart` | Wiring dei nuovi campi dal `GhostMapController` nel `ToolbarState` builder |

```dart
// _toolbar_state.dart
// ── Ghost Map ─────────────────────────────────────────────────────────────
final bool isGhostMapActive;
final int ghostMapGapCount;
```

---

## 2. Premium Visual Polish

### Painter Upgrade (`ghost_map_overlay_painter.dart`)

| Elemento | Prima | Dopo |
|----------|-------|------|
| **Missing nodes** | Opacità piatta (`Color.fromRGBO(...)`) | Radial gradient glassmorphism + double-ring outer glow pulsante |
| **Correct nodes** | Solo bordo verde | Shimmer glow aura verde che pulsa (`sin(t * 1.2)`) |
| **shouldRepaint** | Non confrontava `dismissedNodeIds` | Confronta anche `dismissedNodeIds`, `isDarkMode`, e `canvasScale` |

```dart
// Radial gradient per missing nodes
_p.shader = ui.Gradient.radial(
  gradientCenter,
  bounds.longestSide * 0.6,
  [darkColor, fadeColor],
);

// Shimmer aura per correct nodes
final shimmerPhase = math.sin(animationTime * 1.2) * 0.5 + 0.5;
_p..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
canvas.drawRRect(rrect.inflate(2.0), _p);
```

---

## 3. AI Model Hardening

### System Prompt dedicato (`atlas_ai_service.dart`)

Aggiunta una `systemInstruction` al modello Ghost Map per migliorare la qualità dell'output:

```dart
systemInstruction: Content.system(
  'You are Atlas, an AI tutor embedded in Fluera — a cognitive learning engine. '
  'Your role is to analyze student handwritten notes and identify knowledge gaps. '
  'You must be factually accurate, domain-specific, and pedagogically constructive. '
  'Always respond in Italian. Never invent facts.',
),
```

### Prompt Fix
- Aggiunto `"corretto"` all'enum `stato` nell'`OUTPUT_FORMAT` (era descritto nel `TASK` ma mancava dallo schema JSON)
- `print()` → `debugPrint()` per evitare log in release

---

## 4. Performance Optimization

### Painter rewrite completo

| Ottimizzazione | Impatto | Dettaglio |
|---------------|---------|-----------|
| **TextPainter cache** | 🔴 Alto | Cache statica con LRU eviction (max 64 entries). Emoji e label ora fanno `layout()` una sola volta |
| **Viewport culling** | 🔴 Alto | I nodi fuori viewport vengono saltati completamente via `viewportRect.overlaps()` |
| **Dashed path cache** | 🟡 Medio | `computeMetrics()` (operazione Skia costosa) calcolata una sola volta per RRect, riutilizzata ai frame successivi |
| **Dismissed set O(1)** | 🟡 Medio | Rimosso O(n) `for (final n in nodes) if (isNodeDismissed(n.id))` — ora si passa direttamente il `Set<String>` dal controller |
| **Reusable Path** | 🟢 Basso | Singolo oggetto `Path` statico riutilizzato per connessioni Bézier |
| **Lint cleanup** | 🟢 Bonus | Eliminati 4 warning `unnecessary_non_null_assertion` con local variable `gmc` |

### Widget tree optimization (`_ui_canvas_layer.dart`)

```diff
- valueListenable: _ghostMapController!.version,
- builder: (_, __, ___) => CustomPaint(
-   painter: GhostMapOverlayPainter(
-     result: _ghostMapController!.result!,
-     dismissedNodeIds: {
-       for (final n in _ghostMapController!.result!.nodes)
-         if (_ghostMapController!.isNodeDismissed(n.id)) n.id,
-     },
+ final gmc = _ghostMapController!;
+ // 🚀 Compute viewport rect for culling
+ final viewportRect = Rect.fromLTWH(...);
+ return Transform(
+   child: ValueListenableBuilder<int>(
+     valueListenable: gmc.version,
+     builder: (_, __, ___) => CustomPaint(
+       painter: GhostMapOverlayPainter(
+         result: gmc.result!,
+         dismissedNodeIds: gmc.dismissedNodeIds,
+         viewportRect: viewportRect,
```

---

## 5. UX Improvements

### Auto-dismiss (`ghost_map_controller.dart`)

Quando tutti i nodi azionabili sono risolti, l'overlay si chiude automaticamente dopo 1.5s:

```dart
void _checkAutoComplete() {
  if (!_isActive || !allResolved) return;
  Future.delayed(const Duration(milliseconds: 1500), () {
    if (!_isActive || !allResolved) return;
    HapticFeedback.mediumImpact();
    dismiss();
  });
}
```

**allResolved** = ogni nodo è:
- Missing → rivelato o dismissato
- Weak → dismissato
- Correct → sempre risolto (informativo)

### Haptic Feedback

| Azione | Haptic |
|--------|--------|
| Dismiss singolo nodo | `HapticFeedback.lightImpact()` |
| Auto-complete overlay | `HapticFeedback.mediumImpact()` |

### Hit-test fix

`hitTestGhostNode()` ora salta i nodi dismissati — prima un nodo dismissato era ancora tappabile.

### Retry con backoff

API retry: 1 tentativo aggiuntivo dopo 2s di backoff, con feedback "🔄 Riprovo..." nella UI.

---

## 6. Security Hardening

### Tabella completa dei vettori mitigati

| ID | Vettore d'attacco | Mitigazione | Impatto |
|----|-------------------|-------------|---------|
| **SEC-01** | Prompt Injection | `_sanitizeInput()` strappa: tag HTML/XML, marker di iniezione (`<ROLE>`, `<SYSTEM>`, `<IGNORE>`), caratteri di controllo. Tronca a 500 char | 🔴 Critico |
| **SEC-02** | Coordinate estreme | Posizioni X/Y clampate a `±50000` — impedisce coordinate a `Double.MAX_VALUE` | 🟡 Medio |
| **SEC-03** | UI overflow | `_clampString()` limita: concept ≤ 80ch, explanation ≤ 200ch, conn label ≤ 50ch, conn explanation ≤ 150ch | 🟡 Medio |
| **SEC-04** | Resource exhaustion | Hard cap: ≤ 15 nodi, ≤ 20 connessioni | 🟡 Medio |
| **SEC-05** | API abuse / costi | Rate limiter: 30s cooldown tra chiamate API. Il cache hit bypassa il cooldown | 🔴 Alto |
| **SEC-06** | Self-loop DoS | Connessioni con `sourceId == targetId` scartate | 🟢 Basso |

### Implementazione `_sanitizeInput()`

```dart
static String _sanitizeInput(String text) {
  var sanitized = text
      .replaceAll(RegExp(r'<[^>]*>'), '')                    // Strip HTML/XML
      .replaceAll(RegExp(                                     // Strip injection markers
        r'</?(?:ROLE|SYSTEM|TASK|CONSTRAINTS|...)[^>]*>',
        caseSensitive: false,
      ), '')
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C...]'), '')    // Strip control chars
      .trim();
  if (sanitized.length > 500) sanitized = sanitized.substring(0, 500);
  return sanitized;
}
```

---

## 7. Unit Testing

### Test suite creata

| File | Test | Copertura |
|------|------|-----------|
| `test/canvas/ghost_map_controller_test.dart` | **32 test** | State transitions, reveal, dismiss, attempt scoring, auto-complete, hit-test (skip dismissed), version counter, edge cases |
| `test/canvas/ghost_map_model_test.dart` | **14 test** | Bounds computation, status helpers, pairKey deduplication, statistics, mutable state |

### Testability hook

Aggiunto `@visibleForTesting setResultForTest()` al controller per iniettare risultati nei test senza chiamare la API reale:

```dart
@visibleForTesting
void setResultForTest(GhostMapResult result) {
  _result = result;
  _isActive = true;
  _revealedNodeIds.clear();
  _userAttempts.clear();
  _attemptResults.clear();
  _dismissedNodeIds.clear();
  version.value++;
}
```

### Risultato

```
00:02 +167: All tests passed!
```

167 test totali nella directory `test/canvas/` (inclusi 135 pre-esistenti).

---

## 8. Stato Finale

### Analyzer

```
12 issues found (tutti pre-esistenti: warning/info non correlati alla Ghost Map)
0 errori
```

### Issue risolte durante la sessione

| Prima | Dopo | Delta |
|-------|------|-------|
| 16 issue | 12 issue | **-4** (eliminati warning `unnecessary_non_null_assertion` e `unnecessary_import`) |

### Checklist V1

- [x] Pedagogical gating (Step 4 only)
- [x] Per-node dismiss ("Ignora questo nodo")
- [x] 3-way toolbar toggle (dismiss → reactivate → trigger)
- [x] Active state chip con badge conteggio
- [x] System prompt dedicato per il modello Ghost Map
- [x] Premium visuals (gradient, shimmer, double-ring glow)
- [x] TextPainter cache + viewport culling + dashed path cache
- [x] Input sanitization (anti prompt injection)
- [x] Position & string clamping
- [x] Rate limiter (30s cooldown)
- [x] Node/connection count caps
- [x] Self-loop rejection
- [x] Retry con 2s backoff
- [x] Auto-dismiss when all resolved
- [x] Haptic feedback
- [x] `print()` → `debugPrint()`
- [x] 46 unit test (controller + model)
- [x] `@visibleForTesting` hook

---

## 9. File Modificati

### Codice sorgente

| File | Tipo | Descrizione |
|------|------|-------------|
| `lib/src/canvas/toolbar/_toolbar_state.dart` | MODIFY | Aggiunti `isGhostMapActive`, `ghostMapGapCount` |
| `lib/src/canvas/parts/ui/_ui_toolbar.dart` | MODIFY | Wiring Ghost Map state nel ToolbarState builder |
| `lib/src/canvas/parts/ui/_ui_canvas_layer.dart` | MODIFY | Viewport culling, dismissed set O(1), gmc local var |
| `lib/src/rendering/canvas/ghost_map_overlay_painter.dart` | REWRITE | Cache sistema, gradient glow, shimmer, viewport culling |
| `lib/src/canvas/ai/ghost_map_controller.dart` | MODIFY | Rate limiter, retry, auto-dismiss, haptic, hit-test fix, test hook |
| `lib/src/ai/atlas_ai_service.dart` | MODIFY | System prompt, sanitize, clamp, node/conn caps, self-loop, debugPrint |

### Test

| File | Tipo | Descrizione |
|------|------|-------------|
| `test/canvas/ghost_map_controller_test.dart` | NEW | 32 unit test per il controller |
| `test/canvas/ghost_map_model_test.dart` | NEW | 14 unit test per il data model |

---

## 10. Roadmap V2

Le seguenti funzionalità sono **fuori scope V1** e devono essere pianificate separatamente:

| Feature | Priorità | Dettaglio |
|---------|----------|-----------|
| **Localizzazione (l10n)** | Alta | Stringhe hardcoded ("Tocca per tentare", "Attendi Xs...", "Riprovo...") devono passare per il sistema `fluera_localizations` |
| **Knowledge Flow integration** | Media | Ghost connections dovrebbero potersi "promuovere" a connessioni reali nel Knowledge Graph |
| **Drag-and-drop nativo** | Media | Ghost nodes dovrebbero essere trascinabili sulla canvas come veri nodi |
| **Step 3 → Step 4 bridge** | Bassa | Auto-trigger Ghost Map al completamento del dialogo socratico (Step 3) |
| **Analytics** | Bassa | Tracciamento metriche: tempo per tentativo, tasso di successo, nodi più ignorati |
| **Lint cleanup** | Bassa | 12 warning pre-esistenti in `_drawing_handlers.dart`, `_ui_canvas_layer.dart`, `pdf_export_writer.dart` |
