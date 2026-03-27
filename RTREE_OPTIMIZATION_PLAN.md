# 🔴 R-Tree Optimization Plan — Fluera Engine

## Root Cause Analysis

### Architettura Attuale
```
RTree<T> (spatial_index.dart:29)
├── STR bulk-load: O(N log N) → albero ottimale ✅
├── insert():     O(log N) con split → OK ✅
├── remove():     O(log N) + orphan reinsertion → ⚠️ DEGRADA
├── queryRange(): O(log N + K) → ⚠️ DEGRADA dopo molti insert/remove
└── maxEntries: 9 (fixed)
```

### Problema Fondamentale: **Tree Degradation**

L'R-Tree viene costruito con STR bulk-load (ottimale). Ma successive `insert()` e
`remove()` **degradano la struttura** progressivamente:

1. **insert()** usa `_chooseBestChild` (least area enlargement) — buono ma causa
   overlap crescente tra nodi
2. **remove()** con underflow < 5 entries → raccoglie orphans → reinserisce uno
   per uno → ogni reinserimento può degradare ulteriormente
3. Dopo 1000+ operazioni incrementali, i nodi interni hanno **overlap significativo**
   → `_queryRange` visita nodi che un albero ottimale salterebbe → O(N) effettivo

**Prova**: queryRange cresce linearmente (10K→100K = 9×, 100K→1M = 8×) invece
che logaritmicamente.

---

## 📐 Bottleneck #1: remove() Costoso

### Analisi
```dart
// ATTUALE: remove() → _removeEntry() + orphan reinsertion
bool remove(T item) {
  final orphans = <_Entry<T>>[];
  _removeEntry(_root!, item, bounds, orphans);
  // Re-insert orphaned entries ONE BY ONE
  for (final orphan in orphans) {
    _insertEntry(_root!, orphan);  // ← Ogni insert è O(log N)
  }
}
```

**Costo**: O(log N) per trovare e rimuovere + O(K × log N) per reinserire K orphans.
Con tree degradato, K può essere grande (intero subtree collassato).

### Fix: Lazy Deletion + Periodic Rebuild

**Fase 1: Lazy Remove** — O(1) instant
```dart
// NUOVO: mark-as-deleted invece di rimuovere fisicamente
final Set<T> _tombstones = {}; // identity-based

bool remove(T item) {
  _tombstones.add(item);
  _count--;
  _tombstoneCount++;
  
  // Auto-compact quando >20% tombstones
  if (_tombstoneCount > _count * 0.25) {
    _scheduleCompaction();
  }
  return true;
}

void _queryRange(node, range, results) {
  if (!node.bounds.overlaps(range)) return;
  if (node.isLeaf) {
    for (final entry in node.entries) {
      if (entry.bounds.overlaps(range) && !_tombstones.contains(entry.item)) {
        results.add(entry.item);
      }
    }
  } else {
    for (final child in node.children) {
      _queryRange(child, range, results);
    }
  }
}
```

**Costo remove**: O(1) (HashSet.add)
**Costo query extra**: O(K) tombstone check per risultato (negligible)

**Fase 2: Compaction** — background, asincrono
```dart
void _compact() {
  // Collect all non-tombstone entries
  final live = <_Entry<T>>[];
  _collectEntries(_root!, live);
  live.removeWhere((e) => _tombstones.contains(e.item));
  _tombstones.clear();
  _tombstoneCount = 0;
  
  // STR bulk-rebuild da zero → albero ottimale
  _root = _bulkLoad(live);
  _count = live.length;
}
```

**Complexity**: O(1) per remove, amortized O(N log N / N) = O(log N) per rebuild.

### Impatto Stimato
| Scenario | Prima | Dopo |
|---|---|---|
| 100K: 100 removes | 2,563ms (25ms/remove) | ~0.1ms (0.001ms/remove) |
| 1M: 1 undo | ~250ms 💀 | ~0.001ms ✅ |
| Compaction (100K) | — | ~50ms (background, non-blocking) |

---

## 📐 Bottleneck #2: queryRange Degrada a O(N)

### Analisi
Il `_queryRange` attuale è corretto ma soffre di tree degradation:
- Nodi interni con overlap eccessivo → il pruning `!node.bounds.overlaps(range)` 
  non esclude abbastanza nodi
- Manca early-out per nodi completamente contenuti

### Fix A: Early-out per nodi completamente contenuti
```dart
void _queryRange(_RTreeNode<T> node, Rect range, List<T> results) {
  if (!node.bounds.overlaps(range)) return;
  
  // 🚀 SHORT-CIRCUIT: se il nodo è completamente dentro il range,
  // tutti i figli sono visibili → skip overlap check per ogni entry
  if (_rangeContains(range, node.bounds)) {
    _collectAllItems(node, results);
    return;
  }
  
  if (node.isLeaf) {
    for (final entry in node.entries) {
      if (entry.bounds.overlaps(range)) {
        results.add(entry.item);
      }
    }
  } else {
    for (final child in node.children) {
      _queryRange(child, range, results);
    }
  }
}

void _collectAllItems(_RTreeNode<T> node, List<T> results) {
  if (node.isLeaf) {
    for (final entry in node.entries) {
      results.add(entry.item);
    }
  } else {
    for (final child in node.children) {
      _collectAllItems(child, results);
    }
  }
}

bool _rangeContains(Rect range, Rect inner) {
  return range.left <= inner.left && 
         range.top <= inner.top &&
         range.right >= inner.right && 
         range.bottom >= inner.bottom;
}
```

