#!/bin/sh
set -u
here=$(cd "$(dirname "$0")" && pwd)
mode=${1:?usage: run-tests.sh mac <out> | simd <swiftcode-simd> <dir>}
passed=0
failed=0
tests="t_message t_memory t_arc t_runtime t_threads"
flags_for() {
    case "$1" in
    t_arc) echo "-fobjc-arc" ;;
    *) echo "" ;;
    esac
}
check() {
    if [ "$4" -ne 0 ]; then
        echo "FAIL $1: exit status $4"
        failed=$((failed + 1))
    elif ! diff -u "$2" "$3" > "$3.diff"; then
        echo "FAIL $1: output differs ($3.diff)"
        failed=$((failed + 1))
    else
        echo "ok   $1"
        passed=$((passed + 1))
    fi
}
case "$mode" in
mac)
    out=${2:?usage: run-tests.sh mac <out dir>}
    mkdir -p "$out"
    for t in $tests; do
        CFLAGS=$(flags_for "$t") sh "$here/bench/build-mac.sh" "$out" "$here/tests/$t.m" > "$out/$t.build.log" 2>&1 \
            || { echo "FAIL $t: build ($out/$t.build.log)"; failed=$((failed + 1)); continue; }
        "$out/$t-apple" > "$out/$t.apple.out" 2>&1
        check "$t (Mac runtime)" "$here/tests/$t.expected" "$out/$t.apple.out" $?
        "$out/$t-swiftcode" > "$out/$t.swiftcode.out" 2>&1
        check "$t (SwiftCode runtime, native)" "$here/tests/$t.expected" "$out/$t.swiftcode.out" $?
    done
    ;;
simd)
    simd=${2:?usage: run-tests.sh simd <swiftcode-simd> <dir>}
    dir=${3:?usage: run-tests.sh simd <swiftcode-simd> <dir>}
    out=${OUT:-$PWD/objc-test-runs}
    mkdir -p "$out"
    for t in $tests; do
        "$simd" --macos-root "${MACOS_ROOT:-$here/../out/root}" --timeout-ms 120000 --macos "$dir/$t" \
            > "$out/$t.out" 2> "$out/$t.err"
        check "$t (swiftcode-simd)" "$here/tests/$t.expected" "$out/$t.out" $?
    done
    ;;
*)
    echo "usage: run-tests.sh mac <out> | simd <swiftcode-simd> <dir>" >&2
    exit 2
    ;;
esac
echo "run-tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
