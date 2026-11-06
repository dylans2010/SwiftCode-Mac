# Packaging

How a clean checkout becomes `SwiftCode-<version>.dmg` and
`SwiftCode-<version>-<arch>.flatpak`. The version comes from one place,
[`swiftcode/VERSION`](../swiftcode/VERSION). `SwiftCodeReleaseTests` fails when the Swift
constant or the Flatpak metainfo disagrees with it, or when a packaging script
states a version of its own. To change the version, edit `swiftcode/VERSION`,
`SwiftCodeRelease.version` and the newest `<release>` in the metainfo.

SwiftCode is not affiliated with or endorsed by Apple Inc. Neither package contains
files from Xcode, an SDK or a simulator runtime, and nothing here downloads or
decrypts Apple's archives.

## Everything the scripts take

| Script | Run on | Output |
|---|---|---|
| `swiftcode/scripts/make-app.sh [dir]` | macOS | `<dir>/SwiftCode.app` (default `.build-ide/app`) |
| `swiftcode/scripts/make-dmg.sh [dir]` | macOS | `<dir>/SwiftCode-<version>.dmg` and `.sha256` (default `.build-ide/dist`) |
| `packaging/macos/verify-dmg.sh <dmg>` | macOS | checks a built image; `make-dmg.sh` runs it |
| `packaging/flatpak/build-flatpak.sh [dir]` | Linux, x86-64 or aarch64 | `<dir>/SwiftCode-<version>-<arch>.flatpak`, `<dir>/SwiftCode-<version>-<arch>.tar.xz`, and a `.sha256` for each (default `packaging/flatpak/out`) |
| `swiftcode/scripts/version.sh` | any | prints the version |
| `packaging/generate-notices.py` | any | rewrites `THIRD_PARTY_NOTICES.md` |
| `packaging/flatpak/generate-swift-dependencies.py` | any | rewrites `swift-dependencies.json` after a `Package.resolved` changes |

All are non-interactive and exit nonzero on failure.

### macOS variables (all optional)

| Variable | Meaning |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD` | A Developer ID Application certificate. It goes into a temporary keychain that is removed at the end. |
| `SWIFTCODE_SIGN_IDENTITY` | An identity already in a keychain. Wins over the P12. |
| `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | An App Store Connect API key. All three, plus a real identity, turn on notarizing and stapling. |
| `APPLE_TEAM_ID` | When set with a real identity, the script checks the app is signed by this team. |
| `SWIFTCODE_ARCHS` | The architectures. `make-dmg.sh` defaults to `arm64 x86_64` (universal); `make-app.sh` alone defaults to `arm64`. |
| `SWIFTCODE_BUILD_NUMBER` | `CFBundleVersion`, default 1. |
| `SWIFTCODE_BUILD_ROOT` | SwiftPM scratch folder, default `.build-release`. |
| `SWIFTCODE_SWB_BUILD_ROOT` | Scratch folder for the swift-build helper, default `/tmp/swiftcode-release-<uid>`. Its path ends up in the binaries, so it must name nobody. |
| `SWIFTCODE_ICON_ICNS` | The icon, default `packaging/icon/SwiftCode.icns`. |
| `SWIFTCODE_APP_MINIMAL=1` | `make-app.sh` only: a quick development app with `swiftcode-bsp` as its only helper. |
| `SWIFTCODE_DMG_SKIP_APP=1` | `make-dmg.sh` only: package the app already in `<dir>/stage`. |
| `SWIFTCODE_VERIFY_REQUIRE_GATEKEEPER=1` | `verify-dmg.sh` only: fail when `spctl` rejects the app. Set it in a release that has the secrets. |

With no signing variable the same path gives an ad-hoc signed image, which
Gatekeeper rejects. The scripts never print a secret's value.

### Flatpak variables (all optional)

| Variable | Meaning |
|---|---|
| `SWIFTCODE_SOURCE_REF` | The commit to package, default `HEAD`. Only committed files are packaged. |
| `SWIFTCODE_SOURCE_TAR` | A tar of the same paths, for a machine without the repository's history. |
| `SWIFTCODE_FLATPAK_WORK` | The work folder, default `packaging/flatpak/.work`. |

