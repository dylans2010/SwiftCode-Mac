#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="${OUT:-$here/out}"
[ "$(uname -s)" = "Darwin" ] || { echo "SimGuestAgents/build-wcprobe.sh: needs macOS" >&2; exit 1; }
src="$here/wcprobe"
app="$out/WCProbe.app"
watch="$app/Watch/WCProbeWatch.app"
rm -rf "$app"
mkdir -p "$watch"
plist() {
    /usr/libexec/PlistBuddy -c "Add :$2 $3 ${4-}" "$1" >/dev/null
}
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator -parse-as-library -O \
    -o "$app/WCProbe" "$src/Probe.swift" "$src/App.swift"
xcrun --sdk watchsimulator swiftc -target arm64-apple-watchos27.0-simulator -parse-as-library -O \
    -o "$watch/WCProbeWatch" "$src/Probe.swift" "$src/App.swift"
p="$app/Info.plist"
plist "$p" CFBundleIdentifier string dev.swiftcode.wcprobe
plist "$p" CFBundleExecutable string WCProbe
plist "$p" CFBundleName string WCProbe
plist "$p" CFBundleDisplayName string WCProbe
plist "$p" CFBundlePackageType string APPL
plist "$p" CFBundleInfoDictionaryVersion string 6.0
plist "$p" CFBundleShortVersionString string 1.0
plist "$p" CFBundleVersion string 1
plist "$p" MinimumOSVersion string 27.0
plist "$p" DTPlatformName string iphonesimulator
plist "$p" LSRequiresIPhoneOS bool true
plist "$p" CFBundleSupportedPlatforms array
plist "$p" CFBundleSupportedPlatforms:0 string iPhoneSimulator
plist "$p" UIDeviceFamily array
plist "$p" UIDeviceFamily:0 integer 1
plist "$p" UILaunchScreen dict
plist "$p" UIApplicationSceneManifest dict
plist "$p" UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool true
p="$watch/Info.plist"
plist "$p" CFBundleIdentifier string dev.swiftcode.wcprobe.watchkitapp
plist "$p" CFBundleExecutable string WCProbeWatch
plist "$p" CFBundleName string WCProbe
plist "$p" CFBundleDisplayName string WCProbe
plist "$p" CFBundlePackageType string APPL
plist "$p" CFBundleInfoDictionaryVersion string 6.0
plist "$p" CFBundleShortVersionString string 1.0
plist "$p" CFBundleVersion string 1
plist "$p" MinimumOSVersion string 27.0
plist "$p" DTPlatformName string watchsimulator
plist "$p" WKApplication bool true
plist "$p" WKCompanionAppBundleIdentifier string dev.swiftcode.wcprobe
plist "$p" CFBundleSupportedPlatforms array
plist "$p" CFBundleSupportedPlatforms:0 string WatchSimulator
plist "$p" UIDeviceFamily array
plist "$p" UIDeviceFamily:0 integer 4
codesign --force --sign - --timestamp=none "$watch"
codesign --force --sign - --timestamp=none "$app"
for f in "$app/WCProbe" "$watch/WCProbeWatch"; do echo "$f: $(wc -c < "$f" | tr -d ' ') bytes"; done
echo "SimGuestAgents/build-wcprobe.sh: ok"
