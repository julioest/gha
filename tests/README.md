# Tests

Plain bash, no framework. `python3` is required, `jq` is required, and nothing
else.

```sh
tests/run.sh              # everything
tests/run.sh render       # just the golden renders
tests/run.sh helpers      # just the dfit/dtrunc/dcell unit tests
tests/run.sh --update     # regenerate the fixtures, then run everything
```

## Why python3 is a test dependency and not a script one

`gha` lays its table out in **terminal columns**. A column is not a byte and not
a character: CJK, kana, Hangul and most emoji take two of them, and combining
marks and variation selectors take none — so `⚠️` (U+26A0 followed by VS16) is
one column, not two. Getting that wrong is invisible in a diff and obvious on
screen, as a row whose right-hand times sit a column or two off from every other
row's.

The script measures columns itself, in bash, with no subprocess: forking a
measuring process per table cell would cost more than the entire render. The
tests measure the same thing independently, in python, from `unicodedata` — so
the two can disagree, which is the whole point of having them.

## What each suite asserts

**`render_test.sh`** renders `--demo` at widths 40, 50, 68, 74, 88, 96, 100 and
120, in both the default and `--ascii` glyph modes, plus one `-f` and one
`--bare` case. For each:

1. **Golden file** — byte-identical to `tests/fixtures/<case>.txt`.
2. **The width invariant** — every data row is *exactly* as wide, in terminal
   columns, as the header rule drawn above it. This is the assertion a diff
   cannot make: a fixture can be regenerated into agreement with a layout bug,
   and this cannot.
3. **Locale independence** — the same render under `LC_ALL=POSIX` and under a
   UTF-8 locale must produce the same bytes. bash indexes strings by byte in the
   first and by character in the second.

**`helpers_test.sh`** unit-tests `dfit` (measure), `dtrunc` (cut) and `dcell`
(cut, then pad to exact columns): measurement of ASCII, CJK, astral-plane emoji,
VS16, combining marks and zero-width spaces; truncation at every budget from 0
past the end of the string, which must never split a codepoint and must never
overrun; and padding, which must land on exactly the requested column count.
Everything runs under both `LC_ALL=POSIX` and a UTF-8 locale, and the two
transcripts must be identical.

## Determinism

Renders are pinned with `GHA_NOW` (freezes every clock in the script, so
relative ages never move), `GHA_DEMO_START` (fixes the phase of the demo's
running→passed cycle), `GHA_WIDTH`, `GHA_REPO` and `NO_COLOR=1`. Each render
runs under `env -i` so a developer's own `GHA_*` exports cannot leak into a
fixture.

`GHA_NOW` exists for the tests and nothing else; the live view deliberately does
not set it, or the timers would stop ticking.

## When a fixture legitimately changes

Re-run `tests/run.sh --update`, then **read the diff**. The invariant check runs
against the freshly rendered output, not against the fixture, so a layout
regression fails the suite even after an update — but a fixture diff that
nobody read is how a cosmetic regression gets committed.