## The macOS app

```text
SwiftCode.app/Contents/
  MacOS/SwiftCode                     the IDE
  Helpers/swiftcode                   the command line, the MCP server, `swiftcode sim remote`
  Helpers/swiftcodebuild              the build tool for projects and workspaces
  Helpers/swiftcode-bsp               the build server for sourcekit-lsp
  Helpers/swiftcode-swb               the helper that talks to swift-build
  Helpers/SWBBuildServiceBundle   swift-build's service
  Helpers/SwiftBuild_*.bundle     swift-build's specifications (open source)
  Helpers/swiftcode-sim-viewer        a window on a simulator device (experimental)
  Helpers/swiftcode-simhost           a simulator host's service (experimental)
  Helpers/libSwiftCodeTestAgent.dylib the agent for tests hosted in a Mac app
  Resources/simulator-host/       swiftcode-sim and swiftcode-sim-serve, to copy to a Linux host
  Resources/SwiftCode.icns, LICENSE, THIRD_PARTY_NOTICES.md
```

At launch the app puts `Contents/Helpers` first on its `PATH`
(`SwiftCodeRelease.adoptBundledHelpers`), so every tool lookup finds the bundled copy
wherever the app was copied. Helpers are not in `Contents/MacOS` because `swiftcode`
and `SwiftCode` are the same name on a case-insensitive disk.

The app needs a developer toolchain on the Mac; it does not ship one.

**Architectures.** The image is universal. Each architecture is a separate SwiftPM
build merged with `lipo`, so it takes about twice as long as one. Set
`SWIFTCODE_ARCHS=arm64` for a quicker, smaller image.

**Signing.** Inside out: each helper, then the app. Every executable has the
hardened runtime, and there are **no entitlements**. The app has no JIT and loads
no plug-ins: a preview runs in its own host program, which the toolchain signs. A
tool that needs an exception later must add it here with the reason.

**The image's window** needs no Finder: `packaging/macos/make-dsstore.py` writes the
`.DS_Store` directly, so the build works with nobody logged in and never takes
over a screen. `make-dmg-background.swift` draws the committed
`dmg-background.tiff`.

**`verify-dmg.sh`** mounts the image, copies the app to an empty folder, then
checks the signature with `codesign --verify --deep --strict`, reports `spctl`'s
answer, runs each tool's `--version` with an empty environment, checks linkage and
search paths, searches the binaries for machine paths, and starts the app hidden.
It does not look at the window: open the image once by hand to check the layout.

## The Flatpak

The manifest is `flatpak/io.github.MarcoDotIO.Ycode.yml`, on freedesktop 26.08.
Every download is pinned by SHA-256, and the build itself has no network. The Swift
dependencies are commit archives listed in `flatpak/swift-dependencies.json`;
`prepare-swift-deps.py` turns them into local git repositories for SwiftPM.

