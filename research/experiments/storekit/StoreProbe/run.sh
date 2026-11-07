#!/bin/sh
set -u
U=$1; B=$2; N=$3; OUT=$4; SECS=$5; shift 5
KEEP=""; [ "${1:-}" = keep ] && { KEEP=1; shift; }
[ "${1:-}" = -- ] && shift
mkdir -p "$OUT"
DEV="$HOME/Library/Developer/CoreSimulator/Devices/$U/data"
rm -f "$DEV/tmp/storeprobe-$N.txt"
xcrun simctl terminate "$U" "$B" >/dev/null 2>&1
PLAT=$(xcrun --sdk iphonesimulator --show-sdk-platform-path)/Developer/Library/Frameworks
SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$PLAT" xcrun simctl launch --stderr="/tmp/storeprobe-$N.txt" "$U" "$B" "$@" >/dev/null
i=0
while [ $i -lt "$SECS" ]; do
  grep -q "DONE" "$DEV/tmp/storeprobe-$N.txt" 2>/dev/null && break
  sleep 1; i=$((i + 1))
done
xcrun simctl io "$U" screenshot "$OUT/$N.png" >/dev/null 2>&1
cp "$DEV/tmp/storeprobe-$N.txt" "$OUT/$N.txt" 2>/dev/null
C=$(xcrun simctl get_app_container "$U" "$B" data 2>/dev/null)
[ -n "$C" ] && mkdir -p "$OUT/$N-docs" && cp "$C"/Documents/* "$OUT/$N-docs/" 2>/dev/null && rm -f "$C"/Documents/jws-*.txt
[ -z "$KEEP" ] && xcrun simctl terminate "$U" "$B" >/dev/null 2>&1
echo "done $N after ${i}s: $(wc -l < "$OUT/$N.txt" 2>/dev/null) lines"
