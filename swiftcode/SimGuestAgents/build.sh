#!/bin/sh
# Builds SwiftCode's guest agents for the iOS simulator platform
# (specs/simulator/simulator-features.md "SwiftCode implementation"). Runs on
# macOS only (the iOS simulator SDK's public headers and stubs).
#   out/swiftcode-settings-agent                 the settings agent (settings/): a launchd daemon
#       of the device; settings/swiftcode-settings-agent.entitlements is linked into
#       __TEXT,__entitlements (the simulator reads entitlements from that section,
#       app-install-launch.md §4.5)
#   out/libSwiftCodeEnvironmentOverrides.dylib   Environment Overrides inside one app (overrides/)
#   out/libSwiftCodeGauge.dylib                  Gauge's signpost agent inside a profiled app (gauge/;
#                                            specs/ide/profiler.md §3.1)
#   out/swiftcode-pairing-agent                  the pairing agent (pairing/; device-pairing.md P-4, §8): a launchd
#       daemon of every device; pairing/swiftcode-pairing-agent.entitlements in __TEXT,__entitlements
#   out/watchos/swiftcode-pairing-agent          the pairing agent built for the watchOS simulator (a signed
#       image is not retagged for another platform; watch devices use this one)
# Copy out/ into the guest-tools directory on the simulator host (next to ylaunch);
# swiftcode-simd stages the agent into each device and runs it, and inserts the
# library into apps launched with --environment-overrides.
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
# The watchOS simulator's own builds of the daemons (platform 9): a signed
# image cannot be retagged (GuestImagePlatform), so watch devices get these.
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
