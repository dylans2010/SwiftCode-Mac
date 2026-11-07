#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/fsevents}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-fsevents.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
flags="-target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror"
xcrun --sdk iphonesimulator clang $flags -framework CoreServices -framework CoreFoundation \
    -o "$out/p_fsevents" "$here/fsevents/p_fsevents.c"
echo "$out/p_fsevents: $(wc -c < "$out/p_fsevents" | tr -d ' ') bytes"
echo "build-fsevents.sh: ok"
