# Dictionary asset attribution

The English dictionary assets in this directory (`en.tsv`,
`en.bigrams.tsv`, `en.manifest.json`) are derived from multiple third-party
sources, every one of which permits commercial use (including subscription
sale of the host application). Required attribution is listed below.

## en.tsv

| Column | Source | Licence |
|---|---|---|
| `word`, `freq_rank` | [wordfreq](https://github.com/rspeer/wordfreq) by Robyn Speer | Apache-2.0 (code) + CC BY-SA 4.0 (data) |
| | Bundled SUBTLEX wordlists ([Brysbaert et al.](http://crr.ugent.be/programs-data/subtitle-frequencies)) | Redistributed in wordfreq with explicit e-mail permission from Marc Brysbaert "to be used for any purpose, not just for academic use" (see [wordfreq NOTICE.md](https://github.com/rspeer/wordfreq/blob/master/NOTICE.md)) |
| `pos` | [WordNet 3.0](https://wordnet.princeton.edu/) | WordNet licence — "any purpose and without fee or royalty" |
| `root` | [LemmInflect](https://github.com/bjascob/LemmInflect) | MIT |
| `cefr` | [cefrpy](https://github.com/Maximax67/cefrpy) by Bielikov Maksym | MIT |
| `domains` (`med`) | [MeSH 2025](https://www.nlm.nih.gov/databases/download/mesh.html) by US National Library of Medicine | US-government work — public domain (DC.Rights = "Public Domain") |
| `domains` (`law`) | [US Courts glossary](https://www.uscourts.gov/glossary) by the Administrative Office of the U.S. Courts | US-government work — public domain |
| `pos` (long-tail fallback) | [spaCy](https://spacy.io/) `en_core_web_sm` by Explosion AI | MIT |
| `flags` (`prof` / `slur` / `sexual`) | [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) by Shutterstock | CC BY 4.0 |
| `concrete` / `aoa` | **Model-estimated** (Claude) — original generated data | No third-party dataset (see note below) |

**`concrete` and `aoa` are model-estimated, not empirical data.** They are
Claude-generated estimates of word concreteness (1–5) and age of
acquisition (years), produced for the ~6,000 highest-frequency words. They
are NOT the Brysbaert (2014) concreteness norms or the Kuperman (2012) AoA
norms — those empirical datasets have no documented commercial-reuse
permission and were excluded during the licence audit. The estimates are
original generated content (no licence constraint) and are intended only
as a soft difficulty signal, not as research-grade measurements. Treat
their accuracy accordingly.

Because the wordfreq data component is CC BY-SA 4.0, `en.tsv` itself is
distributed under **CC BY-SA 4.0**. The share-alike obligation applies to
the data file only; the surrounding Fluera application code remains
proprietary. Anyone who extracts and redistributes `en.tsv` must retain
this licence and the attribution above.

Robyn Speer must be credited as "Robyn Speer" (her academic name);
crediting her as Elia Robyn Lake is a serious violation of the wordfreq
licence terms.

## en.bigrams.tsv

Derived from **WikiText-103-raw** (Salesforce) — a language-modelling
corpus of ~100M tokens extracted from the "Good" and "Featured" articles
of English Wikipedia. WikiText-103 is licensed **CC BY-SA** (the same
share-alike class as the wordfreq frequency data). The bigram counts in
`en.bigrams.tsv` are a statistical derivative and inherit CC BY-SA;
bundling the file in the closed-source Fluera APK is fine (copyleft
applies to the data file, not the app code).

Attribution: "WikiText-103 (Salesforce / Wikipedia contributors,
CC BY-SA)".

## en.phrases.tsv

Multi-word expression asset (Stage 6). Derived entirely from sources
already credited above plus a Fluera-authored curated list — no new
third-party data:

- Medical phrases ← MeSH 2025 Main Headings (US NLM, public domain)
- Legal phrases ← U.S. Courts glossary multi-word terms (public domain)
- Latin / academic phrases ← `data/curated/latin_phrases_en.txt`, a
  factual word list authored for Fluera (no licence constraint)

The `domains` STEM / CS / Finance tags in `en.tsv` are likewise applied
from Fluera-authored curated term lists (`data/curated/*_terms_en.txt`)
— factual vocabulary lists, not third-party datasets.

## Required application credit (Fluera About screen)

The host application MUST display the following attribution lines in its
About / Credits screen (or equivalent surface) before the assets here are
considered legally cleared for distribution:

```
Word frequencies: wordfreq (Robyn Speer, Apache-2.0)
  Includes SUBTLEX-US wordlists (Marc Brysbaert et al.,
  redistributed with explicit permission); SUBTLEX is freely
  available data.
Part-of-speech tags: WordNet 3.0 (Princeton University)
  long-tail fallback via spaCy en_core_web_sm (Explosion AI, MIT)
Inflectional roots: LemmInflect (MIT)
CEFR levels: cefrpy (Bielikov, MIT)
Medical domain tags: MeSH 2025 (US National Library of Medicine,
  public domain)
Legal domain tags: U.S. Courts glossary (Administrative Office of
  the U.S. Courts, public domain)
Profanity tags: LDNOOBW (Shutterstock, CC BY 4.0)
Bigrams: WikiText-103 (Salesforce / Wikipedia contributors, CC BY-SA)
```

Princeton specifies that its name "may not be used in advertising or
publicity pertaining to distribution of the software and/or database",
so keep the WordNet credit in the About screen — do not put it in
marketing copy or the App Store listing.

## What was REMOVED during the licence audit (2026-05-19)

For the record so the next iteration doesn't reintroduce them:

- **SUBTLEX-US** (direct from Ghent) — Psychonomic Society copyright with
  no explicit commercial permission. Now sourced via wordfreq.
- **Brysbaert 2014 concreteness** (Springer ESM) — "permanently-free" to
  read, but no commercial-reuse permission documented.
- **NLTK Brown corpus** — "redistribution permitted" without explicit
  commercial grant.
- **NLTK Reuters-21578** — Reuters Ltd. permission is "for research
  purposes only" — incompatible with a commercial application.
