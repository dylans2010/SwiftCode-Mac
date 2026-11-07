#!/bin/sh
DEV=$1; BUILD=$2; OUT=$3; shift 3
HERE=$(cd "$(dirname "$0")" && pwd)
MODES=${*:-"math map config gesture annot annot:cluster user search dir geo look snap open:openInMaps open:directions open:url open:https sui sui:imagery suicam offline offline:geodstopped"}
xcrun simctl install "$DEV" "$BUILD/MKProbe.app"
xcrun simctl privacy "$DEV" grant location dev.ycode.mkprobe
xcrun simctl location "$DEV" set 37.3349,-122.0090
for mv in $MODES; do
  m=${mv%%:*}; v=; [ "$m" != "$mv" ] && v=${mv#*:}
  case "$m" in user|dir) xcrun simctl location "$DEV" set 37.3349,-122.0090 ;; esac
  xcrun simctl spawn "$DEV" log stream --style compact --predicate 'process == "geod"' > "$OUT/geod-$m${v:+-$v}.stream" 2>&1 &
  LS=$!
  LIMIT=${LIMIT:-300} sh "$HERE/run.sh" "$DEV" "$BUILD" "$OUT" "$m" $v
  kill $LS 2>/dev/null
done
