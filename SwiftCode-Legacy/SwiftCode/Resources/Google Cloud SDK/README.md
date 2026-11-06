# Google Cloud SDK / Antigravity Bundled Runtime

This directory contains the production-ready, self-contained Google Antigravity SDK bundled runtime for the SwiftCode macOS application.

## Architectural Layering

```text
SwiftCode.app
    ↓
Contents/Resources/Google Cloud SDK
    ↓
Bundled Python runtime (runtime/bin/python3, runtime/lib/python3.14/site-packages)
    ↓
Antigravity SDK (google.antigravity v0.1.20)
    ↓
SwiftCode bridge (bridge/main.py, bridge/protocol.py, bridge/agent_runner.py)
```

## Structure

- `runtime/`: Isolated Python runtime environment with bundled dependencies.
  - `bin/python3`: Standalone launcher script with host Python detection and bundled site-packages isolation.
  - `lib/python3.14/site-packages/`: Pre-installed, verified packages including `google-antigravity`, `google-genai`, `mcp`, `pydantic`, `uvicorn`, `websockets`, `cryptography`, and sub-dependencies.
  - `pyvenv.cfg`: Runtime configuration metadata.
- `bridge/`: Python IPC server and Antigravity SDK adapter.
  - `main.py`: Entry point for the subprocess, manages Unix domain socket / IPC lifecycle and protocol dispatch.
  - `protocol.py`: JSON-RPC 2.0 protocol definitions, message framing, error codes.
  - `agent_runner.py`: Antigravity SDK session management, streaming execution, tool hooks, and event translation.
- `skills/`: Bundled agent skills definitions matching the Agent Skills specification (`SKILL.md`).
- `requirements.txt`: Exact pinned dependency manifest.
