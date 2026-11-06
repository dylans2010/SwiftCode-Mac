# Developing SwiftCode

This is the Swift package with the IDE, the command-line tools and the simulator.
To install or try SwiftCode, read the [root README](../README.md) instead.

This is clean-room code. Read [`../CONTRIBUTING.md`](../CONTRIBUTING.md) before you
make any change here.

## Layout

| Path | Contents |
|---|---|
| `Sources/SwiftCode{Plist,Project,Workspace,Settings,MachO}` | Project model, file formats, build settings, Mach-O |
| `Sources/SwiftCode{Build,Language,Debug,Assistant,Completion,Subprocess}` | IDE services: build engines and PIF, LSP and DAP clients, coding assistant, subprocess runs |
| `Sources/SwiftCodeIDECore` | The IDE's portable model, shared by both windows |
| `Sources/SwiftCode{UI,DeviceUI,App}` | The macOS IDE (AppKit) and its device windows |
| `Sources/{SwiftCodeIDEShell,swiftcode-ide}` | The Linux IDE (SwiftUI on OpenViews, `../frameworks/swiftui`) |
| `Sources/SwiftCodeEditorKit` | The Linux IDE's source editor model: buffer, undo, movement, safe saving, recovery copies (portable) |
| `Sources/{SwiftCodeXcodebuild,swiftcodebuild-cli}`, `Tools/swiftcode-swb` | `swiftcodebuild` and its swift-build helper |
| `Sources/SwiftCode{DarwinABI,DarwinKernel,Hypervisor,XPC,HostServices}`, `Sources/swiftcode-simd` | Simulator: the Darwin kernel layer, KVM, XPC, host services, the VM monitor |
| `Sources/SwiftCode{MetalHost,Vulkan}`, `Translator/` | Simulator: Metal on Vulkan, and the AIR to SPIR-V translator |
| `Sources/SwiftCode{DisplayStream,SimFeatures,SimLink}`, `Sources/swiftcode-sim-viewer` | Simulator: the display stream, settings features, the remote link, the viewer |
| `SimShim/`, `SimHostLibs/`, `SimGuestFrameworks/`, `SimGuestAgents/` | Simulator guest side, all our own code |
| `Samples/` | Small projects used by tests |
| `scripts/` | App packaging, simulator launchers, conformance and profiling scripts, the lint wrapper |

## Build and test

Platforms: the libraries and command-line tools build and test on macOS and
Linux (x86-64 and arm64, Swift 6.4). `SwiftCodeUI`, `SwiftCodeDeviceUI`, `SwiftCodeApp`
and `swiftcode-sim-viewer` are macOS only. `swiftcode-simd` runs only on arm64 Linux
with KVM.

```bash
swift build
swift test
scripts/lint.sh                      # SwiftLint over swiftcode/ and frameworks/
scripts/make-app.sh                  # macOS: .build-ide/app/SwiftCode.app
.build/debug/swiftcode describe path/to/App.xcodeproj
.build/debug/swiftcode roundtrip path/to/App.xcodeproj    # also .xcscheme / contents.xcworkspacedata
.build/debug/swiftcode schemes path/to/App.xcworkspace
.build/debug/swiftcode macho path/to/binary
.build/debug/swiftcode dsc path/to/dyld_sim_shared_cache_arm64 [--images N] [--image /usr/lib/libobjc.A.dylib]
.build/debug/swiftcode settings path/to/App.xcodeproj -target App -configuration Debug [--assigned-only] [--json] [NAME=value]
.build/debug/swiftcode deps path/to/executable --root path/to/RuntimeRoot [--tree]
.build/debug/swiftcode build path/to/App.xcodeproj -scheme App [--test] [--engine xcodebuild|swift-build|swiftpm]
.build/debug/swiftcode build path/to/Package [--test]     # Linux and the Flatpak: SwiftPM, as the Linux IDE builds packages
.build/debug/swiftcode pif path/to/App.xcodeproj
.build/debug/swiftcode profile record --linux -o out.gaugetrace -- path/to/executable   # Gauge, the profiler
.build/debug/swiftcode profile summary|tree|flame|annotate|symbolicate out.gaugetrace ...
.build/debug/swiftcode assets compile App/Assets.xcassets App/AppIcon.icon --output out --platform iphonesimulator --app-icon AppIcon
.build/debug/swiftcode assets info out/Assets.car
.build/debug/swiftcode assets icon info|validate|to-json|from-json|render App/AppIcon.icon ...
.build/debug/swiftcode strings compile --output-directory out App/Localizable.xcstrings   # also generate-symbols, extract, convert, info
.build/debug/swiftcode mcp [--workspace path/to/Package] [--allow-writes] [--http [PORT]]   # the MCP server for coding agents
.build/debug/swiftcode mcp install-skill path/to/Package                                # the SwiftCode skill for agents
```

