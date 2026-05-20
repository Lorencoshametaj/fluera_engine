"""POS assignment (Stage 1: hand-curated function words) and flag derivation
(Stage 2: profanity / slur / sexual).

POS: SUBTLEX-US raw dump has no POS column, so Stage 1 uses a small
hand-curated function-word table (~120 words). Stage 2 keeps this table
for the function-word core and adds Stage 3 plans for spaCy/WordNet for
the long tail.

Flags: Stage 2 derives `prof` from the LDNOOBW open-source bad-words
list, with `slur` and `sexual` carved out of the same pool via curated
override files. Anything LDNOOBW-listed but not in the override files
defaults to `prof`. UI suggestion layers should hide `slur`/`sexual` by
default and surface `prof` (with a settings toggle); spellcheck always
validates regardless of flag.

Fluera POS enum:
  n, v, adj, adv, det, pron, prep, conj, intj, num, part, prop, abbr, x
"""

from __future__ import annotations

VALID_POS = {"n", "v", "adj", "adv", "det", "pron", "prep", "conj",
             "intj", "num", "part", "prop", "abbr", "x"}

# Hand-curated POS for the highest-frequency English function words.
# Picked for words where (1) POS is unambiguous and (2) downstream code
# benefits — e.g. spellcheck won't flag bare `a` / `I` and language
# detection scores function-word coverage.
_FUNCTION_WORD_POS: dict[str, str] = {
    # Articles / determiners
    "a": "det", "an": "det", "the": "det",
    "this": "det", "that": "det", "these": "det", "those": "det",
    "some": "det", "any": "det", "no": "det", "every": "det", "all": "det",
    "each": "det", "both": "det", "either": "det", "neither": "det",
    # Pronouns
    "i": "pron", "you": "pron", "he": "pron", "she": "pron", "it": "pron",
    "we": "pron", "they": "pron", "me": "pron", "him": "pron", "her": "pron",
    "us": "pron", "them": "pron", "my": "pron", "your": "pron", "his": "pron",
    "its": "pron", "our": "pron", "their": "pron", "mine": "pron",
    "yours": "pron", "hers": "pron", "ours": "pron", "theirs": "pron",
    "who": "pron", "whom": "pron", "whose": "pron", "which": "pron",
    "what": "pron", "whoever": "pron", "whatever": "pron",
    "myself": "pron", "yourself": "pron", "himself": "pron", "herself": "pron",
    "itself": "pron", "ourselves": "pron", "themselves": "pron",
    # Prepositions
    "of": "prep", "in": "prep", "on": "prep", "at": "prep", "by": "prep",
    "for": "prep", "with": "prep", "about": "prep", "against": "prep",
    "between": "prep", "into": "prep", "through": "prep", "during": "prep",
    "before": "prep", "after": "prep", "above": "prep", "below": "prep",
    "from": "prep", "up": "prep", "down": "prep", "out": "prep", "off": "prep",
    "over": "prep", "under": "prep", "again": "prep", "further": "prep",
    "across": "prep", "behind": "prep", "beyond": "prep", "without": "prep",
    "within": "prep", "along": "prep", "around": "prep", "near": "prep",
    # Conjunctions
    "and": "conj", "or": "conj", "but": "conj", "nor": "conj", "yet": "conj",
    "so": "conj", "because": "conj", "although": "conj", "though": "conj",
    "while": "conj", "whereas": "conj", "if": "conj", "unless": "conj",
    "until": "conj", "since": "conj", "as": "conj",
    # Particles / infinitive marker / negation
    "to": "part", "not": "part",
    # High-frequency verbs (auxiliaries + most common lexical)
    "is": "v", "am": "v", "are": "v", "was": "v", "were": "v", "be": "v",
    "been": "v", "being": "v",
    "have": "v", "has": "v", "had": "v", "having": "v",
    "do": "v", "does": "v", "did": "v", "done": "v", "doing": "v",
    "will": "v", "would": "v", "shall": "v", "should": "v",
    "can": "v", "could": "v", "may": "v", "might": "v", "must": "v",
    "get": "v", "got": "v", "make": "v", "made": "v", "go": "v", "went": "v",
    "say": "v", "said": "v", "know": "v", "knew": "v", "see": "v", "saw": "v",
    "take": "v", "took": "v", "come": "v", "came": "v",
    # Common adverbs
    "very": "adv", "really": "adv", "just": "adv", "only": "adv",
    "also": "adv", "even": "adv", "still": "adv", "already": "adv",
    "always": "adv", "never": "adv", "sometimes": "adv", "often": "adv",
    "now": "adv", "then": "adv", "here": "adv", "there": "adv",
    "where": "adv", "when": "adv", "why": "adv", "how": "adv",
    "yes": "intj", "ok": "intj", "okay": "intj",
}


