#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
DERIVED="${HP_DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/HealthProbe-research}"
COMMON=(-project HealthProbe.xcodeproj -scheme HealthProbe -configuration Debug
        -destination generic/platform=iOS -derivedDataPath "$DERIVED")
if [[ "${1:-}" == "--unsigned" ]]; then
  xcodebuild "${COMMON[@]}" CODE_SIGNING_ALLOWED=NO build
  exit
fi
TEAM="${HP_TEAM:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamManagerLastSelectedTeamID 2>/dev/null || true)}"
if [[ -z "$TEAM" ]]; then
  echo "No team selected: sign in to Xcode (Settings > Accounts) or set HP_TEAM." >&2
  exit 1
fi
PREFIX="${HP_BUNDLE_PREFIX:-org.ycode.research.t$(print -n "$TEAM" | shasum | cut -c1-8)}"
xcodebuild "${COMMON[@]}" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" HP_BUNDLE_PREFIX="$PREFIX" build
echo "built: $DERIVED/Build/Products/Debug-iphoneos/HealthProbe.app"