`swiftcode mcp` is SwiftCode's MCP server (`../specs/ide/coding-assistant.md` §10):
build, test, run (also on the SwiftCode Simulator, with screenshots), issues,
search, previews and String Catalogs for Claude Code, Codex and other MCP
clients, on macOS and Linux. Add it with `claude mcp add swiftcode -- swiftcode mcp`
or `codex mcp add swiftcode -- swiftcode mcp`. It is read-only unless started with
`--allow-writes`; in the IDE's agent mode every change is a proposal the
user reviews.

`swiftcode assets` is SwiftCode's asset catalog compiler (`../specs/formats/assets-car.md`
"SwiftCode implementation"). Builds use it instead of Xcode's `actool` with
`SWIFTCODE_ASSET_COMPILER=swiftcode` (the default off macOS); `Samples/IconSamples`
is an iOS app built that way.

`swiftcode strings` is SwiftCode's String Catalog compiler, extractor and converter
(`../specs/ide/string-catalog.md` "SwiftCode implementation"). Builds use it
instead of Xcode's `xcstringstool` with `SWIFTCODE_STRINGS_COMPILER=swiftcode` (the
default off macOS, and on a Mac whose Xcode has no `xcstringstool`);
`Samples/StringsSamples` is an iOS app built that way.

`swiftcode profile` is Gauge's command line (`../specs/ide/profiler.md` §7). On
Linux it samples with `perf_event_open`, or, where the kernel forbids it
(`perf_event_paranoid` above 2), with `libSwiftCodeGaugeAgent.so` from the same
build directory. Apps on the SwiftCode simulator are recorded by `swiftcode-simd
--profile` (§3.1) and, in the IDE, by Product ▸ Profile (⌘I).

`make-app.sh` builds `SwiftCodeApp` in release, wraps it in an app bundle,
stamps the build SDK so that AppKit uses the current look, and signs it ad
hoc (`../specs/ide/liquid-glass-swiftcode.md` §0).

## swiftcodebuild

`swiftcodebuild` accepts `xcodebuild` command lines (`-list`, `-showsdks`,
`-version`, `-showBuildSettings [-json]`, `-showdestinations`, `build`,
`analyze`, `clean`, `install`, `build-for-testing`, …) and prints the same
formats; see `../specs/xcodebuild/`. Build settings and builds go through
swift-build via a small helper package, built once:

```bash
cd Tools/swiftcode-swb && swift build --product swiftcode-swb && swift build --product SWBBuildServiceBundle
export SWIFTCODE_SWB=$PWD/.build/debug/swiftcode-swb
cd ../.. && .build/debug/swiftcodebuild -project path/to/App.xcodeproj -scheme App build
# Conformance against the reference tool (macOS):
SWIFTCODE_PBXPROJ_CORPUS=manifest.txt python3 -I scripts/xcodebuild-conformance.py --details
```

Tests hosted in an app (`TEST_HOST`) run inside it with SwiftCode's test agent
next to swiftcodebuild (`../specs/ide/testing.md`, "SwiftCode implementation"):

```bash
swift build --product SwiftCodeTestAgent                    # .build/debug/libSwiftCodeTestAgent.dylib (macOS hosts)
OUT=.build/debug SimGuestAgents/build-test-agent.sh     # .build/debug/iphonesimulator/ (the SwiftCode simulator)
.build/debug/swiftcodebuild -project Samples/TestHostSamples/HostMac/HostMac.xcodeproj -scheme HostMac test
# On the SwiftCode simulator: SWIFTCODE_SIM_HOST, SWIFTCODE_SIM_DATA, SWIFTCODE_SIM_RUNTIME, SWIFTCODE_SIM_SIMD (and SWIFTCODE_SIM_DEVICE)
.build/debug/swiftcodebuild -project Samples/TestHostSamples/HostPhone/HostPhone.xcodeproj -scheme HostPhone \
    -destination 'platform=iOS Simulator,name=SwiftCode Simulator,arch=arm64' test
.build/debug/swiftcode results path/to/Test-HostPhone-….xcresult
```