A build machine needs `flatpak` and `flatpak-builder`, and user namespaces. On
Ubuntu 24.04, unprivileged user namespaces are restricted by default, so a CI job
first runs `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.

### It is not really sandboxed

**The Flatpak uses the Swift toolchain installed on your computer, through
`flatpak-spawn --host`. That permission lets SwiftCode run any program on the host as
you, so this package is a convenient way to install SwiftCode, not a security
boundary.** Treat it like any other program you run outside a sandbox.

| Permission | Why |
|---|---|
| `--talk-name=org.freedesktop.Flatpak` | `flatpak-spawn --host` reaches the host's toolchain, git and ssh |
| `--filesystem=home`, `--filesystem=/tmp` | Projects. The host's toolchain must see them at the same paths. |
| `--socket=wayland`, `--socket=fallback-x11`, `--share=ipc`, `--device=dri` | The window and the GPU |
| `--socket=pulseaudio` | Sound from a simulator device |
| `--share=network`, `--socket=ssh-auth` | Packages, coding assistants, the link to a simulator host |
| `--device=kvm` (aarch64 only) | `swiftcode-simd` runs guests under KVM |

`libexec/swiftcode-host` comes first on the `PATH`. It holds a wrapper for each
host tool (`swift`, `swiftc`, `sourcekit-lsp`, `lldb-dap`, `git`, `ssh`, ...). The
wrapper finds the tool through a login shell (your own shell from the password
database, so a profile written for bash still works where `sh` is dash) and
swiftly's folders. If the tool is missing it says what to install, and the message
reaches the build log.

Projects outside your home folder and `/tmp` are not visible to the app. Add them
with `flatpak override --user --filesystem=<path> io.github.MarcoDotIO.Ycode`.

### What each architecture contains

Both: `swiftcode-ide`, `swiftcode`, `swiftcodebuild`, `swiftcode-bsp`, `swiftcode-swb`,
`SWBBuildServiceBundle`, swift-build's and the UI's resources, `swiftcode-sim-viewer`,
`libSwiftCodeGaugeAgent.so`, `scripts/swiftcode-ios-build-linux`, SDL 3, the Swift runtime
libraries the tools load (unmodified from swift.org's toolchain), libxml2 2.13 and
libcurl 8.23 for Foundation (the runtime's copies have another soname or no
versioned symbols), 7-Zip 26.05's `7zz` (built from its own source without the RAR
code; a runtime download reads the runtime's disk image with it, as a separate
program), the host-tool wrappers, and the notices.

aarch64 also: the simulator tools, labelled experimental, in
`/app/lib/swiftcode-sim`, laid out like the source tree the scripts expect:
`swiftcode-simd`, `swiftcode-simhost`, `swiftcode-airc` (with libLLVM), the `SimShim` guest
binaries, the `SimHostLibs` clean-room libraries, `SimGuestFrameworks`, and
`swiftcode-sim`. The guest agents (`SimGuestAgents`) are not included: they build only
on macOS, against the iOS simulator SDK.

The simulator needs a runtime from your own copy of the platform tools. No package
contains one.

### The relocatable tarball

`SwiftCode-<version>-<arch>.tar.xz` holds the same files as the Flatpak's `/app`, under
one top folder (`bin/`, `lib/`, `libexec/`, `share/`), and runs from wherever it is
unpacked:

- Binaries find their libraries through `$ORIGIN` search paths.
- Tools find each other relative to themselves. `SwiftCodeRelease.adoptBundledHelpers`
  puts the package's tools on `PATH` at start, and inside a Flatpak (`FLATPAK_ID`
  set) puts the `libexec/swiftcode-host` wrappers first.
- `flatpak-spawn --host` is used in one file only, `flatpak/host-tool.sh`. A package
  that wraps this tarball declares `--talk-name=org.freedesktop.Flatpak` for it, for
  the reason given above.

It is built against freedesktop 26.08 (glibc 2.44), so it needs that runtime, or a
host with that glibc or newer. Outside a Flatpak the wrappers are not used and tools
come from the host's `PATH`.

### Testing the installed package

```sh
flatpak install --user --bundle SwiftCode-<version>-x86_64.flatpak
flatpak run --user --command=swiftcode io.github.MarcoDotIO.Ycode --version
# In a Swift package folder under the home folder: builds with the host's SwiftPM.
flatpak run --user --command=swiftcode io.github.MarcoDotIO.Ycode build
# Under Xvfb on a desktop that also runs Wayland, ask for X11 for the test:
DISPLAY=:97 flatpak run --user --socket=x11 --nosocket=wayland \
    --env=SWIFTCODE_IDE_WALK=$HOME/walk io.github.MarcoDotIO.Ycode [<package>]
```

`SWIFTCODE_IDE_WALK` (see `swiftcode/Sources/swiftcode-ide/ShellDriver.swift`) walks Welcome,
About, Clone and New Project, and with a package path also Build, Test and Run,
writing a screenshot for each step.

## Third-party licences

`THIRD_PARTY_NOTICES.md` is generated and included in each package. Texts that are
in no checkout or vendored folder are in `licenses/`.
