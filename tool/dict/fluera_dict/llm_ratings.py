"""Generate the model-estimated `concrete` + `aoa` ratings.

The `concrete` / `aoa` columns of en.tsv are NOT the licence-restricted
Brysbaert (2014) / Kuperman (2012) empirical datasets — those have no
documented commercial-reuse permission. They are **Claude-estimated**.

This module scripts the DETERMINISTIC halves of that process:
  - `write_chunks()`   — split the top-N words of en.tsv into chunk files
  - `assemble_ratings()` — merge the per-chunk rating files back into the
    frozen `data/curated/llm_ratings_en.tsv`, verifying word alignment

The MIDDLE step — turning each `chunkNNN.txt` into a `ratingsNNN.tsv` —
is LLM inference. It cannot be a pure offline script: under the project's
no-API-key constraint it is run via interactive Claude agents (see
BUILD.md §"concrete / aoa"). The exact prompt is `RATING_PROMPT` below,
committed so the process is repeatable rather than reverse-engineered.

CLI:
    python -m fluera_dict llm-chunks en      # write chunk files + print prompt
    # ...rate each chunkNNN.txt → ratingsNNN.tsv (agents or API)...
    python -m fluera_dict llm-assemble en    # merge → llm_ratings_en.tsv
"""

from __future__ import annotations

from pathlib import Path

# Intermediate chunk + rating files live here (gitignored — regenerable).
CHUNKS_DIR = Path(__file__).resolve().parent.parent / "data" / "llm_chunks"
CURATED_DIR = Path(__file__).resolve().parent.parent / "data" / "curated"
RATINGS_FILE = "llm_ratings_en.tsv"

# Default scope: the top 15k words by frequency carry essentially all of
# the vocabulary a student actually writes; rarer words stay `-`.
DEFAULT_TOP_N = 15000
DEFAULT_CHUNK_SIZE = 1000

# The exact rating prompt. One agent (or one API call) handles one
# chunkNNN.txt and writes the matching ratingsNNN.tsv. {chunk_in} and
# {ratings_out} are the only substitutions.
RATING_PROMPT = """\
You are a psycholinguistic rating engine. Read the word list at \
`{chunk_in}` (one English word per line) and for EVERY word output two \
estimates.

Write your output to `{ratings_out}`. Format: one line per input word, \
exactly `word<TAB>concreteness<TAB>aoa`, SAME ORDER as the input, 2 \
decimal places, no header, no commentary, no blank lines.

## CONCRETENESS — 1.00 to 5.00
How much the word refers to something perceptible by the senses.
- 5.00 fully concrete: carrot, hammer, dog, rain, finger
- 4.00 mostly concrete: kitchen, river, soldier, engine
- 3.00 intermediate: travel, cook, busy, group
- 2.00 mostly abstract: plan, reason, method, chance
- 1.00 fully abstract: justice, although, irony, essence, of
Anchors: chair 4.95 - run 3.50 - money 3.20 - idea 1.60 - the 1.10

## AGE OF ACQUISITION (aoa) — 2.00 to 16.00
Average age in years a native English speaker first learns the word.
- 2-4 earliest: mum, dog, ball, eat, big
- 5-8 primary: school, friend, money, river, build
- 9-12 middle: government, electricity, ancient, technology
- 13-16 advanced: bureaucracy, photosynthesis, jurisprudence, paradigm
Anchors: milk 3.00 - garden 5.00 - planet 8.00 - economy 11.00 - democracy 13.00

## Rules
- Rate EVERY word; output line count must equal input line count.
- Independent estimates from your own judgement — do NOT recall any \
published dataset, estimate from meaning.
- Keep numbers within range, always 2 decimals. Preserve input order.
"""