**Impatto**: Viewport che contiene molti strokes → O(K) diretto senza overlap check.
A zoom out estremo (tutti visibili): da O(N × overlap_checks) a O(N) flat collect.

### Fix B: Periodic Rebuild dopo N insert/remove
```dart
int _mutationsSinceRebuild = 0;

void insert(T item) {
  // ... existing logic ...
  _mutationsSinceRebuild++;
  if (_mutationsSinceRebuild > _count * 0.3) {
    _scheduleRebuild();
  }
}

void _scheduleRebuild() {
  // Non-blocking: collect entries, bulk-load fresh tree
  final entries = <_Entry<T>>[];
  _collectEntries(_root!, entries);
  entries.removeWhere((e) => _tombstones.contains(e.item));
  _root = _bulkLoad(entries);
  _tombstones.clear();
  _mutationsSinceRebuild = 0;
}
```

### Impatto Stimato
| N | Prima | Fix A | Fix A+B |
|---|---|---|---|
| 100K viewport query | 1,101µs | ~600µs | ~200µs |
| 1M viewport query | 8,740µs | ~4,000µs | ~1,500µs |

---

## 📐 Bottleneck #3: Hit Test = Point Query Lento

### Analisi
Hit test usa `queryRange` con un piccolo rect (punto + raggio). Il problema è lo
stesso: tree degradation causa visit di troppi nodi interni.

### Fix: Point-specific Query + Rebuild
Il fix B (periodic rebuild) risolve anche questo. In aggiunta, per hit test il
short-circuit di Fix A è meno utile (il range è piccolo). Ma la compaction è
fondamentale.

### Fix C: maxEntries tuning
```dart
// Attuale: maxEntries = 9
// Per 100K+: maxEntries = 16 riduce altezza e migliora cache locality
// Per 1M+: maxEntries = 32 per leaf nodes flat

RTree(this._boundsOf, {int maxEntries = 16})  // ← da 9 a 16
```

Con maxEntries=16:
- 100K items: altezza 4 (vs 5 con 9) → 20% meno nodi visitati
- 1M items: altezza 5 (vs 7 con 9) → 28% meno nodi visitati

---

## 🏗️ Piano di Implementazione

### Step 1: Lazy Deletion (30 min) — CRITICAL
**File**: `spatial_index.dart` → `RTree.remove()`

1. Aggiungere `Set<T> _tombstones` usando `Set.identity()`
2. `remove()` → `_tombstones.add(item); _count--; return true;`
3. `_queryRange()` → skip tombstoned items
4. `queryVisible()` → skip tombstoned items
5. `insert()` → rimuovi da tombstones se re-inserito
6. Aggiungere `compact()` → collect non-tombstone entries → `_bulkLoad()`
7. Auto-compact quando tombstones > 25% di count

### Step 2: Short-circuit Query (15 min) — HIGH
**File**: `spatial_index.dart` → `RTree._queryRange()`

1. Aggiungere `_rangeContains()` helper
2. In `_queryRange`: se `range` contiene completamente `node.bounds`, 
   chiamare `_collectAllItems()` bypassing overlap checks
3. Aggiungere `_collectAllItems()` flat collector

### Step 3: maxEntries Tuning (5 min) — MEDIUM
**File**: `spatial_index.dart` → `RTree` constructor

1. Cambiare default `maxEntries` da 9 a 16
2. Aggiornare `_minEntries` di conseguenza

### Step 4: Auto-Rebuild dopo Mutations (15 min) — HIGH
**File**: `spatial_index.dart` → `RTree.insert()` e `remove()`

1. Track `_mutationsSinceRebuild`
2. Dopo > 30% mutations vs count → schedule compaction
3. Compaction = collect entries → filter tombstones → `_bulkLoad()`

### Step 5: Test & Benchmark (20 min)
1. Unit test per lazy deletion + compaction
2. Benchmark: 100K insert → 1000 remove → query → verify < 500µs
3. Benchmark: 1M insert → viewport query → verify < 2ms

---

## 🎯 Target Performance

| Operazione | 100K attuale | 100K target | 1M attuale | 1M target |
|---|---|---|---|---|
| remove() | 25ms | **0.001ms** | ~250ms | **0.001ms** |
| viewport query | 1,101µs | **<500µs** | 8,740µs | **<2,000µs** |
| hit test | 988µs | **<300µs** | 8,902µs | **<1,500µs** |
| insert() | ~O(log N) | ~O(log N) | ~O(log N) | ~O(log N) |

**Tutto entro budget 120Hz (8.33ms)** ✅
