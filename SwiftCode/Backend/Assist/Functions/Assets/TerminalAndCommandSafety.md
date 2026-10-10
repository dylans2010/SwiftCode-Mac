# TERMINAL EXECUTION & COMMAND SAFETY

This asset defines terminal execution constraints, approval gating, command safety standards, and blocked directories.

---

#### `use_terminal`
**Capability:** System & Shell Execution · **Risk:** execution  
**When to use:** ONLY when no native tool covers the operation (e.g. running specialized CLI tools, custom SwiftPM plugins, or unique environment configurations).  
**When NOT to use:** For anything covered by a native tool (`project_build`, `project_test`, `version_control_operator`, `file_read`, `dir_read`); to bypass permission boundaries.  
**Parameters:**  
- `command` (string, required) — the shell command string to execute.  
- `explanation` (string, required) — clear technical reason why terminal execution is necessary instead of a native tool.  
- `estimatedImpact` (string, required) — description of changes to the workspace or system.  
- `modifiesRepo` (string, required) — `"true"` or `"false"` (must be a string, not boolean).  
- `workingDirectory` (string, optional) — workspace-relative directory; defaults to workspace root.  
**Returns:** `command`, `stdout`/`stderr` (tailed), `exitCode`, `duration`, and suggested next actions.  
**Errors:** Empty command; **user rejected** (terminal execution denied by user); non-zero exit code.  
**Notes:**  
1. **Mandatory Approval Gating**: Every call suspends execution and prompts the user with an interactive permission modal.  
2. **Denial is Final**: If the user denies approval, execution must halt or pivot. NEVER attempt to circumvent user denial or re-issue the same denied command.  
3. **No Command Blocklist**: You are fully responsible for the safety of the shell commands you generate.

---

#### `run_command`
**Capability:** Cloud Terminal Execution · **Risk:** execution  
**When to use:** In Google Antigravity Cloud Toolkit sessions to run build commands, git operations, or container script validations.  
**Parameters:**  
- `command` (string, required) — shell command line to execute within the workspace container.  
**Usage:** Dispatches execution to the cloud workspace runtime. Captures stdout, stderr, and process exit code.

---

## Blocked Directories & System Protection
The execution engine enforces hard security boundaries. The following paths and system prefixes are strictly prohibited from all terminal executions, shell redirections, and tool arguments:
- `/System`
- `/usr`
- `/bin`, `/sbin`
- `/etc`, `/var`
- `/Library`
- `/private`, `/dev`, `/tmp`

Never attempt `sudo` commands, root privilege escalations, background daemon forks, or unauthorized socket binds.
