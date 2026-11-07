#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS="$REPO_ROOT/sdk/scripts"
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }
for s in assemble-sdk.sh build-sdk.sh package-sdk.sh verify-sdk.sh smoke-sdk-scripts.sh; do
    bash -n "$SCRIPTS/$s" || fail "$s does not parse"
done
ok "all five scripts parse (bash -n)"
for p in sdk/package sdk/cli sdk/runtime-adapter sdk/templates \
         sdk/Contracts/Manifest/swiftcode-extension-v1.schema.json \
         sdk/Contracts/Manifest/ExampleManifests swiftcode/Package.swift; do
    [ -e "$REPO_ROOT/$p" ] || fail "assemble input missing: $p"
done
ok "all assemble-sdk.sh source trees exist"
if grep -h -E "populate-distribution|cross-200mb|reach-threshold|expand-to-target|final-gate|reach-gate|add-final" "$SCRIPTS/assemble-sdk.sh" "$SCRIPTS/build-sdk.sh" "$SCRIPTS/package-sdk.sh" "$SCRIPTS/verify-sdk.sh" | sed 's/#.*//' | grep -q -E "populate-distribution|cross-200mb|reach-threshold|expand-to-target|final-gate|reach-gate|add-final"; then
    fail "sdk/scripts still references synthetic-filler generators in live code"
fi
if grep -h -E "exec stat -f|\\\$\\(stat -f" "$SCRIPTS/assemble-sdk.sh" "$SCRIPTS/build-sdk.sh" "$SCRIPTS/package-sdk.sh" "$SCRIPTS/verify-sdk.sh" ; then
    fail "sdk/scripts still uses BSD-only stat -f at a call site (the portable probe itself is the only allowed use)"
fi
ok "no filler references and no BSD-only stat -f in sdk/scripts"
grep -q "below the legacy 200 MB threshold" "$SCRIPTS/assemble-sdk.sh" || fail "assemble-sdk.sh lost its report-only size note"
grep -q "below the legacy 200,000,000 bytes threshold" "$SCRIPTS/verify-sdk.sh" || fail "verify-sdk.sh lost its report-only size note"
if grep -A2 "TOTAL_BYTES.*-lt 200000000" "$SCRIPTS/assemble-sdk.sh" | grep -q "exit 1"; then
    fail "assemble-sdk.sh still hard-fails the 200 MB gate"
fi
ok "200 MB size gate is report-only in assemble-sdk.sh and verify-sdk.sh"
T=$(mktemp -d /tmp/smoke-sdk-scripts-XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts"
cp "$SCRIPTS/verify-sdk.sh" "$SCRIPTS/package-sdk.sh" "$T/scripts/"
if "$T/scripts/verify-sdk.sh" >/dev/null 2>&1; then
    fail "verify-sdk.sh succeeded with no distribution present"
fi
ok "verify-sdk.sh fails closed on a missing distribution"
if "$T/scripts/package-sdk.sh" >/dev/null 2>&1; then
    fail "package-sdk.sh succeeded with no distribution present"
fi
ok "package-sdk.sh fails closed (verify step) on a missing distribution"
if stat -f '%z' "$0" >/dev/null 2>&1; then
    probe=(stat -f %z)
else
    probe=(stat -c %s)
fi
probe_size=$("${probe[@]}" "$SCRIPTS/assemble-sdk.sh")
wc_size=$(wc -c < "$SCRIPTS/assemble-sdk.sh" | tr -d ' ')
[ "$probe_size" = "$wc_size" ] || fail "size probe ($probe_size) disagrees with wc -c ($wc_size)"
ok "portable size probe agrees with wc -c ($probe_size bytes)"
if [ -n "$(cd "$REPO_ROOT" && git ls-files sdk/Distribution)" ]; then
    fail "sdk/Distribution output is committed; it must stay build output only"
fi
ok "no sdk/Distribution output committed"
echo "SMOKE PASS: SDK distribution regeneration path checks out (full assemble still needs swift build on a Mac)."
