#!/bin/sh
set -u
U=$1; B=$2; N=$3; OUT=$4; SECS=$5; shift 5
mkdir -p "$OUT"
DEV="$HOME/Library/Developer/CoreSimulator/Devices/$U/data"
rm -f "$DEV/tmp/wkprobe-$N.txt"
xcrun simctl terminate "$U" "$B" >/dev/null 2>&1
xcrun simctl launch --stderr="/tmp/wkprobe-$N.txt" "$U" "$B" "$@"
sleep "$SECS"
xcrun simctl io "$U" screenshot --display=LCD "$OUT/$N.png" >/dev/null 2>&1
cp "$DEV/tmp/wkprobe-$N.txt" "$OUT/$N.txt" 2>/dev/null
xcrun simctl terminate "$U" "$B" >/dev/null 2>&1
echo "done $N: $(wc -l < "$OUT/$N.txt" 2>/dev/null) lines"
