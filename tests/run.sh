#!/usr/bin/env bash
# The gha test suite. Plain bash, no framework.
#
#   tests/run.sh              run everything
#   tests/run.sh --update     regenerate the golden fixtures, then run everything
#   tests/run.sh render       run one suite (render | helpers)
#
# Requires: bash, jq, python3. python3 is the test suite's own dependency, not
# the script's -- `gha` must never fork a measuring process per table cell, so
# the thing that measures the output has to live out here.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GHA_BIN="${GHA_BIN:-$HERE/../gha}"

UPDATE=false
SUITES=""
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=true ;;
    render|helpers) SUITES+="$arg " ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run.sh: unknown argument $arg" >&2; exit 2 ;;
  esac
done
[[ -z "$SUITES" ]] && SUITES="render helpers"

for dep in jq python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "run.sh: $dep is required" >&2; exit 1; }
done
[[ -x "$GHA_BIN" ]] || { echo "run.sh: $GHA_BIN is not executable" >&2; exit 1; }

if $UPDATE; then
  "$HERE/render_test.sh" --update || exit 1
fi

rc=0
for suite in $SUITES; do
  echo
  echo "── ${suite}_test ─────────────────────────────────────────────"
  "$HERE/${suite}_test.sh" || rc=1
done

echo
if (( rc == 0 )); then echo "all suites passed"; else echo "SUITE FAILURES"; fi
exit $rc
