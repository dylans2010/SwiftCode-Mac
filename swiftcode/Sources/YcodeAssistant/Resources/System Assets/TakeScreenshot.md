<!-- system-index-depends: AvailableTools.md -->

# TAKE SCREENSHOT — Native macOS Screen Capture

The `take_screenshot` tool enables Assist to capture real screen pixels from the user's desktop or a user-selected interactive screen region, save a high-resolution PNG artifact to the native artifact store, and inject visual image tokens directly into the active AI model's context for visual analysis and multimodal reasoning.

---

## 1. Tool Identifier & Risk Posture

- **Identifier:** `take_screenshot`
- **Category:** Diagnostics / Screen & Vision
- **Risk Level:** `safeRead`
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
| `capture_mode` | `string` | No | `"screen"` | Capture mode: `"screen"` (entire display) or `"region"` (interactive rectangular selection on screen). |
| `display_id` | `integer` | No | `nil` | Optional display ID (CGDirectDisplayID) to target when multiple monitors are connected. Defaults to main display. |
| `include_cursor` | `boolean` | No | `false` | Whether to include the mouse cursor pointer in the captured screenshot. |
| `image_format` | `string` | No | `"png"` | Target image format (`"png"` is standard). |
| `purpose` | `string` | No | `nil` | Natural language explanation of why the screenshot is being captured. |

---

## 4. Examples of Valid Invocations

### Example A: Full Screen Capture for Visual Inspection
```json
{
  "capture_mode": "screen",
  "include_cursor": false,
  "purpose": "Inspecting current state of the running macOS application window"
}
```

### Example B: User-Selected Interactive Region Capture
```json
{
  "capture_mode": "region",
  "purpose": "Capturing user-selected area around the simulator view"
}
```

---

## 5. Expected Output Structure

The tool returns a standard Assist result dictionary:
```json
{
  "success": true,
  "output": "Captured full screen (2560x1440) -> image.png",
  "data": {
    "artifact_name": "image.png",
    "artifact_path": ".assist_temp/artifacts/image.png",
    "capture_mode": "screen",
    "width": 2560,
    "height": 1440,
    "scale_factor": 2.0,
    "image_format": "png",
    "byte_count": 1420580,
    "has_image_data": true
  }
}
```

In addition to returning structured metadata, the engine automatically attaches the base64-encoded PNG image as an `AIMessageAttachment` to the current Assist session turn. For multimodal providers (Anthropic Claude 3.5/3.7, OpenAI GPT-4o, OpenRouter, Google Gemini), the active model receives the image directly in its visual context window on the subsequent inference turn.

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
- **User Cancelled Region (`cancelled`):** If the user presses Escape or dismisses the selection overlay during region capture, the tool reports that selection was cancelled. Proceed without failing catastrophically.
- **Display Unavailable (`notFound`):** If a specified `display_id` is invalid or disconnected, the tool falls back to the primary display.
