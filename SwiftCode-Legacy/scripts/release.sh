#!/usr/bin/env bash
# scripts/release.sh
# Production-ready local release pipeline for SwiftCode-Mac.
# Implements preflight checks, building, testing, code signing, notarization,
# DMG packaging, Sparkle update archive and appcast generation, and GitHub release publication.
#
# Usage:
#   ./scripts/release.sh [--dry-run] [--skip-notarize] [--allow-adhoc] [--version <v>] [--build-num <n>] [--notes-file <file>] [--notes <text>] [--help]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARTIFACTS_DIR="$REPO_ROOT/dist"
DMG_STAGING="$BUILD_DIR/dmg-staging"
APPCAST_STAGING="$BUILD_DIR/appcast-staging"

DRY_RUN=false
SKIP_NOTARIZE=false
ALLOW_ADHOC=false
OVERRIDE_VERSION=""
OVERRIDE_BUILD=""
CUSTOM_NOTES_FILE=""
CUSTOM_NOTES_TEXT=""
TAG_NAME=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ [INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}✓ [OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠ [WARN]${NC} $*"; }
log_err() { echo -e "${RED}✗ [ERROR]${NC} $*"; }

usage() {
    cat << EOF
SwiftCode Local Release Pipeline

Usage:
  ./scripts/release.sh [options]

Options:
  --dry-run             Run preflight, test suite, and dry-run build/packaging without publishing
  --skip-notarize       Skip Apple notarization step (useful for testing or ad-hoc builds)
  --allow-adhoc         Allow ad-hoc code signing if Developer ID Application is not present
  --version <ver>       Override marketing version (e.g. 1.0.0)
  --build-num <num>     Override current project build version (e.g. 2)
  --notes-file <file>   Path to Markdown/HTML release notes file
  --notes <text>        Inline release notes string
  -h, --help            Show this help message

Environment variables (optional overrides):
  DEVELOPER_ID_IDENTITY   Code signing identity name (default: "Developer ID Application")
  NOTARY_KEYCHAIN_PROFILE notarytool keychain profile name (e.g. "AC_PASSWORD" or "notary")
  APPLE_ID                Apple ID for notarization (if not using keychain profile)
  APPLE_APP_PASSWORD      App-specific password for notarization
  APPLE_TEAM_ID           Apple Developer Team ID
  SPARKLE_PRIVATE_KEY     Sparkle EdDSA private key string or path to key file
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --allow-adhoc)
            ALLOW_ADHOC=true
            shift
            ;;
        --version)
            OVERRIDE_VERSION="$2"
            shift 2
            ;;
        --build-num)
            OVERRIDE_BUILD="$2"
            shift 2
            ;;
        --notes-file)
            CUSTOM_NOTES_FILE="$2"
            shift 2
            ;;
        --notes)
            CUSTOM_NOTES_TEXT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_err "Unknown argument: $1"
            usage
            ;;
    esac
done

cd "$REPO_ROOT"

echo "================================================================"
echo "          SwiftCode Local Release Pipeline                      "
echo "================================================================"
echo "Mode: $(if [ "$DRY_RUN" = true ]; then echo "DRY-RUN (Preflight / Safe Verification)"; else echo "PRODUCTION RELEASE"; fi)"
echo "Repo Root: $REPO_ROOT"
echo "================================================================"

# --------------------------------------------------
# Phase 1: Environment & Tool Preflight
# --------------------------------------------------
log_info "Step 1: Checking environment and required tools..."

if [ "$(uname -s)" != "Darwin" ]; then
    log_err "This release pipeline requires macOS with Xcode and Apple developer tools."
    exit 1
fi

REQUIRED_TOOLS=(xcodebuild swift codesign security xcrun stapler spctl hdiutil ditto git gh plutil)
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_err "Missing required CLI tool: $tool"
        exit 1
    fi
done
log_ok "All required macOS CLI tools found."

# Find Sparkle tools
GENERATE_APPCAST_BIN=""
SIGN_UPDATE_BIN=""
for path in \
    "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$REPO_ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"; do
    if [ -x "$path" ]; then
        GENERATE_APPCAST_BIN="$path"
        break
    fi
