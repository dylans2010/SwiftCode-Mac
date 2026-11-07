<!-- system-index-depends: Safeguards.md, AvailableTools.md -->
# UsingSystem — Operating Instructions for the use_system Tool

`use_system` is the dedicated native tool for macOS system diagnostics and one narrowly-scoped, explicitly authorized user-level configuration operation. These are operating instructions for calling it correctly during Assist sessions. The tool's schema (operations, parameters) is defined in the runtime registry — this document teaches *when* and *how* to use it, never redefines it.

## 1. Purpose

`use_system` exists so you can investigate the macOS system underneath a problem — OS version and hardware, developer-tooling state, processes, network interfaces and listeners, connectivity, disk capacity, accessible system logs, launchd service status, and allowlisted sysctl configuration — and return *real measured state* instead of guesses. It also exposes exactly one mutation: writing a scalar value to a user-domain defaults key (`user_defaults_write`), which is validated, explicitly confirmed, and verified by read-back. It is not a shell, not a privilege-escalation path, and not a second `use_terminal`.

## 2. When to use it

Reach for `use_system` when the task genuinely depends on system state:

- **macOS configuration problems** — confirm the actual OS version/build, architecture, hostname, or hardware (`system_info`) before blaming the OS.
- **Development environment failures** — Xcode/CLT/Swift missing or mismatched (`dev_environment`) when builds fail for toolchain reasons.
- **System-service diagnostics** — check whether a user launchd service is loaded and its last exit status (`service_status`).
- **Network connectivity problems** — enumerate interfaces (`network_interfaces`), confirm what is actually listening (`listening_sockets`), and test a bounded TCP connection to a host/port (`connectivity`) instead of asserting "the port is open".
- **File permission problems** — inspect disk capacity and volume state (`disk_info`) when writes fail; use the file tools for file-level metadata.
- **Accessible system logs** — pull bounded, predicated excerpts from the unified log (`system_log`) when diagnosing crashes, daemons, or install failures.
- **Authorized system configuration changes** — the *only* supported mutation is `user_defaults_write` to a user-domain defaults key, and only when the user explicitly asked for that change.
- **Verification of system-level repairs** — after any change, re-run the relevant diagnostic op and report the *measured* new state.

## 3. When NOT to use it

Do not use `use_system` when:

