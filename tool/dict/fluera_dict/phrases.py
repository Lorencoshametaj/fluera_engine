"""Build the multi-word expression asset
`fluera_engine/assets/dictionaries/<lang>.phrases.tsv`.

The main dictionary (`en.tsv`) is single-token only, so fixed expressions
like "machine learning", "in vivo", "burden of proof", "bone marrow"
cannot be looked up. Stage 6 adds a companion asset for them.

Sources (all already cached / commercial-OK):
  - MeSH 2025 Main Headings with a space  → kind=medical, domains=med
  - US Courts glossary multi-word terms   → kind=legal,   domains=law
  - curated Latin / academic phrases      → kind=latin,   domains=-

Output schema (tab-separated, lex-sorted, `#` header lines):
    phrase<TAB>domains<TAB>kind
"""

from __future__ import annotations

import hashlib
import re
import unicodedata
from pathlib import Path

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
CURATED_DIR = Path(__file__).resolve().parent.parent / "data" / "curated"

VALID_KINDS = {"latin", "medical", "legal", "general"}

# A phrase must be 2-4 whitespace tokens, each ≥ 2 chars, pure alphabetic.
_TOKEN_OK = re.compile(r"[a-z]+(?:'[a-z]+)?\Z")


def build_phrases() -> list[tuple[str, list[str], str]]:
    """Collect, dedupe and sort the phrase rows. Returns
    `[(phrase, domains, kind)]` sorted by phrase."""
    # phrase → (domains set, kind). First writer wins on kind; domains merge.
    acc: dict[str, tuple[set[str], str]] = {}

    def add(phrase: str, domain: str | None, kind: str) -> None:
        norm = _normalize_phrase(phrase)
        if norm is None:
            return
        if norm in acc:
            doms, _kind = acc[norm]
            if domain:
                doms.add(domain)
        else:
            acc[norm] = ({domain} if domain else set(), kind)

    # 1. Curated Latin / academic phrases.
    latin_path = CURATED_DIR / "latin_phrases_en.txt"
    if latin_path.exists():
        for raw in latin_path.read_text(encoding="utf-8").splitlines():
            s = raw.strip()
            if s and not s.startswith("#"):
                add(s, None, "latin")

    # 2. US Courts glossary multi-word legal terms.
    glossary = RAW_DIR / "uscourts_glossary.html"
    if glossary.exists():
        html = glossary.read_text(encoding="utf-8", errors="ignore")
        for term in re.findall(r"<dt[^>]*>([^<]+)</dt>", html, re.IGNORECASE):
            add(term.strip(), "law", "legal")

    # 3. MeSH Main Headings with a space (medical multi-word terms).
    mesh = RAW_DIR / "mesh_d2025.bin"
    if mesh.exists():
        with mesh.open("r", encoding="latin-1") as fh:
            for line in fh:
                if not line.startswith("MH = "):
                    continue
                value = line[5:].strip()
                if " " not in value:
                    continue  # single-word MH already in en.tsv
                add(_deinvert(value), "med", "medical")

    rows = [
        (phrase, sorted(doms), kind)
        for phrase, (doms, kind) in acc.items()
    ]
    rows.sort(key=lambda r: r[0])
    return rows


def emit_phrases_tsv(
    rows: list[tuple[str, list[str], str]],
    out_path: Path,
    lang: str,
    built_iso: str,
) -> str:
    """Write the phrases TSV and register it in the shared manifest.
    Returns sha256 of the body."""
    from . import SCHEMA_VERSION
    from .emit import update_manifest

    out_path.parent.mkdir(parents=True, exist_ok=True)
    body_lines = [
        f"{phrase}\t{','.join(doms) if doms else '-'}\t{kind}"
        for phrase, doms, kind in rows
    ]
    body = "\n".join(body_lines) + "\n"
    body_sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
    header = [
        f"# fluera-phrases v{SCHEMA_VERSION} lang={lang} built={built_iso} "
        f"sha256={body_sha} rows={len(rows)}",
        "phrase\tdomains\tkind",
    ]
    out_path.write_text("\n".join(header) + "\n" + body, encoding="utf-8")
    print(f"[phrases] wrote {out_path} ({len(rows)} rows, body sha256={body_sha[:12]})")
    update_manifest(out_path.parent, lang, out_path.name, body_sha, len(rows))
    return body_sha


def _deinvert(value: str) -> str:
    """MeSH stores many headings inverted: "Abdomen, Acute" really means
    "Acute Abdomen". Swap a single 2-part comma inversion back to natural
    order; leave everything else as-is."""
    parts = [p.strip() for p in value.split(",")]
    if len(parts) == 2 and all(parts):
        return f"{parts[1]} {parts[0]}"
    return value.replace(",", " ")


def _normalize_phrase(raw: str) -> str | None:
    """Lowercase + NFC + collapse whitespace. Returns None unless the
    phrase is 2-4 tokens, each a pure-alphabetic word ≥ 2 chars."""
    s = unicodedata.normalize("NFC", raw).strip().lower()
    s = re.sub(r"\s+", " ", s)
    if not s:
        return None
    tokens = s.split(" ")
    if not (2 <= len(tokens) <= 4):
        return None
    for t in tokens:
        if len(t) < 2 or not _TOKEN_OK.match(t):
            return None
    return s