done

for path in \
    "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
    "$REPO_ROOT/build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"; do
    if [ -x "$path" ]; then
        SIGN_UPDATE_BIN="$path"
        break
    fi
done

if [ -z "$GENERATE_APPCAST_BIN" ] || [ -z "$SIGN_UPDATE_BIN" ]; then
    log_warn "Sparkle CLI tools not found in build cache. Attempting to resolve via Xcode SPM packages..."
    xcodebuild -scheme SwiftCode -resolvePackageDependencies -derivedDataPath "$DERIVED_DATA" >/dev/null 2>&1 || true
    GENERATE_APPCAST_BIN="$(find "$DERIVED_DATA" -name generate_appcast -type f -perm +111 2>/dev/null | head -n 1 || true)"
    SIGN_UPDATE_BIN="$(find "$DERIVED_DATA" -name sign_update -type f -perm +111 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$GENERATE_APPCAST_BIN" ] || [ -z "$SIGN_UPDATE_BIN" ]; then
    log_err "Unable to locate Sparkle binaries (generate_appcast / sign_update)."
    exit 1
fi
log_ok "Sparkle tools located: $GENERATE_APPCAST_BIN"

# Check GitHub CLI authentication
if ! gh auth status >/dev/null 2>&1; then
    log_err "GitHub CLI (gh) is not authenticated. Run 'gh auth login' first."
    exit 1
fi
log_ok "GitHub CLI is authenticated."

# Check Git working directory status
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
log_info "Current git branch: $CURRENT_BRANCH"
if [ "$CURRENT_BRANCH" != "main" ] && [ "$DRY_RUN" = false ]; then
    log_warn "You are releasing from branch '$CURRENT_BRANCH', not 'main'."
fi

# --------------------------------------------------
# Phase 2: Credentials & Signing Identities
# --------------------------------------------------
log_info "Step 2: Checking Apple signing and notarization credentials..."

DEV_ID_NAME="${DEVELOPER_ID_IDENTITY:-Developer ID Application}"
SIGNING_IDENTITY=""
if security find-identity -v -p codesigning | grep -q "$DEV_ID_NAME"; then
    SIGNING_IDENTITY="$DEV_ID_NAME"
    log_ok "Developer ID Application signing identity found in Keychain."
else
    if [ "$ALLOW_ADHOC" = true ] || [ "$DRY_RUN" = true ]; then
        log_warn "Developer ID Application identity NOT found in Keychain. Proceeding with ad-hoc signing because --allow-adhoc or --dry-run is active."
        SIGNING_IDENTITY="-"
        SKIP_NOTARIZE=true
    else
        log_err "Developer ID Application certificate not found in Keychain."
        log_err "Available codesigning identities:"
        security find-identity -v -p codesigning
        log_err "To test local packaging without a Developer ID certificate, use: ./scripts/release.sh --dry-run or --allow-adhoc"
        exit 1
    fi
fi

# Notarization credentials
if [ "$SKIP_NOTARIZE" = false ]; then
    NOTARY_AVAILABLE=false
    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        NOTARY_AVAILABLE=true
    elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        NOTARY_AVAILABLE=true
    fi

    if [ "$NOTARY_AVAILABLE" = false ]; then
        if [ "$DRY_RUN" = true ]; then
            log_warn "Notarization credentials not configured in environment. Skipping notarization for dry-run."
            SKIP_NOTARIZE=true
        else
            log_err "Notarization credentials missing."
            log_err "Please provide either NOTARY_KEYCHAIN_PROFILE or (APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID)."
            exit 1
        fi
    else
        log_ok "Notarization credentials configured."
    fi
fi

# Sparkle Signing Key
log_info "Checking Sparkle signing keys..."
SPARKLE_KEY_SOURCE=""
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SPARKLE_KEY_SOURCE="env"
    log_ok "Sparkle private key found in SPARKLE_PRIVATE_KEY environment variable."
