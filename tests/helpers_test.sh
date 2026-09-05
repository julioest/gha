#!/usr/bin/env bash
# Unit tests for the display-width helpers in `gha`: dfit (measure), dtrunc
# (cut) and dcell (cut then pad to exact columns).
#
# Everything runs TWICE, once under LC_ALL=POSIX and once under a UTF-8 locale.
# That is the point of the suite rather than a detail of it: bash indexes a
# string by BYTE in the first and by CHARACTER in the second, the helpers force
# LC_ALL=C internally to get a single byte-wise code path, and if that ever
# stops working the two runs stop agreeing. Both runs must produce byte-
# identical transcripts, and the transcript is then checked against python's
# unicodedata, which the script itself is not allowed to call.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHA="${GHA_BIN:-$HERE/../gha}"

# ── Body: run every case and write a transcript on stdout ──────────────────
# Invoked as `helpers_test.sh --body`. Kept free of assertions so its output is
# pure data; the driver below does the judging.
if [[ "${1:-}" == "--body" ]]; then
  # Pull the helper block out of `gha` and define it here. Sourcing the script
  # itself would run it, and gha has no library mode -- the anchors are the
  # section banners, and the guard below fails loudly if they ever move.
  block="$(sed -n '/^# ── Display width/,/^# Glyphs\./p' "$GHA" | sed '$d')"
  eval "$block"
  if ! declare -F dfit >/dev/null || ! declare -F dtrunc >/dev/null \
     || ! declare -F dcell >/dev/null; then
    echo "# ERROR: could not extract dfit/dtrunc/dcell from $GHA" >&2
    exit 3
  fi
  ELL='…'

  hex() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'; }

  t_fit()   { dfit "$2";               printf 'dfit|%s|%s|-|-|%s\n'   "$1" "$(hex "$2")" "$D_W"; }
  t_trunc() { dtrunc "$2" "$3" "${4-}"; printf 'dtrunc|%s|%s|%s|%s|%s\n' "$1" "$(hex "$2")" "$3" "$(hex "$D_S")" "$D_W"; }
  t_cell()  { dcell "$2" "$3" "${4-}";  printf 'dcell|%s|%s|%s|%s|%s\n'  "$1" "$(hex "$2")" "$3" "$(hex "$D_S")" "$D_W"; }

  CJK='機能/検索ページ'          # 7 wide + 1 ASCII = 15 columns
  JP='日本語'                    # 6 columns
  ROCKET='🚀 ship it'            # astral plane, 2 + 8 = 10 columns
  WARN='⚠️ retry storm'          # U+26A0 U+FE0F: 1 + 0, then 13 = 14 columns
  ACCENT=$'e\xcc\x81clair'       # e + U+0301 combining acute = 7 columns
  ZWSP=$'a\xe2\x80\x8bb'         # ZWSP between two letters = 2 columns

  # -- measurement ----------------------------------------------------------
  t_fit empty        ''
  t_fit ascii        'CI / build (3.12)'
  t_fit cjk          "$CJK"
  t_fit jp           "$JP"
  t_fit astral       "$ROCKET"
  t_fit vs16         "$WARN"
  t_fit vs16-bare    '⚠'
  t_fit combining    "$ACCENT"
  t_fit zero-width   "$ZWSP"
  t_fit ellipsis     '…'
  t_fit mixed        "CI $JP build 🚀"
  # Every glyph the table puts in a PADDED position must be one column, in both
  # glyph modes, or the left cluster stops lining up. (I_WAIT '⏳' is two
  # columns, but it is only ever printed in free-flowing text.)
  t_fit glyph-ok     '✓'
  t_fit glyph-bad    '✗'
  t_fit glyph-run    '●'
  t_fit glyph-queue  '○'
  t_fit glyph-cancel '⊘'
  t_fit glyph-skip   '–'
  t_fit glyph-rule   '─'
  t_fit glyph-sep    '·'
  t_fit glyph-ascii  '+x*o/-~.'

  # -- truncation -----------------------------------------------------------
  # Walk every budget from 0 to past the end. The cut has to land on a codepoint
  # boundary each time; a budget that splits a two-column character must drop it
  # rather than emit half of one.
  for n in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 20; do
    t_trunc "cjk-$n"    "$CJK"    "$n" "$ELL"
    t_trunc "astral-$n" "$ROCKET" "$n" "$ELL"
    t_trunc "vs16-$n"   "$WARN"   "$n" "$ELL"
  done
  t_trunc fits         'short'          20 "$ELL"
  t_trunc exact        'exactly-ten'    11 "$ELL"
  t_trunc hard-cut     "$CJK"            8 ''
  t_trunc hard-cut-asc 'abcdefghij'      4 ''
  t_trunc ascii-ell    'abcdefghij'      4 "$ELL"
  t_trunc ascii-tilde  'abcdefghij'      4 '~'
  t_trunc combining    "$ACCENT"         3 "$ELL"

  # -- padding --------------------------------------------------------------
  # dcell is the one with an unconditional promise: exactly COLS columns out,
  # whatever went in.
  for n in 1 2 5 8 13 14 15 16 20; do
    t_cell "cjk-$n"    "$CJK"    "$n" "$ELL"
    t_cell "astral-$n" "$ROCKET" "$n" "$ELL"
    t_cell "vs16-$n"   "$WARN"   "$n" "$ELL"
    t_cell "ascii-$n"  'develop' "$n" "$ELL"
    t_cell "empty-$n"  ''        "$n" "$ELL"
  done
  # The real column widths the table uses.
  for n in 5 8 13 14 16 20; do
    t_cell "branch-$n" 'experiment/very-long-branch-name-that-overflows' "$n" "$ELL"
  done
  exit 0
