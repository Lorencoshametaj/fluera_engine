"""Serialize the curated word table to TSV, and maintain the shared
`en.manifest.json` integrity + provenance registry.

Output is byte-identical for the same input (deterministic sort; the
`built` field is a static manual release date, not a timestamp).
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from . import SCHEMA_V1, SCHEMA_VERSION, BUILT, EMPTY, SOURCES, COLUMN_PROVENANCE


def emit_tsv(
    rows: list[tuple[
        str, int, str, list[str], str | None, str | None,
        float | None, float | None, list[str],
    ]],
    out_path: Path,
    lang: str,
    built_iso: str,
) -> str:
    """Write the 9-column TSV. Returns sha256 of the body (excluding header).

    Row shape: `(word, freq_rank, pos, domains, root, cefr, concrete, aoa, flags)`.
    Floats render with 2 decimal places for stable diff; missing values
    and empty lists emit the `-` sentinel.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)

    body_lines = []
    for word, rank, pos, domains, root, cefr, concrete, aoa, flags in rows:
        cells = [
            word,
            str(rank),
            pos,
            ",".join(sorted(domains)) if domains else EMPTY,
            root if root else EMPTY,
            cefr if cefr else EMPTY,
            f"{concrete:.2f}" if concrete is not None else EMPTY,
            f"{aoa:.2f}" if aoa is not None else EMPTY,
            ",".join(sorted(flags)) if flags else EMPTY,
        ]
        body_lines.append("\t".join(cells))
    body = "\n".join(body_lines) + "\n"
    body_sha = hashlib.sha256(body.encode("utf-8")).hexdigest()

    header_lines = [
        f"# fluera-dict v{SCHEMA_VERSION} lang={lang} built={built_iso} "
        f"sha256={body_sha} rows={len(rows)}",
        f"# schema={','.join(SCHEMA_V1)}",
        "\t".join(SCHEMA_V1),
    ]
    out_path.write_text("\n".join(header_lines) + "\n" + body, encoding="utf-8")
    print(f"[emit] wrote {out_path} ({len(rows)} rows, body sha256={body_sha[:12]})")
    return body_sha


def update_manifest(
    out_dir: Path,
    lang: str,
    asset_filename: str,
    asset_sha: str,
    asset_rows: int,
) -> None:
    """Record one asset's sha256 + row count in `<lang>.manifest.json`.

    The manifest is the integrity + provenance registry for ALL THREE
    sibling assets (en.tsv / en.phrases.tsv / en.bigrams.tsv). Each build
    command — `build`, `phrases`, `bigrams` — calls this for its own
    asset; the existing `assets` entries for the other two are read back
    and preserved, so running the three commands in any order converges
    on a complete manifest.
    """
    path = out_dir / f"{lang}.manifest.json"

    # Preserve sibling asset entries from any existing manifest.
    existing_assets: dict[str, dict] = {}
    if path.exists():
        try:
            prev = json.loads(path.read_text(encoding="utf-8"))
            existing_assets = prev.get("assets", {})
        except (json.JSONDecodeError, OSError):
            existing_assets = {}
    existing_assets[asset_filename] = {"sha256": asset_sha, "rows": asset_rows}

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "language": lang,
        "built": BUILT,
        "columns": list(SCHEMA_V1),          # describes en.tsv
        "empty_sentinel": EMPTY,
        "assets": dict(sorted(existing_assets.items())),
        "column_provenance": COLUMN_PROVENANCE,
        "sources": SOURCES,
    }
    path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"[emit] manifest updated — {asset_filename} "
          f"({asset_rows} rows, sha256={asset_sha[:12]})")