- An existing specialized native tool does the job (`env_info` for basic environment facts, `xcode_toolchain_info`, `process_monitor_tool`, file tools for file content/metadata, `use_terminal` for genuinely arbitrary commands).
- Ordinary file operations suffice — reading, writing, or editing files is not system diagnostics.
- The task only requires editing source code.
- The requested operation is unsupported: anything needing root/admin, TCC-gated data (Full Disk Access logs, other users' processes), SIP-protected paths, or non-allowlisted sysctl names. The tool will refuse these honestly — do not retry them through another tool to dodge the refusal.
- The requested change is unrelated to the user's goal. "While I'm here" system tweaks are unrequested modifications (see §7).

## 4. Tool selection priority

Prefer the most specialized native tool that can genuinely complete the operation. The priority order is:

1. A specialized native tool whose responsibility matches the task (`env_info`, `process_monitor_tool`, file tools, build tools).
2. `use_system`, for the system-level operations listed in §2 that belong to its responsibilities.
3. `use_terminal`, when the task truly needs an arbitrary command — it is allowed when appropriate but is **never** the default answer to a system question. Do not use `use_terminal` to re-implement a `use_system` operation, and never use it to circumvent a `use_system` permission or validation refusal. A refusal is final.

## 5. Diagnostic workflow

For every system-level investigation, follow this sequence:

1. **Understand** the reported problem in the user's own terms.
2. **Identify** the relevant system component (OS, toolchain, process, network, disk, service, log, configuration).
3. **Collect evidence** with the narrowest appropriate `use_system` operation and tight bounds (filters, row caps, short log windows).
4. **Analyze** the actual returned results — quote measured values, not expectations.
5. **Separate verified findings from hypotheses.** "The log shows X" is a finding; "so the daemon must be crashing because Y" is a hypothesis until evidence confirms it.
6. **Decide** whether any change is necessary at all. Most diagnostics end with a finding, not a mutation.
7. **Obtain required authorization.** The single mutation op requires the user's explicit request *and* `confirm: true` on the call.
8. **Apply the smallest appropriate change** — one key, one domain, one value.
9. **Verify** by re-reading the affected state (the tool verifies `user_defaults_write` by read-back itself; you verify the broader outcome with a follow-up diagnostic).
10. **Report** findings, actions, authorization limits, and verification results accurately (see §10).

## 6. Authorization requirements

A tool call grants no privileges. `use_system` runs with your normal user privileges — the same as the SwiftCode process itself. There is no elevation path: it never runs anything as root, never prompts for an administrator password, and never disables SIP, TCC, or sandbox restrictions.

Consequences you must internalize:

- An Info.plist usage-description key authorizes nothing by itself; it only supplies the user-facing string *if* a privacy prompt were triggered. No `use_system` operation triggers one.
- When an operation needs rights you do not have (another user's sockets, TCC-protected log categories, admin-only daemons), the tool returns an explicit `permissionDenied`/`unsupportedOperation` error. **Explain the limitation to the user and stop.** Do not retry, do not reroute through `use_terminal`, do not present the refusal as success.
- `user_defaults_write` is the only mutation, and it still requires two authorizations: the user's explicit request for that specific change, and `confirm: true` on the call. One missing, no write.

## 7. Security restrictions

The following are prohibited. They are not judgment calls:

- Unrequested system modifications of any kind.
- Silent privilege escalation, or any attempt to work around a permission denial.
- Collecting credentials (passwords, tokens, keys) via system inspection and placing them in tool arguments, logs, or model context.
- Disabling security controls (SIP, TCC, Gatekeeper, sandbox, firewall) as a workaround for a failed operation.
- Destructive actions (killing processes, deleting system data, changing network configuration) without the user's explicit authorization — and note that `use_system` does not offer destructive operations at all; do not improvise them via `use_terminal`.
- Claiming success without evidence. If you did not measure it, you did not do it.

## 8. Error handling

Respond to tool errors by their code, not by retrying blindly:

- **`permissionDenied`** — the OS refused. Explain what was blocked and why (e.g., "reading another user's listening sockets requires privileges this tool does not have"), suggest what the user can do themselves, and move on. Never escalate.
- **`unsupportedOperation`** — unknown operation name, non-allowlisted sysctl, or a privileged action this tool does not implement. Pick a supported operation or tell the user it is out of scope.
- **`missingArgument` / `invalidInput`** — your call was malformed (bad domain, bad key, out-of-range port, unparseable predicate). Fix the arguments and re-run once; if it still fails, reconsider the approach.
- **`notFound`** — the named resource does not exist (interface, sysctl, service). Verify the name against a listing op first.
- **`timeout`** — narrow the work (shorter log window, tighter predicate, smaller row limit) and retry once. Do not loop retries.
- **Partial results** — some ops degrade honestly (e.g., `listening_sockets` may omit other users' sockets). Report exactly what was covered and what was excluded.
- **Failed verification** — if `user_defaults_write` reports a read-back mismatch, the write did *not* take effect. Report the failure; do not retry the write without understanding why it failed.
- **Unavailable system APIs** — on a non-macOS host or a stripped-down environment, subprocess-based ops fail with `executionFailed`. Say so plainly.

## 9. Output interpretation

Always inspect the structured result, not just the prose summary:

- `success: true` means the operation genuinely completed — check the data fields (e.g., `verified: true` on a mutation, `reachable`/`latencyMs` on connectivity) before drawing conclusions.
- `success: true` with empty or sparse data means "ran fine, found nothing" — not "the system is healthy". Say which.
- Warnings and truncation markers (`truncated: true`, `[truncated: …]`) mean you saw a slice, not the whole. Narrow and re-run rather than extrapolating.
- The `Error [<code>]` footer plus `Recovery:` hint tells you the failure class — route your next step from the code (§8), not from the message text alone.
- Distinguish four outcomes in your reasoning: **success** (measured), **failure** (error code), **denied** (permission), **partial** (completed with exclusions). Never collapse denied/partial into success.

## 10. Verification and reporting

Close every system-level investigation with a short report containing:

1. **Findings** — measured values with the operation that produced them.
2. **Actions performed** — every mutation, with its before/after verified state.
3. **Authorization limits** — anything you could not do and the exact reason (permission denied, unsupported, out of scope).
4. **Verification results** — how you confirmed the final state (re-run diagnostic, read-back value, follow-up check).

Do not report a system as "fixed" because a command exited zero — report it as fixed because a subsequent diagnostic shows the desired state. If verification was impossible, say so explicitly and mark the outcome provisional.
