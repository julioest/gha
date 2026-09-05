#!/usr/bin/env bash
# Golden-file renders of `gha --demo`, plus the column-width invariant.
#
#   tests/render_test.sh            diff every case against its fixture
#   tests/render_test.sh --update   regenerate the fixtures instead
#
# Every case is rendered twice, once under a UTF-8 locale and once under
# LC_ALL=POSIX, and both must produce the same bytes: bash slices strings by
# character in the former and by byte in the latter, and the width helpers in
# `gha` are supposed to paper over exactly that difference.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$HERE/lib/common.sh"

GHA="${GHA_BIN:-$HERE/../gha}"
FIXTURES="$HERE/fixtures"
DWIDTH="$HERE/lib/dwidth.py"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

# A fixed instant, so relative ages ("52s ago", "3h ago") never move, and a demo
# anchor 12s behind it, so the cycling Deploy run always renders mid-flight at
# 0:12 rather than wherever the wall clock happens to leave it.
NOW=1750000000
DEMO_START=$(( NOW - 12 ))

# The two locales the helpers have to agree under. C.UTF-8 exists on the Linux
# runners and not on macOS, which ships en_US.UTF-8 instead.
utf8_locale() {
  # Snapshot `locale -a` first: piping it straight into `grep -q` makes grep
  # exit early, and the SIGPIPE that kills `locale` trips `set -o pipefail`.
  local have l
  have="$(locale -a 2>/dev/null)"
  for l in C.UTF-8 en_US.UTF-8; do
    case $'\n'"$have"$'\n' in *$'\n'"$l"$'\n'*) printf '%s' "$l"; return ;; esac
  done
  printf ''
}
UTF8="$(utf8_locale)"

# render LOCALE WIDTH ENV ARGS... — one hermetic render. `env -i` keeps a
# developer's GHA_* exports, NO_COLOR, COLUMNS and locale out of the fixtures.
# GHA_REPO is pinned so the output does not depend on which checkout it ran in,
# and GHA_REPOS_FILE is pointed at a path that cannot exist so a real
# ~/.config/gha/repos on the machine running the tests can never leak into a
# fixture. ENV is a space-separated list of KEY=VALUE that overrides both --
# multi-repo cases pass GHA_REPOS there (comma-separated, since the field itself
# is split on spaces).
render() {
  local loc="$1" width="$2" extra="$3"; shift 3
  # shellcheck disable=SC2086  # $extra is a deliberate word-split KEY=VALUE list
  env -i \
    PATH="$PATH" HOME="$HOME" TERM=dumb TZ=UTC LC_ALL="$loc" \
    NO_COLOR=1 GHA_REPO=demo/repo GHA_REPOS_FILE=/nonexistent/gha/repos \
    GHA_NOW="$NOW" GHA_DEMO_START="$DEMO_START" GHA_WIDTH="$width" \
    $extra \
    bash "$GHA" --demo "$@" 2>&1
}

# The three demo repos a multi-repo case renders. demo_json gives each a
# different set of runs, timed to interleave, so a merged table is only correct
# if the recency sort across repos actually works.
MULTI="GHA_REPO= GHA_REPOS=demo/api,demo/web-frontend,demo/infra"

# The matrix: every width in both glyph modes, plus one case each for the two
# render flags that change the table's shape rather than its width.
WIDTHS="40 50 68 74 88 96 100 120"
CASES=""
for w in $WIDTHS; do
  CASES+="w${w}|${w}||"$'\n'
  CASES+="w${w}-ascii|${w}||--ascii"$'\n'
done
CASES+="failed-w88|88||-f"$'\n'
CASES+="bare-w88|88||--bare"$'\n'

# Multi-repo. 44, 104 and 112 are in here alongside the single-repo widths
# because they are where the repo column's own thresholds sit: 44 is the
# narrowest width that still carries a repo column, 104 is where workflow
# reappears beside it and 112 is where event does.
for w in 40 44 50 68 74 88 96 100 104 112 120; do
  CASES+="multi-w${w}|${w}|${MULTI}|"$'\n'
done
CASES+="multi-w88-ascii|88|${MULTI}|--ascii"$'\n'
CASES+="multi-failed-w88|88|${MULTI}|-f"$'\n'

if $UPDATE; then
  [[ -z "$UTF8" ]] && { echo "render_test: no UTF-8 locale available; refusing to write fixtures" >&2; exit 1; }
  mkdir -p "$FIXTURES"
  n=0
  while IFS='|' read -r name width cenv args; do
    [[ -z "$name" ]] && continue
    # shellcheck disable=SC2086  # $args is a deliberate word-split flag list
    render "$UTF8" "$width" "$cenv" $args > "$FIXTURES/$name.txt"
    n=$(( n + 1 ))
  done <<< "$CASES"
  echo "render_test: wrote $n fixture(s) to tests/fixtures/"
  exit 0
fi

while IFS='|' read -r name width cenv args; do
  [[ -z "$name" ]] && continue
  fixture="$FIXTURES/$name.txt"

  # shellcheck disable=SC2086
  out="$(render "${UTF8:-C}" "$width" "$cenv" $args)"

  # 1. Golden file.
  if [[ ! -f "$fixture" ]]; then
    fail "render $name: fixture missing" "run tests/run.sh --update to create it"
  else
    if diff -u "$fixture" <(printf '%s\n' "$out") > /tmp/gha-diff.$$ 2>&1; then
      pass "render $name matches fixture"
    else
      fail "render $name differs from fixture" "$(cat /tmp/gha-diff.$$)"
    fi
    rm -f /tmp/gha-diff.$$
  fi

  # 2. The invariant a diff cannot state: every data row is exactly as wide, in
  #    terminal columns, as the header rule the layout drew above it.
  if msg="$(printf '%s\n' "$out" | python3 "$DWIDTH" check "$name" 2>&1)"; then
    pass "width  $name: every row lands on the rule width"
  else
    fail "width  $name: rows do not land on the rule width" "$msg"
  fi

  # 3. The same render under LC_ALL=POSIX, where bash slices bytes instead of
  #    characters, must be byte-identical.
  if [[ -n "$UTF8" ]]; then
    # shellcheck disable=SC2086
    posix_out="$(render POSIX "$width" "$cenv" $args)"
    if [[ "$posix_out" == "$out" ]]; then
      pass "locale $name: POSIX render matches $UTF8"
    else
      fail "locale $name: POSIX and $UTF8 renders differ" \
           "$(diff -u <(printf '%s\n' "$out") <(printf '%s\n' "$posix_out") | head -40)"
    fi
  else
    skip "locale $name: no UTF-8 locale on this machine"
  fi
done <<< "$CASES"

summary "render_test"
