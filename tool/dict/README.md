# fluera-dict

Build pipeline for the Fluera dictionary assets at
`fluera_engine/assets/dictionaries/`. Lives at `fluera_engine/tool/dict/`
so the generator is version-controlled in the same repository as the
assets it produces.

**Full reproduction guide — including the source URLs, build order, and
the model-estimated `concrete`/`aoa` process — is in [`BUILD.md`](BUILD.md).**

## Quickstart

```bash
cd fluera_engine/tool/dict
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
python -m fluera_dict build en
python -m fluera_dict validate en
python -m fluera_dict bigrams en --top-n 100000
```

## Layout

```
fluera_dict/
  cli.py            entrypoint
  ingest.py         fetch source data → data/raw/
  normalize.py      NFC + homoglyph strip + dedupe + sort
  enrich.py         POS (WordNet) + root (LemmInflect) + CEFR (cefrpy) + flags
  curate.py         apply override files
  bigrams.py        build en.bigrams.tsv from Gutenberg PD corpus
  validate.py       schema / sort / dup / homoglyph / range checks
  emit.py           write TSV + manifest.json
data/
  raw/              gitignored cache of downloaded datasets
  curated/          checked-in manual lists
tests/              pytest suite (build idempotency, validation)
```

## Source data — **all verified commercial-OK**

A licensing audit on 2026-05-19 removed three sources whose terms could
not be confirmed for closed-source commercial use (SUBTLEX-US direct,
Brysbaert 2014 concreteness ESM, Reuters-21578 NLTK corpus). The
remaining sources have explicit commercial-use permission in their
licence text or NOTICE files:

| Source | Used for | Licence | Attribution required |
|---|---|---|---|
| **wordfreq** (Robyn Speer 2022) | `word` + `freq_rank` | Apache-2.0 code, CC BY-SA 4.0 data. Bundled SUBTLEX wordlists redistributed with explicit e-mail permission from Marc Brysbaert "to be used for any purpose, not just for academic use" (see wordfreq `NOTICE.md`) | Credit "wordfreq (Robyn Speer)" + "SUBTLEX (Brysbaert et al.)" + note "SUBTLEX is freely available data" |
| **WordNet 3.0** (Princeton) | `pos` | Princeton WordNet licence — "any purpose and without fee or royalty" | Princeton copyright notice |
| **LemmInflect** | `root` | MIT | Standard MIT notice |
| **cefrpy** (Bielikov 2024) | `cefr` | MIT, includes its own EN word→level data | Standard MIT notice |
| **LDNOOBW** (Shutterstock) | `flags=prof/slur/sexual` | CC BY 4.0 | "Shutterstock" + link to repo |
| **NLTK Gutenberg sample** | `en.bigrams.tsv` | 18 books from Project Gutenberg, all pre-1923 authors → US public domain | Conventional "Project Gutenberg" credit |

### REMOVED 2026-05-19 — licence audit failed

| Source | Why dropped |
|---|---|
| **SUBTLEX-US** (direct from Ghent) | Copyright "Psychonomic Society, Inc."; no explicit commercial permission in published distribution. Now sourced via `wordfreq` which carries Brysbaert's commercial-use e-mail permission. |
| **Brysbaert 2014 concreteness** (Springer ESM) | Article is "permanently-free" to read, but no commercial-reuse permission documented for the supplementary data. `concrete` column stays `-` until a commercial-OK replacement is identified. |
| **NLTK Brown corpus** | Licence wording "redistribution permitted" doesn't explicitly grant commercial use. Skipped on the conservative side. |
| **NLTK Reuters-21578 corpus** | Reuters Ltd. permission is "for research purposes only" — explicitly incompatible with a commercial app. |

## Attribution in the shipping app

`Fluera` MUST surface the following lines in its About / Credits screen
(or equivalent) before shipping the bundled `en.tsv` and `en.bigrams.tsv`
assets:

```
Word frequencies: wordfreq (Robyn Speer, Apache-2.0)
  Includes SUBTLEX-US wordlists (Marc Brysbaert et al., redistributed
  with explicit permission); SUBTLEX is freely available data.
Part-of-speech tags: WordNet 3.0 (Princeton University)
Inflectional roots: LemmInflect (MIT)
CEFR levels: cefrpy (Bielikov, MIT)
Profanity tags: LDNOOBW (Shutterstock, CC BY 4.0)
Bigrams: Project Gutenberg (public domain)
```

The emitted `en.tsv` itself inherits CC BY-SA 4.0 from the wordfreq data
component — bundling it inside the closed-source Fluera APK is fine
(copyleft applies to the data file, not to surrounding application
code), but any redistribution of the TSV outside the app must preserve
the licence + attribution.

## Reproducibility

`python -m fluera_dict build en` must be **byte-identical** across
re-runs on the same machine. Enforced by `tests/test_build.py`.
