# shellcheck shell=bash
# Shared plumbing for the gha test suites. No framework: a counter, three
# assertions, and a summary. Sourced by tests/*_test.sh, which are in turn run
# by tests/run.sh.

TESTS_RUN=0
TESTS_FAILED=0
FAILED_NAMES=""

# Colour only on a terminal, so CI logs stay plain.
if [[ -t 1 ]]; then
  T_G=$'\033[32m'; T_R=$'\033[31m'; T_D=$'\033[90m'; T_X=$'\033[0m'
else
  T_G=""; T_R=""; T_D=""; T_X=""
fi

pass() { TESTS_RUN=$(( TESTS_RUN + 1 )); printf '  %sok%s   %s\n' "$T_G" "$T_X" "$1"; }

fail() {                                   # fail NAME [DETAIL...]
  TESTS_RUN=$(( TESTS_RUN + 1 )); TESTS_FAILED=$(( TESTS_FAILED + 1 ))
  FAILED_NAMES+="${FAILED_NAMES:+
}    $1"
  printf '  %sFAIL%s %s\n' "$T_R" "$T_X" "$1"
  shift
  local line
  for line in "$@"; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line" | sed 's/^/       /'
  done
}

skip() { printf '  %sskip%s %s\n' "$T_D" "$T_X" "$1"; }

# assert_eq NAME EXPECTED ACTUAL
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"
  else fail "$1" "expected: [$2]" "actual:   [$3]"; fi
}

# summary SUITE — print the tally and return 1 if anything failed.
summary() {
  printf '\n%s: %d test(s), %d failed\n' "$1" "$TESTS_RUN" "$TESTS_FAILED"
  if (( TESTS_FAILED )); then
    printf '  failing:\n%s\n' "$FAILED_NAMES"
    return 1
  fi
  return 0
}