fi

# ── Driver ─────────────────────────────────────────────────────────────────
# shellcheck source=tests/lib/common.sh
. "$HERE/lib/common.sh"

utf8_locale() {
  local have l
  have="$(locale -a 2>/dev/null)"
  for l in C.UTF-8 en_US.UTF-8; do
    case $'\n'"$have"$'\n' in *$'\n'"$l"$'\n'*) printf '%s' "$l"; return ;; esac
  done
  printf ''
}
UTF8="$(utf8_locale)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/gha-helpers.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

run_body() {                                  # run_body LOCALE OUTFILE
  LC_ALL="$1" bash "${BASH_SOURCE[0]}" --body > "$2" 2> "$2.err"
}

LOCALES="POSIX"
[[ -n "$UTF8" ]] && LOCALES="POSIX $UTF8"

LAST_OUT=""
for loc in $LOCALES; do
  out="$tmp/${loc//[^A-Za-z0-9]/_}.txt"
  LAST_OUT="$out"
  if run_body "$loc" "$out"; then
    pass "helpers run under LC_ALL=$loc"
  else
    fail "helpers run under LC_ALL=$loc" "$(cat "$out.err")"
    continue
  fi

  if msg="$(python3 "$HERE/lib/verify_cells.py" < "$out" 2>&1)"; then
    pass "LC_ALL=$loc: ${msg#verify_cells: }"
  else
    fail "LC_ALL=$loc: results disagree with unicodedata" "$msg"
  fi
done

# The two locales must not merely both be self-consistent -- they must be the
# same. This is the assertion that catches the helpers falling back to bash's
# own (locale-dependent) idea of string length.
if [[ -n "$UTF8" ]]; then
  a="$tmp/POSIX.txt"; b="$tmp/${UTF8//[^A-Za-z0-9]/_}.txt"
  if [[ -s "$a" && -s "$b" ]]; then
    if diff -q "$a" "$b" >/dev/null; then
      pass "LC_ALL=POSIX and LC_ALL=$UTF8 produce identical results"
    else
      fail "LC_ALL=POSIX and LC_ALL=$UTF8 disagree" "$(diff -u "$a" "$b" | head -30)"
    fi
  fi
else
  skip "cross-locale comparison: no UTF-8 locale on this machine"
fi

# A handful of expectations spelled out by hand, so the suite still says
# something readable when the oracle and the helpers are wrong together.
expect() {                                    # expect NAME KIND EXPECTED
  local got
  got="$(grep -m1 "^$2|$1|" "$LAST_OUT" | cut -d'|' -f6)"
  assert_eq "$2 $1 = $3 columns" "$3" "$got"
}
expect ascii      dfit 17
expect jp         dfit 6
expect cjk        dfit 15
expect astral     dfit 10
expect vs16       dfit 13      # U+26A0 is one column; the VS16 after it is none
expect combining  dfit 6       # e + U+0301, not the precomposed é
expect zero-width dfit 2
expect glyph-run  dfit 1
expect cjk-16     dcell 16
expect cjk-15     dcell 15
expect vs16-1     dcell 1

summary "helpers_test"
