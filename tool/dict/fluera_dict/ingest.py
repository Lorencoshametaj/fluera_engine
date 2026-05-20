"""Source data ingestion.

Every source bundled here has been **explicitly verified commercial-OK**:

- **wordfreq** (Robyn Speer, Apache 2.0). Data files are CC BY-SA 4.0, with
  bundled SUBTLEX (Brysbaert) wordlists redistributed under explicit e-mail
  permission from Marc Brysbaert "to be used for any purpose, not just for
  academic use" (see wordfreq NOTICE.md). Attribution required: SUBTLEX
  authors + clear note that SUBTLEX is freely available.
- **LDNOOBW** (Shutterstock, CC BY 4.0). Attribution required.
- **NLTK Gutenberg sample**. Pre-1923 authors → US public domain. Used for
  bigram derivation. Brown and Reuters corpora are intentionally NOT used
  (Brown's terms are commercial-ambiguous; Reuters-21578 is explicitly
  "for research purposes only").

The legacy SUBTLEX-US direct download + Brysbaert 2014 concreteness XLSX
ingestion was removed (2026-05-19) after a licensing audit found neither
had explicit commercial-use permission documented at the source.
"""

from __future__ import annotations

import hashlib
import re
import urllib.request
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"


# ── wordfreq frequencies (replaces SUBTLEX-US direct download) ───────────


def read_wordfreq_en(target_size: int = 30_000) -> list[tuple[str, float]]:
    """Return `[(word, zipf_frequency)]` for the top [target_size] English
    words from wordfreq's 'best' wordlist.

    Zipf scale: 1.0 (rarest, 1 in 10^9) to ~8.0 (top-frequency function
    words). Caller assigns dense rank 1..N based on returned order.
    """
    import wordfreq
    top = wordfreq.top_n_list("en", target_size, wordlist="best")
    out: list[tuple[str, float]] = []
    for w in top:
        zipf = wordfreq.zipf_frequency(w, "en", wordlist="best")
        out.append((w, zipf))
    print(f"[ingest] wordfreq: {len(out)} EN words (zipf scale)")
    return out


# ── LDNOOBW profanity list (Stage 2) ─────────────────────────────────────


LDNOOBW_URL = (
    "https://raw.githubusercontent.com/LDNOOBW/"
    "List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/en"
)
LDNOOBW_FILENAME = "ldnoobw_en.txt"


