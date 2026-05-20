"""Stage 1 build pipeline tests.

Two invariants we need to hold from day one:
  1. The build is **idempotent** — re-running `python -m fluera_dict build en`
     on the same machine produces a byte-identical TSV. Without this the
     git diff churns on every build and review becomes impossible.
  2. The emitted TSV **validates** — sort order, no homoglyphs, every row
     has 9 cells, sha256 header matches the body.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

import pytest

# This file lives at fluera_engine/tool/dict/tests/test_build.py
# parents: [0]=tests [1]=dict [2]=tool [3]=fluera_engine
TOOLS_DIR = Path(__file__).resolve().parents[1]            # tool/dict/
ENGINE_ROOT = Path(__file__).resolve().parents[3]          # fluera_engine/
ASSET_TSV = ENGINE_ROOT / "assets" / "dictionaries" / "en.tsv"


@pytest.fixture(scope="module")
def built_tsv(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Run the build once into a temp file. Skip if wordfreq isn't available
    (CI without the package installed)."""
    try:
        import wordfreq  # noqa: F401
    except ImportError:
        pytest.skip("wordfreq not installed in this env — `pip install -e .` first")
    out = tmp_path_factory.mktemp("out") / "en.tsv"
    _run_build(out)
    assert out.exists(), "build did not produce the TSV"
    return out


def test_build_is_idempotent(built_tsv: Path, tmp_path: Path) -> None:
    """Re-running the build produces the exact same bytes."""
    sha_first = _sha256(built_tsv)
    out2 = tmp_path / "en_second.tsv"
    _run_build(out2)
    sha_second = _sha256(out2)
    assert sha_first == sha_second, (
        f"build is not deterministic: {sha_first[:12]} → {sha_second[:12]}"
    )


