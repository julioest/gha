#!/usr/bin/env python3
"""Display-width oracle for the gha test suite.

The table in `gha` pads and truncates in TERMINAL COLUMNS, which is neither the
byte length nor the character count.  This module is the independent measuring
stick the tests compare the script against, so it deliberately derives widths
from `unicodedata` rather than re-stating the range table that `gha` carries.

Width rules (these are the rules the invariant is stated in):
  * 0 columns — combining marks and other non-spacing/format codepoints:
    anything with a non-zero combining class, or general category Mn / Me / Cf.
    That covers combining diacriticals, ZWJ/ZWNJ, and the variation selectors,
    so U+26A0 U+FE0F ("warning sign" + VS16) measures 1, not 2.
  * 2 columns — East Asian Wide and Fullwidth (`east_asian_width` in W, F).
    CJK, Hangul syllables, kana, fullwidth forms and most emoji land here.
  * 1 column — everything else.  East Asian Ambiguous counts as 1, which is
    what a terminal on a Western locale does.

Subcommands
  width          read lines on stdin, print "<columns>\\t<line>" for each
  check          read a rendered gha table on stdin and assert the row invariant
  chars          read one codepoint-per-line (hex), print "<hex> <columns>"
"""

import re
import sys
import unicodedata

# ANSI SGR colour runs, plus OSC 8 hyperlink wrappers (ESC ] 8 ; ; URL ESC \).
# Neither occupies a column.  The tests render with NO_COLOR=1 and no tty, so
# these should not appear at all -- stripping them keeps a stray escape from
# being silently counted as printable width.
_OSC8 = re.compile(r"\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)")
_SGR = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def strip_escapes(s):
    return _SGR.sub("", _OSC8.sub("", s))


def char_width(ch):
    if unicodedata.combining(ch) or unicodedata.category(ch) in ("Mn", "Me", "Cf"):
        return 0
    if unicodedata.east_asian_width(ch) in ("W", "F"):
        return 2
    return 1


def width(s):
    return sum(char_width(ch) for ch in strip_escapes(s))


def read_stdin():
    """Read stdin as UTF-8, tolerating invalid bytes.

    Invalid bytes are themselves a failure worth reporting rather than crashing
    on: they mean the script sliced a multibyte sequence in half.  U+FFFD stands
    in for each bad byte, and `bad_bytes` says whether any appeared.
    """
    raw = sys.stdin.buffer.read()
    text = raw.decode("utf-8", errors="replace")
    return text, ("\ufffd" in text and "\ufffd" not in raw.decode("utf-8", "ignore"))


def cmd_width(argv):
    text, _ = read_stdin()
    for line in text.split("\n"):
        sys.stdout.write("%d\t%s\n" % (width(line), line))
    return 0


def cmd_chars(argv):
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        sys.stdout.write("%s %d\n" % (line, char_width(chr(int(line, 16)))))
    return 0


def cmd_check(argv):
    """Assert every data row is exactly as wide as the header rule.

    A rendered table looks like:

        <repo>   OK 2  X 1  . updated 3m ago      <- summary, not padded
        --------------------------------------    <- the rule: defines the width
        state . branch . title . when             <- column labels (--bare drops)
          OK  develop   Fix the thing      3m ago  <- data rows, must all match

    The rule line is the one made entirely of the rule glyph; data rows are the
    ones indented by two spaces, which is how `gha` opens every row and nothing
    else.
    """
    label = argv[0] if argv else "<stdin>"
    text, bad_bytes = read_stdin()
    lines = [strip_escapes(l) for l in text.split("\n")]

    if bad_bytes:
        print("%s: output is not valid UTF-8 -- a multibyte sequence was split"
              % label)
        return 1

    rule_w = None
    for line in lines:
        stripped = set(line)
        if line and (stripped <= {"─"} or stripped <= {"-"}):
            rule_w = width(line)
            break
    if rule_w is None:
        print("%s: no header rule found -- cannot state the invariant" % label)
        return 1

    bad = []
    rows = 0
    for n, line in enumerate(lines, 1):
        if not line.startswith("  "):
            continue
        rows += 1
        w = width(line)
        if w != rule_w:
            bad.append((n, w, line))

    if not rows:
        print("%s: no data rows found -- cannot state the invariant" % label)
        return 1

    if bad:
        print("%s: %d/%d row(s) do not match the rule width of %d columns"
              % (label, len(bad), rows, rule_w))
        for n, w, line in bad:
            print("    line %-3d %3d columns (%+d): %s|" % (n, w, w - rule_w, line))
        return 1
    return 0


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    cmds = {"width": cmd_width, "check": cmd_check, "chars": cmd_chars}
    cmd = cmds.get(sys.argv[1])
    if cmd is None:
        sys.stderr.write("dwidth.py: unknown subcommand %r\n" % sys.argv[1])
        return 2
    return cmd(sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
