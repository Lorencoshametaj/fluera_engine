"""CLI entrypoint: `python -m fluera_dict <command> <lang>`."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from . import build as build_mod
from . import validate as validate_mod


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="fluera-dict", description=__doc__)
    p.add_argument("--version", action="version", version=f"fluera-dict {__version__}")
    sub = p.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build", help="build a language dictionary TSV")
    b.add_argument("lang", choices=["en"], help="language code")
    b.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output TSV path (default: ../../fluera_engine/assets/dictionaries/<lang>.tsv)",
    )
    b.add_argument("--target-size", type=int, default=55000, help="max rows to emit")

    v = sub.add_parser("validate", help="validate an emitted TSV")
    v.add_argument("lang", choices=["en"], help="language code")
    v.add_argument("--path", type=Path, default=None, help="TSV path to validate")
    v.add_argument("--phrases", action="store_true",
                   help="validate the <lang>.phrases.tsv asset instead of the dict")

    bg = sub.add_parser("bigrams", help="build the en.bigrams.tsv asset")
    bg.add_argument("lang", choices=["en"], help="language code")
    bg.add_argument("--top-n", type=int, default=100_000, help="keep top N bigrams")
    bg.add_argument("--out", type=Path, default=None, help="output path")

    ph = sub.add_parser("phrases", help="build the en.phrases.tsv asset")
    ph.add_argument("lang", choices=["en"], help="language code")
    ph.add_argument("--out", type=Path, default=None, help="output path")

    lc = sub.add_parser("llm-chunks",
                        help="split top-N words into chunk files for LLM rating")
    lc.add_argument("lang", choices=["en"], help="language code")
    lc.add_argument("--top-n", type=int, default=15000, help="words to rate")

    la = sub.add_parser("llm-assemble",
                        help="merge rated chunks → data/curated/llm_ratings_en.tsv")
    la.add_argument("lang", choices=["en"], help="language code")

    args = p.parse_args(argv)

    if args.cmd == "build":
        out = args.out or _default_out_path(args.lang)
        return build_mod.run(lang=args.lang, out=out, target_size=args.target_size)
    if args.cmd == "validate":
        if args.phrases:
            path = args.path or _default_out_path(args.lang).with_suffix(".phrases.tsv")
            return validate_mod.run_phrases(path=path)
        path = args.path or _default_out_path(args.lang)
        return validate_mod.run(path=path, lang=args.lang)
    if args.cmd == "bigrams":
        from . import bigrams as bg_mod
        from . import build as build_mod_inner
        out = args.out or _default_out_path(args.lang).with_suffix(".bigrams.tsv")
        counts = bg_mod.build_bigrams(top_n=args.top_n)
        bg_mod.emit_bigrams_tsv(counts, out_path=out, lang=args.lang, built_iso=build_mod_inner.BUILT_ISO)
        return 0
    if args.cmd == "phrases":
        from . import phrases as ph_mod
        from . import build as build_mod_inner
        out = args.out or _default_out_path(args.lang).with_suffix(".phrases.tsv")
        rows = ph_mod.build_phrases()
        ph_mod.emit_phrases_tsv(rows, out_path=out, lang=args.lang,
                                built_iso=build_mod_inner.BUILT_ISO)
        return 0
    if args.cmd == "llm-chunks":
        from . import llm_ratings as lr_mod
        en_tsv = _default_out_path(args.lang)
        lr_mod.write_chunks(en_tsv, top_n=args.top_n)
        return 0
    if args.cmd == "llm-assemble":
        from . import llm_ratings as lr_mod
        lr_mod.assemble_ratings()
        return 0
    return 1


def _default_out_path(lang: str) -> Path:
    # This file lives at  fluera_engine/tool/dict/fluera_dict/cli.py
    # parents: [0]=fluera_dict [1]=dict [2]=tool [3]=fluera_engine
    engine_root = Path(__file__).resolve().parents[3]
    return engine_root / "assets" / "dictionaries" / f"{lang}.tsv"


if __name__ == "__main__":
    sys.exit(main())
