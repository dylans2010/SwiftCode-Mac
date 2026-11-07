#!/bin/sh
set -e
OUT=${1:?output directory}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -O1 -g -Wall \
    -o "$OUT/bsmitm" "$HERE/bsmitm.c"
codesign -s - -f "$OUT/bsmitm" >/dev/null 2>&1 || true
echo "built $OUT/bsmitm"
