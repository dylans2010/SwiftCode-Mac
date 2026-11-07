#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$1
mkdir -p "$OUT"
for src in "$HERE"/shaders/*.metal; do
    n=$(basename "$src" .metal)
    xcrun -sdk iphonesimulator metal -std=metal3.1 "$src" -o "$OUT/$n.metallib"
done
ls "$OUT"
