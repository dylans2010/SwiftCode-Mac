#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/.." && pwd)
HOST_CC=${HOST_CC:-cc}
case "$(uname -m)" in
aarch64 | arm64) ;;
*)
    echo "kernel host tests: skipped (not an arm64 host)"
    exit 0
    ;;
esac
t="$root/out/host-tests-kernel"
rm -rf "$t"
mkdir -p "$t"
objs=""
for src in "$here/spawn.c" "$here/libproc.c"; do
    o="$t/$(basename "$src").o"
    "$HOST_CC" -DYC_HOST_TEST -O2 -fno-builtin -fno-strict-aliasing -fvisibility=hidden -Wall -Wextra \
        -I"$root/common" -I"$here" -c -o "$o" "$src"
    objs="$objs $o"
done
"$HOST_CC" -O1 -Wall -Wextra -c -o "$t/test_main.o" "$here/tests/test_main.c"
"$HOST_CC" -o "$t/kernel_tests" "$t/test_main.o" $objs
"$t/kernel_tests"
