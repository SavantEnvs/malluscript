#!/usr/bin/env bash
#
# mayhem/build.sh — build malluscript's cargo-fuzz target (parser+lexer) as a
# sanitized libFuzzer binary. Also compiles the test suite for mayhem/test.sh.
#
# Runs inside the commit image as `mayhem` in /mayhem.
# Toolchain at $CARGO_HOME=/opt/toolchains/rust/cargo (pinned by Dockerfile ENV).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# The first (online) build populates the cargo registry. The re-run uses
# CARGO_NET_OFFLINE=true from the rlenv runtime — do NOT hard-code --offline.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Honor SANITIZER_FLAGS knob: when non-empty → ASan instrumentation.
RUST_SAN=""
if [ -n "${SANITIZER_FLAGS:-}" ]; then
  RUST_SAN="-Zsanitizer=address"
fi

# DWARF < 4 gate (SPEC §6.2 item 10): pin DWARF version for Rust, C, and C++.
export RUSTFLAGS="${RUSTFLAGS:-} ${RUST_DEBUG_FLAGS:-} --cfg fuzzing ${RUST_SAN} -Zdwarf-version=3 -Cdebuginfo=1 -Cforce-frame-pointers"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# Strip debug info from the bundled ASan runtime archive (DWARF-5 by default).
# Idempotent: stripping an already-stripped archive is a no-op.
if [ -n "${RUST_SAN}" ]; then
  RT_LIB_DIR="$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/lib"
  for asan in "$RT_LIB_DIR"/librustc-*_rt.asan.a; do
    [ -f "$asan" ] || continue
    if [ -w "$asan" ]; then
      objcopy --strip-debug "$asan" "$asan.stripped" && mv "$asan.stripped" "$asan"
      echo "stripped debug info from bundled ASan runtime: $asan"
    fi
  done
fi

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Explicit target list: only the declared [[bin]] fuzz targets (executor.rs is a
# helper module, not a standalone fuzz target — excluded from the list).
FUZZ_TARGETS=("malluscript")

echo "=== cargo fuzz build (nightly-2025-05-14, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Pre-compile the test suite (no sanitizers) so mayhem/test.sh only runs it.
echo "=== pre-compiling test suite (cargo test --no-run) ==="
env -u RUSTFLAGS cargo test --no-run 2>&1

echo "build.sh complete"
