"""Validate an emitted TSV. Exit non-zero on any check failure.

Checks (Stage 1):
  - Header present, schema row matches SCHEMA_V1
  - Every body row has exactly len(SCHEMA_V1) cells
  - No duplicate words
  - Rows sorted lexicographically by word (NFC)
  - No homoglyph codepoints in word column (Greek/Cyrillic disguised as Latin)
  - freq_rank parses as positive int
  - pos in VALID_POS
  - header `rows=N` matches actual body row count
  - header sha256 matches recomputed body sha256
"""

from __future__ import annotations

import hashlib
import re
import unicodedata
from pathlib import Path

from . import SCHEMA_V1
from .enrich import VALID_POS, VALID_FLAGS, VALID_DOMAINS

VALID_CEFR = {"A1", "A2", "B1", "B2", "C1", "C2"}

_FORBIDDEN_CODEPOINTS = {
    "ο",  # Greek omicron
    "η",  # Greek eta
    "а", "е", "о", "р", "с", "х",  # Cyrillic look-alikes
}


def run(path: Path, lang: str) -> int:
    if not path.exists():
        print(f"[validate] FAIL: {path} does not exist")
        return 1

    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines:
        print("[validate] FAIL: empty file")
        return 1

    header_rows = _parse_header_rows(lines[0])
    declared_sha = _parse_header_sha(lines[0])
    schema_line = next((ln for ln in lines if ln.startswith("# schema=")), None)
    if schema_line is None:
        print("[validate] FAIL: missing `# schema=` line")
        return 1

    # First non-comment row = column header; rest = body
    body_start_idx = None
    for i, ln in enumerate(lines):
        if not ln.startswith("#"):
            body_start_idx = i
            break
    if body_start_idx is None:
        print("[validate] FAIL: no body rows")
        return 1

    col_header = lines[body_start_idx].split("\t")
    if tuple(col_header) != SCHEMA_V1:
        print(f"[validate] FAIL: column header mismatch\n  got: {col_header}\n  expected: {list(SCHEMA_V1)}")
        return 1

    body_lines = lines[body_start_idx + 1:]
    fails = 0
    prev_word = ""
    seen: set[str] = set()
    for n, ln in enumerate(body_lines, start=body_start_idx + 2):
        cells = ln.split("\t")
        if len(cells) != len(SCHEMA_V1):
            print(f"[validate] FAIL line {n}: expected {len(SCHEMA_V1)} cells, got {len(cells)}")
            fails += 1
            continue
        word = cells[0]
        freq = cells[1]
        pos = cells[2]
        domains_cell = cells[3]
        root_cell = cells[4]
        cefr_cell = cells[5]
        concrete_cell = cells[6]
        aoa_cell = cells[7]
        flags_cell = cells[8]
        # Homoglyph check
        for cp in _FORBIDDEN_CODEPOINTS:
            if cp in word:
                print(f"[validate] FAIL line {n}: homoglyph U+{ord(cp):04X} in {word!r}")
                fails += 1
                break
        # NFC check
        if unicodedata.normalize("NFC", word) != word:
            print(f"[validate] FAIL line {n}: word not NFC-normalized: {word!r}")
            fails += 1
        # Dup check
        if word in seen:
            print(f"[validate] FAIL line {n}: duplicate word {word!r}")
            fails += 1
        seen.add(word)
        # Sort check
        if word < prev_word:
            print(f"[validate] FAIL line {n}: out of order ({prev_word!r} > {word!r})")
            fails += 1
        prev_word = word
        # freq_rank
        if not freq.isdigit() or int(freq) < 1:
            print(f"[validate] FAIL line {n}: bad freq_rank {freq!r}")
            fails += 1
        # pos
        if pos not in VALID_POS:
            print(f"[validate] FAIL line {n}: pos {pos!r} not in {VALID_POS}")
            fails += 1
        # flags (csv-in-cell; '-' = empty)
        if flags_cell != "-":
            for f in flags_cell.split(","):
                if f not in VALID_FLAGS:
                    print(f"[validate] FAIL line {n}: flag {f!r} not in {VALID_FLAGS}")
                    fails += 1
        # root (single token or '-')
        if root_cell != "-":
            if " " in root_cell or "\t" in root_cell:
                print(f"[validate] FAIL line {n}: root {root_cell!r} contains whitespace")
                fails += 1
            elif root_cell == word:
                # Build pipeline collapses self-roots to '-' to keep the
                # asset compact; surfacing self-roots wastes diff churn.
                print(f"[validate] FAIL line {n}: root equals word {word!r} (should be `-`)")
                fails += 1
        # domains (csv-in-cell; '-' = empty)
        if domains_cell != "-":
            for d in domains_cell.split(","):
                if d not in VALID_DOMAINS:
                    print(f"[validate] FAIL line {n}: domain {d!r} not in {VALID_DOMAINS}")
                    fails += 1
        # cefr (A1..C2 or '-')
        if cefr_cell != "-" and cefr_cell not in VALID_CEFR:
            print(f"[validate] FAIL line {n}: cefr {cefr_cell!r} not in {VALID_CEFR}")
            fails += 1
        # concrete (1.00–5.00 Brysbaert scale)
        if concrete_cell != "-":
            try:
                v = float(concrete_cell)
                if not (1.0 <= v <= 5.0):
                    print(f"[validate] FAIL line {n}: concrete {v} outside [1, 5]")
                    fails += 1
            except ValueError:
                print(f"[validate] FAIL line {n}: concrete {concrete_cell!r} not float")
                fails += 1
        # aoa (1.00–18.00 Kuperman scale)
        if aoa_cell != "-":
            try:
                v = float(aoa_cell)
                if not (1.0 <= v <= 18.0):
                    print(f"[validate] FAIL line {n}: aoa {v} outside [1, 18]")
                    fails += 1
            except ValueError:
                print(f"[validate] FAIL line {n}: aoa {aoa_cell!r} not float")
                fails += 1

    # Row-count header check
    if header_rows is not None and header_rows != len(body_lines):
        print(f"[validate] FAIL: header rows={header_rows} but body has {len(body_lines)}")
        fails += 1

    # Sha256 header check
    body_text = "\n".join(body_lines) + "\n"
    actual_sha = hashlib.sha256(body_text.encode("utf-8")).hexdigest()
    if declared_sha is not None and declared_sha != actual_sha:
        print(f"[validate] FAIL: header sha256 {declared_sha[:12]}.. but body sha is {actual_sha[:12]}..")
        fails += 1

    if fails:
        print(f"[validate] {fails} failure(s)")
        return 1
    print(f"[validate] OK — {len(body_lines)} rows, sha256={actual_sha[:12]}")
    return 0


