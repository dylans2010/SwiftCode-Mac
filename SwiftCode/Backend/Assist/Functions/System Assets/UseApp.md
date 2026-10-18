<!-- system-index-depends: AvailableTools.md -->

# USE APP — Native macOS Application Interaction & Accessibility Automation

The `use_app` tool enables Assist to launch, activate, inspect, operate, and verify the UI state of installed macOS applications through native macOS Accessibility APIs (`AXUIElement`) and `NSWorkspace`.

---

## 1. Tool Identifier & Risk Posture

- **Identifier:** `use_app`
- **Category:** System Execution / Application Automation
- **Risk Level:** `safeMutation`
- **Capabilities:** Non-destructive UI inspection, standard window management, control activation (clicks, typing, menu navigation), and state transition verification.

---

## 2. Purpose & Supported Use Cases

### When to Use
- **Automated Verification:** Verifying whether an application launched successfully, opened expected windows, or displayed expected UI elements after building.
- **Workflow Navigation:** Operating standard controls (clicking buttons, entering search text or form values, invoking application menus).
- **Accessibility Inspection:** Reading the accessible UI hierarchy of an application (windows, buttons, text fields, menu bars, labels, and roles) to understand its current state.
- **State Transition Testing:** Checking whether triggering an action produced the intended outcome (e.g. verifying a label changed or a new sheet appeared).

### When NOT to Use
- **Do not interact with sensitive password/credential fields** or security prompts.
- **Do not perform irreversible or destructive actions** (e.g. account deletion, disk erasure, making purchases) without explicit user authorization.
- **Do not guess element coordinates** if accessible elements can be targeted by title, identifier, or role.

---

## 3. Invocation Schema & Argument Descriptions

| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `app_identifier` | `string` | **Yes** | — | Target application identifier (bundle identifier like `com.apple.calculator`, app name like `"Calculator"`, or PID). |
| `action` | `string` | **Yes** | — | Requested action: `"inspect_ui"`, `"launch"`, `"activate"`, `"click"`, `"type_text"`, `"select_menu"`, `"verify"`. |
| `target` | `string` | No | `nil` | Target UI element name, title, accessibility label, or identifier to interact with. |
| `value` | `string` | No | `nil` | Input text to enter when action is `"type_text"`. |
| `arguments` | `object` | No | `nil` | Optional action parameters (e.g. `menu_path` array for `"select_menu"`). |
| `verification` | `boolean` | No | `true` | Whether to automatically inspect resulting state after executing the action. |
| `purpose` | `string` | No | `nil` | Natural language explanation of the interaction. |

---

## 4. Supported Action Types

1. **`launch`**: Launches the target application if not already running, brings it to foreground, and returns window information.
2. **`activate`**: Focuses and brings an already running application to the front.
3. **`inspect_ui`**: Traverses the application's accessible UI element tree via `AXUIElement` up to 5 levels deep, returning structured element roles, titles, labels, identifiers, values, and enabled states.
4. **`click`**: Finds an accessible button, menu, radio button, or checkbox matching `target` and triggers `kAXPressAction`.
5. **`type_text`**: Focuses the input element matching `target` (or the currently focused element if omitted) and sets `kAXValueAttribute` with `value`.
6. **`select_menu`**: Traverses application menu bar items to activate a menu item (e.g. File > New, Edit > Select All).
7. **`verify`**: Inspects whether an element or value exists in the application interface.

---

## 5. Examples of Valid Invocations

### Example A: Inspect UI of Calculator App
```json
{
  "app_identifier": "com.apple.calculator",
  "action": "inspect_ui",
  "purpose": "Inspecting available buttons and display value in Calculator"
}
```

### Example B: Click a Button in an Application
```json
{
  "app_identifier": "Calculator",
  "action": "click",
  "target": "7",
  "verification": true,
  "purpose": "Clicking button 7"
}
```

### Example C: Type Text into a Form Field
```json
{
  "app_identifier": "TextEdit",
  "action": "type_text",
  "target": "Document",
  "value": "Hello world from Assist automation!",
  "verification": true
}
```

---

## 6. Expected Output Structure

```json
{
  "success": true,
  "output": "Clicked '7' in Calculator (verified)",
  "data": {
    "action": "click",
    "app_identifier": "com.apple.calculator",
    "target_app_name": "Calculator",
    "target": "7",
    "target_found": true,
    "element_role": "AXButton",
    "verified": true,
    "current_value": "7"
  }
}
```

---

## 7. Required macOS Permissions & Accessibility Setup

- **Permission:** **Accessibility** (`TCC` category `kTCCServiceAccessibility`).
- **Authorization Check:**
  - Evaluated via `AXIsProcessTrustedWithOptions()`.
  - If SwiftCode does not have Accessibility privileges, macOS requires the user to grant access in **System Settings > Privacy & Security > Accessibility** by toggling **SwiftCode** on.
  - The tool produces an actionable error explaining the requirement and providing instructions if accessibility access is denied.