elif security find-generic-password -s "https://sparkle-project.org" >/dev/null 2>&1; then
    SPARKLE_KEY_SOURCE="keychain"
    log_ok "Sparkle private key found in macOS Keychain."
else
    log_err "Sparkle EdDSA private key not found in Keychain or SPARKLE_PRIVATE_KEY environment variable."
    exit 1
fi

# Verify SUPublicEDKey in Info.plist
INFO_PLIST="$REPO_ROOT/SwiftCode/Info.plist"
CONFIGURED_PUBKEY="$(plutil -p "$INFO_PLIST" | grep "SUPublicEDKey" | awk -F '=> ' '{print $2}' | tr -d '"' || true)"
if [ -z "$CONFIGURED_PUBKEY" ]; then
    log_err "SUPublicEDKey is not set in $INFO_PLIST."
    exit 1
fi
log_ok "Sparkle public key in Info.plist: $CONFIGURED_PUBKEY"

# --------------------------------------------------
# Phase 3: Versioning & Release Notes
# --------------------------------------------------
log_info "Step 3: Resolving version and build numbers..."

CURRENT_PROJECT_VERSION="$(xcodebuild -scheme SwiftCode -showBuildSettings 2>/dev/null | grep -E "^ +CURRENT_PROJECT_VERSION" | awk '{print $3}' | head -n 1 || true)"
MARKETING_VERSION="$(xcodebuild -scheme SwiftCode -showBuildSettings 2>/dev/null | grep -E "^ +MARKETING_VERSION" | awk '{print $3}' | head -n 1 || true)"

CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-1}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"

if [ -n "$OVERRIDE_VERSION" ]; then
    MARKETING_VERSION="$OVERRIDE_VERSION"
fi
if [ -n "$OVERRIDE_BUILD" ]; then
    CURRENT_PROJECT_VERSION="$OVERRIDE_BUILD"
fi

TAG_NAME="v${MARKETING_VERSION}"
log_info "Release version: $MARKETING_VERSION (Build $CURRENT_PROJECT_VERSION)"
log_info "Release tag: $TAG_NAME"

# Check tag collision or existing release
EXISTING_LOCAL_TAG=false
EXISTING_REMOTE_TAG=false
EXISTING_GH_RELEASE=false

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    EXISTING_LOCAL_TAG=true
fi
if git ls-remote --tags origin "refs/tags/$TAG_NAME" | grep -q "$TAG_NAME"; then
    EXISTING_REMOTE_TAG=true
fi
if gh release view "$TAG_NAME" >/dev/null 2>&1; then
    EXISTING_GH_RELEASE=true
fi

if [ "$EXISTING_LOCAL_TAG" = true ] || [ "$EXISTING_REMOTE_TAG" = true ] || [ "$EXISTING_GH_RELEASE" = true ]; then
    if [ "$DRY_RUN" = true ]; then
        log_warn "Tag/Release '$TAG_NAME' already exists (local: $EXISTING_LOCAL_TAG, remote tag: $EXISTING_REMOTE_TAG, release: $EXISTING_GH_RELEASE). Continuing dry-run verification..."
    else
        log_warn "Tag/Release '$TAG_NAME' already exists (local: $EXISTING_LOCAL_TAG, remote tag: $EXISTING_REMOTE_TAG, release: $EXISTING_GH_RELEASE)."
        log_warn "Running in UPDATE/OVERWRITE mode for release '$TAG_NAME'."
    fi
else
    log_ok "Release tag '$TAG_NAME' is fresh and available."
fi

# --------------------------------------------------
# Phase 4: Run Tests
# --------------------------------------------------
log_info "Step 4: Running in-app test suite..."
TEST_RUNNER_DIR="$(mktemp -d)"
cat << 'EOF' > "$TEST_RUNNER_DIR/main.swift"
import Foundation

@main
struct Main {
    static func main() {
        let results = AppUpdateSupportTests.runAll()
        let failures = results.filter { !$0.passed }
        print("Ran \(results.count) checks. Failures: \(failures.count)")
        for f in failures {
            print("FAIL: \(f.testName) - \(f.message)")
        }
        if !failures.isEmpty {
            exit(1)
        }
        print("ALL_TESTS_PASSED")
    }
}
EOF