VALID_PHRASE_KINDS = {"latin", "medical", "legal", "general"}


def run_phrases(path: Path) -> int:
    """Validate an emitted <lang>.phrases.tsv. Same exit-code contract as
    `run`: 0 = clean, 1 = at least one failure."""
    if not path.exists():
        print(f"[validate] FAIL: {path} does not exist")
        return 1
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines:
        print("[validate] FAIL: empty file")
        return 1

    declared_sha = _parse_header_sha(lines[0])
    declared_rows = _parse_header_rows(lines[0])

    body_start = None
    for i, ln in enumerate(lines):
        if not ln.startswith("#"):
            body_start = i
            break
    if body_start is None:
        print("[validate] FAIL: no body rows")
        return 1
    if lines[body_start].split("\t") != ["phrase", "domains", "kind"]:
        print(f"[validate] FAIL: bad column header {lines[body_start]!r}")
        return 1

    body = lines[body_start + 1:]
    fails = 0
    seen: set[str] = set()
    prev = ""
    for n, ln in enumerate(body, start=body_start + 2):
        cells = ln.split("\t")
        if len(cells) != 3:
            print(f"[validate] FAIL line {n}: expected 3 cells, got {len(cells)}")
            fails += 1
            continue
        phrase, domains_cell, kind = cells
        toks = phrase.split(" ")
        if not (2 <= len(toks) <= 4):
            print(f"[validate] FAIL line {n}: phrase {phrase!r} not 2-4 tokens")
            fails += 1
        if phrase in seen:
            print(f"[validate] FAIL line {n}: duplicate phrase {phrase!r}")
            fails += 1
        seen.add(phrase)
        if phrase < prev:
            print(f"[validate] FAIL line {n}: out of order ({prev!r} > {phrase!r})")
            fails += 1
        prev = phrase
        if kind not in VALID_PHRASE_KINDS:
            print(f"[validate] FAIL line {n}: kind {kind!r} not in {VALID_PHRASE_KINDS}")
            fails += 1
        if domains_cell != "-":
            for d in domains_cell.split(","):
                if d not in VALID_DOMAINS:
                    print(f"[validate] FAIL line {n}: domain {d!r} not in {VALID_DOMAINS}")
                    fails += 1

    if declared_rows is not None and declared_rows != len(body):
        print(f"[validate] FAIL: header rows={declared_rows} but body has {len(body)}")
        fails += 1
    body_text = "\n".join(body) + "\n"
    actual_sha = hashlib.sha256(body_text.encode("utf-8")).hexdigest()
    if declared_sha is not None and declared_sha != actual_sha:
        print(f"[validate] FAIL: header sha256 mismatch")
        fails += 1

    if fails:
        print(f"[validate] {fails} failure(s)")
        return 1
    print(f"[validate] OK — {len(body)} phrases, sha256={actual_sha[:12]}")
    return 0


def _parse_header_rows(line: str) -> int | None:
    m = re.search(r"\brows=(\d+)", line)
    return int(m.group(1)) if m else None


def _parse_header_sha(line: str) -> str | None:
    m = re.search(r"\bsha256=([0-9a-f]{64})\b", line)
    return m.group(1) if m else None
