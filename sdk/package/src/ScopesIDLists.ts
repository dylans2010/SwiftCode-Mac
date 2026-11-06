/**
 * Capability → scope ID list for `@swiftcode/sdk`.
 *
 * GENERATED — do not hand-edit. Regenerated from the Swift host table
 * `ycode/Sources/YcodeSDK/Host/ScopesIDLists.swift` (`ScopesIDLists.all`)
 * by `~/SwiftCode-Migration-Workspace/scripts/generate-scopes-ts.py`.
 * The two files are kept in sync by `tests/scopes-sync.test.mjs`, which
 * parses BOTH files and fails on any ID, kind, ipcMethod, or viewId drift
 * in either direction. When adding a capability to the fixed registry,
 * add the entry in the Swift host table and re-run the generator.
 *
 * 32 entries — NOT 35: `use.Security` and `assist.main` are
 * umbrella/entitlement surfaces, not separately requestable scopes.
 * 12 entries are views (`ui.openView` + registered openers in
 * `SDKViewOpenerBuiltIns.swift`); 20 are API capabilities served by the
 * host adapters. Entries with `ipcMethod: null` have a broker capability
 * but no wired host method in this release — `assist.invoke` is the
 * deny-by-default exception (spec §9): it is never grantable and no
 * method pattern reaches it (`SDKAssistGate`). The `assist.ui` and
 * `assist.headless` entries are entitlement-only: their `assist.invoke`
 * route is the dedicated entitled path the dispatcher/gate implements,
 * not a manifest grant.
 */

/**
 * `"view"`: the scope opens a host view through `ui.openView` (the view ID
 * travels in the payload's `viewId` field and is authorized at the
 * capability broker like any other capability). `"api"`: the scope is
 * served by the host's adapters over its own IPC method(s).
 */
export type ScopeKind = "view" | "api";

export interface ScopeIDEntry {
  /** Lookup key and wire capability ID. */
  readonly id: string;
  /** Short user-facing title (matches `SDKCapabilityInfo.title`). */
  readonly title: string;
  /** One-sentence plain-language description of what the scope allows. */
  readonly description: string;
  readonly kind: ScopeKind;
  /**
   * The primary IPC method serving this capability.
   * - View entries: always `"ui.openView"`; see `viewId` for the payload value.
   * - API entries: the real host method string (e.g. `"build.run"`), or
   *   `null` when the host has not wired an IPC method for the capability
   *   in this release. `null` is honest, never a placeholder: a capability
   *   whose grant exists but whose method is `null` cannot be invoked yet.
   *   A capability may span several methods (e.g. `build.execute` also
   *   covers `build.wait`/`build.cancel`); this field names the primary one.
   */
  readonly ipcMethod: string | null;
  /**
   * The fixed `SDKCapabilityID` registry value — wire-stable, matched
   * verbatim (case-sensitive) in manifests, grants, and IPC messages.
   */
  readonly capabilityId: string;
  /**
   * Present only for `kind: "view"`: the exact `viewId` payload value the
   * extension sends to `ui.openView` to open this view.
   */
  readonly viewId?: string;
}
/**
 * Every capability ID in the fixed registry, in host-table order,
 * each paired with its scope kind and primary IPC method.
 */
