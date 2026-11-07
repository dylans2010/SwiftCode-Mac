#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=$1; LIBS=$2; ORACLE=$3; WORK=$4
shift 4
mkdir -p "$WORK/spv" "$WORK/out"
AIRC="$BUILD/swiftcode-airc"
grep -v '^#' "$HERE/gpu/tests.txt" | while read -r kind name lib f1 f2 rest; do
    [ -n "$kind" ] || continue
    if [ "$kind" = compute ]; then
        "$AIRC" translate "$LIBS/$lib.metallib" -f "$f1" --link "$LIBS/$lib.metallib" \
            -o "$WORK/spv/$lib.$f1.spv" -r "$WORK/spv/$lib.$f1.json" >/dev/null ||
            echo "translate $lib.$f1 failed: $("$AIRC" translate "$LIBS/$lib.metallib" -f "$f1")"
    else
        "$AIRC" translate "$LIBS/$lib.metallib" -f "$f1" -o "$WORK/spv/$lib.$f1.spv" -r "$WORK/spv/$lib.$f1.json" >/dev/null
        CONST=""
        [ "$name" = draw_fconst ] && CONST="--constant 0=1 --constant 1=2"
        "$AIRC" translate "$LIBS/$lib.metallib" -f "$f2" --link-vertex "$LIBS/$lib.metallib:$f1" $CONST \
            -o "$WORK/spv/$lib.$f2.spv" -r "$WORK/spv/$lib.$f2.json" >/dev/null ||
            echo "translate $lib.$f2 failed"
    fi
done
n=0
for f in "$WORK"/spv/*.spv; do spirv-val --target-env vulkan1.3 "$f" && n=$((n + 1)); done
echo "spirv-val --target-env vulkan1.3: $n modules valid"
"$BUILD/airc-gpu" "$HERE/gpu/tests.txt" "$WORK/spv" "$ORACLE" "$WORK/out" "$@"
