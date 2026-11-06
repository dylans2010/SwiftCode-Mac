#!/bin/sh
# Builds SwiftCode's hosted-test agent, libSwiftCodeTestAgent.dylib
# (Sources/SwiftCodeTestAgent and Sources/CSwiftCodeTestAgentLoader; specs/ide/testing.md
# "SwiftCode implementation"), for the iOS simulator platform. Runs on macOS
# only (the iOS simulator SDK). The agent links neither XCTest nor Testing.
#   out/iphonesimulator/libSwiftCodeTestAgent.dylib
# swiftcodebuild finds it in iphonesimulator/ next to itself, or through
# SWIFTCODE_TEST_AGENT_IPHONESIMULATOR:
#   OUT=.build/debug SimGuestAgents/build-test-agent.sh      (from swiftcode/)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../Sources"
out="${OUT:-$here/out}/iphonesimulator"
[ "$(uname -s)" = "Darwin" ] || { echo "SimGuestAgents/build-test-agent.sh: needs macOS" >&2; exit 1; }
target="${TARGET:-arm64-apple-ios17.0-simulator}"
mkdir -p "$out/obj-test-agent"
xcrun --sdk iphonesimulator clang -target "$target" -O2 -Wall -Wextra -Werror \
    -I "$src/CSwiftCodeTestAgentLoader/include" -c -o "$out/obj-test-agent/loader.o" "$src/CSwiftCodeTestAgentLoader/loader.c"
xcrun --sdk iphonesimulator swiftc -target "$target" -O -module-name SwiftCodeTestAgent -parse-as-library \
    -emit-library -Xlinker -install_name -Xlinker @rpath/libSwiftCodeTestAgent.dylib \
    -o "$out/libSwiftCodeTestAgent.dylib" "$src/SwiftCodeTestAgent/TestAgent.swift" "$out/obj-test-agent/loader.o"
rm -rf "$out/obj-test-agent"
echo "$out/libSwiftCodeTestAgent.dylib: $(wc -c < "$out/libSwiftCodeTestAgent.dylib" | tr -d ' ') bytes"
echo "SimGuestAgents/build-test-agent.sh: ok"