Set `SWIFTCODE_SIM_RUNTIME_ROOT` to a simulator `RuntimeRoot` to run the runtime
tests on Linux.

To test on a Linux machine, sync the package without build outputs, then build
and test there:

```sh
rsync -az --delete --exclude .build --exclude .build-ide swiftcode/ <user>@<linux-host>:SwiftCode/swiftcode/
ssh <user>@<linux-host> 'cd SwiftCode/swiftcode && swift build && swift test'
```

`.build-ide` holds test and IDE scratch output. Tests write into their own
temporary directories, so it can be deleted at any time.

### Tests in a full run

A full run executes each test bundle's suites in parallel, and other runs may
share the machine. What made tests pass alone and fail in full runs:

- **The main actor is shared.** UI suites run on it, and synchronous work in
  one suite (a window build, a toolchain call) holds it from all the others,
  for 150 s and more at the start of a full UI run. Wait for conditions with
  `waitUntil` (UI tests), which counts only the time the main actor actually
  had, never with a wall-clock deadline. Time limits are hang guards.
- **The cooperative pool is shared.** Never block a pool thread for long
  (`flock`, `waitUntilExit`, a blocking `read` in a detached task): a dozen
  such waits leave no thread for streamed replies or other suites, and can
  deadlock the process. `InterprocessLock.acquire` polls for this reason.
  Work that a blocked caller waits for (a pipe reader or writer) gets a
  `Thread` of its own, never `DispatchQueue.global()`: when waiting callers
  fill that queue's pool, the work never starts. `Subprocess.run` hung the
  3-core CI runner this way.
- **Host state moves.** Volume free space, clocks and the process list
  change while a test runs; compare only what the code under test decides.
- **Fixed pauses race.** Wait for the state itself (a thread blocked in the
  kernel, a line in the console), not for a few milliseconds.
- **Checkouts differ.** A test's scratch paths contain the checkout's name
  (`…/visionos-r10b/…`): read meaning only from the part of a
  path the code owns (a runtime's platform comes from the runtime's own
  name, not from the directories above it).
- **Fakes must end.** A stand-in launcher or server answers every command
  the code under test may send; one that hangs keeps a child process and a
  thread to the end of the run, and `ProcessAudit` fails the bundle (it
  names the child and its arguments).
- Suites that keep a language server on the sample package use their own
  copy (`samplePackage(directory:)`); others rewrite and build the shared one.

Known flaky tests (rerun alone before reporting one; CI reads the same list from
`../.github/ci/known-flaky.txt` and retries nothing else):
`SnapshotKernelRoundTripTests.calendarTimersFollowTheWallClockAcrossARestore`,
`CLIAgentTests.cancelInterruptsTheTool`,
`MainThreadResponsivenessTests.fileSystemWatcherReportsChanges`,
`threadSelfusageCountsTheCallingThread` under load,
`StreamingProcessTests.anInheritedPipeDoesNotHoldTheExitBack` under load (its
limit was 3.9 s, with 3.9 and 4.8 s seen in full runs; since 2026-11-04 the
child lives 60 s and the limit is 20 s),
`SourceKitLSPEndToEndTests` timeouts on the arm64 Linux host, and, on the
3-core macOS CI runner only, `BuildServerWindowTests.projectWindowUsesTheBuildServer`
(it passes alone). Two layout tests,
`NavigatorInspectorR45Tests.filterOptionsAndTogglesSitInsideTheField` and
`UISpacingTests.hubSidebarGroupEndsAtTheSidebarEdge`, need macOS 27.2: their
positions were measured there, and CI's macOS 27.0 lays these controls out
differently.

CI runs on macOS and on Linux x86-64 and arm64 (`../.github/workflows/ci.yml`),
one test at a time (`swift test --no-parallel`): its machines have three or four
cores, and a parallel run there spent minutes waiting for the main actor.
Its hosted machines have no KVM guarantee, GPU, simulator runtime or corpus, so
those tests skip themselves; each job's summary lists what it skipped. A clean
checkout on an x86-64 Linux machine with 16 cores builds in under 2 minutes and
runs all of its 2,216 tests in about 3.

## Corpus tests

`PBXProjCorpusTests` runs against real projects that are not checked in. It
reads a manifest from `../research/dirty/pbxproj-corpus.txt`, or from the path
in `SWIFTCODE_PBXPROJ_CORPUS`. The manifest has one path per line:

- `= /path/App.xcodeproj`: written by Xcode. The round trip must be
  byte-identical.
