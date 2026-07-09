#!/usr/bin/env bash
#
# radvd/mayhem/test.sh — RUN radvd's own libcheck unit-test suite (test/check.c: the `util` and
# `send` suites, ~36 behavioral assertions — golden-buffer comparisons of built RA packets,
# known-answer string/time helpers) that mayhem/build.sh already built as build-tests/check_all.
# PATCH-grade oracle: the suite asserts exact output buffers/values (ck_assert_*), so a no-op /
# exit(0) sabotage of the library fails it. Emits a CTRF summary; exit 0 iff no test failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
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

RUNNER="$SRC/build-tests/check_all"
if [ ! -x "$RUNNER" ]; then
  echo "FATAL: $RUNNER missing — mayhem/build.sh must build the test suite" >&2
  emit_ctrf "libcheck" 0 1
  exit 1
fi

# libcheck summary line: "NN%: Checks: T, Failures: F, Errors: E"
# Run from $SRC: the suites load their fixtures via relative paths ("test/test1.conf").
out="$(cd "$SRC" && ./build-tests/check_all -m NORMAL 2>&1)"; rc=$?
echo "$out"
summary="$(printf '%s\n' "$out" | grep -Eo 'Checks: [0-9]+, Failures: [0-9]+, Errors: [0-9]+' | tail -1)"
if [ -z "$summary" ]; then
  echo "FATAL: could not parse libcheck summary (runner rc=$rc)" >&2
  emit_ctrf "libcheck" 0 1
  exit 1
fi
total="$(printf '%s' "$summary" | sed -E 's/Checks: ([0-9]+).*/\1/')"
failures="$(printf '%s' "$summary" | sed -E 's/.*Failures: ([0-9]+).*/\1/')"
errors="$(printf '%s' "$summary" | sed -E 's/.*Errors: ([0-9]+)/\1/')"
failed=$(( failures + errors ))
passed=$(( total - failed ))

emit_ctrf "libcheck" "$passed" "$failed"
