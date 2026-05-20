// =============================================================================
// 📖 DICT ENTRY — per-word metadata value class
//
// Shipped by the fluera-dict build pipeline (tool/dict/) as a 9-column TSV
// at assets/dictionaries/<lang>.tsv. Stage 1 populates `word`, `freqRank`,
// `pos`; later stages add `domains`, `root`, `cefr`, `concreteness`, `aoa`,
// and `flags`. Always immutable, always isolate-safe (no Flutter imports).
// =============================================================================

import 'dart:convert' show LineSplitter;

/// CEFR (Common European Framework of Reference) level — A1 easiest, C2 hardest.
/// Used by Ghost Map vocabulary gating and Socratic question difficulty scaling.
enum CefrLevel { a1, a2, b1, b2, c1, c2 }

CefrLevel? cefrFromString(String? s) {
  if (s == null || s.isEmpty || s == '-') return null;
  switch (s.toLowerCase()) {
    case 'a1': return CefrLevel.a1;
    case 'a2': return CefrLevel.a2;
    case 'b1': return CefrLevel.b1;
    case 'b2': return CefrLevel.b2;
    case 'c1': return CefrLevel.c1;
    case 'c2': return CefrLevel.c2;
  }
  return null;
}

/// Immutable per-word record. Field semantics:
///
/// - [word]: canonical lowercase form (NFC).
/// - [freqRank]: 1 = most frequent word in the language. Drives ranking in
///   prefix completion and ML Kit candidate reranking.
/// - [pos]: short POS tag — `n`, `v`, `adj`, `adv`, `det`, `pron`, `prep`,
///   `conj`, `intj`, `num`, `part`, `prop`, `abbr`, `x` (unknown).
/// - [domains]: vocabulary domains the word belongs to (`med`, `law`,
///   `stem`, `cs`, `fin`, `arts`, `sport`, `food`, `relig`, `slang`,
///   `arch`, `gen`). Empty when the word is general or untagged.
/// - [root]: inflectional root (e.g. `ran` → `run`); null when the word is
///   itself the root.
/// - [cefr]: scaffolding level for ZPD-aware vocabulary gating.
/// - [concreteness]: 1.0–5.0 (Brysbaert 2014) — drives Picture Superiority
///   Effect targeting (low concreteness → ask for a doodle).
/// - [aoa]: average age of acquisition in years (Kuperman 2012) — proxy
///   for cognitive difficulty; drives Atlas concept ordering.
/// - [flags]: arbitrary tag set (`prof`, `slur`, `sexual`, `proper`,
///   `contraction`, `inflected`, `archaic`).
class DictEntry {
  final String word;
  final int freqRank;
  final String pos;
  final List<String> domains;
  final String? root;
  final CefrLevel? cefr;
  final double? concreteness;
  final double? aoa;
  final Set<String> flags;

  const DictEntry({
    required this.word,
    required this.freqRank,
    required this.pos,
    this.domains = const [],
    this.root,
    this.cefr,
    this.concreteness,
    this.aoa,
    this.flags = const {},
  });

  /// True when the word carries a flag the UI may want to hide from
  /// autocomplete suggestions (`prof`, `slur`, `sexual`). Validation
  /// passes are unaffected.
  bool get isProfane =>
      flags.contains('prof') ||
      flags.contains('slur') ||
      flags.contains('sexual');

  @override
  String toString() => 'DictEntry($word, rank=$freqRank, pos=$pos'
      '${domains.isEmpty ? '' : ', domains=$domains'}'
      '${flags.isEmpty ? '' : ', flags=$flags'})';
}

/// Parsed result of one TSV body row. Top-level type so `compute()` can
/// ship it across the isolate boundary without capturing closures.
class ParsedDictRow {
  final String word;
  final int freqRank;
  final String pos;
  final List<String> domains;
  final String? root;
  final String? cefrRaw;
  final double? concrete;
  final double? aoa;
  final List<String> flags;

  const ParsedDictRow({
    required this.word,
    required this.freqRank,
    required this.pos,
    required this.domains,
    required this.root,
    required this.cefrRaw,
    required this.concrete,
    required this.aoa,
    required this.flags,
  });
}

/// Parse one 9-column TSV row body line. Returns null on malformed input
/// rather than throwing — caller skips bad rows.
ParsedDictRow? parseDictRow(String line) {
  if (line.isEmpty) return null;
  final cells = line.split('\t');
  if (cells.length != 9) return null;
  final word = cells[0];
  if (word.isEmpty) return null;
  final rank = int.tryParse(cells[1]);
  if (rank == null || rank < 1) return null;
  return ParsedDictRow(
    word: word,
    freqRank: rank,
    pos: cells[2],
    domains: _csvCell(cells[3]),
    root: _orNull(cells[4]),
    cefrRaw: _orNull(cells[5]),
    concrete: _floatOrNull(cells[6]),
    aoa: _floatOrNull(cells[7]),
    flags: _csvCell(cells[8]),
  );
}

/// Top-level TSV parser, isolate-safe (no Flutter imports, no `this`).
/// Skips `#` comment lines and the column-header row. Tolerates trailing
/// blank lines and CRLF line endings.
List<ParsedDictRow> parseDictTsv(String data) {
  final out = <ParsedDictRow>[];
  bool headerSeen = false;
  for (final raw in const LineSplitter().convert(data)) {
    if (raw.isEmpty) continue;
    if (raw.startsWith('#')) continue;
    if (!headerSeen) {
      // First non-comment line is the column header — skip it.
      headerSeen = true;
      continue;
    }
    final row = parseDictRow(raw);
    if (row != null) out.add(row);
  }
  return out;
}

/// Top-level parser for `<lang>.phrases.tsv` (multi-word expressions).
/// Returns `{phrase: domains}` keyed by lowercased phrase. Isolate-safe.
/// Skips `#` comment lines and the `phrase\tdomains\tkind` header.
Map<String, List<String>> parsePhrasesTsv(String data) {
  final out = <String, List<String>>{};
  bool headerSeen = false;
  for (final raw in const LineSplitter().convert(data)) {
    if (raw.isEmpty) continue;
    if (raw.startsWith('#')) continue;
    if (!headerSeen) {
      headerSeen = true; // skip column header
      continue;
    }
    final cells = raw.split('\t');
    if (cells.length != 3) continue;
    final phrase = cells[0];
    if (phrase.isEmpty) continue;
    out[phrase] = _csvCell(cells[1]);
  }
  return out;
}

List<String> _csvCell(String s) {
  if (s.isEmpty || s == '-') return const [];
  return s.split(',');
}

String? _orNull(String s) => (s.isEmpty || s == '-') ? null : s;

double? _floatOrNull(String s) {
  if (s.isEmpty || s == '-') return null;
  return double.tryParse(s);
}
