#!/bin/sh
BIN=$1; OUT=$2; shift 2
RR=${YC_RR:-"/Library/Developer/CoreSimulator/Volumes/iOS_24A94401/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.1.simruntime/Contents/Resources/RuntimeRoot"}
export YC_LIB="$RR/usr/lib/system/host/liblaunch_sim.dylib"
DYLD_INSERT_LIBRARIES=$BIN/lsinterpose.dylib $BIN/lsprobe call "$@" > "$OUT" 2>&1
echo "exit=$?" >> "$OUT"
