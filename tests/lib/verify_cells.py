#!/usr/bin/env python3
"""Validate a transcript of dfit / dtrunc / dcell results against unicodedata.

tests/helpers_test.sh runs the helpers in bash and records what came back; this
checks the recordings.  Keeping the oracle out of bash is deliberate: `gha`
itself must not fork a python per table cell, but a test may.

Transcript lines are pipe-separated and pure ASCII, so they survive any locale
and diff cleanly between the two the suite runs under:

    dfit|<name>|<arg-hex>|-|-|<reported columns>
    dtrunc|<name>|<arg-hex>|<cols>|<result-hex>|<reported columns>
    dcell|<name>|<arg-hex>|<cols>|<result-hex>|<reported columns>

Checks applied:
  * every result is strictly decodable UTF-8 -- a truncation that split a
    codepoint shows up here and nowhere else;
  * the columns bash reported equal the columns unicodedata measures;
  * dcell output is EXACTLY the requested column count;
  * dtrunc output never exceeds the requested count, and falls at most one
    column short (which only a two-column character straddling the cut can do).
"""

import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from dwidth import width  # noqa: E402


def unhex(h):
    return bytes.fromhex(h) if h != "-" else b""


def main():
    failures = []
    checked = 0
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        kind, name, arg_hex, cols, res_hex, reported = raw.split("|")
        arg_b = unhex(arg_hex)
        checked += 1

        def bad(msg):
            failures.append("%s %s: %s" % (kind, name, msg))

        try:
            arg = arg_b.decode("utf-8")
        except UnicodeDecodeError:
            bad("test input is not valid UTF-8")
            continue

        if kind == "dfit":
            if width(arg) != int(reported):
                bad("measured %s columns, unicodedata says %d (%r)"
                    % (reported, width(arg), arg))
            continue

        res_b = unhex(res_hex)
        try:
            res = res_b.decode("utf-8")
        except UnicodeDecodeError:
            bad("result is not valid UTF-8 -- a codepoint was split: %r" % res_b)
            continue

        n = int(cols)
        w = width(res)
        if w != int(reported):
            bad("reported %s columns, result measures %d (%r)" % (reported, w, res))
        if kind == "dcell" and w != n:
            bad("padded to %d columns, wanted exactly %d (%r)" % (w, n, res))
        if kind == "dtrunc":
            if w > n:
                bad("kept %d columns, budget was %d (%r)" % (w, n, res))
            elif w < n and res != arg:
                # A short result is only legitimate when the next character
                # would not fit: two columns of it into one column of room.
                if n - w > 1:
                    bad("kept %d columns of a %d-column budget (%r)" % (w, n, res))

    if failures:
        print("verify_cells: %d of %d case(s) failed" % (len(failures), checked))
        for f in failures:
            print("    " + f)
        return 1
    print("verify_cells: %d case(s) agree with unicodedata" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
