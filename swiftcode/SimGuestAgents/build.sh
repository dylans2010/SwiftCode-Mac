#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/out}"
[ "$(uname -s)" = "Darwin" ] || { echo "SimGuestAgents/build.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out"
cc="xcrun --sdk iphonesimulator clang -target arm64-apple-ios27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror"
$cc -framework Foundation -framework CoreLocation \
    -Wl,-sectcreate,__TEXT,__entitlements,"$here/settings/swiftcode-settings-agent.entitlements" \
    -o "$out/swiftcode-settings-agent" "$here/settings/swiftcode-settings-agent.m"
xcrun otool -l "$out/swiftcode-settings-agent" | grep -q "sectname __entitlements" \
    || { echo "SimGuestAgents/build.sh: no __entitlements section" >&2; exit 1; }
$cc -fobjc-arc-exceptions -framework Foundation \
    -Wl,-sectcreate,__TEXT,__entitlements,"$here/pairing/swiftcode-pairing-agent.entitlements" \
    -o "$out/swiftcode-pairing-agent" "$here/pairing/swiftcode-pairing-agent.m"
xcrun otool -l "$out/swiftcode-pairing-agent" | grep -q "sectname __entitlements" \
    || { echo "SimGuestAgents/build.sh: no __entitlements section in the pairing agent" >&2; exit 1; }
wcc="xcrun --sdk watchsimulator clang -target arm64-apple-watchos27.0-simulator -fobjc-arc -O2 -Wall -Wextra -Werror"
mkdir -p "$out/watchos"
$wcc -fobjc-arc-exceptions -framework Foundation \
    -Wl,-sectcreate,__TEXT,__entitlements,"$here/pairing/swiftcode-pairing-agent.entitlements" \
    -o "$out/watchos/swiftcode-pairing-agent" "$here/pairing/swiftcode-pairing-agent.m"
$cc -dynamiclib -framework Foundation -framework UIKit -framework Accessibility -install_name @rpath/libSwiftCodeEnvironmentOverrides.dylib \
    -o "$out/libSwiftCodeEnvironmentOverrides.dylib" "$here/overrides/SwiftCodeEnvironmentOverrides.m"
$cc -dynamiclib -install_name @rpath/libSwiftCodeGauge.dylib -o "$out/libSwiftCodeGauge.dylib" "$here/gauge/SwiftCodeGauge.c"
for f in swiftcode-settings-agent swiftcode-pairing-agent libSwiftCodeEnvironmentOverrides.dylib libSwiftCodeGauge.dylib watchos/swiftcode-pairing-agent; do echo "$out/$f: $(wc -c < "$out/$f" | tr -d ' ') bytes"; done
echo "SimGuestAgents/build.sh: ok"
