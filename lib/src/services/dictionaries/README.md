# 📖 Word Completion Engine v7.1

> Production-grade, 45-language handwriting word prediction for Fluera Engine.
> **916,000+ words** across **12 writing systems** with RTL support.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  InkPredictionService                │
│  (MyScript iink → raw candidates)                   │
│                       │                             │
│              _enrichWithDictionary()                │
│                       │                             │
│         ┌─────────────▼──────────────┐              │
│         │  WordCompletionDictionary   │              │
│         │         (Singleton)         │              │
│         │                            │              │
│         │  🌳 Trie ──── O(k) lookup  │              │
│         │  📈 Frequency ranking      │              │
│         │  🧠 Persistent learning    │              │
│         │  📉 Temporal decay         │              │
│         │  🔗 Bigram context         │              │
│         │  📝 Canvas context         │              │
│         │  🔍 Fuzzy matching         │              │
│         │  👻 Ghost suffix + RTL     │              │
│         └────────────────────────────┘              │
│                       │                             │
│         ┌─────────────▼──────────────┐              │
│         │    InkPredictionBubble      │              │
│         │  Ghost suffix: "Wor"[ld]   │              │
│         │  RTL: [كلم]"ات"            │              │
│         └────────────────────────────┘              │
└─────────────────────────────────────────────────────┘
```

## Dual-Loading Strategy

```
App Start ──► Instant Fallback (.dart const lists, ~50 words)
         └──► Background Asset (.txt, 1K-25K words, via Isolate)
```

1. **Instant Fallback**: Each `.dart` file exports `xxxWords` + `xxxFrequency` — loaded synchronously, zero jank.
2. **Background Asset**: Each `.txt` file in `assets/dictionaries/` is parsed on an Isolate via `compute()`, then merged into the Trie.

## Supported Languages (45)

### 🔤 Latin Script (28 languages)

| Code | Language | Fallback (.dart) | Asset (.txt) |
|------|----------|:-:|:-:|
| `en` | 🇬🇧 English | ✅ ~2500 | ✅ 25K |
| `it` | 🇮🇹 Italian | ✅ ~900 | ✅ 25K |
| `es` | 🇪🇸 Spanish | ✅ ~800 | ✅ 25K |
| `fr` | 🇫🇷 French | ✅ ~800 | ✅ 25K |
| `de` | 🇩🇪 German | ✅ ~800 | ✅ 25K |
| `pt` | 🇧🇷 Portuguese | ✅ ~800 | ✅ 25K |
| `nl` | 🇳🇱 Dutch | ✅ ~50 | ✅ 25K |
| `pl` | 🇵🇱 Polish | ✅ ~50 | ✅ 25K |
| `sv` | 🇸🇪 Swedish | ✅ ~50 | ✅ 25K |
| `da` | 🇩🇰 Danish | ✅ ~50 | ✅ 25K |
| `no` | 🇳🇴 Norwegian | ✅ ~50 | ✅ 25K |
| `fi` | 🇫🇮 Finnish | ✅ ~50 | ✅ 25K |
| `ro` | 🇷🇴 Romanian | ✅ ~50 | ✅ 25K |
| `hu` | 🇭🇺 Hungarian | ✅ ~50 | ✅ 25K |
| `cs` | 🇨🇿 Czech | ✅ ~50 | ✅ 25K |
| `tr` | 🇹🇷 Turkish | ✅ ~50 | ✅ 25K |
| `vi` | 🇻🇳 Vietnamese | ✅ ~50 | ✅ 25K |
| `id` | 🇮🇩 Indonesian | ✅ ~50 | ✅ 25K |
| `hr` | 🇭🇷 Croatian | ✅ ~50 | ✅ 25K |
| `sk` | 🇸🇰 Slovak | ✅ ~50 | ✅ 25K |
| `sl` | 🇸🇮 Slovenian | ✅ ~50 | ✅ 25K |
| `et` | 🇪🇪 Estonian | ✅ ~50 | ✅ 25K |
| `lt` | 🇱🇹 Lithuanian | ✅ ~50 | ✅ 25K |
| `lv` | 🇱🇻 Latvian | ✅ ~50 | ✅ 25K |
| `tl` | 🇵🇭 Filipino | ✅ ~50 | ✅ 842 (curated) |
| `ms` | 🇲🇾 Malay | ✅ ~50 | ✅ 25K |
| `ca` | Catalan | ✅ ~50 | ✅ 25K |
| `sw` | 🇰🇪 Swahili | ✅ ~48 | ✅ 48 (stub) |

### 🔵 Cyrillic Script (3 languages)

| Code | Language | Fallback (.dart) | Asset (.txt) |
|------|----------|:-:|:-:|
| `ru` | 🇷🇺 Russian | ✅ ~50 | ✅ 25K |
| `uk` | 🇺🇦 Ukrainian | ✅ ~50 | ✅ 25K |
| `bg` | 🇧🇬 Bulgarian | ✅ ~50 | ✅ 25K |

### 🟢 Greek Script (1 language)

| Code | Language | Fallback (.dart) | Asset (.txt) |
|------|----------|:-:|:-:|
| `el` | 🇬🇷 Greek | ✅ ~50 | ✅ 25K |

### 🔴 CJK (3 languages)

| Code | Language | Fallback (.dart) | Asset (.txt) |
|------|----------|:-:|:-:|
| `ja` | 🇯🇵 Japanese | ✅ ~50 | ✅ 25K |
| `ko` | 🇰🇷 Korean | ✅ ~50 | ✅ 25K |
| `zh` | 🇨🇳 Chinese | ✅ ~50 | ✅ ~10K (curated) |

### 🟡 South Asian Scripts (5 languages)

| Code | Language | Script | Fallback (.dart) | Asset (.txt) |
|------|----------|--------|:-:|:-:|
| `hi` | 🇮🇳 Hindi | Devanagari | ✅ ~50 | ✅ ~4.4K (curated) |
| `bn` | 🇧🇩 Bengali | Bengali | ✅ ~50 | ✅ ~3.9K |
| `ta` | 🇮🇳 Tamil | Tamil | ✅ ~48 | ✅ ~1.2K |
| `te` | 🇮🇳 Telugu | Telugu | ✅ ~48 | ✅ ~1.4K |
| `mr` | 🇮🇳 Marathi | Devanagari | ✅ ~48 | ✅ 48 (stub) |

### 🟡 Thai Script (1 language)

| Code | Language | Fallback (.dart) | Asset (.txt) |
|------|----------|:-:|:-:|
| `th` | 🇹🇭 Thai | ✅ ~50 | ✅ ~10.5K |

### 🔵 RTL Scripts (4 languages)

| Code | Language | Script | Fallback (.dart) | Asset (.txt) | RTL |
|------|----------|--------|:-:|:-:|:-:|
| `ar` | 🇸🇦 Arabic | Arabic | ✅ ~48 | ✅ 25K | ✅ |
| `he` | 🇮🇱 Hebrew | Hebrew | ✅ ~48 | ✅ 25K | ✅ |
| `fa` | 🇮🇷 Persian | Arabic | ✅ ~48 | ✅ 25K | ✅ |
| `ur` | 🇵🇰 Urdu | Nastaliq | ✅ ~48 | ✅ ~9K | ✅ |

## RTL Support

The `isRtl` getter on `WordCompletionDictionary` returns `true` for Arabic, Hebrew, Persian, and Urdu. This is consumed by `GhostInkPainter` to:
- Set `TextDirection.rtl` on the paragraph
- Invert the ghost text x-offset (completions appear to the **left** of the cursor)

```dart
bool get isRtl =>
    _language == DictLanguage.ar ||
    _language == DictLanguage.he ||
    _language == DictLanguage.fa ||
    _language == DictLanguage.ur;
