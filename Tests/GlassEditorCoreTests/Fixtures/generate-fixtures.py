#!/usr/bin/env python3
"""Regenerate the encoding / line-ending fixtures byte-for-byte.

Fixtures are checked in as binary so tests are deterministic, but they are
generated rather than hand-typed because several of them (BOMs, lone CR,
overlong UTF-8) do not survive an editor round trip. Run from anywhere:

    python3 Tests/GlassEditorCoreTests/Fixtures/generate-fixtures.py

The expected DetectedEncoding / LineEndingStyle for each file is asserted in
DocumentTests.swift — if you change a fixture here, change the expectation there.
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))


def write(name: str, data: bytes) -> None:
    path = os.path.join(HERE, name)
    with open(path, "wb") as f:
        f.write(data)
    print(f"{name}: {len(data)} bytes")


# --- UTF-8, no BOM, LF ------------------------------------------------------
write(
    "utf8-plain.txt",
    "GlassEditorKit\ncafé — naïve\n日本語のテキスト\nsmile 🙂 astral\n".encode("utf-8"),
)

# --- UTF-8 with BOM, LF -----------------------------------------------------
write(
    "utf8-bom.txt",
    b"\xef\xbb\xbf" + "byte order mark leads\ncafé\n🙂\n".encode("utf-8"),
)

# --- UTF-16 LE with BOM, LF -------------------------------------------------
UTF16_TEXT = "utf-16 little endian\ncafé\n日本語\n🙂 surrogate pair\n"
write("utf16le-bom.txt", b"\xff\xfe" + UTF16_TEXT.encode("utf-16-le"))

# --- UTF-16 BE with BOM, LF -------------------------------------------------
write("utf16be-bom.txt", b"\xfe\xff" + UTF16_TEXT.encode("utf-16-be"))

# --- CRLF only --------------------------------------------------------------
write(
    "crlf.txt",
    "SELECT 1;\r\nSELECT 2;\r\n-- trailing comment\r\n".encode("utf-8"),
)

# --- Lone CR only (classic Mac OS) -----------------------------------------
write(
    "cr-only.txt",
    "old mac line one\rold mac line two\rold mac line three\r".encode("utf-8"),
)

# --- Mixed: 3 CRLF, 2 LF, 1 CR -> dominant is CRLF --------------------------
write(
    "mixed-endings.txt",
    "one\r\ntwo\r\nthree\r\nfour\nfive\nsix\rseven".encode("utf-8"),
)

# --- Combining marks: decomposed é, stacked marks, Hangul jamo --------------
# Deliberately mixes decomposed and precomposed forms of the SAME grapheme so a
# round-trip that normalizes silently would produce different bytes.
write(
    "combining-marks.txt",
    (
        "decomposed: é (e + U+0301)\n"
        "precomposed: é (U+00E9)\n"
        "stacked: à́̂̃\n"
        "hangul jamo: 각\n"
        "hangul precomposed: 각\n"
        "devanagari: क्षि\n"
    ).encode("utf-8"),
)

# --- Bidi: RTL scripts with embedded LTR runs and explicit marks ------------
write(
    "bidi.txt",
    (
        "arabic: مرحبا GlassEditorKit وداعا\n"
        "hebrew: שלום world עולם\n"
        "with RLM: abc‏אבג‎def\n"
        "isolates: ⁦LTR⁩ ⁧RTL⁩ ⁨neutral⁩\n"
        "numbers: السعر 123.45 USD\n"
    ).encode("utf-8"),
)

# --- Invalid UTF-8: lone continuation, overlong, truncated multibyte --------
# Every byte here is a valid ISO-8859-1 code unit, which is exactly why
# latin1Fallback round-trips it losslessly.
write(
    "invalid-utf8.bin",
    b"plain ascii line\n"
    b"lone continuation: \x80\x81\n"
    b"overlong solidus: \xc0\xaf\n"
    b"truncated multibyte: \xe2\x82\n"
    b"latin1 accents: caf\xe9 na\xefve\n"
    b"high bytes: \xa9\xae\xb1\xff\n",
)