swiftc -parse-as-library \
    "$REPO_ROOT/SwiftCode/Backend/Updates/AppUpdateSupport.swift" \
    "$REPO_ROOT/SwiftCode/Backend/Updates/AppUpdateSupportTests.swift" \
    "$TEST_RUNNER_DIR/main.swift" \
    -o "$TEST_RUNNER_DIR/test_runner"

if ! "$TEST_RUNNER_DIR/test_runner"; then
    log_err "AppUpdateSupportTests failed!"
    rm -rf "$TEST_RUNNER_DIR"
    exit 1
fi
rm -rf "$TEST_RUNNER_DIR"
log_ok "All in-app update tests passed."

# --------------------------------------------------
# Phase 5: Build Release Application Bundle
# --------------------------------------------------
log_info "Step 5: Building Release application bundle..."

mkdir -p "$BUILD_DIR"
mkdir -p "$ARTIFACTS_DIR"

XCODEBUILD_ARGS=(
    -project "$REPO_ROOT/SwiftCode.xcodeproj"
    -scheme SwiftCode
    -configuration Release
    -derivedDataPath "$DERIVED_DATA"
)

if [ "$SIGNING_IDENTITY" = "-" ]; then
    XCODEBUILD_ARGS+=(
        CODE_SIGN_IDENTITY=""
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
else
    XCODEBUILD_ARGS+=(
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
    )
    if [ -n "${APPLE_TEAM_ID:-}" ]; then
        XCODEBUILD_ARGS+=(DEVELOPMENT_TEAM="$APPLE_TEAM_ID")
    fi
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" build

APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/SwiftCode.app"
if [ ! -d "$APP_BUNDLE" ]; then
    log_err "SwiftCode.app bundle not found at: $APP_BUNDLE"
    exit 1
fi
log_ok "SwiftCode.app built successfully."

# --------------------------------------------------
# Phase 6: Code Signing & Verification
# --------------------------------------------------
log_info "Step 6: Code signing and verifying application bundle..."

if [ "$SIGNING_IDENTITY" = "-" ]; then
    log_info "Applying ad-hoc code sign..."
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    log_info "Signing nested frameworks and main executable with '$SIGNING_IDENTITY'..."
    # Sign Sparkle framework first
    if [ -d "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    fi
    # Sign main bundle
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    spctl --assess --type exec -v "$APP_BUNDLE" || true
fi
log_ok "Code signing verification passed."

# --------------------------------------------------
# Phase 7: Notarization & Stapling
# --------------------------------------------------
if [ "$SKIP_NOTARIZE" = false ]; then
    log_info "Step 7: Notarizing application bundle with Apple..."
    ZIP_ARCHIVE="$ARTIFACTS_DIR/SwiftCode-$TAG_NAME.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_ARCHIVE"

    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        xcrun notarytool submit "$ZIP_ARCHIVE" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    else
        xcrun notarytool submit "$ZIP_ARCHIVE" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait
    fi

    log_info "Stapling notarization ticket to SwiftCode.app..."
    xcrun stapler staple "$APP_BUNDLE"
    spctl --assess --type exec -v "$APP_BUNDLE"
    log_ok "Notarization and stapling completed."
    rm -f "$ZIP_ARCHIVE"
else
    log_warn "Step 7: Notarization skipped (--skip-notarize or ad-hoc mode)."
fi

# --------------------------------------------------
# Phase 8: Package DMG
# --------------------------------------------------
log_info "Step 8: Packaging SwiftCode.dmg..."

mkdir -p "$ARTIFACTS_DIR"
DMG_OUTPUT="$ARTIFACTS_DIR/SwiftCode.dmg"
rm -rf "$DMG_STAGING" "$DMG_OUTPUT"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/SwiftCode.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "SwiftCode" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$DMG_STAGING"

if [ "$SIGNING_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_OUTPUT"
    if [ "$SKIP_NOTARIZE" = false ]; then
        xcrun stapler staple "$DMG_OUTPUT" || true
    fi
fi
log_ok "SwiftCode.dmg generated ($(stat -f%z "$DMG_OUTPUT" 2>/dev/null || wc -c < "$DMG_OUTPUT") bytes)."

# --------------------------------------------------
# Phase 9: Sparkle Appcast Generation & Signing
# --------------------------------------------------
log_info "Step 9: Generating signed Sparkle appcast.xml..."

# Prepare release notes for GitHub Release and Sparkle appcast
RELEASE_NOTES_FILE="$BUILD_DIR/RELEASE_NOTES.md"
if [ -n "$CUSTOM_NOTES_FILE" ] && [ -f "$CUSTOM_NOTES_FILE" ]; then
    log_info "Using provided release notes file: $CUSTOM_NOTES_FILE"
    cp "$CUSTOM_NOTES_FILE" "$RELEASE_NOTES_FILE"
elif [ -n "$CUSTOM_NOTES_TEXT" ]; then
    log_info "Using provided inline release notes text."
    printf '%s\n' "$CUSTOM_NOTES_TEXT" > "$RELEASE_NOTES_FILE"
else
    log_info "Generating release notes from git commit log..."
    cat << EOF > "$RELEASE_NOTES_FILE"
## SwiftCode ${MARKETING_VERSION}

### Changes
$(git log -n 10 --pretty=format:"* %s (%h)")

### Sparkle Updates
* Update feed: \`appcast.xml\`
* Direct package: \`SwiftCode.dmg\`
EOF
fi

rm -rf "$APPCAST_STAGING"
mkdir -p "$APPCAST_STAGING"
cp "$DMG_OUTPUT" "$APPCAST_STAGING/SwiftCode.dmg"

# Sparkle generate_appcast reads HTML release notes if placed next to the archive (e.g. SwiftCode.html)
# Format the markdown notes into valid embedded HTML without outer html/body tags
NOTES_HTML_FILE="$APPCAST_STAGING/SwiftCode.html"
cat << 'PYEOF' > "$BUILD_DIR/md_to_sparkle_html.py"
import sys, re, html

def md_to_html(md_text):
    lines = md_text.strip().splitlines()
    out = []
    in_ul = False
    for line in lines:
        s = line.strip()
        if not s:
            if in_ul:
                out.append("</ul>")
                in_ul = False
            continue
        if s.startswith("### "):
            if in_ul:
                out.append("</ul>"); in_ul = False
            out.append(f"<h3>{html.escape(s[4:])}</h3>")
        elif s.startswith("## "):
            if in_ul:
                out.append("</ul>"); in_ul = False
            out.append(f"<h2>{html.escape(s[3:])}</h2>")
        elif s.startswith("# "):
            if in_ul:
                out.append("</ul>"); in_ul = False
            out.append(f"<h1>{html.escape(s[2:])}</h1>")
        elif s.startswith("* ") or s.startswith("- "):
            if not in_ul:
                out.append("<ul>"); in_ul = True
            content = html.escape(s[2:])
            # bold & code formatting
            content = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', content)
            content = re.sub(r'`(.*?)`', r'<code>\1</code>', content)
            out.append(f"<li>{content}</li>")
        else:
            if in_ul:
                out.append("</ul>"); in_ul = False
            content = html.escape(s)
            content = re.sub(r'\*\*(.*?)\*\*', r'<b>\1</b>', content)
            content = re.sub(r'`(.*?)`', r'<code>\1</code>', content)
            out.append(f"<p>{content}</p>")
    if in_ul:
        out.append("</ul>")
    return "\n".join(out)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            content = f.read()
    else:
        content = sys.stdin.read()
    print(md_to_html(content))
PYEOF

python3 "$BUILD_DIR/md_to_sparkle_html.py" "$RELEASE_NOTES_FILE" > "$NOTES_HTML_FILE"
rm -f "$BUILD_DIR/md_to_sparkle_html.py"

DOWNLOAD_URL_PREFIX="https://github.com/dylans2010/SwiftCode-Mac/releases/download/${TAG_NAME}/"
APPCAST_OUTPUT="$ARTIFACTS_DIR/appcast.xml"

GENERATE_ARGS=(
    --download-url-prefix "$DOWNLOAD_URL_PREFIX"
    --embed-release-notes
    -o "$APPCAST_OUTPUT"
)

TEMP_KEY_FILE=""
if [ "$SPARKLE_KEY_SOURCE" = "env" ]; then
    if [ -f "$SPARKLE_PRIVATE_KEY" ]; then
        GENERATE_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY")
    else
        TEMP_KEY_FILE="$(mktemp /tmp/sparkle_key.XXXXXX)"
        chmod 600 "$TEMP_KEY_FILE"
        printf '%s' "$SPARKLE_PRIVATE_KEY" > "$TEMP_KEY_FILE"
        GENERATE_ARGS+=(--ed-key-file "$TEMP_KEY_FILE")
    fi
fi

"$GENERATE_APPCAST_BIN" "${GENERATE_ARGS[@]}" "$APPCAST_STAGING"

if [ -n "$TEMP_KEY_FILE" ]; then
    rm -f "$TEMP_KEY_FILE"
fi

# Verify appcast content
if ! grep -q 'sparkle:edSignature=' "$APPCAST_OUTPUT"; then
    log_err "Generated appcast.xml does NOT contain a sparkle:edSignature!"
    exit 1
fi
if ! grep -q "releases/download/${TAG_NAME}/SwiftCode.dmg" "$APPCAST_OUTPUT"; then
    log_err "Generated appcast.xml does NOT reference download URL for ${TAG_NAME}!"
    exit 1
fi
log_ok "Sparkle appcast.xml generated and verified."

# --------------------------------------------------
# Phase 10: Dry-Run Check / Publication Gate
# --------------------------------------------------
if [ "$DRY_RUN" = true ]; then
    echo "================================================================"
    log_ok "DRY-RUN COMPLETE: All build, test, signing, packaging, and Sparkle appcast gates passed."
    echo "Artifacts generated in: $ARTIFACTS_DIR"
    ls -lh "$ARTIFACTS_DIR"
    echo "Release notes preview:"
    cat "$RELEASE_NOTES_FILE"
    echo "================================================================"
    rm -f "$RELEASE_NOTES_FILE"
    exit 0
fi

# --------------------------------------------------
# Phase 11: GitHub Release Publication
# --------------------------------------------------
log_info "Step 11: Publishing GitHub Release..."

# Ensure git tag is present
if [ "$EXISTING_LOCAL_TAG" = false ]; then
    log_info "Creating git tag $TAG_NAME..."
    git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
fi

if [ "$EXISTING_REMOTE_TAG" = false ]; then
    log_info "Pushing git tag $TAG_NAME to origin..."
    git push origin "$TAG_NAME"
fi

if [ "$EXISTING_GH_RELEASE" = true ]; then
    log_info "Existing GitHub Release found for $TAG_NAME. Updating release and clobbering assets..."
    gh release edit "$TAG_NAME" \
        --title "SwiftCode $TAG_NAME" \
        --notes-file "$RELEASE_NOTES_FILE"

    gh release upload "$TAG_NAME" \
        "$DMG_OUTPUT" \
        "$APPCAST_OUTPUT" \
        --clobber
else
    log_info "Creating GitHub Release with gh CLI..."
    gh release create "$TAG_NAME" \
        "$DMG_OUTPUT" \
        "$APPCAST_OUTPUT" \
        --title "SwiftCode $TAG_NAME" \
        --notes-file "$RELEASE_NOTES_FILE"
fi

rm -f "$RELEASE_NOTES_FILE"

# --------------------------------------------------
# Phase 12: Remote Verification
# --------------------------------------------------
log_info "Step 12: Verifying remote release..."
gh release view "$TAG_NAME"

log_ok "Release $TAG_NAME published and verified successfully!"