export const SCOPES_ID_LIST: readonly ScopeIDEntry[] = [
  {
    id: "project.read",
    title: "Project metadata",
    description: "Read basic facts about the active project.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "project.read"
  },
  {
    id: "workspace.read",
    title: "Workspace file reading",
    description: "Read files inside the approved workspace scope.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "workspace.read"
  },
  {
    id: "workspace.write",
    title: "Workspace file writing",
    description: "Create or modify files inside the approved workspace through the host's constrained file API.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "workspace.write"
  },
  {
    id: "source-control.read",
    title: "Source control reading",
    description: "Inspect repository status, diffs, branch, and approved history. Read-only.",
    kind: "api",
    ipcMethod: "sourceControl.getStatus",
    capabilityId: "source-control.read"
  },
  {
    id: "source-control.write",
    title: "Source control changes",
    description: "Perform explicitly supported source-control mutations.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "source-control.write"
  },
  {
    id: "build.execute",
    title: "Build execution",
    description: "Request builds through SwiftCode's managed build service.",
    kind: "api",
    ipcMethod: "build.run",
    capabilityId: "build.execute"
  },
  {
    id: "task.execute",
    title: "Host task execution",
    description: "Invoke approved host task types.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "task.execute"
  },
  {
    id: "network.request",
    title: "Network requests",
    description: "Make network requests constrained by host policy.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "network.request"
  },
  {
    id: "ui.contribute",
    title: "UI contributions",
    description: "Register supported extension UI contributions.",
    kind: "api",
    ipcMethod: "commands.register",
    capabilityId: "ui.contribute"
  },
  {
    id: "credentials.use",
    title: "Credential use",
    description: "Use a narrowly scoped, host-mediated credential for an approved service.",
    kind: "api",
    ipcMethod: null,
    capabilityId: "credentials.use"
  },
  {
    id: "assist.invoke",
    title: "Assist invocation",
    description: "Request Assist operations. Unavailable to extensions in this release.",
    kind: "api",
    ipcMethod: "assist.invoke",
    capabilityId: "assist.invoke"
  },
  {
    id: "assist.ui",
    title: "Assist embedded UI",
    description: "Embed the host's Assist main view. Entitlement-only.",
    kind: "api",
    ipcMethod: "assist.invoke",
    capabilityId: "assist.ui"
  },
  {
    id: "assist.headless",
    title: "Assist headless API",
    description: "Drive Assist sessions over the entitled assist.invoke route. Entitlement-only.",
    kind: "api",
    ipcMethod: "assist.invoke",
    capabilityId: "assist.headless"
  },
  {
    id: "use.SwiftCodeModel",
    title: "SwiftCode Cloud Model",
    description: "Call the SwiftCode Cloud Model through the host under host-enforced quota.",
    kind: "api",
    ipcMethod: "cloudModel.complete",
    capabilityId: "use.SwiftCodeModel"
  },
  {
    id: "terminal.sandbox",
    title: "Sandboxed command execution",
    description: "Run allow-listed commands through the host's sandboxed execution service.",
    kind: "api",
    ipcMethod: "terminalSandbox.run",
    capabilityId: "terminal.sandbox"
  },
  {
    id: "security.addValue",
    title: "Store a secret",
    description: "Store a named secret in the host's Keychain vault.",
    kind: "api",
    ipcMethod: "security.addValue",
    capabilityId: "security.addValue"
  },
  {
    id: "security.hasValue",
    title: "Check a stored secret",
    description: "Check whether a named secret exists, without revealing the value.",
    kind: "api",
    ipcMethod: "security.hasValue",
    capabilityId: "security.hasValue"
  },
  {
    id: "security.listValueIDs",
    title: "List stored secret names",
    description: "List the names of the extension's stored secrets.",
    kind: "api",
    ipcMethod: "security.listValueIDs",
    capabilityId: "security.listValueIDs"
  },
  {
    id: "security.deleteValue",
    title: "Delete a stored secret",
    description: "Permanently delete a named stored secret.",
    kind: "api",
    ipcMethod: "security.deleteValue",
    capabilityId: "security.deleteValue"
  },
  {
    id: "security.useValue",
    title: "Use a stored secret",
    description: "Have the host inject a stored secret into an approved operation.",
    kind: "api",
    ipcMethod: "security.useValue",
    capabilityId: "security.useValue"
  },
  {
    id: "db.ExploreView",
    title: "Database Explorer",
    description: "Open the Database Explorer window for project databases.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "db.ExploreView",
    viewId: "db.ExploreView"
  },
  {
    id: "ci.VisualWF",
    title: "CI / visual workflow",
    description: "Open the CI and visual workflow views.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "ci.VisualWF",
    viewId: "ci.VisualWF"
  },
  {
    id: "sandbox.view",
    title: "Terminal",
    description: "Open SwiftCode's real Terminal view (full interactive shell).",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "sandbox.view",
    viewId: "sandbox.view"
  },
  {
    id: "virtualization.view",
    title: "Virtualization console",
    description: "Open the Virtualization console.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "virtualization.view",
    viewId: "virtualization.view"
  },
  {
    id: "deployConsole.view",
    title: "Deployments console",
    description: "Open the Deployments console.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "deployConsole.view",
    viewId: "deployConsole.view"
  },
  {
    id: "simulator.view",
    title: "Simulator workspace",
    description: "Open the Simulator workspace.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "simulator.view",
    viewId: "simulator.view"
  },
  {
    id: "preview.live",
    title: "Live SwiftUI preview",
    description: "Render live SwiftUI previews of project views.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "preview.live",
    viewId: "preview.live"
  },
  {
    id: "uibuilder.open",
    title: "Visual UI Builder",
    description: "Open the Visual UI Builder.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "uibuilder.open",
    viewId: "uibuilder.open"
  },
  {
    id: "symbols.browse",
    title: "SF Symbol picker",
    description: "Open the SF Symbol picker.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "symbols.browse",
    viewId: "symbols.browse"
  },
  {
    id: "docs.search",
    title: "Documentation browser",
    description: "Open the documentation browser.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "docs.search",
    viewId: "docs.search"
  },
  {
    id: "dictionary.open",
    title: "Coding dictionary",
    description: "Open the coding dictionary reference.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "dictionary.open",
    viewId: "dictionary.open"
  },
  {
    id: "deviceconnect.open",
    title: "Device Connect",
    description: "Open the Device Connect surface for paired devices.",
    kind: "view",
    ipcMethod: "ui.openView",
    capabilityId: "deviceconnect.open",
    viewId: "deviceconnect.open"
  },
];

/**
 * `SCOPES_ID_LIST` keyed by `id`. Every key is a wire capability ID;
 * every value is the same entry object from the list.
 */
export const SCOPES_BY_ID: Readonly<Record<string, ScopeIDEntry>> =
  Object.fromEntries(SCOPES_ID_LIST.map((entry) => [entry.id, entry]));
