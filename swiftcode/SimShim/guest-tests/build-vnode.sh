#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/vnode}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-vnode.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
flags="-target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror"
xcrun --sdk iphonesimulator clang $flags -o "$out/p_vnode" "$here/vnode/p_vnode.c"
echo "$out/p_vnode: $(wc -c < "$out/p_vnode" | tr -d ' ') bytes"
echo "build-vnode.sh: ok"