def pos_for(word: str) -> str:
    """Return the POS for `word` or `x` if unknown.

    Resolution order:
      1. Hand-curated function-word table (highest precision, covers ~120
         high-frequency closed-class words where WordNet under-tags).
      2. WordNet synsets — pick the POS with the most synsets ("dominant
         sense" heuristic). Covers ~95% of the top 30k frequent words.
      3. spaCy en_core_web_sm fallback for the long tail — proper nouns,
         tech slang ("blockchain", "wifi"), brands, foreign-origin words
         that WordNet doesn't index. Less precise on single-word inputs
         (no sentence context) but reliably better than `x`.
      4. Final fallback `x` (genuinely unknown).
    """
    if word in _FUNCTION_WORD_POS:
        return _FUNCTION_WORD_POS[word]
    wn_pos = _wordnet_pos_for(word)
    if wn_pos != "x":
        return wn_pos
    return _spacy_pos_for(word)


# ── WordNet POS lookup (Stage 2) ─────────────────────────────────────────


# Synset.pos() → Fluera POS enum
_WORDNET_POS_MAP = {
    "n": "n",
    "v": "v",
    "a": "adj",  # adjective
    "s": "adj",  # adjective satellite
    "r": "adv",
}


def _wordnet_pos_for(word: str) -> str:
    """Best-effort POS via WordNet. `x` when no synset exists."""
    syns = _wn_synsets(word)
    if not syns:
        return "x"
    # Count synsets per POS — pick the dominant one.
    counts: dict[str, int] = {}
    for s in syns:
        mapped = _WORDNET_POS_MAP.get(s.pos(), "x")
        counts[mapped] = counts.get(mapped, 0) + 1
    return max(counts.items(), key=lambda kv: kv[1])[0]


# ── Inflectional root (Stage 3, via LemmInflect) ─────────────────────────


# LemmInflect supports only the four open-class UPOS tags. Closed-class
# words (DET, PRON, ADP, ...) don't inflect meaningfully so the lemma is
# the word itself — skip the call entirely.
_FLUERA_TO_UPOS = {
    "n": "NOUN",
    "v": "VERB",
    "adj": "ADJ",
    "adv": "ADV",
}


def root_for(word: str, fluera_pos: str) -> str | None:
    """Return the inflectional root of [word] given its Fluera POS, or
    `None` when the word is itself a lemma (root == word) or POS is one
    that LemmInflect can't handle.
    """
    upos = _FLUERA_TO_UPOS.get(fluera_pos)
    if upos is None:
        return None
    try:
        from lemminflect import getLemma
    except ImportError:
        return None
    lemmas = getLemma(word, upos=upos)
    if not lemmas:
        return None
    # Pick the first lemma; LemmInflect orders by likelihood.
    root = lemmas[0]
    if root == word:
        return None  # word is already its own root → emit `-` downstream
    # Validity guard: LemmInflect over-eagerly strips a trailing `s` from
    # proper nouns and non-words ("aarhus" → "aarhu", a non-word). Only
    # trust a root that WordNet recognises as a real lemma — this rejects
    # the garbage de-pluralisations without dropping genuine roots
    # ("run", "child", "good" are all in WordNet).
    if not _wn_synsets(root):
        return None
    return root


# Brysbaert 2014 concreteness ingestion was REMOVED 2026-05-19 after a
# licensing audit failed to confirm commercial-use permission for the
# Springer ESM dataset. The TSV schema retains the `concrete` column
# (always `-`) so re-adding the data later doesn't shift columns. If a
# commercial-OK concreteness corpus surfaces, restore `concreteness_for`
# here and wire it back into build.py.


# ── Domain tagging (Stage 4 — medical via MeSH) ──────────────────────────


VALID_DOMAINS = {"gen", "med", "law", "stem", "cs", "fin", "arts",
                 "sport", "food", "relig", "slang", "arch"}


def domain_for(
    word: str,
    *,
    mesh_terms: set[str],
    legal_terms: set[str],
    stem_terms: set[str] = frozenset(),
    cs_terms: set[str] = frozenset(),
    finance_terms: set[str] = frozenset(),
) -> list[str]:
    """Return the list of vocabulary domains [word] belongs to.

    Stage 4 added `med` (MeSH), Stage 5 `law` (US Courts), Stage 6
    `stem` / `cs` / `fin` (curated lists). A word can carry multiple
    domains — `tort` is `law,med`, `algorithm` is `stem,cs`. Domains are
    appended in a fixed order so the emitted cell is deterministic.
    """
    domains: list[str] = []
    if word in mesh_terms:
        domains.append("med")
    if word in legal_terms:
        domains.append("law")
    if word in stem_terms:
        domains.append("stem")
    if word in cs_terms:
        domains.append("cs")
    if word in finance_terms:
        domains.append("fin")
    return domains


# ── CEFR (Stage 3, via cefrpy MIT package) ───────────────────────────────


_CEFR_ANALYZER = None  # lazy import

# CEFR ladder — index = difficulty rank, used for the frequency cap.
_CEFR_ORDER = ["A1", "A2", "B1", "B2", "C1", "C2"]
_CEFR_INDEX = {lvl: i for i, lvl in enumerate(_CEFR_ORDER)}

