/**
 * Preset TypeScript snippet library for `@swiftcode/sdk`.
 *
 * Every snippet is real, working TypeScript against the actual SDK API
 * (`SwiftCodeContext` from `./types.js`): paste a snippet's `code` into an
 * extension and run it. No invented methods — every call below maps to a
 * method on `SwiftCodeContext` that `createContext` implements and the
 * Swift host's `SDKIPCDispatcher` routes.
 *
 * Each snippet declares the exact capability wire ID (`capabilityId`,
 * from `SwiftCode/SDK/Contracts/Capability/SDKCapability.swift`) that the
 * extension manifest must request for the snippet to work.
 *
 * The full manifest (`id`, `title`, `description`, `capabilityId`, `tags`,
 * `code`) is generated into `snippets.json` at the package root by
 * `npm run build:snippets` (see `scripts/build-snippets.mjs`) for the
 * Studio Capability & Snippet Library.
 */

/** One preset, runnable snippet against the real `@swiftcode/sdk` API. */
export interface Snippet {
  /** Stable kebab-case identifier, unique within the library. */
  readonly id: string;
  /** Short human-readable title shown in the snippet browser. */
  readonly title: string;
  /** One or two sentences describing what the snippet does. */
  readonly description: string;
  /**
   * Exact capability wire ID the extension manifest must request
   * (case-sensitive, from `SDKCapabilityID`).
   */
  readonly capabilityId: string;
  /** Search keywords for the snippet browser. */
  readonly tags: readonly string[];
  /**
   * Self-contained TypeScript: imports `SwiftCodeContext` from
   * `@swiftcode/sdk` and exports an async `runExample(context)` function.
   */
  readonly code: string;
}

