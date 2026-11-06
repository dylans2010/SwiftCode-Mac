<!-- Re-derived 2026-11-06 from the live SwiftCode tool catalogue (433 tools, 0 duplicate IDs) — derivation method and evidence: specs/ide/wave19-system-assets.md. Legacy source: SwiftCode/Backend/Assist/Functions/System Assets/TakeScreenshot.md (Legacy main d51a8f0d). Every tool ID below was verified against swiftcode/Sources/SwiftCodeMCP/ at local HEAD 305696b. -->
<!-- system-index-depends: AvailableTools.md -->

# TAKE SCREENSHOT — Native macOS Screen Capture

The `take_screenshot` tool enables Assist to capture real screen pixels from the user's desktop or a user-selected interactive screen region, save a high-resolution PNG artifact to the native artifact store, and inject visual image tokens directly into the active AI model's context for visual analysis and multimodal reasoning.

---

## 1. Tool Identifier & Risk Posture

- **Identifier:** `take_screenshot`
- **Category:** Terminal (live registration family `terminalTools`)
- **Risk Level:** `externalSideEffect` (writes an artifact; annotations `readOnly: false, idempotent: true, openWorld: true`, `writes: true`)
- **Output Artifacts:** Valid PNG image stored as `.assist_temp/artifacts/image.png` (plus timestamped uniquely named artifact e.g. `screenshot_<timestamp>.png`).

---

## 2. Purpose & Supported Use Cases

### When to Use
- **Visual Inspection of Running Apps:** The user requests feedback, debugging, or validation of an application window, UI layout, visual artifact, or layout regression.
- **Verification of State:** After executing code changes or UI actions via `use_app`, capture the screen to verify that UI elements rendered as expected.
- **Multimodal Visual Reasoning:** When diagnosing graphical glitches, alignment issues, color differences, or non-textual UI state that cannot be inspected via accessibility trees.
- **Targeted Region Analysis:** When the user wants to highlight or inspect a specific portion of their screen (e.g., a simulator, a browser preview, or a canvas).

### When NOT to Use
- **Do not use for text extraction** when source code, build logs, or accessibility hierarchy can be read directly via native text tools (`file_read`, `use_app` action: `inspect_ui`).
- **Do not capture the screen repeatedly in a tight loop** without performing intermediate actions or awaiting state changes.
- **Do not use to capture sensitive credentials**, password fields, or confidential user personal data.

---

## 3. Invocation Schema & Argument Descriptions

| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `capture_mode` | `string` | No | `"fullscreen"` | Capture mode: `"fullscreen"` (entire display), `"region"` (a screen rect — needs `region`), or `"window"` (one window — needs `window_id`). |
| `display_id` | `integer` | No | `nil` | Optional display ID (CGDirectDisplayID) to target when multiple monitors are connected. Defaults to main display. |
| `region` | `object` | No | `nil` | Screen rect for `capture_mode: "region"`: `{x, y, width, height}` in screen points, origin top-left of the main display. |
| `window_id` | `string` | No | `nil` | Target window identifier for `capture_mode: "window"` (e.g. `'window_12345'` as listed by `use_app` `list_windows`, or a bare window number). |
| `include_cursor` | `boolean` | No | `true` | Whether to include the mouse cursor pointer in the captured screenshot. |
| `image_format` | `string` | No | `"png"` | Target image format. Must be `"png"`. |
| `purpose` | `string` | No | `nil` | Natural language explanation of why the screenshot is being captured. |

---

## 4. Examples of Valid Invocations

### Example A: Full Screen Capture for Visual Inspection
```json
{
  "capture_mode": "fullscreen",
  "include_cursor": false,
  "purpose": "Inspecting current state of the running macOS application window"
}
```

### Example B: Region Capture by Explicit Coordinates
```json
{
  "capture_mode": "region",
  "region": {"x": 120, "y": 45, "width": 800, "height": 600},
  "purpose": "Capturing the area around the simulator view"
}
```
There is no interactive region-selection overlay in SwiftCode — region capture takes explicit coordinates. (`window` mode targets a window by `window_id` instead.)

---

## 5. Expected Output Structure

The tool returns a standard Assist result dictionary:
```json
{
  "success": true,
  "output": "Captured full screen (2560x1440) -> image.png",
  "data": {
    "path": ".assist_temp/artifacts/image.png",
    "artifact_id": "image.png",
    "capture_mode": "fullscreen",
    "width": 2560,
    "height": 1440,
    "display_id": 0,
    "format": "png",
    "size_bytes": 1420580,
    "base64": "<base64-encoded PNG>"
  }
}
```

In addition to returning structured metadata, the result carries the base64-encoded PNG image (`base64`) and makes it available to the active AI model for visual analysis on the subsequent inference turn.

---

## 6. Required macOS Permissions & Preconditions

- **Permission:** **Screen Recording** (`TCC` category `kTCCServiceScreenCapture`).
- **Authorization Flow:**
  - On macOS 14+ / Sonoma / Sequoia, macOS enforces Screen Recording permissions via `CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()`.
  - If access has not been granted, the tool returns a descriptive permission error explaining that the user must open **System Settings > Privacy & Security > Screen Recording** and toggle **SwiftCode** on.
  - If denied or revoked, do not attempt to bypass or retry in a loop. Ask the user to authorize Screen Recording in System Settings.

---

## 7. Known Platform & API Limitations

- **ScreenCaptureKit:** Modern macOS (14+) utilizes `SCShareableContent` and `SCScreenshotManager` for high-performance Retina frame capture.
- **Retina Displays:** Pixel dimensions may be 2x the logical points (e.g., 2560x1600 physical pixels for a 1280x800 point display). Coordinates are automatically translated.
- **Headless Environments:** Screen capture requires an active graphical window server session (CoreGraphics / WindowServer). Capture will fail gracefully if no display is connected.

---

## 8. Error Handling & Recovery

- **Permission Denied (`permissionDenied`):** Inform the user that macOS Screen Recording permission is required and guide them to System Settings.
- **Display Unavailable (`notFound`):** If a specified `display_id` is invalid or disconnected, the tool falls back to the primary display.
