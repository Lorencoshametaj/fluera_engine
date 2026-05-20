# Rebuilding the English dictionary assets

This document is the full reproduction guide for the three assets in
`fluera_engine/assets/dictionaries/`:

| Asset | Built by | Reproducible offline? |
|---|---|---|
| `en.tsv` | `python -m fluera_dict build en` | yes (committed code + curated data + re-downloadable sources) |
| `en.phrases.tsv` | `python -m fluera_dict phrases en` | yes |
| `en.bigrams.tsv` | `python -m fluera_dict bigrams en` | yes |
| `en.manifest.json` | written by all three | yes |

Every build command is **idempotent** — byte-identical output across
re-runs on the same machine (`tests/test_build.py` enforces this).

## 0. Setup

```bash
cd fluera_engine/tool/dict
python3 -m venv .venv && source .venv/bin/activate
pip install -e '.[dev]'
python -m spacy download en_core_web_sm   # POS fallback model (~12 MB)
```

## 1. Source data

All sources are verified commercial-use-OK (see
`../../assets/dictionaries/LICENSE.md`). Most are fetched automatically by
`ingest.py` on first build and cached in `data/raw/` (gitignored).

| Source | Used for | How it's obtained |
|---|---|---|
| **wordfreq** (pip) | `word`, `freq_rank` | `pip install` — bundles its own data |
| **WordNet 3.0** (nltk) | `pos` | `nltk.download('wordnet')` — auto on first build |
| **spaCy `en_core_web_sm`** | `pos` fallback | `python -m spacy download en_core_web_sm` |
| **LemmInflect** (pip) | `root` | `pip install` |
| **cefrpy** (pip) | `cefr` | `pip install` — bundles its level data |
| **MeSH 2025** | `domains=med` | auto-download from `nlmpubs.nlm.nih.gov/.../d2025.bin` |
| **US Courts glossary** | `domains=law` | auto-download from `uscourts.gov/glossary` |
| **LDNOOBW** | `flags=prof` | auto-download from the LDNOOBW GitHub repo |
| **WikiText-103** | `en.bigrams.tsv` | manual: download `wikitext-103-raw-v1.zip` from `wikitext.smerity.com` into `data/raw/` |
| curated term lists | `domains=stem/cs/fin`, Latin phrases | committed in `data/curated/` |

If an auto-download URL breaks, drop the file into `data/raw/` by hand
with the filename `ingest.py` expects, and re-run.

## 2. Build order

```bash
python -m fluera_dict build en       # → en.tsv  + manifest entry
python -m fluera_dict phrases en      # → en.phrases.tsv  + manifest entry
python -m fluera_dict bigrams en      # → en.bigrams.tsv  + manifest entry
python -m fluera_dict validate en              # exit 0 = en.tsv OK
python -m fluera_dict validate en --phrases    # exit 0 = en.phrases.tsv OK
```

`build` reads the frozen `data/curated/llm_ratings_en.tsv` for the
`concrete` / `aoa` columns (see §3). Pipeline stages, in order:
ingest → normalize (junk filters) → enrich (pos / root / cefr / domains /
flags) → curate (force-include/exclude) → emit (TSV + manifest merge).

## 3. concrete / aoa — the model-estimated columns

The `concrete` (concreteness 1–5) and `aoa` (age of acquisition, years)
columns are **NOT** the Brysbaert (2014) / Kuperman (2012) empirical
datasets — those carry no commercial-reuse permission. They are
**Claude-estimated**, frozen in `data/curated/llm_ratings_en.tsv`
(committed). `build` just reads that file.

Regenerating `llm_ratings_en.tsv` is a three-step process. Steps 1 and 3
are committed scripts; step 2 is LLM inference.

**Step 1 — split** (committed script):
```bash
python -m fluera_dict llm-chunks en --top-n 15000
```
Writes `data/llm_chunks/chunk1.txt … chunk15.txt` (1000 words each, the
top-15k by frequency) and prints the exact rating prompt.

**Step 2 — rate** (LLM inference — not a pure offline script):
For each `chunkNNN.txt`, produce a matching `ratingsNNN.tsv` with lines
`word<TAB>concrete<TAB>aoa`, same order. The prompt is the
`RATING_PROMPT` constant in `fluera_dict/llm_ratings.py` (also printed by
step 1). Two ways to run it:
- **Interactive Claude agents** (no API key, no cost — the path used for
  the committed data): hand each chunk to a Claude agent with the prompt.
- **Anthropic API**: a small script looping the prompt over chunks with
  the `anthropic` SDK. Costs ~$5–15 for 15k words on Haiku. Not committed
  (the project deliberately avoided an API-key dependency).
Either way the output is the same: 15 `ratingsNNN.tsv` files in
`data/llm_chunks/`.

**Step 3 — assemble** (committed script):
```bash
python -m fluera_dict llm-assemble en
```
Merges the chunk/rating pairs into `data/curated/llm_ratings_en.tsv`,
**verifying word-by-word alignment** (an agent dropping a line raises an
error), clamping to range, deduping, sorting. Deterministic — given the
same `ratingsNNN.tsv` files it reproduces the file byte-identically.

To extend coverage beyond 15k, raise `--top-n`, rate the new chunks,
re-run `llm-assemble`, then `build`.

## 4. Integrity verification

```bash
sha256sum ../../assets/dictionaries/en.tsv
# compare against  assets[en.tsv].sha256  (body sha)  in en.manifest.json
```

The manifest `en.manifest.json` records `sha256` + `rows` for all three
assets and the per-column provenance. `validate` recomputes the body
sha256 and fails if the header's declared sha doesn't match.

`built` in the manifest + asset headers is a **manual release date**
(`BUILT` in `fluera_dict/__init__.py`) — not a timestamp, so re-runs stay
byte-identical. Bump it by hand when you genuinely regenerate the data.
