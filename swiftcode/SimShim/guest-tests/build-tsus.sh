#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/tsus}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-tsus.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
flags="-target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror"
xcrun --sdk iphonesimulator clang $flags -o "$out/p_tsus" "$here/tsus/p_tsus.c"
xcrun --sdk iphonesimulator clang $flags -o "$out/p_jsgc" "$here/tsus/p_jsgc.c" -framework JavaScriptCore
for p in p_tsus p_jsgc; do echo "$out/$p: $(wc -c < "$out/$p" | tr -d ' ') bytes"; done
echo "build-tsus.sh: ok"