def test_build_validates(built_tsv: Path) -> None:
    """The emitted TSV passes its own validator."""
    proc = subprocess.run(
        [sys.executable, "-m", "fluera_dict", "validate", "en", "--path", str(built_tsv)],
        cwd=TOOLS_DIR, capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"validate failed:\nstdout={proc.stdout}\nstderr={proc.stderr}"


def test_critical_words_present(built_tsv: Path) -> None:
    """Bug fixes from the analysis are baked in: single-letter function
    words present, homoglyph entries absent."""
    body = built_tsv.read_text(encoding="utf-8")
    # Single-letter pronoun/article — broke spellcheck previously.
    assert "\na\t" in "\n" + body, "'a' missing"
    assert "\ni\t" in "\n" + body, "'i' missing"
    # Homoglyph survivors — the Greek omicron in 'οf' etc. must not survive.
    for bad in ("οf", "nο", "tο", "yοu", "ηe"):
        assert bad + "\t" not in body, f"homoglyph {bad!r} survived"


def _domains_of(body: str, word: str) -> list[str]:
    """Return the `domains` cell (col 3) for [word], or raise if absent."""
    idx = ("\n" + body).find(f"\n{word}\t")
    assert idx >= 0, f"{word!r} missing from dict"
    line_end = body.find("\n", idx)
    cells = body[idx:line_end if line_end > 0 else None].split("\t")
    assert len(cells) >= 4, f"{word!r} row malformed"
    return cells[3].split(",")


def _cells_of(body: str, word: str) -> list[str]:
    """Return all 9 cells for [word], or raise if absent."""
    idx = ("\n" + body).find(f"\n{word}\t")
    assert idx >= 0, f"{word!r} missing from dict"
    line_end = body.find("\n", idx)
    cells = body[idx:line_end if line_end > 0 else None].split("\t")
    assert len(cells) == 9, f"{word!r} row malformed: {cells}"
    return cells


def test_medical_domain_tagging(built_tsv: Path) -> None:
    """Stage 4 MeSH integration: core medical terms carry `med` domain."""
    body = built_tsv.read_text(encoding="utf-8")
    for w in ("hepatitis", "neuron", "chromosome", "pathology"):
        assert "med" in _domains_of(body, w), f"{w!r} should be tagged med"


def test_legal_domain_tagging(built_tsv: Path) -> None:
    """Stage 5 US Courts glossary: core legal terms carry `law` domain."""
    body = built_tsv.read_text(encoding="utf-8")
    for w in ("plaintiff", "affidavit", "subpoena", "indictment"):
        assert "law" in _domains_of(body, w), f"{w!r} should be tagged law"


def test_stage6_domains(built_tsv: Path) -> None:
    """Stage 6: stem / cs / fin domains are populated from curated lists."""
    body = built_tsv.read_text(encoding="utf-8")
    assert "stem" in _domains_of(body, "theorem")
    assert "cs" in _domains_of(body, "compiler")
    assert "fin" in _domains_of(body, "inflation")


def test_stage6_derived_flags(built_tsv: Path) -> None:
    """Stage 6: proper / inflected / contraction flags are auto-derived."""
    body = built_tsv.read_text(encoding="utf-8")
    # `running` is an inflection of `run` → inflected flag + root populated.
    running = _cells_of(body, "running")
    assert running[4] == "run", f"running root = {running[4]!r}"
    assert "inflected" in running[8].split(",")
    # `don't` is a contraction.
    dont = _cells_of(body, "don't")
    assert "contraction" in dont[8].split(",")


def test_stage6_junk_absent(built_tsv: Path) -> None:
    """Stage 6 cleanup: possessives, repeated-char spam, 1-char noise and
    2-char non-words must not survive into the emitted dictionary."""
    body = built_tsv.read_text(encoding="utf-8")
    lines = [l for l in body.splitlines() if l]
    words = [l.split("\t")[0] for l in lines]
    # Possessive forms — only the closed set of `'s` contractions allowed.
    s_contractions = {
        "it's", "that's", "there's", "here's", "what's", "who's",
        "where's", "how's", "she's", "he's", "let's", "when's", "why's",
    }
    for w in words:
        if w.endswith("'s"):
            assert w in s_contractions, f"possessive {w!r} leaked through"
        assert not w.endswith("s'"), f"plural possessive {w!r} leaked through"
    # Repeated-char spam.
    import re
    for w in words:
        assert not re.search(r"(.)\1\1", w), f"repeated-char {w!r} leaked through"
    # 1-char entries — only `a` and `i`.
    one_char = sorted(w for w in words if len(w) == 1)
    assert one_char == ["a", "i"], f"unexpected 1-char entries: {one_char}"


def test_stage6_cefr_freq_cap(built_tsv: Path) -> None:
    """Stage 6 CEFR fix: a high-frequency word cannot be rated C1/C2."""
    body = built_tsv.read_text(encoding="utf-8")
    for w in ("the", "good", "water", "house"):
        cells = _cells_of(body, w)
        rank, cefr = int(cells[1]), cells[5]
        if cefr != "-" and rank <= 1000:
            assert cefr in ("A1", "A2"), \
                f"{w!r} rank {rank} should cap at A2, got {cefr}"


def test_phrases_build_and_validate(tmp_path: Path) -> None:
    """Stage 6: the phrases asset builds, validates, and is idempotent."""
    out = tmp_path / "en.phrases.tsv"
    for _ in range(2):
        proc = subprocess.run(
            [sys.executable, "-m", "fluera_dict", "phrases", "en", "--out", str(out)],
            cwd=TOOLS_DIR, capture_output=True, text=True,
        )
        assert proc.returncode == 0, f"phrases build failed:\n{proc.stderr}"
    body = out.read_text(encoding="utf-8")
    # Idempotent: a second run already overwrote — check determinism by sha.
    sha_a = _sha256(out)
    subprocess.run(
        [sys.executable, "-m", "fluera_dict", "phrases", "en", "--out", str(out)],
        cwd=TOOLS_DIR, capture_output=True, text=True, check=True,
    )
    assert _sha256(out) == sha_a, "phrases build is not deterministic"
    # Validates.
    proc = subprocess.run(
        [sys.executable, "-m", "fluera_dict", "validate", "en",
         "--phrases", "--path", str(out)],
        cwd=TOOLS_DIR, capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"phrases validate failed:\n{proc.stdout}"
    # Known multi-word expressions present.
    assert "\nin vivo\t" in "\n" + body, "'in vivo' missing from phrases"
    assert "\nburden of proof\t" in "\n" + body, "'burden of proof' missing"


def _run_build(out: Path) -> None:
    proc = subprocess.run(
        [sys.executable, "-m", "fluera_dict", "build", "en", "--out", str(out)],
        cwd=TOOLS_DIR, capture_output=True, text=True,
    )
    assert proc.returncode == 0, f"build failed:\nstdout={proc.stdout}\nstderr={proc.stderr}"


def _sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()
