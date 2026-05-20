"""Apply manual override lists from data/curated/.

Files (one word per line, '#' comments ignored):
  include_<lang>.txt   words to force-include (rank assigned at end of list if absent)
  exclude_<lang>.txt   words to force-exclude (e.g., homoglyph survivors)
"""

from __future__ import annotations

from pathlib import Path

CURATED_DIR = Path(__file__).resolve().parent.parent / "data" / "curated"


def load_list(name: str) -> set[str]:
    """Read a one-word-per-line list. Skip blanks and '#' comments."""
    path = CURATED_DIR / name
    if not path.exists():
        return set()
    out: set[str] = set()
    with path.open("r", encoding="utf-8") as f:
        for raw in f:
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            out.add(s.lower())
    return out


def apply_includes(
    rows: list[tuple[str, int, str]],
    includes: set[str],
    default_pos: str = "x",
) -> list[tuple[str, int, str]]:
    """Ensure every word in `includes` appears in `rows`. Append missing at end."""
    present = {w for w, _, _ in rows}
    missing = includes - present
    if not missing:
        return rows
    base_rank = max((r for _, r, _ in rows), default=0) + 1
    extras = [(w, base_rank + i, default_pos) for i, w in enumerate(sorted(missing))]
    return rows + extras


def apply_excludes(
    rows: list[tuple[str, int, str]],
    excludes: set[str],
) -> list[tuple[str, int, str]]:
    """Drop any row whose word is in `excludes`."""
    if not excludes:
        return rows
    return [r for r in rows if r[0] not in excludes]