def write_chunks(
    en_tsv: Path,
    top_n: int = DEFAULT_TOP_N,
    chunk_size: int = DEFAULT_CHUNK_SIZE,
) -> int:
    """Split the top-[top_n] words of [en_tsv] (by freq_rank) into
    `CHUNKS_DIR/chunkNNN.txt` files of [chunk_size] words each.
    Returns the number of chunk files written."""
    lines = en_tsv.read_text(encoding="utf-8").splitlines()
    body = [l for l in lines if not l.startswith("#")][1:]  # skip col header
    rows = [l.split("\t") for l in body]
    rows.sort(key=lambda r: int(r[1]))                      # by freq_rank
    words = [r[0] for r in rows[:top_n]]

    CHUNKS_DIR.mkdir(parents=True, exist_ok=True)
    n = 0
    for i in range(0, len(words), chunk_size):
        n += 1
        chunk = words[i:i + chunk_size]
        (CHUNKS_DIR / f"chunk{n}.txt").write_text(
            "\n".join(chunk) + "\n", encoding="utf-8"
        )
    print(f"[llm-ratings] wrote {n} chunk files to {CHUNKS_DIR}")
    print(f"[llm-ratings] rate each chunkNNN.txt → ratingsNNN.tsv, then run "
          f"`llm-assemble`. Prompt:\n")
    print(RATING_PROMPT.format(chunk_in="<chunkNNN.txt>",
                               ratings_out="<ratingsNNN.tsv>"))
    return n


def assemble_ratings(out_path: Path | None = None) -> Path:
    """Merge every `chunkNNN.txt` + `ratingsNNN.tsv` pair in CHUNKS_DIR
    into the frozen `data/curated/llm_ratings_en.tsv`.

    Verifies word-by-word that each rating line matches its chunk word
    (an agent dropping/reordering a line would corrupt the mapping).
    Clamps values to range, dedupes, sorts. Raises on any misalignment.
    """
    out_path = out_path or (CURATED_DIR / RATINGS_FILE)
    chunk_files = sorted(
        CHUNKS_DIR.glob("chunk*.txt"),
        key=lambda p: int(p.stem.removeprefix("chunk")),
    )
    if not chunk_files:
        raise FileNotFoundError(f"no chunk files in {CHUNKS_DIR}")

    seen: dict[str, tuple[float, float]] = {}
    for chunk_path in chunk_files:
        n = chunk_path.stem.removeprefix("chunk")
        ratings_path = CHUNKS_DIR / f"ratings{n}.tsv"
        if not ratings_path.exists():
            raise FileNotFoundError(f"missing {ratings_path}")
        chunk_words = [w for w in
                       chunk_path.read_text(encoding="utf-8").splitlines() if w]
        rating_lines = [l for l in
                        ratings_path.read_text(encoding="utf-8").splitlines()
                        if l.strip()]
        if len(chunk_words) != len(rating_lines):
            raise ValueError(
                f"chunk{n}: {len(chunk_words)} words vs "
                f"{len(rating_lines)} ratings")
        for cw, rl in zip(chunk_words, rating_lines):
            parts = rl.split("\t")
            if len(parts) != 3:
                raise ValueError(f"chunk{n}: malformed line {rl!r}")
            rw, c, a = parts
            if rw != cw:
                raise ValueError(
                    f"chunk{n}: word misalignment {cw!r} vs {rw!r}")
            cf = max(1.0, min(5.0, float(c)))
            af = max(2.0, min(16.0, float(a)))
            seen.setdefault(cw, (cf, af))

    rows = sorted(seen.items())
    with out_path.open("w", encoding="utf-8") as f:
        f.write("# fluera llm-ratings v1 lang=en\n")
        f.write("# Model-estimated concreteness (1-5) + age-of-acquisition (years).\n")
        f.write("# Original generated data — NOT the Brysbaert/Kuperman empirical\n")
        f.write("# datasets. See assets/dictionaries/LICENSE.md.\n")
        f.write("# word\\tconcrete\\taoa\n")
        for w, (c, a) in rows:
            f.write(f"{w}\t{c:.2f}\t{a:.2f}\n")
    print(f"[llm-ratings] assembled {len(rows)} ratings → {out_path}")
    return out_path
