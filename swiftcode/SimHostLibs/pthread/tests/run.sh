#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/.." && pwd)
HOST_CC=${HOST_CC:-cc}
t="$root/out/host-tests-pthread"
rm -rf "$t"
mkdir -p "$t"
objs=""
for src in "$here"/*.c; do
    o="$t/$(basename "$src").o"
    "$HOST_CC" -DYC_HOST_TEST -O2 -fno-builtin -fno-strict-aliasing -fvisibility=hidden -Wall -Wextra \
        -I"$root/common" -I"$here" -c -o "$o" "$src"
    objs="$objs $o"
done
"$HOST_CC" -O1 -Wall -pthread -c -o "$t/test_main.o" "$here/tests/test_main.c"
"$HOST_CC" -pthread -o "$t/pthread_tests" "$t/test_main.o" $objs
"$t/pthread_tests"
