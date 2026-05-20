"""fluera-dict — build pipeline for Fluera dictionary assets.

Produces three sibling assets in fluera_engine/assets/dictionaries/:
  - en.tsv          9-column word table (word + 8 metadata columns)
  - en.phrases.tsv  multi-word expressions
  - en.bigrams.tsv  word-pair frequency counts

A single `en.manifest.json` is the integrity + provenance registry for
all three (sha256 + row count per asset, plus per-column provenance).
"""

__version__ = "0.2.0"

# ── On-disk format version ───────────────────────────────────────────────
# Bumped 1 → 2 (2026-05-20) because column *semantics* changed even though
# the column *layout* did not: `concrete`/`aoa` went from empty-placeholder
# to model-estimated values, and `flags` went from profanity-only to
# mostly-morphological (proper / inflected / contraction). A consumer that
# disk-caches parsed assets should treat v1 and v2 as incompatible.
SCHEMA_VERSION = 2

# Manual release date for the bundled data. NOT an auto build-timestamp —
# kept static so `build` is byte-identical across re-runs on any day.
# Bump by hand when the source data is genuinely regenerated.
BUILT = "2026-05-20"

# Schema columns — order is part of the on-disk contract; only append.
SCHEMA_V1 = (
    "word",
    "freq_rank",
    "pos",
    "domains",
    "root",
    "cefr",
    "concrete",
    "aoa",
    "flags",
)

EMPTY = "-"  # canonical empty-cell sentinel

# ── Per-column provenance ────────────────────────────────────────────────
# Where each column's *data* actually comes from. Distinct from `SOURCES`
# below (a licence registry) — this answers "what produced this value".
COLUMN_PROVENANCE = {
    "word": "wordfreq",
    "freq_rank": "wordfreq",
    "pos": "WordNet 3.0, with spaCy fallback + curated function-word table",
    "domains": "MeSH 2025 (med), US Courts glossary (law), "
               "curated term lists (stem/cs/fin)",
    "root": "LemmInflect (WordNet-validated)",
    "cefr": "cefrpy, lemma-lookup + frequency-capped",
    "concrete": "model-estimated (Claude) — top-15k words only",
    "aoa": "model-estimated (Claude) — top-15k words only",
    "flags": "mostly derived (proper from pos, inflected from root, "
             "contraction from apostrophe); prof/slur/sexual from LDNOOBW",
}

# ── Licence registry ─────────────────────────────────────────────────────
# Every bundled third-party source + its commercial-use licence. All
# verified commercial-OK (see assets/dictionaries/LICENSE.md).
SOURCES = {
    "wordfreq": "Robyn Speer 2022, Apache-2.0 code + CC BY-SA 4.0 data "
                "(bundles SUBTLEX-US with explicit commercial permission "
                "from Marc Brysbaert via wordfreq NOTICE.md)",
    "WordNet 3.0": "Princeton — 'any purpose' licence, attribution required",
    "spaCy en_core_web_sm": "Explosion AI, MIT (build-time POS fallback)",
    "LemmInflect": "MIT",
    "cefrpy": "Bielikov 2024, MIT",
    "MeSH 2025": "US National Library of Medicine, public domain "
                 "(US Government work)",
    "US Courts glossary": "Administrative Office of the US Courts, "
                          "public domain (US Government work)",
    "WikiText-103": "Salesforce / Wikipedia contributors, CC BY-SA "
                    "(bigrams source)",
    "LDNOOBW": "Shutterstock, CC BY 4.0 — source for the prof/slur/sexual "
               "flags only (a small minority of the flags column)",
    "curated term lists": "STEM/CS/Finance + Latin phrases — factual word "
                          "lists authored for Fluera, no third-party licence",
    "concrete/aoa ratings": "model-estimated (Claude), original generated "
                            "data — NOT the Brysbaert/Kuperman empirical "
                            "datasets",
}
