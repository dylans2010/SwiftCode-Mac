#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/out}"
[ "$(uname -s)" = "Darwin" ] || { echo "SimGuestAgents/build-health.sh: needs macOS" >&2; exit 1; }
mkdir -p "$out/watchos"
plist() {
    /usr/libexec/PlistBuddy -c "Add :$2 $3 ${4-}" "$1" >/dev/null
}
info() {
    p=$1
    rm -f "$p"
    plist "$p" CFBundleIdentifier string "$2"
    plist "$p" CFBundleExecutable string "$3"
    plist "$p" CFBundleName string "$4"
    plist "$p" CFBundleDisplayName string "$4"
    plist "$p" CFBundlePackageType string APPL
    plist "$p" CFBundleInfoDictionaryVersion string 6.0
    plist "$p" CFBundleShortVersionString string 1.0
    plist "$p" CFBundleVersion string 1
    plist "$p" MinimumOSVersion string 27.0
    plist "$p" DTPlatformName string "$5"
    plist "$p" NSHealthShareUsageDescription string "Reads synthetic health data written by the SwiftCode simulator."
    plist "$p" NSHealthUpdateUsageDescription string "Writes synthetic health data for testing apps in the SwiftCode simulator."
    plist "$p" CFBundleSupportedPlatforms array
    if [ "$5" = watchsimulator ]; then
        plist "$p" CFBundleSupportedPlatforms:0 string WatchSimulator
        plist "$p" UIDeviceFamily array
        plist "$p" UIDeviceFamily:0 integer 4
    else
        plist "$p" CFBundleSupportedPlatforms:0 string iPhoneSimulator
        plist "$p" UIDeviceFamily array
        plist "$p" UIDeviceFamily:0 integer 1
    fi
}
entitlements_check() {
    xcrun otool -l "$1" | grep -q "sectname __entitlements" \
        || { echo "SimGuestAgents/build-health.sh: no __entitlements section in $1" >&2; exit 1; }
}
for platform in iphonesimulator watchsimulator; do
    if [ $platform = iphonesimulator ]; then
        app="$out/SwiftCodeHealth.app"; target=arm64-apple-ios27.0-simulator
    else
        app="$out/watchos/SwiftCodeHealth.app"; target=arm64-apple-watchos27.0-simulator
    fi
    rm -rf "$app"
    mkdir -p "$app"
    xcrun --sdk $platform clang -target $target -fobjc-arc -fobjc-arc-exceptions -O2 -Wall -Wextra -Werror \
        -framework Foundation -framework HealthKit -framework CoreLocation \
        -Wl,-sectcreate,__TEXT,__entitlements,"$here/health/swiftcode-health-agent.entitlements" \
        -o "$app/SwiftCodeHealth" "$here/health/swiftcode-health-agent.m"
    entitlements_check "$app/SwiftCodeHealth"
    info "$app/Info.plist" dev.swiftcode.health SwiftCodeHealth "SwiftCode Health" $platform
    plist "$app/Info.plist" SBAppTags array
    plist "$app/Info.plist" SBAppTags:0 string hidden
done
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ent() {
    cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$2</string>
<key>com.apple.developer.healthkit</key><true/>
</dict></plist>
EOF
}
app="$out/HealthCheck.app"
watch="$app/Watch/HealthCheckWatch.app"
rm -rf "$app"
mkdir -p "$watch"
ent "$tmp/phone.entitlements" dev.swiftcode.healthcheck
ent "$tmp/watch.entitlements" dev.swiftcode.healthcheck.watchkitapp
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -parse-as-library -O \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$tmp/phone.entitlements" \
    -o "$app/HealthCheck" "$here/healthcheck/HealthCheck.swift"
xcrun --sdk watchsimulator swiftc -target arm64-apple-watchos27.0-simulator -parse-as-library -O \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$tmp/watch.entitlements" \
    -o "$watch/HealthCheckWatch" "$here/healthcheck/HealthCheck.swift"
entitlements_check "$app/HealthCheck"
entitlements_check "$watch/HealthCheckWatch"
info "$app/Info.plist" dev.swiftcode.healthcheck HealthCheck "Health Check" iphonesimulator
plist "$app/Info.plist" LSRequiresIPhoneOS bool true
plist "$app/Info.plist" UILaunchScreen dict
plist "$app/Info.plist" UIApplicationSceneManifest dict
plist "$app/Info.plist" UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool true
info "$watch/Info.plist" dev.swiftcode.healthcheck.watchkitapp HealthCheckWatch "Health Check" watchsimulator
plist "$watch/Info.plist" WKApplication bool true
plist "$watch/Info.plist" WKCompanionAppBundleIdentifier string dev.swiftcode.healthcheck
codesign --force --sign - --timestamp=none --entitlements "$tmp/watch.entitlements" "$watch"
codesign --force --sign - --timestamp=none --entitlements "$tmp/phone.entitlements" "$app"
for f in "$out/SwiftCodeHealth.app/SwiftCodeHealth" "$out/watchos/SwiftCodeHealth.app/SwiftCodeHealth" "$app/HealthCheck" "$watch/HealthCheckWatch"; do
    echo "$f: $(wc -c < "$f" | tr -d ' ') bytes"
done
echo "SimGuestAgents/build-health.sh: ok"
