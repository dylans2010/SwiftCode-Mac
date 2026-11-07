<!-- system-index-depends: Safeguards.md, AvailableTools.md -->
# UsingApp — Operating Instructions for the use_app Tool

`use_app` is the dedicated native macOS application interaction system for Assist. It allows you to inspect, navigate, operate, and verify third-party and installed macOS applications through native macOS Accessibility APIs (`AXUIElement`), CoreGraphics synthetic event generation (`CGEvent`), `ScreenCaptureKit` visual perception, and `NSWorkspace` session lifecycle management.

The tool's schema is registered in `AssistToolRegistry`. This document teaches *when* and *how* to use it, following Assist's operational standards.

---

## 1. Tool Identity & Risk Posture

- **Identifier:** `use_app`
- **Category:** System Execution / Application Automation
- **Risk Level:** `safeMutation`
- **Capabilities:** Non-destructive UI inspection, window management, semantic Accessibility control, synthetic mouse and keyboard event injection, visual perception with screenshot verification, and state transition validation.

---

## 2. When to Use It

Reach for `use_app` when:
- **Operating installed applications** — opening, activating, and navigating real native macOS apps, Electron apps, browsers, text editors, developer utilities, and System Settings.
- **Verifying build outcomes** — launching a newly built `.app` bundle, verifying that its primary window opens, controls render, and expected initial UI elements exist.
- **Workflow navigation** — clicking accessible buttons, entering text into form fields, selecting tabs, adjusting sliders, and choosing application menu items (e.g. `File > Save`).
- **Investigating application UI state** — reading the structured accessible UI tree (`inspect_ui`) or obtaining a fresh window screenshot (`take_screenshot`) when accessibility labels are incomplete.
- **Interactive UI testing** — executing multi-step user workflows (e.g. create document, type text, save file) and comparing actual state before and after each action.

---

## 3. When NOT to Use It

Do not use `use_app` when:
- **Executing arbitrary shell commands** — when a command needs to run in a shell or terminal session, use `use_terminal`. Do not bypass terminal approval or execution policy by launching a terminal application via `use_app`.
- **Handling sensitive credentials or security prompts** — never enter passwords, authentication tokens, or private secrets into third-party fields. If an application presents an authentication prompt, request user intervention.
- **Performing unconfirmed destructive or consequential operations** — closing applications (`close_application`), deleting account data, formatting disks, making purchases, or sending unauthorized messages requires explicit user confirmation.
- **A specialized native tool exists** — use `file_read` / `file_write` for project source files, `project_build` for building schemes, and `env_info` for environment facts.

---

## 4. Invocation Schema & Parameters

| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `app_identifier` | `string` | **Yes** | — | Bundle ID (`com.apple.finder`), app name (`Finder`, `Calculator`), PID, or session ID (`app_session_...`). |
| `action` | `string` | **Yes** | — | Action to perform (see §5 for complete action catalog). |
| `target` | `string` | No | `nil` | Target element ID (`elem_1`), accessibility identifier, title, label, or menu path (`File > Save`). |
| `value` | `string` | No | `nil` | Text input to type, shortcut name (`Cmd+S`), key name (`Return`), or expected value for verification. |
| `coordinates` | `object` | No | `nil` | Point coordinates `{"x": 100, "y": 200, "coordinate_space": "screen"\|"window"\|"screenshot_pixel"}`. |
| `drag_destination` | `object` | No | `nil` | Destination point for drag actions `{"x": 300, "y": 400}`. |
| `scroll_delta` | `object` | No | `nil` | Pixel scroll deltas `{"dx": 0, "dy": -100}` (negative dy scrolls down). |
| `window_id` | `string` | No | `nil` | Specific window ID (`window_1`) when operating on multi-window apps. |
| `modifiers` | `array` | No | `[]` | Key modifier list for key press: `["command", "shift", "option", "control"]`. |
| `timeout` | `number` | No | `5.0` | Bounded timeout in seconds for wait operations (1–60s). |
| `verification` | `boolean` | No | `true` | Whether to automatically inspect resulting state after executing action. |
| `confirm` | `boolean` | No | `false` | Explicit user authorization required for consequential actions (e.g. `close_application`). |
| `purpose` | `string` | No | `nil` | Natural language explanation of the interaction purpose. |

---

## 5. Supported Action Vocabulary

### Application Lifecycle
- `list_applications`: Discovers installed and running applications across system, utility, and user domains.
- `inspect_application`: Returns running status, process ID, bundle URL, and active window summary.
- `launch`: Launches target application if not running, brings it to foreground, and waits for its initial window.
- `activate`: Focuses an already running application and brings its primary window to the front.
- `list_windows`: Enumerates all open windows, their titles, bounding frames, and minimized states.
- `select_window`: Brings a specific window (`window_id`) to the front and raises focus.
- `close_application`: Gracefully terminates application (requires `confirm: true`).

