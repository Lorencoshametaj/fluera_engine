"""Orchestrate the build: ingest → normalize → enrich → curate → emit."""

from __future__ import annotations

from pathlib import Path

from . import ingest, normalize, enrich, curate, emit
from . import BUILT

# Back-compat alias — `phrases`/`bigrams` import `build.BUILT_ISO`.
BUILT_ISO = BUILT


# Row shape (Stage 4):
#   (word, freq_rank, pos, domains, root, cefr, concrete, aoa, flags)
# `domains` gets `med` from MeSH (US NLM public domain, Stage 4).
# Other domains (law/stem/etc.) await curated sources in later stages.
# `concrete` stays None (Brysbaert ESM lacks commercial permission).
# `aoa` stays None unless Kuperman 2012 dropped manually in data/raw/.
RowT = tuple[
    str, int, str,
    list[str],         # domains
    str | None,        # root
    str | None,        # cefr
    float | None,      # concrete
    float | None,      # aoa
    list[str],         # flags
]


def run(lang: str, out: Path, target_size: int) -> int:
    if lang != "en":
        print(f"[build] FAIL: lang {lang!r} not supported in current stage")
        return 1

    # 1. Ingest — frequency core via wordfreq (commercial-OK Apache 2.0 +
    #    SUBTLEX-via-Speer commercial permission). The legacy direct
    #    SUBTLEX-US dump was removed during the 2026-05-19 license audit.
    word_freqs = ingest.read_wordfreq_en(target_size=target_size * 2)

    # Stage 2 — profanity flags
    ldnoobw_path = ingest.download_ldnoobw()
    profanity_pool = ingest.read_ldnoobw_single_words(ldnoobw_path)
    slur_overrides = curate.load_list(f"slurs_{lang}.txt")
    sexual_overrides = curate.load_list(f"sexual_{lang}.txt")

    # Stage 3 / 6.1 — cognitive metadata.
    # Brysbaert concreteness + Kuperman AoA were removed during the licence
    # audit (no commercial-use permission). Stage 6.1 replaces them with
    # *model-estimated* values frozen in data/curated/llm_ratings_en.tsv —
    # original generated data, no third-party dataset, clearly labelled as
    # estimates (see LICENSE.md). Empty dict ⇒ concrete/aoa stay `-`.
    llm_ratings = ingest.read_llm_ratings()

    # Stage 4 — medical domain via MeSH (US NLM, public domain).
    mesh_path = ingest.download_mesh()
    mesh_terms = ingest.read_mesh_single_word_terms(mesh_path)

    # Stage 5 — legal domain via US Courts glossary (US gov, public domain).
    glossary_path = ingest.download_uscourts_glossary()
    legal_terms = ingest.read_uscourts_single_word_terms(glossary_path)

    # Stage 6 — STEM / CS / Finance domains via curated word lists
    # (factual term lists we author → no third-party licence).
    stem_terms = curate.load_list(f"stem_terms_{lang}.txt")
    cs_terms = curate.load_list(f"cs_terms_{lang}.txt")
    finance_terms = curate.load_list(f"finance_terms_{lang}.txt")

    # 2. Normalize + enrich one row at a time. wordfreq already returns
    #    words in descending frequency order; we assign a dense rank.
    ranked: list[RowT] = []
    for rank, (word, _zipf) in enumerate(word_freqs, start=1):
        norm = normalize.normalize_word(word)
        if norm is None:
            continue
        pos = enrich.pos_for(norm)
        root = enrich.root_for(norm, pos)
        cefr = enrich.cefr_for(norm, root=root, freq_rank=rank)
        domains = enrich.domain_for(
            norm,
            mesh_terms=mesh_terms,
            legal_terms=legal_terms,
            stem_terms=stem_terms,
            cs_terms=cs_terms,
            finance_terms=finance_terms,
        )
        flags = enrich.flag_for(
            norm,
            profanity_pool=profanity_pool,
            slur_overrides=slur_overrides,
            sexual_overrides=sexual_overrides,
        )
        flags = _with_derived_flags(flags, word=norm, pos=pos, root=root)
        concrete, aoa = llm_ratings.get(norm, (None, None))
        ranked.append((norm, rank, pos, domains, root, cefr, concrete, aoa, flags))
        if len(ranked) >= target_size:
            break

    # 3. Curate
    includes = curate.load_list(f"include_{lang}.txt")
    includes = {w for w in (normalize.normalize_word(x) for x in includes) if w}
    excludes = curate.load_list(f"exclude_{lang}.txt")
    excludes = {w for w in (normalize.normalize_word(x) for x in excludes) if w}

    ranked = _apply_excludes(ranked, excludes)
    ranked = _apply_includes(
        ranked, includes,
        profanity_pool=profanity_pool,
        slur_overrides=slur_overrides,
        sexual_overrides=sexual_overrides,
        llm_ratings=llm_ratings,
        mesh_terms=mesh_terms,
        legal_terms=legal_terms,
        stem_terms=stem_terms,
        cs_terms=cs_terms,
        finance_terms=finance_terms,
    )

    final = _dedupe_and_sort(ranked)

    # 4. Emit + register in the shared manifest.
    body_sha = emit.emit_tsv(final, out_path=out, lang=lang, built_iso=BUILT_ISO)
    emit.update_manifest(
        out_dir=out.parent,
        lang=lang,
        asset_filename=out.name,
        asset_sha=body_sha,
        asset_rows=len(final),
    )

    # Coverage telemetry for reviewers.
    total = len(final)
    n_pos = sum(1 for r in final if r[2] != "x")
    n_root = sum(1 for r in final if r[4] is not None)
    n_cefr = sum(1 for r in final if r[5] is not None)
    n_conc = sum(1 for r in final if r[6] is not None)
    n_aoa = sum(1 for r in final if r[7] is not None)
    dom_counts = {d: sum(1 for r in final if d in r[3])
                  for d in ("med", "law", "stem", "cs", "fin")}
    flag_counts: dict[str, int] = {}
    for r in final:
        for f in r[8]:
            flag_counts[f] = flag_counts.get(f, 0) + 1
    cefr_counts: dict[str, int] = {}
    for r in final:
        if r[5] is not None:
            cefr_counts[r[5]] = cefr_counts.get(r[5], 0) + 1

    print(f"[build] coverage — pos={n_pos}/{total} ({100*n_pos//total}%), "
          f"root={n_root}/{total} ({100*n_root//total}%), "
          f"cefr={n_cefr}/{total} ({100*n_cefr//total}%), "
          f"concrete={n_conc}/{total} ({100*n_conc//total}%), "
          f"aoa={n_aoa}/{total} ({100*n_aoa//total}%)")
    print(f"[build] domains — " + ", ".join(f"{d}={c}" for d, c in dom_counts.items()))
    print(f"[build] cefr — " + ", ".join(
        f"{lv}={cefr_counts.get(lv, 0)}" for lv in
        ("A1", "A2", "B1", "B2", "C1", "C2")))
    print(f"[build] flags — " + ", ".join(
        f"{f}={c}" for f, c in sorted(flag_counts.items())))
    print(f"[build] DONE — {total} rows → {out}")
    return 0