def download_ldnoobw(force: bool = False) -> Path:
    """Cache the LDNOOBW English list in data/raw/."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / LDNOOBW_FILENAME
    if out.exists() and not force:
        return out
    print(f"[ingest] downloading LDNOOBW from {LDNOOBW_URL}", flush=True)
    req = urllib.request.Request(
        LDNOOBW_URL,
        headers={"User-Agent": "fluera-dict/0.1 (build-pipeline)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    out.write_bytes(data)
    print(f"[ingest] wrote {out} ({len(data)} bytes)")
    return out


def read_ldnoobw_single_words(path: Path) -> set[str]:
    """Return the LDNOOBW set restricted to single-word entries."""
    out: set[str] = set()
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip().lower()
            if not s or " " in s or len(s) < 2:
                continue
            out.add(s)
    return out


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ── Model-estimated concreteness + AoA (Stage 6.1) ───────────────────────


CURATED_DIR = Path(__file__).resolve().parent.parent / "data" / "curated"
LLM_RATINGS_FILE = "llm_ratings_en.tsv"


def read_llm_ratings() -> dict[str, tuple[float | None, float | None]]:
    """Return `{word: (concreteness, aoa)}` from the checked-in
    `data/curated/llm_ratings_en.tsv`.

    These are **model-estimated** values, NOT the empirical Brysbaert /
    Kuperman datasets (those have no commercial-use permission). Generated
    once and frozen as a curated file so the build stays idempotent.
    Returns an empty dict when the file is absent — concrete/aoa columns
    then stay `-`.

    File format (tab-separated, `#` comment lines skipped):
        word<TAB>concrete<TAB>aoa
    Either metric may be `-` for a given word.
    """
    path = CURATED_DIR / LLM_RATINGS_FILE
    if not path.exists():
        print(f"[ingest] {LLM_RATINGS_FILE} not present — concrete/aoa stay '-'")
        return {}
    out: dict[str, tuple[float | None, float | None]] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        cells = line.split("\t")
        if len(cells) != 3:
            continue
        word = cells[0]
        concrete = _float_or_none(cells[1])
        aoa = _float_or_none(cells[2])
        out[word] = (concrete, aoa)
    print(f"[ingest] parsed {len(out)} model-estimated concrete/aoa ratings")
    return out


def _float_or_none(cell: str) -> float | None:
    cell = cell.strip()
    if not cell or cell == "-":
        return None
    try:
        return round(float(cell), 2)
    except ValueError:
        return None


# ── US Courts legal glossary (Stage 5) ───────────────────────────────────


# The official glossary of legal terms published by the Administrative
# Office of the U.S. Courts. A U.S.-government work → public domain.
USCOURTS_GLOSSARY_URL = "https://www.uscourts.gov/glossary"
USCOURTS_FILENAME = "uscourts_glossary.html"

_DT_RE = re.compile(r"<dt[^>]*>([^<]+)</dt>", re.IGNORECASE)


def download_uscourts_glossary(force: bool = False) -> Path:
    """Cache the US Courts legal glossary HTML in data/raw/."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / USCOURTS_FILENAME
    if out.exists() and not force:
        return out
    print(f"[ingest] downloading US Courts glossary from {USCOURTS_GLOSSARY_URL}", flush=True)
    req = urllib.request.Request(
        USCOURTS_GLOSSARY_URL,
        headers={"User-Agent": "fluera-dict/0.1 (build-pipeline)"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    out.write_bytes(data)
    print(f"[ingest] wrote {out} ({len(data) // 1024} KB)")
    return out


def read_uscourts_single_word_terms(path: Path) -> set[str]:
    """Return single-word legal terms from the US Courts glossary.

    The glossary marks each headword in a `<dt>` element. Multi-word
    entries ("Bankruptcy judge", "Burden of proof") are skipped — same
    rationale as MeSH: tokenising them pollutes the set with general
    English. Top-1000 common English words are excluded so general terms
    that happen to be glossary headwords ("answer", "file", "court",
    "issue", "record") don't false-positive as primarily legal.
    """
    import wordfreq
    exclusion = {
        w for w in wordfreq.top_n_list("en", 1000, wordlist="best")
        if w.isalpha()
    }

    html = path.read_text(encoding="utf-8", errors="ignore")
    out: set[str] = set()
    for raw in _DT_RE.findall(html):
        term = raw.strip()
        if not term or " " in term:
            continue
        low = term.lower()
        if len(low) >= 3 and low.isalpha() and low not in exclusion:
            out.add(low)
    print(f"[ingest] parsed {len(out)} single-word US Courts legal terms "
          f"(after top-1000 EN exclusion)")
    return out


# ── MeSH 2025 medical vocabulary (Stage 4) ───────────────────────────────


# US National Library of Medicine — Medical Subject Headings.
# Explicit public-domain declaration (DC.Rights = "Public Domain") since
# MeSH is a US-government work; commercial reuse is unrestricted.
MESH_URL = (
    "https://nlmpubs.nlm.nih.gov/projects/mesh/2025/asciimesh/d2025.bin"
)
MESH_FILENAME = "mesh_d2025.bin"


def download_mesh(force: bool = False) -> Path:
    """Cache the MeSH 2025 ASCII descriptor file in data/raw/."""
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / MESH_FILENAME
    if out.exists() and not force:
        return out
    print(f"[ingest] downloading MeSH 2025 from {MESH_URL}", flush=True)
    req = urllib.request.Request(
        MESH_URL,
        headers={"User-Agent": "fluera-dict/0.1 (build-pipeline)"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    out.write_bytes(data)
    print(f"[ingest] wrote {out} ({len(data) // 1024 // 1024} MB)")
    return out


def read_mesh_single_word_terms(path: Path) -> set[str]:
    """Return the set of lowercased single-word medical terms extracted
    from MeSH MH (Main Heading) and ENTRY (synonym) lines.

    Filtering rules:
      1. Single-token only — multi-word phrases ("Abdominal Injuries")
         are dropped so we don't tokenise them into general English
         components ("the", "good", "computer").
      2. Top-1000 most common English words are excluded — MeSH
         legitimately lists "Child" / "Computer" / "Algorithm" as
         standalone descriptors for medical age categories, computational
         aids, and clinical algorithms, but tagging them as primarily
         medical false-positives in our setting (a Fluera user typing
         "child" almost never means the MeSH "Child" descriptor).
    """
    # Build the high-frequency exclusion set lazily via wordfreq.
    import wordfreq
    exclusion = {
        w for w in wordfreq.top_n_list("en", 1000, wordlist="best")
        if w.isalpha()
    }

    out: set[str] = set()
    with path.open("r", encoding="latin-1") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if not (line.startswith("MH = ") or line.startswith("ENTRY = ")):
                continue
            value = line.split(" = ", 1)[1]
            value = value.split("|", 1)[0].strip()
            if not value or any(c in value for c in " ,-/'."):
                continue
            low = value.lower()
            if len(low) >= 3 and low.isalpha() and low not in exclusion:
                out.add(low)
    print(f"[ingest] parsed {len(out)} single-token MeSH terms "
          f"(after top-1000 EN exclusion)")
    return out