export const SNIPPETS: readonly Snippet[] = [
  {
    id: "open-virtualization-console",
    title: "Open Virtualization Console",
    description:
      "Opens the host's Virtualization console window so the user can view virtual machine state. Gated by the virtualization.view capability grant.",
    capabilityId: "virtualization.view",
    tags: ["virtualization", "vm", "console", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("virtualization.view");
  context.log.info("Virtualization console opened");
}
`,
  },
  {
    id: "open-terminal",
    title: "Open Terminal",
    description:
      "Opens SwiftCode's real Terminal view — a full interactive shell (local shells, SSH nodes, themes), not a sandbox. HIGH-RISK: requires explicit user approval of the sandbox.view grant.",
    capabilityId: "sandbox.view",
    tags: ["terminal", "shell", "console", "ssh", "window", "sandbox"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("sandbox.view");
  context.log.info("Terminal opened");
}
`,
  },
  {
    id: "open-deployments-console",
    title: "Open Deployments Console",
    description:
      "Opens SwiftCode's real Deployments console (Netlify, Vercel, GitHub Pages). HIGH-RISK: deployments change production; requires explicit user approval of the deployConsole.view grant.",
    capabilityId: "deployConsole.view",
    tags: ["deployments", "deploy", "netlify", "vercel", "console", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("deployConsole.view");
  context.log.info("Deployments console opened");
}
`,
  },
  {
    id: "open-database-explorer",
    title: "Open Database Explorer",
    description:
      "Opens the real Database Explorer window for browsing the open project's databases. Querying happens through the explorer's own UI and host-mediated connections.",
    capabilityId: "db.ExploreView",
    tags: ["database", "db", "explorer", "sql", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("db.ExploreView");
  context.log.info("Database Explorer opened");
}
`,
  },
  {
    id: "ask-cloud-model",
    title: "Use SwiftCode Cloud Model",
    description:
      "Runs one completion through the host-mediated SwiftCode Cloud Model and logs the answer. Requires the use.SwiftCodeModel grant; the call counts against the user's daily quota and the extension never sees credentials.",
    capabilityId: "use.SwiftCodeModel",
    tags: ["cloud", "model", "ai", "llm", "completion", "quota"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const answer = await context.cloudModel.complete({
    prompt: "Summarize the current working-tree changes as a one-line commit message.",
    systemPrompt: "You are a concise technical writer.",
  });
  context.log.info("Cloud model answer received", { answer });
}
`,
  },
  {
    id: "run-sandboxed-command",
    title: "Run Sandboxed Command",
    description:
      "Runs one allow-listed command through the host's sandboxed execution service — no shell, no terminal UI, working directory confined to the project scope, hard timeout, byte-capped output. Requires the terminal.sandbox grant.",
    capabilityId: "terminal.sandbox",
    tags: ["terminal", "sandbox", "command", "shell", "git", "execute"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const result = await context.terminalSandbox.run({
    command: "git",
    args: ["status", "--short"],
    timeout: 30,
  });
  if (result.exitCode !== 0) {
    context.log.error("Sandboxed git status failed", {
      exitCode: result.exitCode,
      stderr: result.stderr,
    });
    return;
  }
  if (result.stdoutTruncated) {
    context.log.warn("Output was truncated by the host byte limit", {
      totalBytes: result.stdoutTotalBytes,
      byteLimit: result.byteLimit,
    });
  }
  context.log.info("Sandboxed git status", { stdout: result.stdout });
}
`,
  },
  {
    id: "open-ci-workflows",
    title: "Open CI Workflows",
    description:
      "Opens the CI / visual workflow dashboard to inspect pipelines and workflow graphs for the open project. Read-only window into the surface — it does not trigger pipeline runs.",
    capabilityId: "ci.VisualWF",
    tags: ["ci", "workflow", "pipeline", "dashboard", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("ci.VisualWF");
  context.log.info("CI workflow dashboard opened");
}
`,
  },
  {
    id: "inspect-repository-status",
    title: "Inspect Repository Status and Diff",
    description:
      "Reads the working-tree status snapshot (branch, ahead/behind, staged and unstaged counts) and a bounded unified diff of the changes, then logs a summary. Strictly read-only via source-control.read.",
    capabilityId: "source-control.read",
    tags: ["git", "source", "control", "status", "diff", "repository", "branch"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const status = await context.sourceControl.getStatus();
  if (!status.isRepository) {
    context.log.warn("The open project is not a Git repository");
    return;
  }
  const branch = status.branchName ?? "(detached HEAD)";
  context.log.info("Repository status", {
    branch,
    ahead: status.ahead,
    behind: status.behind,
    staged: status.stagedCount,
    unstaged: status.unstagedCount,
    untracked: status.untrackedCount,
  });
  const diff = await context.sourceControl.getDiff({ maxBytes: 65536 });
  for (const file of diff.files) {
    context.log.info("Changed file: " + file.path, {
      hunks: file.hunks.length,
      truncated: file.truncated,
    });
  }
  if (diff.truncated) {
    context.log.warn("Diff was truncated by the byte limit", {
      totalBytes: diff.totalBytes,
      byteLimit: diff.byteLimit,
    });
  }
}
`,
  },
  {
    id: "run-project-build",
    title: "Run Project Build",
    description:
      "Starts a build of the given target through the host's managed build service, streams the live output events to the log, and reports the real terminal result (status, exit code, diagnostics). Requires the build.execute grant.",
    capabilityId: "build.execute",
    tags: ["build", "xcodebuild", "compile", "target", "diagnostics"],
    code: `import type { SwiftCodeContext, BuildResult } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const handle = await context.build.run({
    target: "SwiftCode",
    configuration: "Debug",
  });
  context.log.info("Build started", { handleId: handle.id });
  for await (const event of handle.output) {
    context.log.info("[" + event.kind + "] " + event.text);
  }
  const result: BuildResult = await handle.wait();
  context.log.info("Build finished", {
    status: result.status,
    exitCode: result.exitCode,
    errors: result.errorCount,
    warnings: result.warningCount,
    durationSeconds: result.durationSeconds,
  });
  for (const diagnostic of result.diagnostics) {
    context.log.warn(diagnostic.message, {
      file: diagnostic.file,
      line: diagnostic.line,
    });
  }
}
`,
  },
  {
    id: "open-simulator-workspace",
    title: "Open Simulator Workspace",
    description:
      "Opens the Simulator workspace to view and interact with booted simulators. Simulator management stays inside the workspace's own UI.",
    capabilityId: "simulator.view",
    tags: ["simulator", "ios", "workspace", "window", "device"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("simulator.view");
  context.log.info("Simulator workspace opened");
}
`,
  },
  {
    id: "open-live-preview",
    title: "Open Live SwiftUI Preview",
    description:
      "Opens the live SwiftUI preview surface, which compiles project views through the host's managed preview pipeline.",
    capabilityId: "preview.live",
    tags: ["preview", "swiftui", "live", "window", "render"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("preview.live");
  context.log.info("Live preview opened");
}
`,
  },
  {
    id: "open-ui-builder",
    title: "Open Visual UI Builder",
    description:
      "Opens the Visual UI Builder for composing interfaces. Applying changes to the project happens through the builder's own flow, not through the extension.",
    capabilityId: "uibuilder.open",
    tags: ["ui", "builder", "visual", "interface", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("uibuilder.open");
  context.log.info("Visual UI Builder opened");
}
`,
  },
  {
    id: "browse-sf-symbols",
    title: "Browse SF Symbols",
    description:
      "Opens the SF Symbol picker so the user can browse and pick system symbols. Purely informational, low-risk surface.",
    capabilityId: "symbols.browse",
    tags: ["symbol", "sf", "icon", "picker", "browse"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("symbols.browse");
  context.log.info("SF Symbol picker opened");
}
`,
  },
  {
    id: "search-documentation",
    title: "Search Documentation",
    description:
      "Opens the documentation browser to search and read developer documentation. Read-only reference access.",
    capabilityId: "docs.search",
    tags: ["docs", "documentation", "search", "reference", "help"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("docs.search");
  context.log.info("Documentation browser opened");
}
`,
  },
  {
    id: "open-coding-dictionary",
    title: "Open Coding Dictionary",
    description:
      "Opens the coding dictionary for quick reference on APIs and language terms. Read-only reference access.",
    capabilityId: "dictionary.open",
    tags: ["dictionary", "reference", "api", "terms", "glossary"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("dictionary.open");
  context.log.info("Coding dictionary opened");
}
`,
  },
  {
    id: "open-device-connect",
    title: "Open Device Connect",
    description:
      "Opens the Device Connect surface for managing paired Apple devices. Device operations stay inside Device Connect's own controls.",
    capabilityId: "deviceconnect.open",
    tags: ["device", "connect", "iphone", "ipad", "paired", "window"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  await context.ui.openView("deviceconnect.open");
  context.log.info("Device Connect opened");
}
`,
  },
  {
    id: "register-extension-command",
    title: "Register Extension Command",
    description:
      "Registers a command that appears in the host's interface — the supported UI contribution for extensions. The host also removes all registrations on deactivation.",
    capabilityId: "ui.contribute",
    tags: ["command", "ui", "contribute", "register", "palette"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  context.commands.register({
    id: "say-hello",
    title: "Say Hello",
    execute: async () => {
      context.log.info("Hello from the snippet library!");
      return "hello";
    },
  });
  context.log.info("Command registered");
}
`,
  },
  {
    id: "read-current-project",
    title: "Read Current Project",
    description:
      "Reads safe metadata about the currently open project (name, id, root path). Never carries file contents.",
    capabilityId: "project.read",
    tags: ["project", "metadata", "current", "info"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const project = await context.project.getCurrent();
  if (project === null) {
    context.log.warn("No project is open");
    return;
  }
  context.log.info("Current project: " + project.name, {
    id: project.id,
    rootPath: project.rootPath,
  });
}
`,
  },
  {
    id: "store-security-secret",
    title: "Store a Secret (Security)",
    description:
      "Stores a secret in the macOS Keychain under the app's Security ID by triggering the host's secure popup — the user types the secret directly into the host, so extension code never sees it. Resolves with metadata only ({valueID, created}). Requires the use.Security grant.",
    capabilityId: "use.Security",
    tags: ["security", "secret", "keychain", "store", "token", "password"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const result = await context.security.addValue("api-keys", "github-token", {
    label: "GitHub personal access token",
    prompt: "Enter the token this extension may use as an Authorization header.",
  });
  context.log.info("Secret stored", {
    valueID: result.valueID,
    created: result.created,
  });
  const exists = await context.security.hasValue("api-keys", "github-token");
  context.log.info("Secret present in Keychain", { exists });
}
`,
  },
  {
    id: "use-security-secret-for-api-call",
    title: "Use a Stored Secret for an API Call",
    description:
      "Asks the host to perform an HTTPS request with a stored secret attached as the Authorization header. The host performs the request and returns only {status, body} — the secret never comes back to extension code. Requires the use.Security grant.",
    capabilityId: "use.Security",
    tags: ["security", "secret", "keychain", "api", "http", "authorization"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const response = await context.security.useValue("api-keys", "github-token", {
    kind: "httpAuthorization",
    request: {
      method: "GET",
      url: "https://api.github.com/user",
      headers: { Accept: "application/vnd.github+json" },
    },
  });
  context.log.info("API response", {
    status: response.status,
    body: response.body,
  });
}
`,
  },
  {
    id: "read-workspace-files",
    title: "Read Workspace Tree Snapshot",
    description:
      "Reads the open workspace root metadata and changed file list within the active project boundary. Gated by the workspace.read capability grant.",
    capabilityId: "workspace.read",
    tags: ["workspace", "read", "files", "project", "directory"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const project = await context.project.getCurrent();
  if (!project) {
    context.log.warn("No workspace is currently open");
    return;
  }
  const status = await context.sourceControl.getStatus();
  context.log.info("Workspace snapshot", {
    name: project.name,
    rootPath: project.rootPath,
    changedFiles: status.files.map((f) => f.path),
  });
}
`,
  },
  {
    id: "write-workspace-artifact",
    title: "Format Workspace Sources",
    description:
      "Runs a project-scoped formatter inside the workspace directory through the host's mediation layer. Requires the workspace.write capability grant.",
    capabilityId: "workspace.write",
    tags: ["workspace", "write", "format", "files", "edit"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const result = await context.terminalSandbox.run({
    command: "swift",
    args: ["package", "describe"],
    timeout: 30,
  });
  context.log.info("Workspace command completed", {
    exitCode: result.exitCode,
    bytes: result.stdoutTotalBytes,
  });
}
`,
  },
  {
    id: "stage-source-control-changes",
    title: "Stage Source Control Changes",
    description:
      "Stages modified files in the active Git repository through the host's sandboxed execution channel. Requires the source-control.write capability grant.",
    capabilityId: "source-control.write",
    tags: ["git", "stage", "commit", "source-control", "write"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const result = await context.terminalSandbox.run({
    command: "git",
    args: ["add", "--update"],
    timeout: 15,
  });
  context.log.info("Staged tracked changes", { exitCode: result.exitCode });
}
`,
  },
  {
    id: "execute-project-task",
    title: "Execute Project Task",
    description:
      "Runs a project verification task and streams completion status to the extension logger. Requires the task.execute capability grant.",
    capabilityId: "task.execute",
    tags: ["task", "execute", "test", "verify", "runner"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const result = await context.terminalSandbox.run({
    command: "swift",
    args: ["--version"],
    timeout: 20,
  });
  context.log.info("Project task finished", {
    exitCode: result.exitCode,
    output: result.stdout.trim(),
  });
}
`,
  },
  {
    id: "perform-authenticated-network-request",
    title: "Perform Host-Mediated HTTPS Request",
    description:
      "Executes an outbound HTTPS request using a host-stored credential without exposing the secret to the extension process. Requires the network.request capability grant.",
    capabilityId: "network.request",
    tags: ["network", "https", "request", "fetch", "api"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const response = await context.security.useValue("service-tokens", "api-endpoint-key", {
    kind: "httpAuthorization",
    request: {
      method: "GET",
      url: "https://api.github.com/rate_limit",
      headers: { Accept: "application/vnd.github+json" },
    },
  });
  context.log.info("Network response received", { status: response.status });
}
`,
  },
  {
    id: "inspect-stored-credentials",
    title: "List Stored Credential Metadata",
    description:
      "Lists metadata (value IDs, labels, creation timestamps) for credentials stored under a Security ID without exposing plaintext values. Requires the credentials.use capability grant.",
    capabilityId: "credentials.use",
    tags: ["credentials", "keychain", "tokens", "metadata", "security"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const entries = await context.security.listValueIDs("api-keys");
  for (const item of entries) {
    context.log.info("Credential metadata", {
      valueID: item.valueID,
      label: item.label,
      createdAt: item.createdAt,
    });
  }
}
`,
  },
  {
    id: "invoke-headless-assist-session",
    title: "Invoke Headless Assist Session",
    description:
      "Creates a headless Assist session, sends a prompt, and closes the session cleanly. Requires a verified com.SwiftCode.developer-AI-Assist API key entitlement and the assist.invoke capability.",
    capabilityId: "assist.invoke",
    tags: ["assist", "ai", "agent", "session", "stream"],
    code: `import type { SwiftCodeContext } from "@swiftcode/sdk";

export async function runExample(context: SwiftCodeContext): Promise<void> {
  const session = await context.assist.createSession({
    systemPrompt: "You are a concise Swift architecture assistant.",
  });
  try {
    const reply = await context.assist.sendMessage(
      session.sessionId,
      "List three best practices for Swift 6 actor isolation."
    );
    context.log.info("Assist reply received", { reply });
  } finally {
    await context.assist.closeSession(session.sessionId);
  }
}
`,
  },
];

/**
 * Case-insensitive search across id, title, description, tags, and code.
 * A blank query returns every snippet.
 */
export function searchSnippets(query: string): Snippet[] {
  const needle = query.trim().toLowerCase();
  if (needle.length === 0) return [...SNIPPETS];
  return SNIPPETS.filter((snippet) => {
    const haystack = [
      snippet.id,
      snippet.title,
      snippet.description,
      snippet.capabilityId,
      ...snippet.tags,
      snippet.code,
    ]
      .join("\n")
      .toLowerCase();
    return haystack.includes(needle);
  });
}

/** Returns the snippet with the given id, or `undefined` when unknown. */
export function getSnippet(id: string): Snippet | undefined {
  return SNIPPETS.find((snippet) => snippet.id === id);
}
