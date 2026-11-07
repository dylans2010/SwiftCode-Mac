# Working with Artboards & Visual UI Builder

This guide provides canonical instructions and architectural context for Assist when interacting with SwiftCode's **Artboards**, **Visual UI Builder**, and **SwiftUI Live Preview** subsystem.

---

## 1. Architecture Overview

The Visual UI Builder allows visual design, layout composition, and live SwiftUI rendering on macOS. It is composed of three interconnected layers:

```
┌─────────────────────────────────────────────────────────────┐
│                   Visual UI Builder Canvas                   │
│          VisualUIDocument  <───>  VisualUIScene              │
│                 └── VisualUIArtboard[]                      │
│                          └── VisualComponentNode Tree        │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                    DocumentCoordinator                       │
│    compiledArtboardViews [UUID: NSView]                     │
│    compiledArtboardErrors [UUID: String]                    │
│    activeDocument (SourceFileDocument)                       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       Preview Engine                         │
│     PreviewManager  <───>  PreviewSession                   │
│     XcodeBuildAPI   <───>  BuildDestinationResolver         │
│     FullAppRunManager (Simulator sandboxing & launch)       │
└─────────────────────────────────────────────────────────────┘
```

### Core Data Models
- **`VisualUIDocument`**: Top-level document controller handling undo/redo checkpoints and disk persistence.
- **`VisualUIScene`**: Scene container holding an array of `artboards`, the `activeArtboardID`, and `currentFramework` (SwiftUI, UIKit, AppKit, etc.).
- **`VisualUIArtboard`**: An individual artboard canvas representation:
  - `id`: UUID.
  - `name`: Human-readable title (e.g., "Default", "Simulator", "CheckoutView").
  - `deviceFrame`: Target simulator frame (e.g., "iPhone 16 Pro", "iPad Pro", dynamically queried from `xcrun simctl`).
  - `rootNode`: Hierarchical tree of `VisualComponentNode` instances (VStack, HStack, Button, Text, etc.).
  - `customSwiftUISource`: Optional custom SwiftUI source code with `#Preview` blocks.
  - `appearance`: "System", "Light", or "Dark".
  - `isPortrait`: Orientation flag.

---

## 2. Execution & Preview Modes

The **Artboard Simulator** supports two primary modes:

### Mode 0: Live Preview
- Compiles the active SwiftUI view or custom artboard code using the JIT/Swift compiler pipeline into a hosted native view (`NativePreviewHost`).
- Provides sub-second interactive canvas updates without launching a full iOS simulator window.
- If an artboard contains custom SwiftUI code, it compiles dynamically into `DocumentCoordinator.shared.compiledArtboardViews`.

### Mode 1: Run Full App
- Uses `FullAppRunManager.shared.runFullApp()`.
- Steps:
  1. Saves active editor buffers.
  2. Resolves target Xcode project / package metadata.
  3. Validates toolchain and SDK environment.
  4. Builds the `.app` bundle via `xcodebuild` targeting a concrete simulator (`platform=iOS Simulator,id=<UUID>`).
  5. Automatically boots the target simulator using `xcrun simctl boot <UUID>`.
  6. Installs and launches the app bundle via `xcrun simctl install` and `xcrun simctl launch`.

---

## 3. Assist Artboard Tools

Assist has dedicated native tools to inspect, mutate, compile, and troubleshoot artboards:

| Tool ID | Capability | Description |
|---|---|---|
| `artboard_list` | `safeRead` | Lists all artboards in the current workspace (IDs, names, devices, modes). |
| `artboard_get` | `safeRead` | Retrieves full details, component tree hierarchy, and custom SwiftUI code for an artboard. |
| `artboard_create` | `safeMutation` | Creates a new artboard with a name, device frame, and optional SwiftUI code. |
| `artboard_update` | `safeMutation` | Modifies an existing artboard's properties, device frame, appearance, or SwiftUI source. |
| `artboard_delete` | `safeMutation` | Deletes an artboard (guards against deleting "Default"). |
| `artboard_compile` | `safeMutation` | Compiles an artboard or the active SwiftUI file for live preview, returning compiler logs. |
| `artboard_run_app` | `safeMutation` | Compiles and executes the full application in a simulator. |
| `fix_artboards` | `safeMutation` | Diagnoses and repairs artboard, preview, simulator, and destination errors. |

---

## 4. Diagnosing & Repairing Issues (`fix_artboards` Playbook)

When the user clicks **"Fix with Assist"** or reports that Visual UI Builder / Previews / Full App Run is failing, Assist must execute `fix_artboards` and follow this step-by-step diagnostic workflow:

### Step 1: Simulator & Destination Alignment
- **Problem**: `xcodebuild` fails with **exit code 70** or `Building for macOS but target is iOS`.
- **Root Cause**: `selectedDestination` was set to `platform=macOS` or a placeholder destination without a simulator UDID.
- **Repair**:
  1. Run `xcrun simctl list devices available -j` to query live, available Apple simulators.
  2. Locate a booted simulator (or an available iOS simulator).
  3. Realign `selectedDestination` to `platform=iOS Simulator,id=<UDID>`.
  4. If the simulator is shutdown, boot it with `xcrun simctl boot <UDID>`.

### Step 2: Code Signing on Simulator
- **Problem**: Build fails during codesigning (`CodeSign error: No identity found`).
- **Repair**: Ensure simulator builds always pass `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.

### Step 3: Bundle Search & Path Resolution
- **Problem**: `POSIXError 2: /tmp/<App>.app failed: No such file or directory`.
- **Root Cause**: Hardcoded `/tmp/` path fallback when derived data location wasn't inspected.
- **Repair**: Dynamically search `./build/DerivedData/Build/Products/Debug-iphonesimulator/<App>.app` and project build directories.

### Step 4: CoreDevice vs. simctl Fallback
- **Problem**: `devicectl` outputs `CoreDeviceError error 1001: The capability Install Application is not supported by this device`.
- **Root Cause**: Passing a simulator UUID to `devicectl` (which only supports physical iOS 17+ devices).
- **Repair**: Always detect simulator destinations and use `xcrun simctl install <UDID> <App.app>` and `xcrun simctl launch <UDID> <bundleID>`.

### Step 5: Syntax & #Preview Verification
- **Problem**: Artboard compile error due to missing `import SwiftUI` or syntax errors.
- **Repair**:
  1. Read the custom artboard source or file.
  2. Verify that `import SwiftUI` is present at the top.
  3. Verify that a valid `#Preview` or `PreviewProvider` block exists referencing the root view.
  4. Save changes and trigger `artboard_compile`.

### Step 6: Keep Working Until Clean Resolution
- If compilation fails, inspect the new error logs, apply the necessary code or configuration adjustments, and re-run compilation until the status is healthy.
