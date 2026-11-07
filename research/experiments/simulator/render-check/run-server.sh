#!/bin/sh
set -e
UDID=${1:?udid}; B=${2:?build}; R=${3:?run dir}; V=${4:?variant}; BOOT=${5:-}
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=dev.ycode.R6.iosurface
mkdir -p "$R/is" "$R/$V"
cd /tmp
if [ "$BOOT" = "--boot" ]; then
  export SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$B/r5/isinterpose.dylib"
  export SIMCTL_CHILD_YC_IS_DIR="$R/is" SIMCTL_CHILD_YC_IS_REDIRECT=$NAME
  export SIMCTL_CHILD_YC_IS_ONLY="backboardd,SpringBoard,Preferences,YcodeProbe"
  export SIMCTL_CHILD_YC_IS_DENY='com.apple.metal.simulator*,com.apple.gputools.service.simulator'
  export SIMCTL_CHILD_SIMULATOR_FRAMEBUFFER_FRAMEWORK="$B/capture/SimFramebuffer.framework/SimFramebuffer"
  export SIMCTL_CHILD_SFBC_DIR="$R" SIMCTL_CHILD_SFBH_LOG="$R/sfb.log"
  xcrun simctl boot "$UDID"
  echo "booted; waiting 60 s"; sleep 60
fi
rm -f "$R/opts"; for kv in $RC_SFBOPTS; do echo "$kv" >> "$R/opts"; done
UP=$(printf '../%.0s' $(seq 1 16))
PL="$R/$V/job.plist"
ENVXML="<key>YC_SRV_DUMPDIR</key><string>$R/$V</string><key>YC_SRV_LOG</key><string>$R/$V/srv.log</string>"
[ -n "$RC_REFUSE" ] && ENVXML="$ENVXML<key>YC_SRV_REFUSE</key><string>$RC_REFUSE</string>"
[ -n "$RC_NOSTATE" ] && ENVXML="$ENVXML<key>YC_SRV_NOSTATE</key><string>1</string>"
[ -n "$RC_FREEZESEED" ] && ENVXML="$ENVXML<key>YC_SRV_FREEZESEED</key><string>1</string>"
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.ycode.R6.isdump</string>
<key>ProgramArguments</key><array><string>/${UP}${B#/}/isdump</string><string>-checkin</string><string>$NAME</string></array>
<key>MachServices</key><dict><key>$NAME</key><true/></dict>
<key>EnvironmentVariables</key><dict>$ENVXML</dict>
</dict></plist>
PLIST
xcrun simctl spawn "$UDID" launchctl bootout user/501/dev.ycode.R6.isdump 2>/dev/null || true
sleep 1
xcrun simctl spawn "$UDID" launchctl bootstrap user/501 "$PL"
xcrun simctl spawn "$UDID" launchctl kickstart user/501/dev.ycode.R6.isdump
sleep 2
L=$(xcrun simctl spawn "$UDID" launchctl print user/501)
BB=$(echo "$L" | awk '$NF=="com.apple.backboardd"{print $1}' | head -1)
SB=$(echo "$L" | awk '$NF=="com.apple.SpringBoard"{print $1}' | head -1)
T0=$(date +%s); touch "$R/t0.mark"
echo "variant $V refuse=[$RC_REFUSE] nostate=[$RC_NOSTATE] freezeseed=[$RC_FREEZESEED] sfbopts=[$RC_SFBOPTS]: killing backboardd $BB SpringBoard $SB"
echo "# variant $V restart" >> "$R/frames.log"
kill -9 "$BB" "$SB"
sleep 45
xcrun simctl spawn "$UDID" log show --last 50s --style compact \
  --predicate 'process == "backboardd" AND eventMessage CONTAINS[c] "screen size"' 2>/dev/null | tail -1 | cut -c1-200
t30() { perl -e 'alarm shift; exec @ARGV' 30 "$@"; }
both() {
  rm -f "$R/$1.txt"; echo "$1" > "$R/snap"
  for i in $(seq 1 40); do [ -f "$R/$1.txt" ] && break; sleep 0.25; done
  sleep 0.5
  mv "$R/$1.raw" "$R/$V/$1-fb.raw" 2>/dev/null; mv "$R/$1.txt" "$R/$V/$1-fb.txt"
  ID=$(sed -n 's/^surface_id=//p' "$R/$V/$1-fb.txt")
  echo "$1-srv $ID" > "$R/$V/req"
  for i in $(seq 1 40); do [ -f "$R/$V/$1-srv.txt" ] && [ ! -f "$R/$V/req" ] && break; sleep 0.25; done
  python3 -I "$HERE/raw2png.py" "$R/$V/$1-fb.raw" || cat "$R/$V/$1-fb.txt"
  python3 -I "$HERE/raw2png.py" "$R/$V/$1-srv.raw" || cat "$R/$V/$1-srv.txt"
  if cmp -s "$R/$V/$1-fb.raw" "$R/$V/$1-srv.raw"; then echo "$1: framebuffer and service bytes identical"; else echo "$1: bytes DIFFER"; fi
}
if [ "$RC_MODE" = tick ]; then
  xcrun simctl install "$UDID" "$B/YcodeTick.app"
  t30 xcrun simctl launch "$UDID" dev.ycode.r6.tick || echo "tick launch failed or timed out"
  sleep 5
  for w in $(seq 1 ${RC_TICKWIN:-1}); do
    F0=$(grep -c '^frame' "$R/frames.log"); sleep 10; F1=$(grep -c '^frame' "$R/frames.log")
    echo "tick: window $w: frames presented in 10 s: $((F1 - F0))"
  done
  both tick1; sleep 3; both tick2
  t30 xcrun simctl terminate "$UDID" dev.ycode.r6.tick || true
  echo "crash reports since restart:"
  find ~/Library/Logs/DiagnosticReports -name '*.ips' -newer "$R/t0.mark" 2>/dev/null | sed 's|.*/||'
  exit 0
fi
both home
t30 xcrun simctl launch "$UDID" com.apple.Preferences || echo "launch Settings failed or timed out"
sleep 8; both settings
t30 xcrun simctl terminate "$UDID" com.apple.Preferences || echo "terminate Settings failed or timed out"
t30 xcrun simctl launch "$UDID" dev.ycode.probe || echo "probe launch failed or timed out"
sleep 8; both probe
t30 xcrun simctl terminate "$UDID" dev.ycode.probe || true
echo list > "$R/$V/req"; sleep 1; cat "$R/$V/surfaces.txt" | head -20
echo "service requests by method:"; awk '{print $4, $5}' "$R/$V/srv.log" | sort | uniq -c | sort -rn | head -12
echo "crash reports since restart:"
find ~/Library/Logs/DiagnosticReports -name '*.ips' -newer "$R/t0.mark" 2>/dev/null | sed 's|.*/||'
sed -n '/# variant '"$V"' restart/,$p' "$R/frames.log" | grep -c '^frame'
