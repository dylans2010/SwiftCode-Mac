# Studio and SDK release readiness — 2026-10-12

## Status

**Not approved for a production release yet.** The concrete routing, navigation
and packaging defects below are fixed and tested, but the full macOS application
cannot currently build because its Cloud providers use Supabase APIs absent from
the resolved Supabase 2.1.0 dependency. No remote release, commit, or installed-app
replacement was performed.

## Behavior delivered

- Welcome has a Studio action card and toolbar action opening `SDKStudioView`
  through `SDKStudioWindowManager`.
- Studio has 10 sections: Projects, Extensions, API Keys, Security, Logs, Code
  Editor, Installed, Assist Access, SDK & Downloads, Ship & Export.
- Extensions' Manifest/Grants links now have a detail NavigationStack. The Code
  Editor already hosts snippets, build/run, tabs, navigator and console. Security
  and Assist approval sheets remain under their owning sections.
- Install/repair is accessible even after declining the first-launch installer.
  SDK & Downloads can save the bundled `.tgz` with a native save panel and open
  the bundled documentation.
- Google account credentials stay on Google/Gemini requests. Account mode sends
  OAuth Bearer auth and a real quota project, never an API key or a fabricated
  project. The SDK protobuf serializer no longer copies Bearer tokens into its
  `api_key` field.
- Non-Google provider requests cannot inherit a Google token/key, lose their own
  provider key due to an ambient Google token, or inherit the previous provider's
  base URL. Credential-less direct provider models are excluded from fallback.
- Both bundled Python entry points execute the same canonical bridge runner.
  The checked Python launcher is preferred over arbitrary external installations.
- The installer checks the exact remote archive, requires successful npm exit
  plus package name/version/runtime entry points, disables lifecycle scripts,
  and falls back honestly on failed/incomplete remote releases. The rebuilt
  archive includes Assist and Assist UI modules absent from the previous archive.
- `Distribution/bundle-sdk.sh` ships prebuilt package, CLI and its runtime
  dependencies, runtime adapter, templates, schemas/contracts, snippets,
  documentation and offline archive under `Resources/SwiftCodeSDK`. Missing
  required artifacts fail the build rather than generating a partial app.
- Normal Xcode builds no longer replace `/Applications/SwiftCode.app`.
  Installation is explicitly opt-in with `SWIFTCODE_INSTALL_APP=YES`.

## Verification completed

| Check | Result |
|---|---|
| Python auth/config helpers | 30 tests passed |
| Real Python SDK configs and serialized endpoint protos (mocked Agent transport) | 4 tests passed |
| TypeScript SDK build and tests | 112 tests passed; includes real create/build/package/install/adapter activation, integrity and adversarial security checks |
| Runtime adapter build/typecheck | Passed; its standalone `npm test` contains **zero tests**; exercised through SDK round-trip tests instead |
| Swift installer XCTest suite, isolated SwiftPM target | 15 tests passed; actual bundled npm install and public module import included |
| Live pinned remote installer attempt | Installed successfully **using bundled fallback**; the current remote release was not usable/complete |
| Copied, app-layout toolkit | Real create → build → package → install → activate → shutdown passed with `verify-bundle.mjs` |
| Swift configuration isolated executable | Provider/credential-kind separation and token-rotation reuse checks passed |
| Native Studio shell executable | All 10 section deep links and open/close/reopen passed; sibling panes were stubs, not full-app UI QA |
| Xcode project plist / whitespace | Passed |
| Full Xcode Debug build (rerun) | **Failed, exit 65**, in unchanged SupabaseProvider/SupabaseCloudProvider (`from`, `rpc`, `channel`, `RealtimeChannelV2`, `InsertAction`, `UpdateAction`) |

No live Google inference request was sent and no account tokens were inspected.
A Google account session is not equivalent to general SwiftCode/Appwrite sign-in.
The latter alone does not grant Gemini or Anthropic provider access.

### Repeatable SDK checks

From the repository root:

```bash
(cd SwiftCode/SDK/TypeScript/package && npm ci && npm run build && npm test && npm pack --pack-destination ../../Distribution)
(cd SwiftCode/SDK/TypeScript/cli && npm ci)
(cd SwiftCode/SDK/TypeScript/runtime-adapter && npm ci && npm run build && npm run typecheck)
PYTHONDONTWRITEBYTECODE=1 python3 "SwiftCode/Resources/Google Cloud SDK/bridge/gemini_auth_test.py"
PYTHONDONTWRITEBYTECODE=1 "SwiftCode/Resources/Google Cloud SDK/runtime/bin/python3" "SwiftCode/Resources/Google Cloud SDK/bridge/session_auth_test.py"
SRCROOT="$PWD" TARGET_BUILD_DIR="$PWD/build/sdk-check" UNLOCALIZED_RESOURCES_FOLDER_PATH=Resources bash SwiftCode/SDK/Distribution/bundle-sdk.sh
node SwiftCode/SDK/Distribution/verify-bundle.mjs build/sdk-check/Resources/SwiftCodeSDK
```

The installer XCTest source can be run in an isolated SwiftPM target named
`SwiftCode` containing SDKInstaller.swift, with its test target containing
SDKInstallerTests.swift. Set `SWIFTCODE_TEST_SDK_TARBALL` to the absolute path of
the rebuilt release archive; the test sandbox never installs into the user's
real `~/.swiftcode/sdk`.

## Mandatory release gates still open

1. Resolve Cloud-provider/Supabase API compatibility without bypassing auth or
   disabling Cloud code; pass full Debug and Release builds.
2. Run the actual app: Welcome → Studio, every real detail pane and nested
   sheet, sidebar switching, retained editor state, installer cancel/error/retry,
   save/overwrite/cancel, docs, grant revocation, install/update/uninstall and
   extension activation/deactivation. The isolated shell does not prove these.
3. With a consenting test account and quota project, verify actual Gemini OAuth
   inference, refresh/expiry, scope failure, quota/billing denial, failover, and
   key-rotation mode in both execution profiles. Never substitute an API key for
   account authentication to make this check pass.
4. Publish a new complete, immutable/versioned remote SDK artifact with digest
   verification; do not silently overwrite a previously released 1.0.0 tag.
   Existing fallback makes local installs usable, not the remote release current.
5. Verify packaged app on clean supported Macs. Node.js and host Python 3.14 are
   currently external prerequisites; the Python launcher is **not** a standalone
   interpreter. Test architecture/native harness compatibility and signed bundle
   read-only behavior, code signing, notarization and runtime sandbox boundaries.
6. Finish SDK host security/lifecycle audits. Passing TypeScript client and CLI
   tests does not certify all privileged host services or native integrations.

## Authentication reference

- Gemini Developer API OAuth scopes and quota-project REST header:
  https://ai.google.dev/gemini-api/docs/oauth
- Google quota-project permissions (`serviceusage.services.use`):
  https://docs.cloud.google.com/docs/authentication/troubleshoot-adc
- Direct Claude API requires separate Anthropic authentication; Google sign-in
  alone cannot authorize `api.anthropic.com`:
  https://platform.claude.com/docs/en/manage-claude/authentication
