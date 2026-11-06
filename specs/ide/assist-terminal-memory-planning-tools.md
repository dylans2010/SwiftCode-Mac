# Assist terminal / memory / planning tools — behaviour (Wave 4)

Behaviour for the 34 Legacy Assist tools ported in Wave 4 onto Ycode's MCP
host: 17 terminal / system tools, 9 memory / context tools, 8 planning /
workflow / agent-control tools. See `assist-tool-catalogue.md` §86–§125 for
each tool's ID, schema, capability / risk / permission, and gate. Legacy
source (Dylan's own code, ported under MIT): `SwiftCode/Backend/Assist/`
in `dylans2010/SwiftCode-Legacy` @ `d51a8f0d`. Registry order below is
Legacy's `registerAllTools()` order.

## 1. Conventions shared by the terminal tools

- **Argument vectors, never a shell.** `use_terminal` tokenizes its `command`
  string into an argv vector (`terminalTokenizeCommand`); any shell
  metacharacter anywhere in the string (`| & ; < > \` $ ( ) { } * ? ~ # !`,
  newline) is rejected with `Command '<command>' cannot run without a shell
  (it uses pipes, redirects, variables, globbing, or other shell syntax).
  Split it into separate plain commands, or use a dedicated tool (git_*,
  file_*, build).` Legacy ran `/bin/zsh -c`; the port never runs a shell.
  The program is resolved against `PATH` (`terminalResolveProgram`); an
  unresolvable program fails with `Process execution failed: command
  '<program>' was not found (no executable on PATH or at that path).`
  All other local commands in this family run fixed binaries with fixed
  argv (`terminalRunFixed` / `Subprocess.run`): `/bin/ps`, `/sbin/ifconfig`,
  `lsof` (resolved on `PATH` — Legacy's fixed `/usr/sbin/lsof` does not
  exist on Linux), `/usr/bin/log`, `/bin/launchctl`, `/usr/bin/defaults`,
  `uname`, `xcodebuild`, `swift`, `xcrun`. No command string is ever
  assembled.
- **Workspace-confined.** `use_terminal`'s `workingDirectory` resolves with
  `resolveFileReadingPath` (plain relative paths against the session
  working directory; `..` that stays inside the workspace is allowed; no
  path may escape the workspace); an empty value means the session working
  directory, not the workspace root. A missing or non-directory value
  fails with `workingDirectory does not exist or is not a directory:
  <path>`. `environment_variable_manager`, `disk_space_analyzer`, and
  `use_system`'s probes resolve paths the same way; `use_system`'s
  `user_defaults_write` never touches a filesystem path.
- **The environment never waits for a person.** Every terminal / system
  subprocess runs with this process's environment plus
  `GIT_TERMINAL_PROMPT=0` and the developer-tool paths Legacy's
  `AgentTerminalService` appends to `PATH`
  (`:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`),
  stdin closed, and a timeout (`use_terminal` 300 s; `process_monitor` /
  `process_list` / `network_interfaces` / `service_status` 15 s;
  `listening_sockets` 20 s; `system_log` 45 s; `user_defaults_write` /
  `defaults read` 10 s; `dev_environment` probes 60 s). A timeout is
  reported, never retried silently.
- **Approval, no allow-list, no Autopilot.** `use_terminal` gates **every**
  run through the approval path (`terminalApproveChange`, a workspace-root
  `MCPChange`) before executing. Legacy's allow-list (Assist Settings >
  Terminal Command Approvals), Full Access, and Autopilot bypass machinery
  are deliberately **not** ported: the description still says allow-listed
  commands run without a prompt, but in Ycode there is no allow-list and
  every run is approved. `use_system`'s single mutation
  (`user_defaults_write`) needs both Legacy's `confirm: true` and the
  approval gate. `take_screenshot`'s artifact save and `use_app`'s
  `close_application` go through `approve()` before acting. All other
  writes in this family go through `commit()` exactly like the Wave 2
  file-writing tools. Tools registered `writes: true` are refused in
  `readOnly` server mode by `MCPServer.run` before the handler runs.
- **Risk → annotations** (catalogue §1.3, extended the way Wave 3 extended
  it): `safeRead` → `.read` (`readOnly: true, idempotent: true`),
  `writes: false`; `safeMutation` → `readOnly: false, idempotent: true`,
  `writes: true`; `execution` → `readOnly: false, idempotent: false`,
  `writes: true`; `externalSideEffect` → `readOnly: false, idempotent:
  false, openWorld: true`, `writes: true`. One more annotation exists in
  this wave: `externalRead` (`readOnly: true, idempotent: true, openWorld:
  true`, `writes: false`) for `system_notification_tool` and
  `take_screenrecord` — a read that leaves the app (a notification) or
  observes the outside world. `take_screenshot` is the one deliberate
  deviation from the table: Legacy declares it `safeRead`, but the port
  saves a PNG artifact, so it is `readOnly: false, idempotent: true,
  openWorld: true`, `writes: true`.
- **Honestly-failing tools.** A tool whose prerequisite does not exist in
  Ycode is still registered (same ID, same schema) and validates its
  inputs first with Legacy-exact messages, then fails naming the exact
  prerequisite — never a fake success. This wave: `env_capture_logs`,
  `use_extension`, `use_composio`, `use_workers`, `take_screenrecord`
  (fully), `use_mcp` and `use_app` (partially — see §§6, 18).
- **Permissions (Legacy derivation, catalogue §1.2).** `take_screenshot` /
  `take_screenrecord` → `screenRecording`; `use_app` → `accessibility`;
  `use_terminal` → `terminalExecution`; any mutating tool
  (`safeMutation` / `potentiallyDestructive`) → `fileSystem`; else `none`.
  A Ycode permission requirement is documentation here: the MCP host has
  no permission store, and macOS TCC prompts (Screen Recording,
  Accessibility, notifications) are the OS's, surfaced as errors when
  denied — never silently bypassed.
- **The `workspace` parameter.** Every tool in this wave accepts the
  Wave 1 `workspace` parameter. Tools that do not touch a workspace
  (clipboard, notifications, `use_app`, the honestly-failing bridges)
  accept it and ignore it.

## 2. `use_terminal` — Use Terminal

- Input: `command` (string, required), `workingDirectory` (optional,
  relative path), `explanation`, `estimatedImpact`, `modifiesRepo`
  (string `"true"` / `"false"` or boolean — Legacy declares it a string;
  the port accepts either).
- Behaviour: tokenize → resolve → approve → run with a 300 s timeout.
  Stdout is kept in full for the summary's first 2000 chars; the
  structured `stdout` is the last 3000 chars (with a truncation marker
  when cut) and `stderr` the last 2000 chars (same marker scheme).
  `stdoutTruncated` / `stderrTruncated` are booleans; `exitCode` is the
  child's exit code; `duration` is e.g. `"1.23s"`.
- Output (success, exit 0): `Terminal command executed successfully (exit
  code 0 in <duration>):\n<stdout or "(No stdout output)">` with data
  `command`, `workingDirectory` (absolute path actually used), `stdout`,
  `stderr`, `stdoutTruncated`, `stderrTruncated`, `exitCode`, `duration`.
- Errors: empty command → `Command cannot be empty`; bad working
  directory → `Invalid workingDirectory '<path>': <reason>` /
  `workingDirectory does not exist or is not a directory: <path>`;
  shell syntax → the cannot-run-without-a-shell message (§1); unknown
  program → the not-found message (§1); launch failure → `Process
  execution failed: could not launch <executable>`; timeout → error
  `Terminal command timed out after 300s: <command>` (with the partial
  output data attached); non-zero exit → error `Terminal command failed
  with exit code <n> (<duration>):\n<stderr or stdout, last 1500 chars>`
  (with the full data attached). Approval refused →
  `The change was rejected in Ycode's review; nothing was written.` and
  nothing runs.

## 3. `task_runner` — Run Task

