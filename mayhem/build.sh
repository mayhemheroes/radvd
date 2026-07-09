#!/usr/bin/env bash
#
# radvd/mayhem/build.sh — build radvd's two OSS-Fuzz harnesses as sanitized libFuzzer targets
# (+ standalone reproducers) AND radvd's own libcheck test suite (normal flags) for mayhem/test.sh.
#
# Fuzzed surfaces (ported 1:1 from google/oss-fuzz projects/radvd):
#   fuzz_config  — readin_config(): the real flex/bison radvd.conf parser (libradvd-parser.a).
#   fuzz_process — process(): the ICMPv6 Router Solicitation/Advertisement input path (process.o).
#
# Two sequential IN-TREE autotools builds (radvd's test headers use "../config.h" relative
# includes, so VPATH builds break):
#   1) NORMAL flags, --with-check → the `check_all` libcheck runner, stashed to build-tests/
#      for mayhem/test.sh to RUN (test.sh never compiles); then `make distclean`.
#   2) CFLAGS = $SANITIZER_FLAGS $DEBUG_FLAGS + fuzzer-no-link coverage → the instrumented
#      project objects the harnesses link against.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-$(cd "$(dirname "$0")/.." && pwd)}"
export SRC
cd "$SRC"

# SanitizerCoverage on the compiled objects (fuzzer-no-link) — instrumentation happens at compile
# time; linking $LIB_FUZZING_ENGINE alone would leave the library edge-blind. Passing it at link
# time too pulls in the sancov runtime even when SANITIZER_FLAGS is empty (the off-switch build).
COV="-fsanitize=fuzzer-no-link"

# ── 0) autogen once (idempotent) ────────────────────────────────────────────────────────────────
[ -x configure ] || ./autogen.sh

# ── 1) NORMAL-flags test build (in-tree) → stash check_all in build-tests/ for test.sh ──────────
env -u CC -u CXX -u CFLAGS -u CPPFLAGS -u LDFLAGS \
    ./configure --with-check CFLAGS="-O2 -g ${COVERAGE_FLAGS}" LDFLAGS="${COVERAGE_FLAGS}"
# check_all's LDADD pulls @CONDITIONAL_SOURCES@ objects (privsep-linux.o, device-linux.o,
# netlink.o) that only the `all` target builds — build all first.
env -u CFLAGS -u LDFLAGS make -j"$MAYHEM_JOBS" all
env -u CFLAGS -u LDFLAGS make -j"$MAYHEM_JOBS" check_all
mkdir -p "$SRC/build-tests"
cp -f check_all "$SRC/build-tests/check_all"
ls -la "$SRC/build-tests/check_all"
make distclean

# ── 2) Sanitized+instrumented project build (in-tree, same recipe as OSS-Fuzz's build.sh) ───────
./configure CC="$CC" CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $COV"
make -j"$MAYHEM_JOBS"

B="$SRC"
# Same link set as OSS-Fuzz's build.sh: exclude radvd.o / radvdump.o (main) and log.o (mocked).
OBJS="$B/util.o $B/interface.o $B/device-common.o $B/device-linux.o $B/privsep-linux.o \
      $B/recv.o $B/socket.o $B/send.o $B/timer.o"

read -r -a SAN_ARR <<< "$SANITIZER_FLAGS"

# Baked-in detect_leaks=0 (STRONG symbol — see mayhem/asan_options.c).
"$CC" "${SAN_ARR[@]}" $DEBUG_FLAGS -c "$SRC/mayhem/asan_options.c" -o /tmp/asan_options.o

# Standalone run-once driver (non-fuzzer reproducer; reads ONE file, natural crash).
"$CC" "${SAN_ARR[@]}" $COV $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

# ── 3) Each harness twice: libFuzzer target + standalone reproducer ─────────────────────────────
STATIC_LIBS="-l:libbsd.a -l:libmd.a"
for h in fuzz_config fuzz_process; do
  "$CC" "${SAN_ARR[@]}" $COV $DEBUG_FLAGS -I"$B" -I"$SRC" -c "$SRC/mayhem/$h.c" -o "/tmp/$h.o"
  extra=""
  [ "$h" = fuzz_process ] && extra="$B/process.o"
  [ "$h" = fuzz_config ]  && extra="$B/libradvd-parser.a"
  "$CC" "${SAN_ARR[@]}" $COV $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
      "/tmp/$h.o" /tmp/asan_options.o $extra $OBJS $STATIC_LIBS -o "/mayhem/$h"
  "$CC" "${SAN_ARR[@]}" $COV $DEBUG_FLAGS \
      "/tmp/$h.o" /tmp/asan_options.o /tmp/standalone_main.o $extra $OBJS $STATIC_LIBS \
      -o "/mayhem/$h-standalone"
  echo "built $h (+ standalone)"
done

echo "build.sh complete:"
ls -la /mayhem/fuzz_config /mayhem/fuzz_process /mayhem/fuzz_config-standalone /mayhem/fuzz_process-standalone
