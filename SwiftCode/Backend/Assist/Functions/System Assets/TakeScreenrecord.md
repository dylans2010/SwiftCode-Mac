<!-- system-index-depends: AvailableTools.md -->

# TAKE SCREENRECORD — Native macOS Application Screen Recording

The `take_screenrecord` tool enables Assist to record real-time video frames from the screen and window of a specifically resolved running macOS application, producing a valid H.264/ProRes `.mov` video artifact in the native Assist artifact store.

---

## 1. Tool Identifier & Risk Posture

- **Identifier:** `take_screenrecord`
- **Category:** Diagnostics / Screen & Video
- **Risk Level:** `safeRead`
- **Output Artifacts:** Valid QuickTime `.mov` video file saved in `.assist_temp/artifacts/<appName>_recording_<timestamp>.mov`.

---

## 2. Purpose & Supported Use Cases

### When to Use
- **Dynamic Interaction Recording:** When the user asks Assist to record the operation of a specific app or reproduce an animation/interaction bug over time.
- **Workflow Validation:** Demonstrating a multi-step user flow or verifying that an asynchronous transition or animation behaves smoothly.
- **Issue Diagnostics:** Creating an observable video artifact when visual static screenshots are insufficient to diagnose timing or transition problems.

### When NOT to Use
- **Do not record without an identifiable target application.** The model must provide a valid `app_identifier` (bundle ID, app name, or PID).
- **Do not use for static verification.** Use `take_screenshot` when a single frame snapshot is sufficient.
- **Do not record indefinitely.** Safety limits constrain duration between 1 and 60 seconds (default 5 seconds).

---

## 3. Invocation Schema & Argument Descriptions

| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `app_identifier` | `string` | **Yes** | — | Target application identifier (bundle identifier like `com.apple.dt.Xcode`, app name, or PID). |
| `recording_duration` | `number` | No | `5.0` | Duration to record in seconds (clamped between `1.0` and `60.0`). |
| `capture_mode` | `string` | No | `"window"` | Target capture scope: `"window"` (app's main window) or `"display"` (display containing app). |
| `include_audio` | `boolean` | No | `false` | Whether to capture audio if permitted (defaults to false). |
| `output_format` | `string` | No | `"mov"` | Video container format (`"mov"` standard). |
| `purpose` | `string` | No | `nil` | Natural language explanation of why the recording is requested. |

---

## 4. Examples of Valid Invocations

### Example A: Record 5 seconds of Xcode Activity
```json
{
  "app_identifier": "com.apple.dt.Xcode",
  "recording_duration": 5.0,
  "capture_mode": "window",
  "purpose": "Observing compile progress in Xcode window"
}
```

### Example B: Record 10 seconds of a Running App
```json
{
  "app_identifier": "Calculator",
  "recording_duration": 10.0,
  "purpose": "Recording calculation workflow and UI responsiveness"
}
```

---

## 5. Expected Output Structure

```json
{
  "success": true,
  "output": "Recorded 5.0s of Calculator (1920x1080 @ 30fps) -> Calculator_recording_1713456789.mov",
  "data": {
    "artifact_name": "Calculator_recording_1713456789.mov",
    "artifact_path": ".assist_temp/artifacts/Calculator_recording_1713456789.mov",
    "app_identifier": "com.apple.calculator",
    "target_app_name": "Calculator",
    "duration_seconds": 5.0,
    "frame_count": 150,
    "width": 1920,
    "height": 1080,
    "fps": 30,
    "format": "mov",
    "byte_count": 3145728
  }
}
```

---

## 6. Required macOS Permissions & Application Resolution

1. **Screen Recording Permission:** Requires macOS Screen Recording authorization under **System Settings > Privacy & Security > Screen Recording**.
2. **Target Application Resolution:**
   - The engine checks running applications via `NSWorkspace.shared.runningApplications`.
   - Matches bundle identifier first, followed by localized application name and process name.
   - If the application is not running, the tool returns an explicit error explaining that the app must be running before recording.

---

## 7. Engine Implementation Details

- **Frameworks:** `ScreenCaptureKit` (`SCStream`, `SCStreamConfiguration`, `SCContentFilter`) and `AVFoundation` (`AVAssetWriter`, `AVAssetWriterInput`).
- **Resource Management:**
  - Recording runs off the main thread with explicit sample buffer delegates.
  - Video tracks are encoded with `AVVideoCodecType.h264`.
  - Sessions automatically finalize and flush when the requested duration elapses or upon cancellation.
  - Concurrent recordings are synchronized with a mutual exclusion lock to prevent resource contention.
