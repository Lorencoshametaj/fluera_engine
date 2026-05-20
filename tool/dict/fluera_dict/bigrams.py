"""Build the bigram asset shipped at
`fluera_engine/assets/dictionaries/<lang>.bigrams.tsv`.

Source (Stage 5): WikiText-103-raw — Salesforce's language-modelling
corpus extracted from the "Good" and "Featured" articles of English
Wikipedia (~100M tokens of modern prose). Licensed CC BY-SA — the same
share-alike class already accepted for the wordfreq frequency data.

This replaced the Stage 3 Gutenberg-only corpus, whose pre-1923 literary
English produced bigrams that missed all modern vocabulary ("machine
learning", "smartphone", "covid"). The Gutenberg builder is kept below
as `build_bigrams_gutenberg` for reference / offline fallback.

Output schema (one bigram per line, tab-separated, lex-sorted):
    w1\\tw2\\tcount
Header lines (prefixed `#`) carry the version + total row count.
"""

from __future__ import annotations

import hashlib
import unicodedata
import zipfile
from collections import Counter
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
WIKITEXT_ZIP = RAW_DIR / "wikitext-103-raw-v1.zip"
WIKITEXT_MEMBER = "wikitext-103-raw/wiki.train.raw"


def build_bigrams(top_n: int = 100_000) -> Counter:
    """Build word bigrams from WikiText-103. Returns a Counter keyed on
    `(w1, w2)`, truncated to the top [top_n] by count."""
    if not WIKITEXT_ZIP.exists():
        raise FileNotFoundError(
            f"{WIKITEXT_ZIP} missing — download wikitext-103-raw-v1.zip "
            "from https://wikitext.smerity.com/wikitext-103-raw-v1.zip"
        )
    counts: Counter = Counter()
    with zipfile.ZipFile(WIKITEXT_ZIP) as zf, zf.open(WIKITEXT_MEMBER) as fh:
        for raw in fh:
            line = raw.decode("utf-8", errors="ignore")
            # Section headers ` = Title = ` carry no running prose.
            stripped = line.strip()
            if not stripped or stripped.startswith("="):
                continue
            # WikiText encodes intra-word punctuation as ` @-@ `, ` @.@ `,
            # ` @,@ `. Turn hyphen-joins into a space (so "role @-@
            # playing" yields the bigram role→playing) and collapse the
            # numeric separators.
            line = line.replace(" @-@ ", " ")
            line = line.replace(" @.@ ", " ").replace(" @,@ ", " ")
            # Period marks a sentence boundary — bigrams don't cross it.
            for sentence in line.split(". "):
                prev: str | None = None
                for tok in sentence.split():
                    w = _normalize_token(tok)
                    if w is None:
                        prev = None
                        continue
                    if prev is not None:
                        counts[(prev, w)] += 1
                    prev = w
    return Counter(dict(counts.most_common(top_n)))


def build_bigrams_gutenberg(top_n: int = 100_000) -> Counter:
    """Stage 3 fallback: bigrams from the NLTK Project Gutenberg sample
    (18 pre-1923 public-domain books). Kept for offline / no-network
    builds; `build_bigrams` (WikiText) is the default."""
    from nltk.corpus import gutenberg
    counts: Counter = Counter()
    for sent in gutenberg.sents():
        prev: str | None = None
        for raw in sent:
            w = _normalize_token(raw)
            if w is None:
                prev = None
                continue
            if prev is not None:
                counts[(prev, w)] += 1
            prev = w
    return Counter(dict(counts.most_common(top_n)))


def emit_bigrams_tsv(counts: Counter, out_path: Path, lang: str, built_iso: str) -> str:
    """Write the bigrams TSV and register it in the shared manifest.
    Returns sha256 of the body."""
    from . import SCHEMA_VERSION
    from .emit import update_manifest

    out_path.parent.mkdir(parents=True, exist_ok=True)
    rows = sorted(counts.items(), key=lambda kv: (kv[0][0], kv[0][1]))
    body_lines = [f"{w1}\t{w2}\t{c}" for (w1, w2), c in rows]
    body = "\n".join(body_lines) + "\n"
    body_sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
    header = [
        f"# fluera-bigrams v{SCHEMA_VERSION} lang={lang} built={built_iso} "
        f"sha256={body_sha} rows={len(rows)}",
        "w1\tw2\tcount",
    ]
    out_path.write_text("\n".join(header) + "\n" + body, encoding="utf-8")
    print(f"[bigrams] wrote {out_path} ({len(rows)} rows, body sha256={body_sha[:12]})")
    update_manifest(out_path.parent, lang, out_path.name, body_sha, len(rows))
    return body_sha


def _normalize_token(raw: str) -> str | None:
    """Lowercase, NFC, alphabetic-only. Allows single-letter words ('a',
    'i') so high-frequency bigrams like 'i am' / 'a few' survive."""
    if not raw:
        return None
    s = unicodedata.normalize("NFC", raw).lower()
    if not s.isalpha():  # rejects punct, digits, mixed tokens
        return None
    return s
