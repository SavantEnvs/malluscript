#!/usr/bin/env bash
#
# mayhem/test.sh — run malluscript's upstream test suite and emit a CTRF report.
#
# Anti-reward-hack: tests assert BEHAVIOR via assert_eq! (parser AST structure,
# arithmetic results, Malayalam variable values). A PATCH that neuters the program
# to exit(0) / a no-op produces no libtest "test result:" marker → this fails.
# Emits CTRF. Exit 0 iff failed==0.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Run the pre-compiled test suite (build.sh ran `cargo test --no-run`).
# env -u RUSTFLAGS: don't let fuzz RUSTFLAGS poison the test run.
LOG="$(mktemp)"
env -u RUSTFLAGS cargo test --no-fail-fast 2>&1 | tee "$LOG"

PASSED=$(grep -hoE '[0-9]+ passed'  "$LOG" | awk '{s+=$1} END{print s+0}')
FAILED=$(grep -hoE '[0-9]+ failed'  "$LOG" | awk '{s+=$1} END{print s+0}')
SKIPPED=$(grep -hoE '[0-9]+ ignored' "$LOG" | awk '{s+=$1} END{print s+0}')
rm -f "$LOG"

# No results parsed → test runner never ran (binary was neutered or missing) → FAIL.
if [ "$((PASSED + FAILED + SKIPPED))" -eq 0 ]; then
  echo "ERROR: no libtest results parsed — test runner did not execute" >&2
  emit_ctrf "cargo-test" 0 1 0
  exit 1
fi

# Floor: suite must have actually run tests (malluscript has 4 #[test] functions).
if [ "$PASSED" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
  echo "ERROR: 0 tests run — oracle would be vacuous" >&2
  emit_ctrf "cargo-test" 0 1 0
  exit 1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$SKIPPED"