def _with_derived_flags(
    flags: list[str], *, word: str, pos: str, root: str | None,
) -> list[str]:
    """Append the flags that are mechanically derivable from other
    columns: `proper` (pos == prop), `inflected` (has a root),
    `contraction` (contains an apostrophe). Keeps the list deduped."""
    out = list(flags)
    if pos == "prop" and "proper" not in out:
        out.append("proper")
    if root is not None and "inflected" not in out:
        out.append("inflected")
    if "'" in word and "contraction" not in out:
        out.append("contraction")
    return out


def _apply_excludes(rows: list[RowT], excludes: set[str]) -> list[RowT]:
    if not excludes:
        return rows
    return [r for r in rows if r[0] not in excludes]


def _apply_includes(
    rows: list[RowT],
    includes: set[str],
    *,
    profanity_pool: set[str],
    slur_overrides: set[str],
    sexual_overrides: set[str],
    llm_ratings: dict[str, tuple[float | None, float | None]],
    mesh_terms: set[str],
    legal_terms: set[str],
    stem_terms: set[str],
    cs_terms: set[str],
    finance_terms: set[str],
) -> list[RowT]:
    present = {r[0] for r in rows}
    missing = sorted(includes - present)
    if not missing:
        return rows
    base_rank = max((r[1] for r in rows), default=0) + 1
    extras: list[RowT] = []
    for i, w in enumerate(missing):
        pos = enrich.pos_for(w)
        root = enrich.root_for(w, pos)
        rank = base_rank + i
        flags = enrich.flag_for(
            w,
            profanity_pool=profanity_pool,
            slur_overrides=slur_overrides,
            sexual_overrides=sexual_overrides,
        )
        flags = _with_derived_flags(flags, word=w, pos=pos, root=root)
        concrete, aoa = llm_ratings.get(w, (None, None))
        extras.append((
            w, rank, pos,
            enrich.domain_for(
                w, mesh_terms=mesh_terms, legal_terms=legal_terms,
                stem_terms=stem_terms, cs_terms=cs_terms,
                finance_terms=finance_terms,
            ),
            root,
            enrich.cefr_for(w, root=root, freq_rank=rank),
            concrete,
            aoa,
            flags,
        ))
    return rows + extras


def _dedupe_and_sort(rows: list[RowT]) -> list[RowT]:
    """Dedupe on word, keep the row with the smallest freq_rank, sort by word."""
    best: dict[str, RowT] = {}
    for r in rows:
        prev = best.get(r[0])
        if prev is None or r[1] < prev[1]:
            best[r[0]] = r
    return sorted(best.values(), key=lambda r: r[0])
