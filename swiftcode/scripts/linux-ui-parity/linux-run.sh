#!/bin/bash
set -u
IDE=$1; OUT=$2; shift 2
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
for S in ${@:-light dark}; do
  WORK=$(mktemp -d)
  "$HERE/make-demo.sh" "$WORK" > /dev/null
  export XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" HOME="$WORK"
  OV_PLATFORM=sdl OV_COLOR_SCHEME=$S SWIFTCODE_IDE_PARITY="$OUT/linux-$S" \
    timeout 300 "$IDE" "$WORK/Greeter" > "$OUT/linux-$S.log" 2>&1
  echo "exit $?" >> "$OUT/linux-$S.log"
  OV_PLATFORM=sdl OV_COLOR_SCHEME=$S SWIFTCODE_IDE_PARITY="$OUT/linux-$S" \
    timeout 60 "$IDE" > "$OUT/linux-$S-welcome.log" 2>&1
  rm -rf "$WORK"
done