```

## Key Features

### 🌳 Trie Data Structure
O(k) prefix lookup where k = prefix length. Tries are built lazily per language and cached in `_trieCache`. Stale tries are evicted after 5 minutes of inactivity.

### 📈 Frequency Ranking
```
effectiveFreq = baseFreq + learnedBoost + bigramBoost + canvasBoost
```

### 🧠 Persistent Learning
When user accepts a prediction: `boost(word)` → frequency +3, timestamp recorded. Saved to `dict_learned_v2.txt`. Top 100 entries kept with temporal decay.

### 📉 Temporal Decay
```
decayFactor = 1.0 / (1.0 + ageHours / 24.0)
```

### 🔗 Bigram Context
Common word pairs. After user accepts a word, `setPreviousWord()` provides context for the next prediction.

### 📝 Canvas Context
`updateCanvasContext(texts)` scans all `DigitalTextElement.plainText` on the canvas for contextual boosting.

### 🔍 Fuzzy Matching
When exact prefix matches < 3 and prefix ≥ 3 chars: transposition matching with -2 frequency penalty.

### 👻 Ghost Suffix
`ghostSuffix("Wor", "World")` → `"ld"`. RTL-aware positioning via `GhostInkPainter`.

## Adding a New Language

1. Create `dictionaries/xx.dart` with:
   ```dart
   const xxxWords = <String>[...];      // ~48 common words
   const xxxFrequency = <String, int>{...}; // tiers 9-10
   ```
2. Create `assets/dictionaries/xx.txt` (one word per line, UTF-8)
3. Import in `word_completion_dictionary.dart`
4. Add to `DictLanguage` enum
5. Add to `setLanguageFromCode()`, `_langCodes`, `_rawWords`, `_frequency`
6. If RTL: add to `isRtl` getter
7. (Optional) Add bigrams to `_bigrams` map

## File Map

```
services/
├── word_completion_dictionary.dart    ← main engine (v7.1, 45 languages)
├── ink_prediction_service.dart        ← MyScript pipeline + enrichment
└── dictionaries/
    ├── README.md                      ← this file
    ├── en.dart  it.dart  es.dart      ← Latin (28 files)
    ├── fr.dart  de.dart  pt.dart
    ├── nl.dart  pl.dart  sv.dart  da.dart  no.dart  fi.dart
    ├── ro.dart  hu.dart  cs.dart  tr.dart
    ├── vi.dart  id.dart  hr.dart  sk.dart  sl.dart
    ├── et.dart  lt.dart  lv.dart  tl.dart  ms.dart  ca.dart  sw.dart
    ├── ru.dart  uk.dart  bg.dart      ← Cyrillic (3)
    ├── el.dart                        ← Greek (1)
    ├── ja.dart  ko.dart  zh.dart      ← CJK (3)
    ├── hi.dart  bn.dart  ta.dart      ← South Asian (5)
    ├── te.dart  mr.dart
    ├── th.dart                        ← Thai (1)
    └── ar.dart  he.dart  fa.dart  ur.dart  ← RTL (4)

assets/dictionaries/
    ├── en.txt … sw.txt                ← 45 asset files (916K+ total words)
    └── (auto-included via pubspec.yaml wildcard)
```