- Input: `task_id` (string, required).
- Behaviour: executes one of the four tasks Legacy's
  `AssistExecutionFunctions.initializeRegistry` registers, against the
  workspace root: `project_indexing` (counts filesystem entries under
  the root), `dependency_analysis` (reports SPM / CocoaPods / Carthage
  presence from `Package.swift` / `Podfile` / `Cartfile`),
  `lint_project` (Legacy's `collectSwiftFindings`: tab indentation,
  lines over 140 characters, trailing whitespace, in every Swift file,
  hidden files skipped, no skipped-directory rule; at most 20 findings
  listed), `project_test` (Legacy's `discoverTestFiles`: Swift files
  whose path contains "test", case-insensitive, sorted; 5 sampled).
- Output (success): `Task '<task_id>' executed successfully.` with data
  `output` (the task's report text).
- Errors: unknown `task_id` → `Task '<task_id>' failed: Task '<task_id>'
  not found in registry.` A task that throws fails the same way
  (`Task '<task_id>' failed: <reason>`).

## 4. `env_capture_logs` — Capture Logs (honestly failing)

- Input: `memoryKey` (string, optional).
- Behaviour: none — the tool needs the Assist snapshot history
  (`AssistSnapshotFunctions`) and the Assist memory store, neither of
  which exists in Ycode's MCP host.
- Errors: always `env_capture_logs needs the Assist snapshot history
  (AssistSnapshotFunctions) and the Assist memory store, neither of
  which exists in Ycode's MCP host; no logs were captured.` The
  `memoryKey` argument is read and ignored, so a missing key is not an
  error.

## 5. `env_info` — Environment Info

- Input: none (beyond `workspace`).
- Behaviour: reads `ProcessInfo` / `Locale` / `TimeZone` of the server
  process. This schema is declared in Ycode; Legacy declares no
  `parametersSchema` for this tool.
- Output (success): `Environment info retrieved` with data `os`
  (e.g. `macOS 26.1 (Build …)`), `locale`, `timezone`, `cpu_count`,
  `physical_memory_bytes`, `workspace_root` (absolute path). The OS
  string names the real OS running the server, never a hardcoded value.

## 6. `use_mcp` — Execute MCP Tool (partial)

- Input: `serverName`, `toolName`, `arguments` (all strings, required;
  `arguments` is a JSON-serialized object string).
- Behaviour: the one branch Legacy answers without a server — the
  configured-server list — is answered honestly: `serverName` `"list"`
  (case-insensitive) or `toolName` `"list_servers"` returns the text
  `No MCP servers are currently configured in Ycode.` Ycode has no
  external MCP client to configure servers in.
- Errors: any other call fails with `use_mcp needs an external MCP
  client (configured MCP servers with a connection manager), which
  Ycode's MCP host does not have yet: no external tool was called.
  Ycode itself is the MCP server here; its own tools are listed by
  tools/list.` Missing required arguments fail first
  (`Missing required parameter: <name>`).

## 7. `use_extension` — Use Extension (honestly failing)

- Input: `action` (string, required), `extensionId`, `command`, `file`,
  `selection` (object: `startLine`, `startColumn`, `endLine`,
  `endColumn`), `args` (object), `confirm` (boolean), `limit`
  (integer).
- Behaviour: none — the tool needs the Extensions v2 platform
  (`ExtV2Manager` + extension host with Node.js), which Ycode's MCP
  host does not have yet.
- Errors: an unknown or missing `action` fails first with `Unknown or
  missing action. Use one of: list, details, list_commands,
  list_xcode_commands, activate, deactivate, execute, run_xcode_command,
  enable, disable, diagnostics.` A known action then fails with
  `use_extension needs the Extensions v2 platform (ExtV2Manager +
  extension host with Node.js), which Ycode's MCP host does not have
  yet; no extension was listed, activated, or executed.` No extension
  was listed, activated, or executed in either case.

**Wave 11 note (this section is Wave 4 history — the tool is now
WIRED).** `use_extension` is implemented against the new
`YcodeExtensions` target; see `specs/ide/extensions-platform.md`
§7.2/§10 and `assist-tool-catalogue.md` §92. All 11 actions work;
mutating actions require `confirm: true` and the Wave 2 approval
gate; Node absent → honest failure naming the prerequisite.

## 8. `use_composio` — Execute Composio Tool (honestly failing)

- Input: `toolSlug`, `arguments` (both strings, required; `arguments`
  is a JSON-serialized object string).
- Behaviour: none — the tool needs the Composio service
  (`ComposioService` with a Composio API key and connected
  integrations), which Ycode's MCP host does not have yet.
- Errors: always `use_composio needs the Composio service
  (ComposioService with a Composio API key and connected integrations),
  which Ycode's MCP host does not have yet; no external tool
  '<toolSlug>' was executed.` Missing required arguments fail first.

## 9. `use_workers` — Create and Coordinate Assist Workers (honestly failing, after validation)

- Input: `workers` (array of objects, required). Each element:
  `name` (string, required — empty defaults to `Worker-<n>`),
  `scope` (string, required), `task` (string, required, max 500
  characters in Legacy), `role` (optional), `dependencies` (array of
  strings, optional), `targetFiles` (array of strings, optional).
- Behaviour: Legacy's validation runs in Legacy's order, then the tool
  fails: each worker needs a non-empty `task` (also read from
  `description`); duplicate names are suffixed (`<name>-<n>`);
  dependencies must name workers in the same batch; at least one worker
  assignment is required. No worker is created or run — the tool needs
  the Assist worker runtime (`WorkerScheduler` +
  `WorkerPersistenceStore` + subagent execution), which Ycode's MCP
  host does not have yet.
- Errors: missing `workers` → `Invalid input: 'workers' argument is
  required and must contain worker assignments.`; missing task →
  `Validation Error: Worker '<name>' missing 'task' description.`;
  empty batch → `Validation Error: At least one worker assignment is
  required.`; unknown dependency → `Validation Error: Worker '<name>'
  depends on unknown worker '<dep>'. Dependencies must reference workers
  in the same batch.`; otherwise `use_workers needs the Assist worker
  runtime (WorkerScheduler + WorkerPersistenceStore + subagent
  execution), which Ycode's MCP host does not have yet; no worker was
  created or run.` Scope / target-file overlap is not validated (the
  failure comes first, as in Legacy's ordering — validation, then the
  runtime prerequisite).

## 10. `environment_variable_manager` — Environment Variable Manager

- Input: `action` (string, required: `list_keys`, `get`, `set`),
  `key`, `value`, `envFilePath` (optional path to a `.env` file,
  default `".env"`, resolved inside the workspace).
- Behaviour: `list_keys` (also accepts `list`) lists `KEY` names from
  `KEY=value` lines, skipping blanks and `#` comments; `get` returns
  the `KEY=value` line for the first matching key; `set` replaces the
  first matching line or appends `KEY=value`, then writes the file
  through `commit()` (approval gate). Legacy's exact line logic is
  reproduced: an empty or missing file splits to one empty line, so a
  brand-new file gets a leading blank line before the new `KEY=value`
  line.
- Output (success): list → `Found <n> environment keys in \`<file>\`:` +
  one `- \`<key>\`` line per key (plain text, no structured data); get →
  the `KEY=value` line; set → `` Successfully set `<key>` in `<file>`. ``
- Errors: missing `action` → `Missing required parameter: action`;
  unknown action → `Unsupported action '<action>'. Supported: list_keys,
  get, set.`; `get` without `key` → `Action 'get' requires 'key.'`;
  `set` without `key` → `Action 'set' requires 'key.'`; missing file
  for list → `No <file> file found in workspace.` (success, not an
  error); missing file for get → the same text as an error; unknown key
  → `Key '<key>' not found in <file>.`; a path outside the workspace →
  `Invalid envFilePath '<path>': paths must stay inside the workspace.`

## 11. `clipboard_manager_tool` — Clipboard Manager

- Input: `action` (string, required: `read` / `copy`), `content`
  (string, for `copy`).
- Behaviour: macOS only (`NSPasteboard`); on any other platform the
  helpers fail with `<tool> is only available on macOS.` `read` (also
  `get`) returns the current clipboard text, previewed at 500 chars;
  `copy` (also `write`, `set`) writes the text to the clipboard.
- Output (success): read with content → `Current Clipboard Content (<n>
  chars):\n\n\`\`\`\n<first 500 chars>\n\`\`\``; empty clipboard →
  `Clipboard is currently empty.`; copy → `Successfully copied <n>
  characters to the system clipboard.` All plain text, no structured
  data.
- Errors: missing `action` → `Missing required parameter: action`;
  unknown action → `Unsupported action '<action>'. Supported: 'read',
  'copy'.`; `copy` without `content` → `Action 'copy' requires
  'content'.` A `copy` is a clipboard write, so the tool is
  `writes: true` and refused in `readOnly` server mode.

## 12. `process_monitor_tool` — Process Monitor

- Input: `filter` (string, optional process-name filter).
- Behaviour: runs fixed `/bin/ps -eo pid,%cpu,%mem,comm` (15 s timeout)
  and reports developer processes: without a filter, lines whose
  command contains `xcode`, `swift`, `clang`, `simctl`, `lldb`, `git`,
  `xcrun`, or `Simulator` (case-insensitive); with a filter, lines
  containing the filter text. At most 25 rows are shown.
- Output (success): a Markdown table `### Active Developer Processes
  (<n> running):` with `PID | %CPU | %MEM | Command` rows (command
  shown as its last path component). No match → `No active processes
  matching developer tools or filter '<filter or Xcode/Swift>'.` Plain
  text, no structured data.
- Errors: `/bin/ps` cannot start → `Failed to query processes: failed
  to launch /bin/ps`.

## 13. `disk_space_analyzer` — Disk Space Analyzer

- Input: `path` (string, optional directory inside the workspace;
  default the workspace root).
- Behaviour: sums file sizes under the target directory (hidden files
  skipped) and under `~/Library/Developer/Xcode/DerivedData`, and lists
  the target's immediate subdirectories by size (top 10). Sizes are
  formatted with `ByteCountFormatter` (`.file` style).
- Output (success): `### Disk Space Analysis:` with the target scope
  size and the DerivedData cache size, plus a `#### Major Directory
  Breakdown:` list when the target has subdirectories. Plain text, no
  structured data. A missing DerivedData folder sizes as zero, never an
  error.
- Errors: a `path` outside the workspace fails with the
  workspace-containment error.

## 14. `system_notification_tool` — Post macOS System Notification

- Input: `title` (default `"Ycode Assist"` — Legacy's default is
  `"SwiftCode Assist"`; the product posting the notification is Ycode),
  `subtitle`, `message` (default `"Task completed."`), `body` (alias
  for `message`), `sound` (`"default"`, `"none"`, or a sound file name;
  default `"default"`), `critical` (boolean, default false). This
  schema is declared in Ycode; Legacy declares no `parametersSchema`
  for this tool.
- Behaviour: posts a genuine macOS notification (`UNUserNotificationCenter`
  with an `osascript` fallback when UserNotifications is unavailable).
  `critical` requests the critical sound; without the critical-alerts
  entitlement the notification still posts, silently without the
  critical sound. The tool is `writes: false` with `externalRead`
  annotations (a notification leaves the app) — posting does not go
  through the approval gate.
- Output (success): the delivery summary text. Delivery failure is an
  error result carrying the same summary text.
- Errors: delivery failure (e.g. notifications denied) → error with
  the failure summary. No argument is required.

## 15. `use_system` — System Diagnostics

- Input: `operation` (string, required), `target` (operation-dependent),
  `parameters` (object), `confirm` (boolean, required true only for
  `user_defaults_write`). `parameters.value` is declared without a JSON
  type (Legacy declares it a string but accepts bool / number) — the
  handler accepts string, number, or boolean only.
- Operations (all fixed-argv subprocesses, never a shell; privileged
  actions are refused, never escalated):
  - `system_info`: OS version string, kernel release (`uname -m -r`),
    architecture, hostname, CPU count, physical memory, uptime.
    Structured keys: `operation`, `osVersion`, `osBuild`, `arch`,
    `hostname`, `cpuCount`, `physicalMemoryBytes`, `uptimeSeconds`,
    `content`. The OS names the real OS.
  - `dev_environment`: probes `xcodebuild -version`, `swift --version`,
    `xcrun --find swift` (60 s each). A missing tool is reported in its
    section (`not available: failed to launch <path>`), never fabricated.
  - `process_list`: `/bin/ps -eo pid,pcpu,pmem,comm`, optional
    `target` / `parameters.filter` filter, `parameters.limit` clamped
    1…200 (default 50). Keys: `operation`, `filter`, `count`,
    `truncated`, `content`.
  - `network_interfaces`: `/sbin/ifconfig [name]` (macOS only);
    the interface name must match `^[A-Za-z0-9._-]+$`.
  - `listening_sockets`: `lsof -iTCP -sTCP:LISTEN -P -n` (20 s),
    resolved on `PATH`; empty output is success with `No TCP listeners
    found.`
  - `connectivity`: TCP connect + poll to `target`:`parameters.port`
    (required, 1–65535), `parameters.timeoutSeconds` clamped 1…30
    (default 5). Keys: `operation`, `host`, `port`, `reachable`,
    `latencyMs`, `content` (`TCP <host>:<port> — reachable/not
    reachable (<ms>ms, timeout <s>s)`).
  - `disk_info`: volume `/` total / available / used bytes and used
    percent (`usedPercent` is a string, e.g. `"12.3"`).
  - `system_log`: `/usr/bin/log show --style compact --last <n>m`
    (macOS only, 45 s), optional `--predicate`; `parameters.minutes`
    clamped 1…60 (default 15). Permission denial is reported as denied
    by the OS (logd / TCC), never escalated.
  - `service_status`: `/bin/launchctl list` (macOS only, 15 s);
    `count` excludes the header line.
  - `config_read`: sysctl by name, allowlist only (`kern.ostype`,
    `kern.osrelease`, `kern.osrevision`, `kern.version`,
    `kern.hostname`, `kern.maxproc`, `hw.model`, `hw.machine`,
    `hw.ncpu`, `hw.physicalmem`, `hw.memsize`, `hw.memsize_usable`,
    `hw.cpufrequency`, `machdep.cpu.brand_string`). Off-list → error
    naming the whole allowlist. macOS only.
  - `user_defaults_write`: the single mutation. Requires
    `confirm: true` **and** the approval gate, then runs
    `/usr/bin/defaults write <domain> <key> <-bool|-int|-float|value>`
    and verifies by read-back; a read-back mismatch fails with
    `Verification failed: expected '<x>' after write, read back '<y>'
    (before: <z>). The write did not take effect.` The domain must
    match `^[A-Za-z0-9.-]+$` (no `..`); `NSGlobalDomain` is blocked
    (`Domain '<domain>' is blocked: writing the global domain affects
    every application…`); the key must match `^[A-Za-z0-9._-]+$`;
    `parameters.value` must be a string, number, or boolean (objects,
    arrays, null rejected). Keys: `operation`, `domain`, `key`,
    `previousValue` (`"<not set>"` when absent), `newValue`,
    `verified: true`, `content`.
- Errors: missing `operation` → `Missing required parameter: operation`;
  unknown operation → `Unknown operation '<op>'. Supported:
  system_info, dev_environment, process_list, network_interfaces,
  listening_sockets, connectivity, disk_info, system_log, service_status,
  config_read, user_defaults_write.`; `connectivity` without a valid
  port → `Missing or invalid parameters.port (must be 1-65535)`;
  `config_read` without a target → `Missing required target: sysctl
  name (must be one of the allowlisted names)`; `user_defaults_write`
  without `confirm: true` → `user_defaults_write requires explicit
  confirmation: re-run with confirm: true, plus target/domain,
  parameters.key, and parameters.value`. macOS-only operations off
  macOS fail with `<tool> is only available on macOS.` (or the
  operation-specific macOS message for `config_read`).

## 16. `take_screenshot` — take_screenshot

- Input: `capture_mode` (`"fullscreen"` default, or `"region"`),
  `display_id` (integer, optional), `include_cursor` (boolean, default
  true), `image_format` (must be `"png"`, default `"png"`),
  `purpose` (optional).
- Behaviour: fullscreen capture only, via ScreenCaptureKit (macOS
  only). The PNG is saved as a Wave 1 artifact
  (`.assist_temp/artifacts/screenshot_<epoch>_<8 hex>.png`, plus the
  `image.png` latest-copy mirror) under a single approval
  (`approveFileWritingChange`), indexed in the artifact index, and
  returned as an image block plus text plus JSON. The tool is
  `writes: true` despite Legacy's `safeRead` risk, because it saves a
  file.
- Output (success): `Captured fullscreen screenshot (<w>×<h> px) on
  display <id>. Artifact saved to '<rel>'.` with structured keys
  `path`, `width`, `height`, `display_id`, `capture_mode`
  (`"fullscreen"`), `artifact_id`, `base64` (the full PNG — a large
  payload, matching Legacy's data keys), `format` (`"png"`),
  `size_bytes`, plus `purpose` when given.
- Errors: `capture_mode "region"` → `capture_mode "region" needs the
  interactive region-selection overlay, which Ycode's MCP host does
  not have; use capture_mode "fullscreen".` A capture that succeeds
  but cannot be saved fails with `Captured screenshot successfully but
  failed to save artifact: <reason>`. Screen Recording permission
  denial surfaces as the capture failure, never a fake image.

## 17. `take_screenrecord` — take_screenrecord (honestly failing)

- Input: `app_identifier` (string, required), `recording_duration`
  (number, 1–60 s, default 10), `capture_mode` (`"window"` default, or
  `"application_display"`), `include_audio` (boolean, default false),
  `output_format` (`"mov"` default, or `"mp4"`), `purpose` (optional).
- Behaviour: none — the tool needs a ScreenCaptureKit stream-recording
  engine (`SCStream` + video writer), which Ycode's MCP host does not
  have yet.
- Errors: missing `app_identifier` → `Missing required parameter
  'app_identifier'. Provide a bundle identifier or application name.`;
  out-of-range duration → `Requested recording duration (<n>s) is
  invalid. Duration must be between 1 and 60 seconds.`; otherwise
  `take_screenrecord needs a ScreenCaptureKit stream-recording engine
  (SCStream + video writer), which Ycode's MCP host does not have yet;
  no recording was made. Recording also requires Screen Recording
  permission in macOS System Settings > Privacy & Security > Screen
  Recording.` No recording was made in any case.

## 18. `use_app` — use_app (partial)

- Input: `app_identifier` (bundle id, app name, PID, or session id),
  `action` (string, required), `target`, `value`, `coordinates`
  (object: `x`, `y`, `coordinate_space`), `drag_destination`,
  `scroll_delta`, `window_id`, `modifiers` (array of strings),
  `timeout` (number, 1–60, default 5), `verification` (boolean,
  default true), `confirm` (boolean), `purpose`. macOS only.
- Behaviour — implemented actions (public macOS APIs only):
  `list_applications` (running apps only — Legacy lists installed apps
  too; the port lists what `NSWorkspace` reports as running, at most
  35 lines, filtered by `target` or `app_identifier`), `launch` /
  `activate` (resolve + launch via `NSWorkspace`, then activate;
  returns `app_identifier`, `app_name`, `pid`, `window_count`,
  `status: "active"`), `close_application` (requires `confirm: true`
  **and** the approval gate; terminates the running app),
  `list_windows` (CoreGraphics window list for the app's PID).
- Behaviour — not implemented: every Accessibility / interaction action
  (`inspect_ui`, `get_accessibility_tree`, `get_focused_element`,
  `inspect_application`, `inspect_window`, `take_screenshot`,
  `select_window`, `click`, `double_click`, `right_click`,
  `move_pointer`, `drag`, `scroll`, `type_text`, `set_value`,
  `press_key`, `press_shortcut`, `select_all`, `copy`, `paste`,
  `activate_element`, `set_element_value`, `select_menu`,
  `wait_for_element`, `wait_for_window`, `verify`,
  `verify_element_state`) fails per-action with `use_app action
  '<action>' needs the macOS Accessibility / app-interaction engine
  (AssistAppInteractionEngine), which Ycode's MCP host does not have
  yet; no application was operated.`
- Errors: missing `action` → `Missing required parameter 'action'.
  Call use_app with an action type.`; missing `app_identifier` (for
  every action except `list_applications`) → `Missing required
  parameter 'app_identifier'. Provide an application bundle identifier
  or app name.`; unknown action → `Unsupported action '<action>'.
  Supported actions: launch, activate, list_applications, list_windows,
  select_window, close_application, inspect_ui, get_accessibility_tree,
  get_focused_element, take_screenshot, click, double_click, right_click,
  move_pointer, drag, scroll, type_text, press_key, press_shortcut,
  select_all, copy, paste, activate_element, select_menu,
  wait_for_element, wait_for_window, verify.`; `close_application`
  without `confirm: true` → the consequential-action message naming
  the terminated-processes / unsaved-state risk; an app that is not
  running → `Application '<id>' is not running.`; a launch that cannot
  be resolved → `Application '<id>' could not be resolved or launched.`

## 19. Terminal error cases — summary table

| Situation | Result |
|---|---|
| `use_terminal` with shell syntax in `command` | `Command '<command>' cannot run without a shell (it uses pipes, redirects, variables, globbing, or other shell syntax). Split it into separate plain commands, or use a dedicated tool (git_*, file_*, build).` |
| `use_terminal` unknown program | `Process execution failed: command '<program>' was not found (no executable on PATH or at that path).` |
| `use_terminal` timeout (300 s) | Error `Terminal command timed out after 300s: <command>` with partial-output data |
| `use_terminal` non-zero exit | Error `Terminal command failed with exit code <n> (<duration>):\n<stderr or stdout>` with full data |
| Approval refused (any gated terminal/system operation) | `The change was rejected in Ycode's review; nothing was written.` and nothing runs |
| Writes in `readOnly` server mode (any `writes: true` tool) | `<tool> changes files, and this Ycode MCP server is read-only. Start it with \`ycode mcp --allow-writes\`, or use agent mode in the Ycode IDE, where each change is reviewed as a proposal.` |
| Honestly-failing tool called | Failure naming the exact prerequisite; nothing faked, nothing executed (§§4, 7, 8, 9, 17; `use_mcp` §6, `use_app` §18) |
| macOS-only behaviour off macOS | `<tool> is only available on macOS.` (clipboard, notifications, screenshot, `use_app`, `use_system` macOS ops, `config_read`) |
| Screen Recording / Accessibility denied | The OS failure surfaces as the tool error; no fake image, no synthetic events |
| Path escapes the workspace | Workspace-containment error (`<path> is outside the workspace folder <root>`) |

## 20. Terminal safety rules (non-negotiable)

- **Never a shell.** No command string is ever passed to a shell, and
  shell metacharacters are rejected rather than reinterpreted. A
  dedicated tool (`git_*`, `file_*`, `build`) is the answer to a
  command that "needs" pipes or redirects.
- **Approval on every `use_terminal` run.** There is no allow-list, no
  Full Access, and no Autopilot bypass in Ycode. The Legacy description
  text is kept verbatim; the behaviour is stricter.
- **Never wait for a person.** Subprocess environments carry
  `GIT_TERMINAL_PROMPT=0`; nothing in this family prompts on stdin,
  asks for a password, or escalates privileges. `lsof` permission
  denial is reported, never worked around.
- **Never fake a result.** A missing binary, a denied permission, a
  missing prerequisite, or a failed launch is an error with the real
  reason — never invented output, never a placeholder image, never a
  "success" for a write that did not land.
- **Workspace-confined.** No path argument may escape the workspace;
  `use_system`'s only mutation is a user-domain defaults write with a
  read-back verification, and the global domain is blocked.

## Memory tools

Behaviour shared by the 9 memory / context tools ported in Wave 4
(`mem_store`, `mem_retrieve`, `mem_clear`, `mem_context_snapshot`,
`context_persistence_store`, `save_to_memory`, `view_memory`,
`manage_memory`, `conversation_context_manager`). See
`assist-tool-catalogue.md` §105–§115 for each tool's ID, schema,
capability / risk / permission, and gate.

### Memory conventions

- **Four stores, all per-workspace.** (A) The session memory graph:
  an in-memory `NSLock` dictionary (`YcodeMemoryGraphStore`), one graph
  per workspace root path, process-lifetime, never persisted — exactly
  like Legacy's `AssistMemoryGraph`, which is held per-`AssistManager`
  and never written to disk. "Long-term" in the Legacy descriptions
  means this graph, not disk. (B) Durable user memory:
  `<workspace>/.assist_temp/memory/UserMemory.md`, Legacy's exact
  Markdown format (header, `## <Category>` sections,
  `- **key**: value <!-- updated: ISO8601 -->` lines, sorted). (C) The
  persistent context store: `<workspace>/.assist_context_store.json`,
  JSON `[String: String]`, pretty-printed with sorted keys — Legacy's
  exact path and writer. (D) Conversation context: one file per
  workspace, `<workspace>/.assist_temp/memory/conversation_context.md`,
  Legacy's exact append format.
- **Deliberate store changes (all documented).** Legacy's durable user
  memory is app-global
  (`~/Library/Application Support/SwiftCode/UserMemory.md`) and would
  leak one workspace's memory into another's, so it is **not** reused;
  the per-workspace file above replaces it, in the same format, with no
  SwiftCode default seed and no `enableUserMemory` gate (the approval
  path gates instead). Legacy's conversation context is one
  `<uuid>.context.md` per conversation under Application Support; the
  MCP host has no conversation identity (`WorkspaceSession` carries
  none), so one file per workspace replaces it. The Application Support
  conversation archive (`~/Library/Application Support/Ycode/
  Conversations/`) was considered and rejected for memory: it belongs
  to the conversation archive, and tests would write into the real
  Application Support directory. No new database layer was invented
  (the destination audit §5: none exists by design).
- **Approval gating.** The four file-writing handlers
  (`context_persistence_store` set/delete, `save_to_memory`,
  `manage_memory` add/edit/delete/clear, `conversation_context_manager`
  `update_summary`) write through `commit()` exactly like the Wave 2
  file-writing tools. The three in-memory-only tools (`mem_store`,
  `mem_clear`, `mem_context_snapshot`) register `writes: true` so the
  server-level gate still refuses them when read-only, but they call
  neither `commit()` nor `approve()`: there is no file change to
  propose, and fabricating an `MCPChange` would show the IDE reviewer
  a fake file proposal. This matches `dir_cd`'s session-state
  precedent. The read-only actions of the mixed tools
  (`context_persistence_store` get, `conversation_context_manager`
  read) request no approval, but the tools are still registered
  `writes: true`, so `MCPServer.run` refuses them in `readOnly` server
  mode — the same treatment Wave 3 gives its mixed git tools.
- **Annotations.** `safeRead` → `.read`, `writes: false`;
  `safeMutation` → `readOnly: false, idempotent: true`, `writes: true`;
  `potentiallyDestructive` (`mem_clear`) → `readOnly: false,
  destructive: true`, `writes: true`. Two behaviour-driven exceptions:
  `mem_context_snapshot` mints a fresh snapshot key on every call, so
  it is not idempotent; `conversation_context_manager`'s
  `update_summary` appends, so it is not idempotent either.
- **No secrets, no cross-workspace leaks.** Memory keys and values are
  caller data; nothing in this family reads credentials, and no store
  is shared between workspaces.

### 21. `mem_store` — Store Memory

- Input: `key`, `value` (both strings, required).
- Behaviour: stores the value under the key in the calling workspace's
  session graph (store A), overwriting any existing entry. In-memory
  only: the entry does not survive a server restart.
- Output (success): `Stored in memory: <key>` with data `key`.
- Errors: `Missing required parameter: key` (absent or empty key);
  `Missing required parameter: value` (absent or empty value).

### 22. `mem_retrieve` — Retrieve Memory

- Input: `key` (string, required).
- Behaviour: reads the calling workspace's session graph (store A).
- Output (success): `Retrieved from memory: <key>` with data `key`,
  `value`.
- Errors: `Missing required parameter: key` (absent or empty key);
  `Key not found in memory: <key>`.

### 23. `mem_clear` — Clear Memory

- Input: none (Legacy declares no `parametersSchema`).
- Behaviour: clears only the calling workspace's session graph (store
  A). Other workspaces' graphs are untouched. No confirmation
  parameter: the destructive annotation plus the `writes: true` gate
  is the protection, as in Legacy (which takes no `confirm` either).
- Output (success): `Memory cleared.` with data `cleared` (boolean,
  always true), `entriesCleared` (integer — how many entries the
  workspace's graph held; a Ycode addition, Legacy returns no data).

### 24. `mem_context_snapshot` — Context Snapshot

- Input: none (Legacy declares no `parametersSchema`).
- Behaviour: stores a payload in the calling workspace's session graph
  (store A) under `context_snapshot:<uuid>`, freshly minted per call.
  The payload is three lines: `session=<session-uuid>`,
  `workspace=<workspace-root-path>`, `latest_snapshot=none`. The
  session UUID is minted once per workspace per process (Legacy's
  `AssistContext.sessionId`, one per Assist session).
  `latest_snapshot` is always `"none"`: Legacy reads it from
  `AssistSnapshotFunctions.listSnapshots()`, and Ycode has no snapshot
  store, so there is never a latest snapshot to name. The stored marker
  is a real graph entry, retrievable with `mem_retrieve`; nothing is
  faked. Open files are not captured: the MCP host has no open-file
  list.
- Output (success): `Context snapshot captured` with data
  `snapshot_key` (`context_snapshot:<uuid>`), `latest_snapshot`
  (`"none"`).
- Errors: none defined (the store cannot fail; Legacy's `catch` around
  `listSnapshots()` is unreachable in the port because there is no
  snapshot list to fail).

### 25. `context_persistence_store` — Persistent Context Store

- Input: `key` (string, required), `action` (string: `set`, `get`, or
  `delete`; default `"get"`), `value` (string, required when `set`).
- Behaviour: reads and writes `<workspace>/.assist_context_store.json`
  (store C), re-reading the file on every call like Legacy. `action`
  is lowercased; absent defaults to `get`. `set` and `delete` write
  through `commit()`; `get` does not write and requests no approval.
- Output (success): set → `Stored context for key <key>`; delete →
  `Deleted key <key>` (a no-op when absent — the file is still
  rewritten, like Legacy); get, and any other action string (Legacy's
  `default` case) → `Retrieved context for key <key>`. Data in all
  cases: `key`, `action` (the action actually performed: `set`,
  `delete`, or `get`), `value` (`""` when the key is absent on get,
  `""` on delete).
- Errors: `Missing key` (absent or empty key); `Missing value` (`set`
  without a value).

### 26. `save_to_memory` — Save to Memory

- Input: `key`, `value` (both strings, required), `category`
  (string, default `"General"`).
- Behaviour: upserts the entry in the workspace's `UserMemory.md`
  (store B) — key and value trimmed, category trimmed and defaulting
  to `General` when absent or blank, key match case-insensitive,
  timestamp refreshed on update. The write goes through `commit()`.
  The file is created (header only, no seed) when it does not exist
  yet.
- Output (success): `Saved to memory [<category>]: **<key>** = <value>`
  followed by `Persisted to .assist_temp/memory/UserMemory.md` (the
  path is the one deliberate wording change from Legacy, which names
  its app-global path). Data: `key`, `value`, `category`.
- Errors: `Missing required parameter: key` (absent or blank key);
  `Missing required parameter: value` (absent or blank value).
  Legacy's failure branch ("Memory recording is currently disabled in
  Assist Settings, or storage failed.") has no Ycode equivalent: there
  is no enable/disable setting, so a storage failure surfaces as the
  write error itself.

### 27. `view_memory` — View Memory

- Input: `query` (optional search query, matched case-insensitively
  against key or content), `category` (optional category filter,
  case-insensitive).
- Behaviour: reads the workspace's `UserMemory.md` (store B) and
  filters by category, then by query.
- Output (success): entries found → `### Active User Memories (<n>
  items):` plus one `- [<category>] **<key>**: <value>` line per
  entry, with data `entries` (array of `key` / `value` / `category` /
  `updatedAt` ISO-8601), `count`, `report` (the same text). No entries
  and an empty/missing file → `No memories are currently stored in
  UserMemory.md.` (count 0). No entries but a non-empty file → `No
  memory items matched the filter. Full UserMemory.md:\n\n<full
  document>` (count 0) — Legacy's actual behaviour after a
  `manage_memory` clear (the file holds only the header, so the
  full-document fallback fires, not the "No memories" text).

### 28. `manage_memory` — Manage Memory

- Input: `action` (string, required: `add`, `edit`, `delete`, or
  `clear`), `key`, `value`, `category`.
- Behaviour: `add` / `edit` (also `save`) upsert like `save_to_memory`
  (case-insensitive key match, timestamp refreshed); `delete` (also
  `remove`) removes the entry; `clear` replaces the file with the
  header only. Every branch writes through `commit()`.
- Output (success): add/edit → `Memory '<key>' successfully updated in
  UserMemory.md.`; delete → `Memory entry '<key>' deleted from
  UserMemory.md.`; clear → `All memories cleared from UserMemory.md.`
  Data: `action` (lowercased as performed), `key`, `category`
  (`""` on delete/clear).
- Errors: missing `action` → `Missing required parameter: action
  ('add', 'edit', 'delete', 'clear')`; add/edit without both key and
  value → `Actions 'add' and 'edit' require both 'key' and 'value.'`;
  delete without a key → `Action 'delete' requires 'key.'`; delete of
  a missing key → `Memory entry '<key>' was not found in
  UserMemory.md.`; unknown action → `Unknown action '<action>'.
  Supported actions: add, edit, delete, clear.`

### 29. `conversation_context_manager` — Conversation Context Manager

- Input: `action` (string, required: `read` or `update_summary`),
  `notes` (string, for `update_summary`).
- Behaviour: `read` (also `view`) returns the workspace's conversation
  context file (store D); `update_summary` (also `update`, `append`)
  appends `\n### Additional Model Context (Updated <ISO-8601>):\n
  <notes>\n` through `commit()`. The file is created with the `# Conversation Context` header when it does not exist.
- Output (success): read with a file → `Conversation Context:\n\n
  <file>` with data `action: "read"`, `context` (the file text),
  `path: ""`; read without a file → `No custom context file found yet
  for the active conversation.` with `context: ""`; update →
  `Successfully updated conversation context file at: <absolute path>`
  with data `action: "update_summary"`, `context: ""`, `path` (the
  absolute file path).
- Errors: missing `action` → `Missing required parameter: action
  ('read' or 'update_summary')`; `update_summary` without notes →
  `Action 'update_summary' requires non-empty 'notes'.`; any other
  action → `Unsupported action '<action>'. Use 'read' or
  'update_summary'.`

### Memory error cases — summary table

| Situation | Result |
|---|---|
| Missing / empty required argument | `Missing required parameter: <name>` (or `Missing key` / `Missing value` for `context_persistence_store`) |
| `mem_retrieve` unknown key | `Key not found in memory: <key>` |
| `manage_memory` delete of a missing key | `Memory entry '<key>' was not found in UserMemory.md.` |
| `manage_memory` / `conversation_context_manager` unknown action | `Unknown action '<action>'. Supported actions: …` / `Unsupported action '<action>'. Use 'read' or 'update_summary'.` |
| Approval refused (any file-writing memory tool) | `The change was rejected in Ycode's review; nothing was written.` and nothing is written |
| Writes in `readOnly` server mode (any `writes: true` memory tool, including `mem_store` / `mem_clear` / `mem_context_snapshot` and the read actions of mixed tools) | `<tool> changes files, and this Ycode MCP server is read-only. Start it with \`ycode mcp --allow-writes\`, or use agent mode in the Ycode IDE, where each change is reviewed as a proposal.` |
| `mem_context_snapshot` latest snapshot | Always `"none"` — Ycode has no snapshot store (§24); the stored marker is real |

## Planning tools

Behaviour shared by the 8 planning / workflow / agent-control tools
ported in Wave 4 (`execution_plan`, `intel_plan_task`,
`intel_breakdown_task`, `intel_autofix`, `intel_explain_code`,
`intel_generate_tests`, `plan-AskUser`, `report_to_user`). See
`assist-tool-catalogue.md` §116–§125 for each tool's ID, schema,
capability / risk / permission, and gate.

### Planning conventions

- **Plans are produced, never executed.** No tool in this family runs a
  plan, invokes another tool, or spawns workers. Execution stays with
  the caller, through the normal approval gate. There is no Autopilot
  anywhere in this family: Legacy's `ExecutionMode` (`"Plan"` /
  `"Autopilot"`) survives only as a label on the plan document, and it
  never changes any gating.
- **Plan storage is in-memory.** `intel_plan_task` /
  `intel_breakdown_task` store plans in a process-wide in-memory store
  (`PlanningPlanStore`, keys `plan:<uuid>` / `plan_breakdown:<uuid>`).
  Legacy stores them in the session's `AssistContext.memory`; Ycode's
  MCP host has no session memory store. Plan IDs are UUIDs, so plans
  from different workspaces cannot collide; plans do not survive a
  server restart.
- **Path resolution** uses the session-aware `resolveFileReadingPath`
  (plain relative paths resolve against the `dir_cd` working directory;
  `..` that stays inside the workspace is allowed; no path may escape
  the workspace), the same resolver the file tools use.
  `execution_plan`'s own repository inspection is deliberately
  separate: it enumerates the workspace root directly (never the
  session working directory), as Legacy does.
- **Approval gating.** The two writing handlers (`execution_plan`,
  which writes `agent_notes.md`, and `intel_generate_tests`, which
  writes the generated test file) gate **before** touching disk,
  through `commit()` — exactly like the Wave 2 file-writing tools.
  `MCPServer.run` already refuses `writes: true` tools when the server
  is read-only; the approval call is still required.
- **Legacy parameter-name aliases are NOT supported.** Ycode's argument
  validation rejects unknown arguments before the handler runs. Legacy
  registry aliases (`plan_askuser` / `plan_ask_user` / `ask_user` →
  `plan-AskUser`, `task_complete` / `task_completion` →
  `report_to_user`) live in `MCPServer.toolAliases`.

### 30. `execution_plan` — Generate Execution Plan

- Input: `objective` (string, required), `mode` (string, required:
  `"plan"` or `"autopilot"`), `relevantFiles` (optional array of file
  paths already known to be relevant).
- Behaviour: inspects the actual repository state — file tree
  (file count, Swift file count), build configuration, `AGENTS.md` /
  instruction files, workspace skills — identifies relevant files by
  keyword match against the objective (Legacy's keyword match also
  matches directories by name, e.g. `Sources/Greeter`, reproduced
  as-is), reads the relevant files, builds the plan, renders it as
  Markdown, and writes it to `agent_notes.md` at the workspace root
  through `commit()`. The mode is accepted case-insensitively:
  Legacy's schema documents lowercase `"plan"` / `"autopilot"` but its
  `ExecutionMode(rawValue:)` init only matches the capitalised
  `"Plan"` / `"Autopilot"`, so a literal `"plan"` silently became
  Autopilot; the port honours the documented values. The mode only
  labels the plan document. There is no "Plan Generation Instructions"
  section: Legacy renders it only when the instruction text is
  non-empty, and Ycode has no `WriteExecutionPlan.md` bundle resource
  to load it from. Worker assignments appear only when more than 8
  relevant files are found.
- Output (success): `Execution Plan generated for: <objective>\nMode:
  <mode>\nFiles inspected: <n> total, <m> Swift\nRelevant files
  identified: <n>\nExecution steps: <n>\nWorkers needed: <n>\nPlan
  written to: agent_notes.md` with data `planFile`
  (`"agent_notes.md"`), `stepCount`, `relevantFileCount`,
  `workerCount`, `mode` (the canonical mode string).
- Errors: missing or blank `objective` → `Missing required argument:
  'objective' must be a non-empty string.` A refused write fails
  instead of writing: Legacy writes the file directly and still returns
  success when the write fails; the Ycode behaviour is the correct one
  under the approval model (a write the reviewer refused must not land
  on disk).

### 31. `intel_plan_task` — Plan Task

- Input: `task` (string, required).
- Behaviour: splits the task text on `,`, `.`, `;`, newlines into
  clauses and numbers them as steps; an empty task (no clauses) yields
  the four default steps (`Analyze requirements`, `Implement changes`,
  `Validate with tests`, `Summarize outputs`). The plan is stored in
  the in-memory plan store under a fresh UUID and is retrievable by
  `intel_breakdown_task`.
- Output (success): `Plan generated for task: <task>` with data
  `planId` (UUID), `steps` (the numbered steps, newline-joined).
- Errors: missing `task` → `Missing required parameter: task`.

### 32. `intel_breakdown_task` — Breakdown Task

- Input: `planId` (string, required — the ID previously returned by
  `intel_plan_task`).
- Behaviour: loads the stored plan and expands every step line into
  three lines: the step itself, `Define acceptance criteria for:
  <step>`, and `Implement and self-review: <step>`. The breakdown is
  stored under `plan_breakdown:<planId>`.
- Output (success): `Task breakdown completed for plan <planId>` with
  data `breakdown` (the expanded steps, newline-joined).
- Errors: missing `planId` → `Missing required parameter: planId`;
  unknown `planId` → `No stored plan found for planId: <planId>`.

### 33. `intel_autofix` — Auto-Fix Errors (honestly failing)

- Input: `path` (string, optional workspace-relative file or directory;
  default `"."`).
- Behaviour: none — Legacy runs `lint_project` and then asks an OpenAI
  LLM (stored API key) to rewrite the file, and Ycode's MCP host has
  neither a lint engine nor an LLM provider wired for this tool.
- Errors: always `intel_autofix needs an LLM provider and lint
  diagnostics: Legacy runs lint_project and then asks an OpenAI LLM
  (stored API key) to rewrite the file, and Ycode's MCP host has
  neither a lint engine nor an LLM provider wired for this tool. No
  file was changed; use the build tool's issues and file_edit to fix
  errors.` No file is touched. (Wave 2 `code_refactor` / Wave 3
  `github_repo` precedent.) The tool has no output schema.

### 34. `intel_explain_code` — Explain Code

- Input: `path` (string, required — workspace-relative file).
- Behaviour: honest static analysis, not an LLM call. Legacy tries an
  OpenAI LLM first and falls back to a one-line static summary when the
  LLM fails; Ycode's MCP host has no LLM provider wired for this tool,
  so the port always takes the static path — and says so in the result
  (`Static analysis for <path>`). The explanation is grounded in the
  file itself (line count, imports, declared types, functions); nothing
  is invented and no LLM output is claimed.
- Output (success): `Static analysis for <path>` with data
  `explanation`.
- Errors: missing `path` → `Missing required parameter: path`; an
  unreadable file → `Failed to explain <path>: <reason>`.

### 35. `intel_generate_tests` — Generate Tests

- Input: `path` (string, required — workspace-relative source file),
  `testPath` (string, optional output path; default
  `Tests/<SourceName>Tests.swift`).
- Behaviour: extracts types and function names from the source with
  Legacy's deterministic regex, renders Legacy's verbatim XCTest stub
  template (setup / teardown, one test method per type / function), and
  writes it through `commit()`. The `@testable import` module is
  derived from the source path (`Sources/<Module>/…`, else the source
  file's parent directory name, else `App`); Legacy hardcodes
  `@testable import SwiftCode`. `test_count` is at least 1
  (`max(1, functions + types)`).
- Output (success): `Tests generated for <path> with <n> test methods`
  with data `test_path` (the requested path as given), `test_count`,
  `types_count`, `functions_count`.
- Errors: missing `path` → `Missing required parameter: path`; an
  unreadable source file → `Failed generating tests for <path>:
  <reason>`.

### 36. `plan-AskUser` — Ask User for Decision

- Input: `question` (string, required), `allowsMultipleAnswers`
  (boolean, required), `choices` (array, required — each item an
  object with `choice` (string, required) and `assistRecommended`
  (boolean)), `userSpecification` (boolean). The ID is hyphenated by
  design: `plan-AskUser` is the documented intentional exception to
  snake_case (Legacy `Tools/validate_tools.py`).
- Behaviour: returns the question as a structured handoff payload and
  returns immediately — it never blocks. Legacy presents a native
  macOS question UI (`PlanUserAskView`) and suspends execution for up
  to 300 seconds waiting for the user's answer, and is available only
  in Plan mode. Ycode's MCP host is non-interactive and has no
  Plan / Autopilot execution mode, so the Legacy Plan-mode-only gate
  is unenforceable here and is not a failure case. The caller must
  present the question to the user and feed the answer back; the tool
  itself never waits and never hangs. The description is Legacy's
  verbatim (it describes the native UI and the Plan-mode restriction);
  the behaviour is the handoff.
- Output (success): `Question for the user (pending — present this
  question to the user; this tool does not wait for an answer):
  <question>` plus a `Choices: <a> | <b> (recommended)` line when
  choices exist and a `The user may also give a free-form answer.`
  line when `userSpecification` is true. Data: `questionId` (fresh
  UUID), `question`, `status` (`"pending"`),
  `allowsMultipleAnswers`, `userSpecification`, `choices` (the choices
  as presented, each `choice` / `assistRecommended`).
- Errors: missing or blank `question` → `Missing required argument:
  'question' must be a non-empty string.`; no choices and
  `userSpecification` false → `At least one choice is required when
  userSpecification is false.` (A missing `choices` argument fails
  earlier, at Ycode's schema validation, because `choices` is
  required.)

### 37. `report_to_user` — Report Task Completion to User

- Input: `summary` (string, required — structured, concise completion
  report, clean Markdown), `status` (string, default `"completed"`),
  `filesModified` (array of strings), `verification` (string).
- Behaviour: normalises and renders the report as polished Markdown
  (Legacy's `normalizeAndRenderMarkdown`); appends a `**Modified
  Files:**` section when files are listed and not already mentioned,
  and a `**Verification:**` section when verification text is given
  and not already mentioned. There is no `AssistManager` to broadcast
  to — Legacy posts the rendered report as the assistant's last
  message; in Ycode the tool result text **is** the report. There is
  no side effect. The handler also reads `message` / `report` /
  `text` as fallbacks for `summary` (not in the schema).
- Output (success): the rendered report as the summary, with data
  `status`, `filesCount`, `renderedLength` (character count of the
  rendered report).
- Errors: none defined — a missing `summary` defaults to `Task
  execution completed.` (the schema still requires it, so Ycode's
  argument validation rejects a missing `summary` first).

### 38. Plan-file format (`execution_plan` → `agent_notes.md`)

The rendered plan is Markdown with these sections, in order:

```markdown
# Execution Plan

## Objective

## Execution Mode

## Repository Findings

## Current State

## Relevant Files

## Detected Problems

## Execution Steps

## Worker Assignments            (only when > 8 relevant files)

## Verification Requirements

## Risk Areas

## Completion Criteria
```

No "Plan Generation Instructions" section: Legacy renders it only
when the instruction text is non-empty, and Ycode has no
`WriteExecutionPlan.md` bundle resource to load it from. The mode
section carries the canonical mode string (`Plan` / `Autopilot` —
the capitalised `ExecutionMode` raw values). Relevant files are the
keyword-matched files (§30), each with the content the tool read.
Worker assignments name distinct workers with non-overlapping scopes,
in Legacy's shape, only when the relevant-file count exceeds 8.

### Planning error cases — summary table

| Situation | Result |
|---|---|
| Missing / blank required argument | `Missing required argument: '<name>' must be a non-empty string.` (`execution_plan`, `plan-AskUser`) / `Missing required parameter: <name>` (`intel_plan_task`, `intel_breakdown_task`, `intel_explain_code`, `intel_generate_tests`) |
| `intel_breakdown_task` unknown `planId` | `No stored plan found for planId: <planId>` |
| `intel_autofix` (any call) | Failure naming the missing LLM provider + lint diagnostics; no file changed (§33) |
| `plan-AskUser` with no choices and no free-form | `At least one choice is required when userSpecification is false.` |
| Approval refused (`execution_plan`, `intel_generate_tests`) | `The change was rejected in Ycode's review; nothing was written.` and nothing is written |
| Writes in `readOnly` server mode (any `writes: true` planning tool) | `<tool> changes files, and this Ycode MCP server is read-only. Start it with \`ycode mcp --allow-writes\`, or use agent mode in the Ycode IDE, where each change is reviewed as a proposal.` |
| `intel_explain_code` / `intel_generate_tests` unreadable file | `Failed to explain <path>: <reason>` / `Failed generating tests for <path>: <reason>` |

### Planning safety rules (non-negotiable)

- **No Autopilot.** The mode is a label on a document, never a
  behaviour switch. No planning tool executes a plan, invokes another
  tool, or spawns workers.
- **Never fake intelligence.** `intel_explain_code` says it is static
  analysis; `intel_autofix` fails rather than pretending to fix;
  `intel_generate_tests` is a deterministic template, not a model.
- **Never wait for a person.** `plan-AskUser` returns a pending
  handoff payload immediately; the tool never suspends, never polls,
  and has no timeout.
- **Plans are grounded.** `execution_plan` inspects the real repository
  and reads the real files; relevant files, steps, and verification
  requirements come from that inspection, never from a template alone.

## What was not ported (exact blockers)

- **`env_capture_logs`:** needs the Assist snapshot history
  (`AssistSnapshotFunctions`) and the Assist memory store. Blocker: a
  snapshot-history + memory store in the MCP host. Registered and
  honestly failing.
- **`use_extension`:** needs the Extensions v2 platform (`ExtV2Manager`
  + extension host with Node.js). Blocker: the extension host /
  marketplace wave. Registered and honestly failing. **(Wave 11:
  UNBLOCKED — the `YcodeExtensions` host is implemented and the tool
  is wired to it; see the Wave 11 note in §7.)**
- **`use_composio`:** needs the Composio service (`ComposioService`
  with a Composio API key and connected integrations). Blocker: a
  Composio service + credential flow. Registered and honestly failing.
- **`use_workers`:** needs the Assist worker runtime (`WorkerScheduler`
  + `WorkerPersistenceStore` + subagent execution). Blocker: a worker /
  subagent runtime in the MCP host. Registered and honestly failing
  (after Legacy's validation).
- **`take_screenrecord`:** needs a ScreenCaptureKit stream-recording
  engine (`SCStream` + video writer) plus Screen Recording permission.
  Blocker: the recording engine. Registered and honestly failing.
- **`use_mcp` (execution only):** needs an external MCP client with
  configured servers and a connection manager. The `list` branch is
  implemented honestly (empty list). Blocker: an external MCP client.
- **`use_app` (Accessibility / interaction actions only):** needs the
  macOS Accessibility / app-interaction engine
  (`AssistAppInteractionEngine`). `list_applications`, `launch` /
  `activate`, `close_application`, and `list_windows` are implemented
  on public APIs. Blocker: the interaction engine.
- **`intel_autofix`:** needs a lint engine plus an OpenAI LLM with a
  stored API key. Blocker: a lint engine + an LLM provider wired into
  MCP. Registered and honestly failing.
- **`intel_explain_code` (LLM path only):** no LLM provider is wired
  into MCP. Implemented as labelled static analysis instead.
- **`plan-AskUser` (native UI + 300 s suspension + Plan-mode gate):**
  the MCP host is non-interactive and has no execution mode.
  Implemented as a pending handoff payload instead.
- **Anything else:** nothing. All other behaviour ported, including
  `mem_context_snapshot`'s `"none"` latest snapshot (honest — there is
  no snapshot store) and `execution_plan`'s lowercase mode handling
  (fixed, §30).

## Evidence

| Claim | Level | Source |
|---|---|---|
| All 34 IDs, titles, descriptions, capabilities, risk levels, and input schemas | 1 | Legacy source, read directly: `SwiftCode/Backend/Assist/Tools/UseTermFunction.swift`, `AssistTaskRunnerTool.swift`, `AssistLogCaptureTool.swift`, `AssistEnvironmentInfoTool.swift`, `UseMCP.swift`, `UseExtensionTool.swift`, `AssistComposioTool.swift`, `Subagents/Tools/UseWorkersTool.swift`, `AssistEnvironmentVariableManagerTool.swift`, `AssistClipboardManagerTool.swift`, `AssistProcessMonitorTool.swift`, `AssistDiskSpaceAnalyzerTool.swift`, `AssistSystemNotificationTool.swift`, `AssistSystemTool.swift`, `AssistTakeScreenshotTool.swift`, `AssistTakeScreenrecordTool.swift`, `AssistUseAppTool.swift`, `AssistStoreMemoryTool.swift`, `AssistRetrieveMemoryTool.swift`, `AssistClearMemoryTool.swift`, `AssistContextSnapshotTool.swift`, `AssistContextPersistenceStore.swift`, `AssistSaveToMemoryTool.swift`, `AssistViewMemoryTool.swift`, `AssistManageMemoryTool.swift`, `AssistConversationContextTool.swift`, `ExecutionPlanTool.swift`, `AssistPlanTaskTool.swift`, `AssistBreakdownTaskTool.swift`, `AssistAutoFixErrorsTool.swift`, `AssistExplainCodeTool.swift`, `AssistGenerateTestsTool.swift`, `PlanAskUserTool.swift`, `ReportToUserTool.swift`, `AssistToolRegistry.swift` (register lines 104, 108–113, 116–120, 122–125, 135, 141–143, 147, 167–170, 207–211, 349, 393–395; alias table lines 430–556), `AssistTool.swift` (capability / risk / permission defaults, `isReadOnly` / `isMutating` / `isDestructive`) |
| `use_terminal` tokenize-to-argv, shell-metacharacter rejection, 300 s timeout, stdout tail 3000 / stderr tail 2000 | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Terminal.swift` (`useTerminal`, `terminalTokenizeCommand`, `terminalRunFixed` in `YcodeTools+TerminalSupport.swift`); Legacy `UseTermFunction.swift`, `AgentTerminalService` |
| `use_system` operations, sysctl allowlist, blocked global domain, read-back verification | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Terminal.swift` (`useSystem` and its sub-handlers); Legacy `Tools/AssistSystemTool.swift` |
| Memory stores: in-memory graph, per-workspace `UserMemory.md` format, `.assist_context_store.json`, conversation file | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Memory.swift`, `YcodeTools+MemorySupport.swift` (`YcodeMemoryGraphStore`, `YcodeUserMemoryFormat`, `YcodeContextStoreFormat`); Legacy `AssistMemoryGraph.swift`, `UserMemoryManager.swift`, `AssistConversationHistory.swift`, `AssistSnapshotFunctions.swift` |
| Planning: in-memory plan store, plan-file sections, `plan-AskUser` handoff, `intel_autofix` prerequisite | 1 | Ycode `ycode/Sources/YcodeMCP/YcodeTools+Planning.swift`, `YcodeTools+PlanningSupport.swift` (`PlanningPlanStore`, `renderPlanMarkdown`); Legacy `ExecutionPlanTool.swift` (`renderPlanMarkdown`), `Functions/System Assets/ExecutionPlans.md`, `Resources/WriteExecutionPlan.md`, `PlanAskUserTool.swift`, `AssistAutoFixErrorsTool.swift` |
| Ycode MCP annotation shape (`.read` preset; `writes` flag; `readOnlyHint`) and the write-policy gate | 1 | Ycode `ycode/Sources/YcodeMCP/MCPServer.swift` (`MCPToolAnnotations`, `MCPServer.run`, `toolAliases`); `ycode/Sources/YcodeMCP/YcodeTools.swift` (`installTools`, `tool`) |
| `plan-AskUser` hyphenated ID is the documented intentional exception to snake_case | 1 | Legacy `SwiftCode/Backend/Assist/Tools/validate_tools.py`; `AssistToolRegistry.swift` alias table (`plan_askuser` / `plan_ask_user` / `ask_user` → `plan-AskUser`) |
| This spec describes behaviour only; no Legacy method bodies, decompiler text, or Apple code are reproduced in it | — | Spec author's conformance to this repo's `AGENTS.md` clean-room protocol (specs describe behaviour and formats only) |
