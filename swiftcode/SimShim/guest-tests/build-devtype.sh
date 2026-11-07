#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/devtype}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-devtype.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -framework Foundation -framework UIKit -o "$out/devprobe" "$here/devtype/devprobe.m"
echo "$out/devprobe: $(wc -c < "$out/devprobe" | tr -d ' ') bytes"
