#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/../out/guest-tests/net}"
[ "$(uname -s)" = "Darwin" ] || { echo "build-net.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
flags="-target arm64-apple-ios27.0-simulator -O2 -Wall -Wextra -Werror"
xcrun --sdk iphonesimulator clang $flags -o "$out/p_net" "$here/net/p_net.c"
xcrun --sdk iphonesimulator clang $flags -fobjc-arc -framework Foundation -o "$out/p_urlsession" "$here/net/p_urlsession.m"
xcrun --sdk iphonesimulator clang $flags -fobjc-arc -framework Foundation -framework Network -framework SystemConfiguration \
    -Wno-deprecated-declarations -o "$out/p_netpath" "$here/net/p_netpath.m"
xcrun --sdk iphonesimulator clang $flags -o "$out/p_dispatch" "$here/net/p_dispatch.c"
for p in p_net p_urlsession p_netpath p_dispatch; do echo "$out/$p: $(wc -c < "$out/$p" | tr -d ' ') bytes"; done
echo "build-net.sh: ok"
