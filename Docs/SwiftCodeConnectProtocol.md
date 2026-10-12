# SwiftCode Connect Interoperability Protocol (V1 Specification)

This specification defines the communication protocol contract between **SwiftCode macOS** (Authoritative Server Host) and **SwiftCode iOS** (Client Controller).

---

## 1. Overview & Service Discovery

SwiftCode macOS advertises itself on the local Wi-Fi / LAN network using Apple's **Network.framework / Bonjour**.

- **Bonjour Service Type**: `_swiftcodeconnect._tcp`
- **Default Port**: Dynamically allocated (or fallback TCP 8088 / WebSocket port 8089)
- **TXT Record Metadata**:
  - `txtvers=1`
  - `proto=1`
  - `macName=<Host Device Name>`
  - `appVers=<SwiftCode macOS Version>`

---

## 2. Authentication & Handshake Flow

```
SwiftCode iOS                        SwiftCode macOS
     │                                    │
     ├─────── Bonjour Discovery ─────────>│
     │                                    │
     ├────── 1. Pairing Request ─────────>│ (Displays UI Pairing Request)
     │   (Device ID, Model, Pin Code)     │
     │<────── 2. Pairing Response ────────┤ (Approved with Token & Permissions)
     │                                    │
     ├────── 3. Session Authenticate ────>│
     │   (Session Token)                  │
     │<────── 4. Authenticated Session ───┤
```

### Verification & Trust Store
- Pairing requires explicit Mac user approval via native SwiftUI prompt.
- Pairing codes (e.g., 6-digit verification code or fingerprint) verify identity.
- Cryptographic identity and active permissions are securely stored in the macOS System Keychain under service `com.swiftcode.connect.truststore`.

---

## 3. Message Envelope Specification

All messages sent over TCP framing or WebSockets are JSON objects matching the canonical `MessageEnvelope`:

```json
{
  "protocolVersion": 1,
  "messageID": "123E4567-E89B-12D3-A456-426614174000",
  "correlationID": "987F6543-E21B-32D1-B654-426614174999",
  "type": "build_request",
  "timestamp": "2026-07-10T14:30:00Z",
  "payload": "<Base64 encoded or UTF-8 nested JSON bytes>"
}
```

---

## 4. Message Types & Operations

### A. Handshake & Security
- `pairing_request` / `pairing_response`
- `auth_request` / `auth_response`
- `ping` / `pong`

### B. Project & Workspace
- `project_request` -> `project_response`
  - Returns active project metadata, active scheme, target, and supported SDK destinations.

### C. Git Control
- `git_status_request` -> `git_status_response`
- `git_branches_request` -> `git_branches_response`
- `git_log_request` -> `git_log_response`

### D. Authoritative Build System
- `build_request` -> `build_response`
- `cancel_build_request`
- Streaming Build Events:
  - `build_started`
  - `build_progress` (phase, completedSteps, totalSteps)
  - `build_diagnostic` (severity, message, file, line, column)
  - `build_completed` (success, duration, errorCount, warningCount)

### E. Remote Testing System
- `test_request` -> `test_response`
- Streaming Test Events:
  - `test_started`
  - `test_progress`
  - `test_completed`

### F. Structured Logging & Telemetry
- `logs_subscribe_request` / `logs_unsubscribe_request`
- `log_event` (timestamp, level, category, message)

### G. Terminal Execution & Interactive Approval
- `terminal_execute_request` -> `terminal_output`, `terminal_exit`
- `terminal_approval_required` (dispatched to client when Mac requests interactive user authorization for sensitive shell execution)

### H. Assist / AI Engine
- `assist_query_request` -> `assist_response`

### I. File System Service
- `file_list_request` -> `file_list_response`
- `file_read_request` -> `file_read_response`
- `file_write_request` -> `file_write_response`

---

## 5. Granular Permissions Model

Client requests are evaluated on the Mac host against assigned device permissions:

- `project.read`
- `git.read`
- `build.execute`
- `tests.execute`
- `logs.read`
- `terminal.execute`
- `files.read`
- `files.write`
- `assist.use`
- `device.read`
- `screen.capture`
- `remote.control`

Rejection returns `error_response` with code `PERMISSION_DENIED`.

---

## 6. Security Invariants
- **No Path Traversal**: File requests containing `..` or leading to targets outside the project root are rejected with `INVALID_PATH`.
- **Authoritative Execution**: Builds, tests, and Assist queries run entirely on the Mac host. Client disconnects do not cancel background builds.
