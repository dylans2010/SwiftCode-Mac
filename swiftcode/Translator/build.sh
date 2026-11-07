#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$HERE/build}
LLVM_DIR=${LLVM_DIR:-$(llvm-config-18 --cmakedir 2>/dev/null || echo /usr/lib/llvm-18/lib/cmake/llvm)}
GEN=""
command -v ninja >/dev/null 2>&1 && GEN="-G Ninja"
cmake -S "$HERE" -B "$OUT" $GEN -DCMAKE_BUILD_TYPE=Release -DLLVM_DIR="$LLVM_DIR" \
    -DSWIFTCODE_AIRC_RPATH="${SWIFTCODE_AIRC_RPATH:-}" >/dev/null
cmake --build "$OUT" -j "$(nproc 2>/dev/null || echo 4)"
echo "built: $OUT/swiftcode-airc"