# Frequency-rank → highest plausible CEFR level. A word common enough to
# rank in the top N cannot genuinely be advanced vocabulary; cefrpy
# over-assigns C2 to any moderately rare form (`squirrels`, `muggy`), so
# we clamp its output against the word's own frequency.
_FREQ_CAP_BANDS = [
    (1000, "A2"),
    (3000, "B1"),
    (8000, "B2"),
    (20000, "C1"),
]  # rank > 20000 → C2 allowed (no cap)


def _raw_cefr(word: str) -> str | None:
    """Bare cefrpy lookup. Returns canonical "A1".."C2" or None."""
    global _CEFR_ANALYZER
    if _CEFR_ANALYZER is None:
        try:
            from cefrpy import CEFRAnalyzer
            _CEFR_ANALYZER = CEFRAnalyzer()
        except ImportError:
            return None
    try:
        level = _CEFR_ANALYZER.get_average_word_level_CEFR(word)
    except Exception:
        return None
    if level is None:
        return None
    s = str(level)  # cefrpy CEFRLevel enum → "A1".."C2"
    return s if s in _CEFR_INDEX else None


def cefr_for(word: str, *, root: str | None = None,
             freq_rank: int | None = None) -> str | None:
    """Return the CEFR level (A1..C2) for [word], or None when unknown.

    Two corrections over the bare cefrpy lookup:
      1. **Lemma-lookup** — query the root form when available so an
         inflection ("squirrels") inherits its lemma's level rather than
         being mis-rated C2 just for being a rarer surface form.
      2. **Frequency cap** — clamp the result against [freq_rank]: a word
         common enough to rank near the top of the corpus cannot really
         be advanced vocabulary, so we cap C1/C2 inflation.
    """
    # 1. Prefer the lemma's level; fall back to the surface form.
    level = None
    if root:
        level = _raw_cefr(root)
    if level is None:
        level = _raw_cefr(word)
    if level is None:
        return None
    # 2. Apply the frequency cap.
    if freq_rank is not None:
        cap = None
        for max_rank, cap_level in _FREQ_CAP_BANDS:
            if freq_rank <= max_rank:
                cap = cap_level
                break
        if cap is not None and _CEFR_INDEX[level] > _CEFR_INDEX[cap]:
            level = cap
    return level


# ── spaCy POS fallback (Stage 4, for WordNet-OOV long tail) ──────────────


_SPACY_UPOS_TO_FLUERA = {
    "NOUN": "n",
    "VERB": "v",
    "ADJ": "adj",
    "ADV": "adv",
    "DET": "det",
    "PRON": "pron",
    "ADP": "prep",
    "CCONJ": "conj",
    "SCONJ": "conj",
    "INTJ": "intj",
    "NUM": "num",
    "PART": "part",
    "PROPN": "prop",
    "AUX": "v",
    # X / SYM / PUNCT / SPACE → x (unmapped)
}

_SPACY_NLP = None  # lazy import — only spin up when fallback fires


def _spacy_pos_for(word: str) -> str:
    """Best-effort POS via spaCy's small English model. Returns `x` on
    miss. spaCy is context-aware, so single-word input is noisier than
    in-sentence tagging (e.g. it may label nouns as PROPN). Acceptable
    trade-off for closing the WordNet long-tail gap.
    """
    global _SPACY_NLP
    if _SPACY_NLP is None:
        try:
            import spacy
            _SPACY_NLP = spacy.load("en_core_web_sm", disable=["parser", "ner"])
        except Exception:
            return "x"
    try:
        doc = _SPACY_NLP(word)
    except Exception:
        return "x"
    if not doc:
        return "x"
    return _SPACY_UPOS_TO_FLUERA.get(doc[0].pos_, "x")


_wn = None  # lazy import — avoids ~1s import latency on commands that don't enrich


def _wn_synsets(word: str):
    """Memoized synset lookup. Caching is per-process — the build runs
    once so we don't need cross-run persistence here."""
    global _wn
    if _wn is None:
        from nltk.corpus import wordnet as wn_module
        # Trigger lazy load + ensure corpus is present.
        try:
            wn_module.synsets("test")
        except LookupError:
            import nltk
            nltk.download("wordnet", quiet=True)
        _wn = wn_module
    return _wn.synsets(word)


# ── Flag derivation (Stage 2) ────────────────────────────────────────────


VALID_FLAGS = {"prof", "slur", "sexual", "proper", "contraction", "inflected", "archaic"}


def flag_for(
    word: str,
    *,
    profanity_pool: set[str],
    slur_overrides: set[str],
    sexual_overrides: set[str],
) -> list[str]:
    """Compute the `flags` list for one word.

    Resolution order (most-specific wins):
      1. `slur` if in `slur_overrides`
      2. `sexual` if in `sexual_overrides`
      3. `prof` if in the general profanity pool
      4. otherwise: empty (no flags)
    """
    if word in slur_overrides:
        return ["slur"]
    if word in sexual_overrides:
        return ["sexual"]
    if word in profanity_pool:
        return ["prof"]
    return []
