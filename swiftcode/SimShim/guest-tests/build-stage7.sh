#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/stage7}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-stage7.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror \
    -framework Foundation -Wl,-sectcreate,__TEXT,__entitlements,"$here/stage7/ylaunch.entitlements" \
    -o "$out/ylaunch" "$here/stage7/ylaunch.m"
xcrun otool -l "$out/ylaunch" | grep -q "sectname __entitlements" || { echo "build-stage7.sh: no __entitlements section" >&2; exit 1; }
echo "$out/ylaunch: $(wc -c < "$out/ylaunch" | tr -d ' ') bytes"
echo "build-stage7.sh: ok"