### UI Observation & Perception
- `inspect_ui` / `get_accessibility_tree`: Traverses accessible controls in the active window up to 10 levels deep. Assigns stable session-local IDs (`elem_1`, `elem_2`, ...) so controls can be targeted directly.
- `get_focused_element`: Identifies which control currently holds active keyboard focus.
- `take_screenshot`: Captures a fresh PNG screenshot of the application's active window bounds, saves an artifact, and returns Base64 data for multimodal visual analysis.
- `inspect_window`: Inspects the active window title and screen geometry.

### Pointer Interaction
- `click`: Clicks target element or coordinates using synthetic CoreGraphics events.
- `double_click`: Double-clicks target element or coordinates.
- `right_click`: Triggers context menu via right mouse click.
- `move_pointer`: Moves mouse cursor smoothly to coordinates.
- `drag`: Drags from start coordinates to `drag_destination`.
- `scroll`: Scrolls horizontally (`dx`) and vertically (`dy`) in pixels.

### Keyboard Interaction
- `type_text`: Enters Unicode text into target or focused field. Supports full UTF-16 characters, emojis, and symbols.
- `press_key`: Presses a navigation or control key (`Return`, `Tab`, `Escape`, `Space`, `Delete`, `ArrowLeft`, etc.).
- `press_shortcut`: Executes a standard keyboard shortcut (e.g. `Cmd+S`, `Cmd+Shift+P`, `Cmd+C`, `Cmd+V`, `Cmd+Z`, `Cmd+A`).
- `select_all`: Shortcut helper executing `Cmd+A`.
- `copy`: Shortcut helper executing `Cmd+C`.
- `paste`: Shortcut helper executing `Cmd+V`.

### Semantic Controls
- `activate_element`: Invokes accessibility actions (`kAXPressAction` or `AXPick`).
- `set_element_value`: Sets accessibility value directly (`kAXValueAttribute`).
- `select_menu` / `select_menu_item`: Traverses native macOS application menu bar and triggers menu items by path (`File > New Window`).

### Synchronization & Verification
- `wait_for_element`: Bounded polling until expected UI element appears in the accessibility hierarchy.
- `wait_for_window`: Bounded polling until expected window title appears.
- `verify` / `verify_element_state`: Confirms an element exists or its value matches expected text.

---

## 6. The Observe-Act-Verify Workflow

Always operate applications through this disciplined loop:

1. **Resolve & Activate**: Call `activate` or `launch` on the target application.
2. **Observe**: Call `inspect_ui` to discover controls and note their session-local IDs (`elem_1`, `elem_2`). If the interface is custom-rendered or accessibility labels are missing, call `take_screenshot`.
3. **Target Resolution**: Prefer targeting by element ID (`elem_X`), exact title, or accessibility identifier. Fall back to verified visual coordinates only when semantic elements are not exposed.
4. **Act**: Dispatch the targeted action (`click`, `type_text`, `select_menu`).
5. **Verify**: Check the resulting state change (`verified: true`, `observed_state`). If ambiguous, re-inspect with `inspect_ui`.
6. **Handle Transitions**: When actions trigger loading or asynchronous window creation, use `wait_for_element` or `wait_for_window` rather than arbitrary long sleeps.

---

## 7. Coordinate Systems & Scaling

macOS uses different coordinate spaces depending on the subsystem:
- **Core Graphics / AX screen space:** Origin `(0,0)` at top-left of primary display. X increases right, Y increases down.
- **Window space:** Origin `(0,0)` at top-left of target window.
- **Screenshot pixel space:** Scaled by Retina backing factor (typically 2x).

When specifying `coordinates`:
```json
{
  "x": 120,
  "y": 45,
  "coordinate_space": "window"
}
```
The interaction engine automatically handles display offsets, multi-monitor setups, and Retina scaling.

---

## 8. Consequential Actions & Safety Rules

- **Application Termination:** Calling `action: "close_application"` terminates running processes. You **MUST** ensure the user authorized this and pass `"confirm": true`.
- **Sensitive Fields:** Do not read or inject text into password fields, security credential prompts, or keychain access windows.
- **Irreversible Mutations:** Any button labeled "Delete Account", "Erase", "Purchase", or "Transfer" requires explicit user confirmation.
- **Clipboard Safety:** If clipboard-assisted pasting is used, the engine restores the user's prior clipboard content automatically.

---

## 9. Error Recovery & Diagnostics

Every failure produces an error code from `AssistToolErrorCode` and an actionable `recoveryHint`:
- `notFound`: Application, window, or UI target was not found. Re-run `list_applications`, `list_windows`, or `inspect_ui` to get the fresh identifier.
- `permissionDenied`: Accessibility or Screen Recording permission is missing in macOS System Settings. Advise the user to enable SwiftCode in System Settings > Privacy & Security > Accessibility.
- `timeout`: State transition did not occur within the timeout period. Re-inspect current UI to determine actual state.
- `invalidInput`: Target was ambiguous or coordinates were invalid. Refine target using an exact `elem_X` ID.
- `executionFailed`: Control rejected action. Try synthetic pointer click or keyboard shortcut fallback.