- `~ /path/App.xcodeproj`: edited by other tools. The round trip must be
  lossless and idempotent.

If there is no manifest, the suite is skipped.

Other opt-in test inputs:

- `SWIFTCODE_SIM_RUNTIME_ROOT`: a simulator `RuntimeRoot`, for the Mach-O and
  runtime tests.
- `SWIFTCODE_KEYCHAIN_TESTS=1`, `SWIFTCODE_LIVE_ASSISTANT=ollama,claude,codex,agy`:
  the coding assistant's keychain and live-provider tests.
- `SWIFTCODE_E2E_REMOTE`, `SWIFTCODE_E2E_DATA`, `SWIFTCODE_E2E_RUNTIME`, `SWIFTCODE_E2E_SIMD`,
  `SWIFTCODE_E2E_APP`: an end-to-end run on a remote SwiftCode simulator.
- `SWIFTCODE_CAMERA_HW_TESTS=1`: tests with a real host webcam.

Tools are found on `PATH` or through overrides: `SWIFTCODE_SWB` (the swift-build
helper), `SWIFTCODE_SOURCEKIT_LSP`, `SWIFTCODE_LLDB_DAP`, `SWIFTCODE_BUILD_TOOL`.

## Try the simulator from a Mac (`scripts/swiftcode-sim-try`)

The simulator (`swiftcode-simd`) runs on an arm64 Linux host with KVM. From a
Mac with ssh key access to that host, one command boots a device there and
opens a viewer window on the Mac:

```sh
# once: tell the launcher where the host and your area on it are
mkdir -p ~/.config/swiftcode
cat > ~/.config/swiftcode/sim-try.env <<'CONF'
SWIFTCODE_SIM_HOST=<user>@<simulator host>
SWIFTCODE_SIM_HOME=<data volume on the host>/<your area>/sim-try
CONF
# and on the host, $SWIFTCODE_SIM_HOME/sim-serve.env names the built tree, the
# runtime, the pristine device and the boot-slot locks (see scripts/swiftcode-sim-serve);
# saving and restoring the device also needs python3 with PIL there

scripts/swiftcode-sim-try            # from swiftcode/
scripts/swiftcode-sim-try --downscale 2 --quality 70   # for a slow link
scripts/swiftcode-sim-try --cold     # boot cold this time (the device keeps its data)
scripts/swiftcode-sim-try --erase    # start over with a new device (data and saved state erased)
```

It builds the viewer (`swiftcode-sim-viewer`), installs `scripts/swiftcode-sim-serve`
and `scripts/swiftcode-sim.sh` (as `swiftcode-sim`, the launcher the IDE's runs use)
on the host, starts the device there in a free boot slot with
`--display-server`, forwards the display socket over the same ssh session,
and opens the viewer. Closing the window saves the device and frees the
slot; the next session restores it in place, so the home screen (or the
app you left open) is back and takes input a few seconds after the slot is
free, with its apps, data and settings as you left them (like Xcode's
Simulator, a device keeps its state until it is erased). The first session,
a new simulator build, or `--cold` boot cold: about 30 s to the home screen
on an idle host and longer for a new device
([`lean-boot.md`](../specs/simulator/lean-boot.md) §9). The window shows
"Booting…" until the first frame, and the app icons come with the wallpaper. A cold-booted device is saved only from 30 s
after its home screen showed; closing the window earlier shuts it down
cleanly and the next session boots it cold again (its data stays).

The device behaves like Xcode's Simulator: it boots to an unlocked home
screen and never dims or locks by itself (⌘L locks it; Home or Lock wakes
it), and the first click on the home screen is taken at once. The first
launch of an app after a cold boot takes about 10–20 s to draw.

In the window: click and drag = one finger (swipe up from the bottom edge
goes home), Option-drag = pinch/rotate, Option-Shift-drag = two-finger pan,
scroll wheel or trackpad = drag, typing = hardware keyboard. ⇧⌘H Home,
⌘L Lock, ⌥⌘↑/↓ volume, ⌘S screenshot (PNG on the Desktop), ⌘1/⌘2/⌘3 window
size. Protocol and design:
[`../specs/simulator/display-stream.md`](../specs/simulator/display-stream.md);
input: [`../specs/simulator/hid-input.md`](../specs/simulator/hid-input.md).
To build the simulator on the host, see
[`../docs/SIMULATOR-LINUX.md`](../docs/SIMULATOR-LINUX.md) §5.
