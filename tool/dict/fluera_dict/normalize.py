"""Normalize words: NFC, lowercase, strip homoglyphs, reject junk.

Why this exists:
  - The legacy en.txt shipped 11 homoglyph entries (Greek omicron / eta
    disguised as Latin o/h) — these get translated or rejected here.
  - The Stage-4 extension to 100k entries dragged in a long junk tail:
    possessive forms (`aaron's`), interjection spam (`aaaand`), 4+ repeated
    chars (`ahhhh`), 2-char non-words (`ac`, `aj`). Stage 6 rejects all of
    those so the emitted dictionary is ~50-55k *real* words.
"""

from __future__ import annotations

import re
import unicodedata

# Words that look identical to ASCII but contain a Greek/Cyrillic codepoint
# get *normalized* via this map when the Latin form is unambiguous.
HOMOGLYPH_MAP = {
    "ο": "o",  # Greek small omicron → Latin o
    "η": "h",  # Greek small eta     → Latin h  (visual loose match)
    "а": "a",  # Cyrillic small a    → Latin a
    "е": "e",  # Cyrillic small ie   → Latin e
    "о": "o",  # Cyrillic small o    → Latin o
    "р": "p",  # Cyrillic small er   → Latin p
    "с": "c",  # Cyrillic small es   → Latin c
    "х": "x",  # Cyrillic small ha   → Latin x
}

# The only single-letter English words. Everything else 1-char is noise.
_ONE_CHAR_OK = {"a", "i"}

# Genuinely common 2-letter English words a study-app user would write.
# Obscure Scrabble-only forms (qi, za, xu, jo) are deliberately excluded —
# if a user writes one they get a spellcheck flag, an acceptable trade-off
# for dropping ~650 noise entries (`ac`, `aj`, `aq`, ...).
_TWO_CHAR_OK = {
    "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in",
    "is", "it", "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to",
    "up", "us", "we", "ah", "eh", "ha", "ho", "ow", "ax", "ox", "ad", "id",
    "pi", "re", "un", "ye",
}

# `'s`-ending tokens that are legitimate contractions, not possessives.
# A genuinely closed set in English (`'s` = is / has / us).
_S_CONTRACTIONS = {
    "it's", "that's", "there's", "here's", "what's", "who's", "where's",
    "how's", "she's", "he's", "let's", "when's", "why's",
}

# Interjection-spam shapes the "3+ identical char" rule doesn't catch
# (2-repeat forms): `aah`, `aand`, `haa`, `ooh`, ... Single-occurrence
# real words ("and", "ah", "ha", "oh") never match because each branch
# requires a doubled run.
_SPAM_RE = re.compile(r"a{2,}h*|a{2,}nd|ha{2,}|h{2,}|u+gh+|m{2,}|o{2,}h*|e{2,}k*")

# 3+ identical consecutive characters — no standard English word has this.
_TRIPLE_RE = re.compile(r"(.)\1\1")


def normalize_word(raw: str) -> str | None:
    """Return a normalized word or None if it must be dropped."""
    s = raw.strip()
    if not s:
        return None
    s = unicodedata.normalize("NFC", s)
    s = s.lower()
    s = "".join(HOMOGLYPH_MAP.get(c, c) for c in s)
    if not (1 <= len(s) <= 40):
        return None
    for ch in s:
        if not _is_acceptable(ch):
            return None
    # Must contain at least one letter (rules out '-', '--', '---').
    if not any(unicodedata.category(c).startswith("L") for c in s):
        return None
    # Reject leading/trailing punctuation (SUBTLEX dialogue artefacts).
    if s[0] in ("-", "'") or s[-1] in ("-", "'"):
        return None

    # ── Stage 6 junk filters ────────────────────────────────────────────
    # Length-based noise.
    if len(s) == 1:
        return s if s in _ONE_CHAR_OK else None
    if len(s) == 2:
        return s if s in _TWO_CHAR_OK else None
    # Possessive forms (`aaron's`, `dogs'`) — keep only true `'s`
    # contractions, drop everything else ending in a possessive marker.
    if s.endswith("'s") and s not in _S_CONTRACTIONS:
        return None
    if s.endswith("s'"):
        return None
    # Repeated-character noise (`ahhhh`, `aaaand`, `brrr`).
    if _TRIPLE_RE.search(s):
        return None
    # Interjection spam the triple rule misses (`aah`, `aand`, `haa`).
    if _SPAM_RE.fullmatch(s):
        return None
    return s


def _is_acceptable(ch: str) -> bool:
    cat = unicodedata.category(ch)
    # Letters, marks (for combining diacritics), apostrophe (contractions),
    # hyphen (compounds). Digits and other punct rejected.
    if cat.startswith("L") or cat.startswith("M"):
        name = unicodedata.name(ch, "")
        if "LATIN" in name or "COMBINING" in name:
            return True
        return False
    return ch in ("'", "-")
