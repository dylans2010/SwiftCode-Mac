#!/bin/sh
set -e
UDID=${1:?udid}; OUT=${2:?out}; CAP=${3:?capture dir}; REFUSE=${4:-}; EXTRA=${5:-}
UP=$(printf '../%.0s' $(seq 1 16))
PL="$OUT/dev.ycode.R5.isserve.plist"
EXTRAXML=""
if [ -n "$EXTRA" ]; then EXTRAXML="<key>${EXTRA%%=*}</key><string>${EXTRA#*=}</string>"; fi
REFXML=""
if [ -n "$REFUSE" ]; then REFXML="<key>YC_SRV_REFUSE</key><string>$REFUSE</string>"; fi
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.ycode.R5.isserve</string>
<key>ProgramArguments</key><array><string>/${UP}${OUT#/}/isserve</string><string>-checkin</string><string>dev.ycode.R5.iosurface</string></array>
<key>MachServices</key><dict><key>dev.ycode.R5.iosurface</key><true/></dict>
<key>EnvironmentVariables</key><dict>$REFXML$EXTRAXML</dict>
</dict></plist>
EOF
cd /tmp
xcrun simctl spawn "$UDID" launchctl bootout user/501/dev.ycode.R5.isserve 2>/dev/null || true
sleep 1
xcrun simctl spawn "$UDID" launchctl bootstrap user/501 "$PL"
xcrun simctl spawn "$UDID" launchctl kickstart user/501/dev.ycode.R5.isserve
sleep 2
L=$(xcrun simctl spawn "$UDID" launchctl print user/501)
BB=$(echo "$L" | awk '$NF=="com.apple.backboardd"{print $1}' | head -1)
SB=$(echo "$L" | awk '$NF=="com.apple.SpringBoard"{print $1}' | head -1)
T0=$(date +%s)
echo "refuse=[$REFUSE] extra=[$EXTRA] killing backboardd $BB SpringBoard $SB"
kill -9 "$BB" "$SB"
sleep 45
L=$(xcrun simctl spawn "$UDID" launchctl print user/501)
echo "$L" | grep -e "com.apple.backboardd$" -e "com.apple.SpringBoard$" -e "dev.ycode.R5.isserve$"
NBB=$(echo "$L" | awk '$NF=="com.apple.backboardd"{print $1}' | head -1)
xcrun simctl spawn "$UDID" log show --last 50s --style compact \
  --predicate 'process == "backboardd" AND (eventMessage CONTAINS[c] "screen size" OR eventMessage CONTAINS[c] "SFBDisplay")' 2>/dev/null | tail -3
echo "crash reports since restart:"
find ~/Library/Logs/DiagnosticReports -name '*.ips' -newermt "@$T0" 2>/dev/null | sed 's|.*/||'
echo "backboardd log: $(ls "$CAP"/backboardd-"$NBB".log 2>/dev/null)"
