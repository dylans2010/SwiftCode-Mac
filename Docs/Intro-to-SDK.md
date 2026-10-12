# SwiftCode SDK --- Full Implementation Specification

**Artifact:** `Into-to-SDK.md`\
**Purpose:** Authoritative implementation brief for an autonomous coding
agent implementing the SwiftCode SDK platform\
**Status:** Proposed architecture and requirements; validate all names
and existing implementation against the repository before coding\
**Primary deliverable:** A working SDK platform integrated into the
existing SwiftCode macOS application, plus a real TypeScript extension
scaffold and developer workflow

------------------------------------------------------------------------

## 1. Mission and outcome

Build a production-minded SwiftCode SDK that turns SwiftCode from a
single application into a platform that supports both:

1.  **Standalone projects** created, opened, built, inspected, and
    managed through SwiftCode.
2.  **SwiftCode extensions** that execute within a defined host/runtime
    contract and can contribute commands and, later, other supported UI
    or workflow contributions.

The first end-to-end extension target is **TypeScript**. The initial
example extension requests exactly these capabilities:

-   `source-control.read`
-   `build.execute`

It **must not request, receive, or access restricted Assist
authorization**. Assist is a separately protected service and must
remain unavailable unless SwiftCode's independent authorization system
grants a specific, scoped, revocable entitlement. A manifest field is
never a security boundary.

The deliverable is not merely a collection of interfaces, documentation,
or a demo. It must connect to real SwiftCode services, return real data,
propagate real failures, enforce permissions at the host boundary, and
be testable end to end.

### 1.1 Product architecture

Implement the platform as clear layers:

-   **SwiftCode SDK Contracts:** stable, versioned, language-neutral
    protocol and data contracts.
-   **SwiftCode SDK Public API:** developer-facing API, beginning with
    TypeScript.
-   **SwiftCode SDK Host:** host-owned API façade and capability broker.
-   **SwiftCode SDK Runtime:** lifecycle, isolation, IPC, message
    validation, timeouts, cancellation, logging, and cleanup.
-   **SwiftCode SDK Services:** adapters over existing SwiftCode
    project, source-control, and build infrastructure.
-   **SwiftCode SDK Assist Gate:** a separately protected authorization
    boundary. It denies extensions by default and is not exposed in the
    first TypeScript extension context.
-   **SwiftCode Studio / Developer Experience:** extension and
    standalone project creation, validation, local development,
    packaging, installation, and management.
-   **Templates, examples, tests, and documentation:** the complete path
    from a generated project to a real installed extension.

Names above are architectural labels, not a requirement to introduce a
separate target for every label. Follow the existing repository's
architecture and build conventions. Prefer a small number of cohesive
Swift packages/modules over a sprawling package graph. Keep boundaries
explicit even if some components initially share a target.

------------------------------------------------------------------------

## 2. Non-negotiable agent operating instructions

Before modifying code, the implementation agent must:

1.  Read all applicable `AGENTS.md` files, repository instructions,
    contribution notes, and relevant architecture documents.
2.  Inspect the entire repository structure and the existing
    `.xcodeproj` / Swift package setup.
3.  Trace existing project/session models, workspace/file access,
    source-control implementation, build and `xcodebuild` execution,
    logging, settings, persistence, permissions, and app navigation.
4.  Identify the actual service APIs, ownership boundaries, threading
    requirements, error types, and test coverage.
5.  Record findings and a task-specific execution plan using the
    repository's established workflow. If the project has an
    `execution_plan` tool or equivalent, invoke it before each task that
    changes code.
6.  Maintain the required per-task `agent_notes.md` (use the exact
    capitalization/path required by current repository instructions; do
    not create competing variants).
7.  Establish a baseline build and tests before implementation. Record
    existing failures separately from new failures.

Do not stop after producing a plan. Continue autonomously through
implementation, testing, and a final report unless a genuine blocker
requires user intervention.

### 2.1 Do not

-   Do not fabricate APIs, service responses, extension activation
    success, build results, source-control status, or permission grants.
-   Do not add mock services or fake data to production code.
-   Do not create placeholder implementations, TODO-only stubs, empty
    success handlers, or "coming soon" behavior as a substitute for
    required functionality.
-   Do not rewrite or duplicate existing project, source-control, build,
    or `xcodebuild` infrastructure. Add adapters and stable facades
    around the real services.
-   Do not bypass host permission checks by allowing extension code to
    call internal services directly.
-   Do not expose internal SwiftUI views, ViewModels, database models,
    secrets, unrestricted filesystem paths, or private implementation
    types through the public SDK.
-   Do not give the extension arbitrary shell execution simply because
    it can request a build.
-   Do not let the extension self-approve capabilities or modify its
    granted permission set.
-   Do not make Assist available based on `assist.requested`, a package
    name, a developer-mode flag, or an extension's own claims.
-   Do not break existing SwiftCode workflows to make the SDK
    architecture easier.
-   Do not ask for confirmation at every phase or stop to present a plan
    when the repository contains enough information to proceed.
-   Do not add new Swift files without including them in the
    `.xcodeproj` if the repository uses explicit Xcode project file
    membership.
-   Do not add broad gradients, cards, shadows, or an iOS-style layout
    to macOS surfaces. Use native SwiftUI/AppKit patterns consistent
    with the existing application.

If a dependency, CLI, schema URL, package name, or API is only proposed
in this document, implement and verify it before describing it as
available.

------------------------------------------------------------------------

## 3. Scope and release boundaries

### 3.1 Required in the first usable release

-   Stable, versioned SDK contracts.
-   Manifest schema and validation.
-   Capability declarations, approval, grant storage, enforcement,
    revocation, and audit events.
-   TypeScript extension support with a real runtime integration.
-   A generated TypeScript extension project.
-   `source-control.read` backed by SwiftCode's real source-control
    service.
-   `build.execute` backed by SwiftCode's real build service, including
    live output, completion state, failure details, and cancellation
    where the underlying service supports it.
-   Extension lifecycle management: validate, start, activate,
    deactivate, stop, crash cleanup.
-   A structured and validated host/runtime communication protocol.
-   Local developer workflow and package validation.
-   Local extension install, disable, enable, uninstall, and
    update/reinstall behavior.
-   Standalone project templates and the same SDK/runtime foundation
    where appropriate.
-   Tests for positive behavior, denied permissions, malformed requests,
    failure paths, lifecycle, and existing app regressions.
-   Documentation explaining how to build, run, debug, package, and
    troubleshoot an extension.

### 3.2 Deliberately deferred unless repository evidence makes them low-cost and safe

-   Public extension marketplace.
-   Remote extension registry and automatic remote code execution.
-   Automatic extension updates from a server.
-   General-purpose arbitrary shell or process execution capability.
-   Automatic grants of broad filesystem/network/credential permissions.
-   Universal support for every language runtime.
-   Full Python extension parity. Python may be supported first for
    standalone projects, but extension runtime support requires its own
    reviewed adapter.
-   Complex extension-contributed native UI beyond the initial
    command-based contribution model.
-   Automatic use of Assist by extensions.
-   A third-party extension ecosystem with no local trust/install
    confirmation.

Do not silently expand the first release to include deferred features.

------------------------------------------------------------------------

## 4. Repository audit and architecture discovery

Perform this audit first. Search the repository rather than assuming a
class name from this document exists.

### 4.1 Find and document

-   Existing app targets, package targets, project structure, deployment
    target, and Swift version.
-   Existing instructions (`AGENTS.md`, build scripts, CI, tests, code
    style).
-   Project creation/opening and active-project selection.
-   Workspace root resolution and file access abstractions.
-   Source-control service: repository detection, status, diffs,
    branches, history, and errors.
-   Build service: target discovery, configuration, destination
    selection, `xcodebuild` invocation, output stream, process lifetime,
    cancellation, and result parsing.
-   Existing task/command registration and menu/toolbar/navigation
    contribution mechanisms.
-   Settings and persistence mechanisms, including where permission
    grants can be stored securely and reliably.
-   Existing process isolation, XPC, helper tools, sandboxing, and app
    entitlements.
-   Existing Assist entry points, credential access, model routing,
    session identity, and authorization logic.
-   Existing logging, telemetry, crash handling, and error presentation.
-   Test fixtures and integration-test strategy.

### 4.2 Architecture decision record

Create or update a short architecture document in the repository
recording:

-   What existing services will be wrapped.
-   Which target owns each public contract and adapter.
-   The selected TypeScript execution strategy and why it is compatible
    with the app's sandbox and deployment target.
-   How the host and extension communicate.
-   How permission grants are stored, scoped, revoked, and audited.
-   How local extension packages are installed and updated.
-   Which first-release limitations remain.

Do not assume that a Node.js executable is installed on every user's
Mac. Decide whether the supported development runtime is bundled,
installed as a managed dependency, or explicitly required only for
developer mode. Document the decision and test the missing-runtime path.
Do not download or execute arbitrary runtime binaries silently.

------------------------------------------------------------------------

## 5. Proposed repository organization

Adapt this layout to the existing project rather than forcing a
disruptive reorganization. Use actual project naming conventions.

``` text
SwiftCode/
├── SDK/
│   ├── Contracts/
│   │   ├── Manifest/
│   │   ├── Protocol/
│   │   ├── Capability/
│   │   └── Errors/
│   ├── Host/
│   │   ├── PublicAPI/
│   │   ├── CapabilityBroker/
│   │   ├── ExtensionRegistry/
│   │   └── ServiceAdapters/
│   ├── Runtime/
│   │   ├── Lifecycle/
│   │   ├── IPC/
│   │   ├── Isolation/
│   │   └── Diagnostics/
│   ├── Internal/
│   │   ├── SandboxBypass/
│   │   ├── TestHarness/
│   │   ├── SDKConfigStore/
│   │   └── DirectServiceAccess/
│   ├── Assist/
│   │   ├── Authorization/
│   │   └── Audit/
│   ├── TypeScript/
│   │   ├── package/
│   │   ├── cli/
│   │   ├── runtime-adapter/
│   │   └── templates/
│   └── Testing/
├── Templates/
│   ├── Extension-TypeScript/
│   ├── Standalone-Swift/
│   └── Standalone-TypeScript/
├── Examples/
│   └── RepositoryBuildExtension/
├── Documentation/
│   ├── SDK-Architecture.md
│   ├── Extension-Manifest.md
│   ├── Capabilities-and-Permissions.md
│   ├── TypeScript-Extensions.md
│   ├── Runtime-and-Security.md
│   └── Compatibility.md
└── Tests/
    ├── SDKContractsTests/
    ├── CapabilityBrokerTests/
    ├── RuntimeLifecycleTests/
    ├── TypeScriptExtensionIntegrationTests/
    └── ExistingAppRegressionTests/
```

Possible package names such as `@swiftcode/sdk` are proposed
identifiers. Before publishing or hardcoding them, check repository
conventions, npm scope ownership, and existing package configuration.
For the first release, a workspace-local package or generated local
dependency is acceptable, but it must be reproducible and must not
resolve to an unrelated public package.

### 5.1 Boundaries

-   **Contracts** contain protocol/data definitions and version
    negotiation, not UI or service implementation.
-   **Host** owns identity, active project resolution, authorization,
    API exposure, and service calls.
-   **Runtime** owns execution, lifecycle, message transport,
    quotas/timeouts, and cleanup.
-   **Service adapters** translate the stable public contract into
    existing SwiftCode services.
- **Internal (`SwiftCode/SDK/Internal/`)** contains internal SDK modules explicitly designed ONLY for internal SwiftCode developers.
  - **Purpose & Scope:** This directory is strictly reserved for internal SwiftCode engineers to manage the SDK, maintain and update APIs, ship new API functions/classes, manage element deprecations, handle SDK deployments, and make performance and structural improvements.
  - **API Management & Deployments:** Serves as the central hub for shipping new APIs, declaring deprecation notices for legacy functions/types, updating internal SDK configuration stores (`SwiftCodeSDK.json`), and driving automated SDK deployment pipelines.
  - **Sandbox Bypass & Testing Harness:** Features direct internal service bindings (`DirectServiceAccess`), high-privilege test harness drivers, and local debug hooks so internal developers can test, execute, and validate SDK code and API extensions directly without macOS App Sandbox restrictions or entitlement prompts during local development and automated testing.
  - **Distribution Guard:** Code under `SwiftCode/SDK/Internal/` is compiled exclusively for internal development/debug build configurations (`#if DEBUG || INTERNAL_BUILD`) and is completely stripped from public production builds to ensure strict security boundaries are maintained.
-   **Assist gate** owns restricted authorization checks and must not be
    bypassed by ordinary SDK methods.
-   **CLI** invokes documented host operations; it must not duplicate
    the host's authorization logic.
-   **Templates** must compile and validate against the actual SDK
    version shipped by the repository.

------------------------------------------------------------------------

## 6. Public SDK design principles

### 6.1 Stable public surface

The public API must be:

-   Versioned and explicitly documented.
-   Language-neutral at the protocol boundary.
-   Typed in TypeScript.
-   Independent of private app UI and persistence models.
-   Async-first for service operations.
-   Stream-aware for long-running work.
-   Cancellable where the underlying operation can be cancelled.
-   Explicit about permissions, scope, errors, and lifecycle.
-   Forward-compatible through optional fields and negotiated protocol
    versions.
-   Small enough that a new developer can understand the first extension
    quickly.

Avoid exposing raw `Process`, `NSWorkspace`, `FileManager`, private
database entities, internal ViewModels, or unrestricted service objects.
The public API should expose *intent-oriented operations*, not a generic
escape hatch.

### 6.2 Proposed TypeScript developer contract

The exact names and signatures must be finalized against actual
implementation, but the API should be similar in intent to the
following:

``` typescript
export interface SwiftCodeExtension {
  readonly id: string;
  activate(context: SwiftCodeContext): Promise<void>;
  deactivate(): Promise<void>;
}

export interface SwiftCodeContext {
  readonly extension: ExtensionInfo;
  readonly project: ProjectAPI;
  readonly sourceControl: SourceControlAPI;
  readonly build: BuildAPI;
  readonly commands: CommandAPI;
  readonly events: EventAPI;
  readonly log: Logger;
  readonly subscriptions: DisposableStore;
}

export interface ProjectAPI {
  getCurrent(): Promise<ProjectInfo | null>;
}

export interface SourceControlAPI {
  getStatus(): Promise<RepositoryStatus>;
  getDiff(options?: DiffOptions): Promise<RepositoryDiff>;
}

export interface BuildAPI {
  run(request: BuildRequest): Promise<BuildHandle>;
}

export interface BuildHandle {
  readonly id: string;
  readonly output: AsyncIterable<BuildOutputEvent>;
  wait(): Promise<BuildResult>;
  cancel(): Promise<void>;
}

export interface CommandAPI {
  register(command: CommandDefinition): Disposable;
}

export interface Disposable {
  dispose(): void;
}

export interface Logger {
  debug(message: string, fields?: Record<string, unknown>): void;
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}
```

This is a design target, not a claim that the API already exists.
Implement actual concrete data models, validation, errors, lifecycle
rules, and tests. Do not ship an interface-only SDK.

### 6.3 Required contract semantics

Document and test:

-   Whether `getCurrent()` can return `null`.
-   Behavior when no project is open.
-   Behavior when the project is not a source-control repository.
-   Diff size limits, binary files, untracked files, and truncation.
-   Build target/configuration/destination validation.
-   How build output is delivered and ordered.
-   How the final build status is determined.
-   Whether cancellation is best-effort and what happens if `xcodebuild`
    cannot be terminated.
-   Timeout semantics and whether the host or extension can choose
    timeouts.
-   Error codes, safe user-facing messages, and diagnostic correlation
    IDs.
-   What happens if an extension activates twice, crashes, times out, or
    deactivates during a build.
-   Whether command registration can be disposed and whether
    registrations are removed automatically on deactivation.
-   How protocol and SDK versions are negotiated.
-   Data-size limits and serialization constraints.

Never return a "successful" build result merely because a process was
launched. The final state must reflect the actual build service's
terminal result.

------------------------------------------------------------------------

## 7. Extension manifest

Use a strict JSON manifest named `swiftcode.json` unless repository
evidence establishes an existing naming convention.

### 7.1 Example manifest for the first extension

``` json
{
  "$schema": "./schemas/swiftcode-extension-v1.schema.json",
  "manifestVersion": 1,
  "id": "com.example.repository-build-extension",
  "name": "Repository Build Extension",
  "version": "0.1.0",
  "description": "Reads repository status and runs a SwiftCode-managed build.",
  "type": "extension",
  "runtime": {
    "language": "typescript",
    "entrypoint": "dist/index.js",
    "minimumSwiftCodeVersion": "1.0.0"
  },
  "sdk": {
    "name": "@swiftcode/sdk",
    "versionRange": "^1.0.0",
    "protocolVersion": 1
  },
  "capabilities": [
    {
      "id": "source-control.read",
      "reason": "Display repository status and diffs."
    },
    {
      "id": "build.execute",
      "reason": "Run builds through SwiftCode's managed build service."
    }
  ],
  "contributes": {
    "commands": [
      {
        "id": "inspect-repository",
        "title": "Inspect Repository"
      },
      {
        "id": "run-build",
        "title": "Build Current Project"
      }
    ]
  },
  "assist": {
    "requested": false
  }
}
```

All versions and the SwiftCode minimum-version value above are
provisional. Align them with the actual release version. The `$schema`
must point to a schema shipped with the SDK or a verified official URL;
do not leave a dead URL.

### 7.2 Manifest validation

Reject the manifest if:

-   JSON is malformed or has an unsupported manifest version.
-   Required fields are absent, incorrectly typed, blank, or over length
    limits.
-   Extension ID or contribution IDs are invalid or duplicated.
-   Entry point escapes the package root or resolves to a missing file.
-   Runtime language is unsupported.
-   SDK/protocol version is incompatible.
-   Capability IDs are unknown or malformed.
-   Contributions contain invalid IDs or duplicate commands.
-   Fields exceed bounded sizes or include unsupported executable
    configuration.
-   A package includes unexpected executable content outside the
    declared runtime/package rules.
-   Package contents contain path traversal, symlinks escaping the
    package root, or invalid file names.

Manifest validation does not establish package trust and does not grant
capabilities. A valid manifest is a request to the host, not an
authorization token.

### 7.3 Manifest compatibility

-   `manifestVersion` identifies the manifest schema generation.
-   `sdk.versionRange` identifies the supported SDK version range.
-   `protocolVersion` identifies the host/runtime IPC contract.
-   The host must explicitly reject unsupported incompatible versions
    with actionable diagnostics.
-   Do not silently reinterpret an unknown capability as a known
    capability.
-   Prefer additive optional fields for compatible evolution; use
    explicit major contract versions for breaking changes.

------------------------------------------------------------------------

## 8. Capability and permission model

Security is a core feature, not a later polish task.

### 8.1 Capability registry

Start with these capability IDs:

  ------------------------------------------------------------------------
  Capability               Intended scope          Explicitly does not
                                                   grant
  ------------------------ ----------------------- -----------------------
  `project.read`           Read safe metadata      File contents or
                           about the active        project mutation
                           project                 

  `workspace.read`         Read files within the   Access outside the
                           approved workspace      workspace
                           scope                   

  `workspace.write`        Write approved          Arbitrary filesystem
                           workspace files through access
                           a constrained API       

  `source-control.read`    Read repository status, Stage, commit,
                           diffs, branch and       checkout, reset, push
                           approved history        or other mutations
                           metadata                

  `source-control.write`   Perform explicitly      Arbitrary Git commands
                           supported               
                           source-control          
                           mutations               

  `build.execute`          Request builds through  Arbitrary shell/process
                           SwiftCode's managed     execution or
                           build service           unrestricted
                                                   build-setting injection

  `task.execute`           Invoke approved host    General process
                           task types              execution

  `network.request`        Make constrained        Arbitrary sockets,
                           network requests under  unrestricted
                           host policy             local-network access,
                                                   or credential theft

  `ui.contribute`          Register supported      Arbitrary native code
                           extension UI            injection
                           contributions           

  `credentials.use`        Use a narrowly scoped,  Read/export raw stored
                           host-mediated           secrets
                           credential for an       
                           approved service        

  `assist.invoke`          Request separately      Automatic access to
                           authorized Assist       Assist, user
                           operations              conversations, or all
                                                   models/tools
  ------------------------------------------------------------------------

The first TypeScript extension requests only `source-control.read` and
`build.execute`. It must not request any other capability.

### 8.2 Permission grant record

Represent a grant as a host-owned, persisted record containing at least:

-   Extension ID.
-   Installed package identity/version or package digest.
-   Capability ID.
-   Scope, such as active project/workspace or a specific approved
    project.
-   Grant timestamp.
-   Granting principal or approval source.
-   Optional expiration.
-   Revocation timestamp/status.
-   Policy/version at grant time.
-   Audit/correlation metadata.

------------------------------------------------------------------------

## 8.2.1 Built-in Developer API Key System

To ensure security, identity verification, and platform control, SwiftCode features a fully built-in Developer API Key System.

### Mandatory Authentication Requirements
- **App Creation & Publishing:** Users must create, configure, and authenticate with a valid Developer API Key in order to build, export, publish, or release apps targeting the SwiftCode platform.
- **Capability Access:** Privileged capabilities (such as network access, custom builds, credentials usage, and platform publishing) require an authenticated API Key with explicit scopes.
- **Key Format:** Developer API keys follow a cryptographically signed format prefix `sc_dev_live_...` or `sc_dev_test_...`.

### API Key Management Lifecycle
1. **Creation:** Users generate API keys via SwiftCode Studio preferences (`Studio -> Settings -> Developer API Keys`).
2. **Scopes & Entitlements:** Each API key can be assigned restricted scope entitlements (e.g. `apps:create`, `apps:publish`, `capabilities:request`).
3. **Keychain Storage:** Generated keys are stored securely on macOS using the System Keychain and are never logged or stored in plain text.
4. **Validation & Revocation:** Every platform action checks key validity against host policy. Users can instantly revoke or rotate keys from Studio settings, immediately invalidating active sessions using that key.

Use the existing secure persistence approach if appropriate. Do not
store API keys, passwords, or private credentials in the manifest or
extension package. Permission state must survive application restart
when expected, but revocation must be immediate at the authorization
boundary.

### 8.3 Approval UX

Before first activation requiring privileged capabilities:

1.  Validate the package and manifest.
2.  Show the extension identity and requested capabilities.
3.  Explain the practical effects in plain language.
4.  Clearly state that `build.execute` may run a potentially expensive
    build and that the host manages execution.
5.  Let the user approve or deny the requested set.
6.  Store only explicitly approved grants.
7.  Activate with the resulting scoped context.
8.  If denied, return a typed permission error and do not activate
    privileged functionality.

Do not bury permission prompts in generic settings or use ambiguous
"Allow everything" defaults. Do not prompt for capabilities the
extension did not request. A denied capability remains denied until the
user explicitly changes the grant.

### 8.4 Enforce at every host call

The host must verify on every privileged request:

-   The extension identity is registered and currently active.
-   The requested API maps to a known capability.
-   The capability is currently granted and not revoked/expired.
-   The request is within the granted project/workspace scope.
-   The request shape, target, and arguments are valid.
-   Resource and time limits are satisfied.
-   The service operation is supported by the actual host service.
-   The call is permitted by current policy.

Never rely on UI hiding, manifest declarations, TypeScript types, or
runtime convention as security controls. A malicious extension can send
arbitrary IPC messages; validate on the receiving side.

### 8.5 `source-control.read`

Allowed operations should initially be read-only, such as:

-   Determine whether the active project is a repository.
-   Read status.
-   Read a bounded diff.
-   Read branch identity or other safe metadata if supported.

Not allowed under this capability:

-   Stage/unstage.
-   Commit/amend.
-   Checkout/switch/reset/clean.
-   Push/pull/fetch if those operations mutate local state or contact
    remotes; classify remote-read operations separately if they are
    later introduced.
-   Run arbitrary Git commands.
-   Read Git credentials or private remote authentication state.

Map the API to existing SwiftCode source-control service methods. Do not
shell out to Git if the app already has a service that owns this
behavior.

### 8.6 `build.execute`

Allowed:

-   Ask SwiftCode's managed build service to build a validated
    target/configuration for the active project.
-   Observe bounded, structured build output and terminal status.
-   Request cancellation of the extension's own build handle.

Not allowed:

-   Arbitrary shell command or executable path.
-   Arbitrary environment-variable injection.
-   Reading build credentials or keychain items.
-   Changing unrelated projects.
-   Writing outside the approved build/output locations.
-   Disabling signing, sandbox, or security controls through an
    unrestricted argument field.

Build requests must use typed fields and host validation. Only add
destinations, schemes, custom build settings, or extra arguments when
there is a specific product need, safe validation, and tests.

### 8.7 Revocation and uninstall

-   Revocation takes effect at the host authorization boundary
    immediately.
-   Active operations should be cancelled where safe and supported.
-   The extension must not retain a direct reference that bypasses
    future checks.
-   Disabling/uninstalling an extension deactivates it, removes
    commands/contributions, closes streams, cancels eligible tasks,
    revokes session-scoped handles, and records an audit event.
-   Reinstalling or changing package content must not silently inherit
    grants for a different package identity. Re-evaluate grants when the
    package digest or publisher identity changes.

------------------------------------------------------------------------

## 9. Restricted Assist authorization

Assist is explicitly out of scope for this first extension. The host
must enforce that fact.

### 9.1 Required behavior

-   Do not include `assist` in the initial `SwiftCodeContext` public
    object.
-   Do not provide a general-purpose method that lets extensions reach
    internal Assist services.
-   Reject `assist.invoke` if requested by an untrusted or unauthorized
    extension.
-   Treat `"assist": {"requested": false}` as descriptive metadata only.
-   If an extension alters the manifest to request Assist, the host must
    still deny it unless the independent Assist authorization system
    grants it.
-   Do not infer authorization from a logged-in user, available model
    key, developer mode, extension signature, or previous grant for
    another capability.
-   Keep Assist authorization distinct from ordinary capability
    approval.
-   Log denied Assist attempts without exposing private conversation
    content, model credentials, or secret data.
-   Tests must verify that the first example extension cannot invoke
    Assist through public API, IPC, direct service resolution, or
    malformed requests.

### 9.2 Future authorization design

If Assist extensions are supported later, require a separate flow that
identifies:

-   Verified extension/package identity.
-   Specific Assist operations allowed.
-   User/project/session scope.
-   Explicit user consent.
-   Expiration and revocation.
-   Applicable rate, cost, and context limits.
-   Auditing and privacy boundaries.
-   Whether data may leave the device.

This must be designed and reviewed as a separate feature. Do not
implement a dormant bypass in the first release.

------------------------------------------------------------------------

## 10. Runtime architecture and isolation

### 10.1 Trust boundary

Treat all third-party extension code and package content as untrusted,
including locally installed code. Developer mode does not mean trusted
code.

Prefer an **out-of-process runtime** for TypeScript extensions. The
macOS app should remain responsive if an extension hangs or crashes. Do
not run untrusted extension code on the main thread.

If an out-of-process boundary cannot be implemented immediately, clearly
label in-process execution as a development-only limitation and do not
describe it as sandboxed. Do not ship a security claim that is not
supported by the actual OS/process design.

### 10.2 Host responsibilities

The host owns:

-   Package and manifest validation.
-   Extension identity and lifecycle state.
-   Capability approval, grants, revocation, and auditing.
-   Project/workspace scope resolution.
-   Service calls.
-   Runtime creation and termination.
-   IPC schema validation and protocol negotiation.
-   Per-extension resource limits.
-   Cancellation and timeout handling.
-   Logging and diagnostics.
-   Contribution registration and cleanup.
-   Version compatibility and package installation.

### 10.3 Runtime responsibilities

The runtime owns:

-   Loading only the validated declared entry point.
-   Activating/deactivating the extension.
-   Maintaining a controlled extension context.
-   Registering commands through host APIs.
-   Serializing requests and responses.
-   Streaming build output and lifecycle events.
-   Correlating requests, events, and results.
-   Reporting crashes and unhandled errors.
-   Respecting host shutdown and cancellation messages.
-   Cleaning up extension registrations and handles.

The runtime must not receive unrestricted internal service objects, raw
secret values, or unrestricted host filesystem access.

### 10.4 IPC protocol

Define a versioned request/response/event protocol. Every message should
include a protocol version, message type, request or operation ID where
applicable, and validated payload. Use bounded message sizes and reject
malformed/unknown privileged messages.

Illustrative envelope:

``` json
{
  "protocolVersion": 1,
  "type": "request",
  "requestId": "generated-correlation-id",
  "method": "sourceControl.getStatus",
  "payload": {}
}
```

Illustrative response:

``` json
{
  "protocolVersion": 1,
  "type": "response",
  "requestId": "generated-correlation-id",
  "ok": true,
  "payload": {}
}
```

Illustrative error:

``` json
{
  "protocolVersion": 1,
  "type": "response",
  "requestId": "generated-correlation-id",
  "ok": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "This extension has not been granted source-control.read.",
    "correlationId": "generated-correlation-id"
  }
}
```

These are examples, not a finalized wire schema. Implement a concrete
schema, schema validation, error taxonomy, compatibility negotiation,
and tests. Do not trust an extension-supplied identity field; bind
identity to the host-created runtime session and validate it at the IPC
boundary.

### 10.5 Lifecycle state machine

At minimum:

`discovered → validated → awaitingPermission → ready → starting → active → stopping → stopped`

Failure states should include validation failure, incompatible version,
denied permission, runtime launch failure, activation failure, crash,
timeout, and forced termination.

Requirements:

-   Invalid packages never activate.
-   Permission denial never produces an active privileged context.
-   Activation failure triggers best-effort deactivation and cleanup.
-   Double activation is rejected or made idempotent by a documented
    rule.
-   Deactivation disposes commands, event subscriptions, build handles,
    and other extension-owned resources.
-   Runtime crash marks the extension failed, removes its contributions,
    cancels eligible operations, and reports actionable diagnostics.
-   Restart behavior must be explicit; never enter an infinite
    crash/restart loop.
-   App shutdown must stop extensions within bounded time.

### 10.6 Resource controls

Implement reasonable configurable limits for:

-   Startup/activation time.
-   Individual host request duration.
-   Maximum IPC message size.
-   Maximum buffered output and diff size.
-   Number of concurrent builds per extension.
-   Number of outstanding requests.
-   Log message size and rate.
-   Runtime memory/CPU where the selected OS/runtime strategy can
    enforce it.

If a limit cannot be enforced by the selected runtime, document the
limitation accurately. Do not claim memory or CPU sandboxing merely
because a timeout exists.

------------------------------------------------------------------------

## 11. Source-control and build service integration

### 11.1 Reuse existing services

Inspect and reuse the existing source-control and build implementations.
Implement adapters that translate public SDK types into internal
requests and map internal responses/errors into stable public types.

The extension must not:

-   Construct private service instances independently.
-   Read internal databases directly.
-   bypass existing build-session tracking.
-   invoke raw `xcodebuild` directly from the TypeScript extension.
-   invent repository status or build output.
-   swallow errors and return empty success-shaped values.

### 11.2 Source-control API

Minimum public operation:

``` typescript
interface SourceControlAPI {
  getStatus(): Promise<RepositoryStatus>;
  getDiff(options?: DiffOptions): Promise<RepositoryDiff>;
}
```

Define `RepositoryStatus` with only necessary, stable data: repository
presence, branch if known, changed/untracked file summaries, and
relevant status counts. Define `RepositoryDiff` with bounded diff text
or structured changes and truncation metadata. Do not leak credentials,
raw environment data, or private internal models.

Error examples should be typed, such as:

-   `PROJECT_NOT_OPEN`
-   `NOT_A_REPOSITORY`
-   `PERMISSION_DENIED`
-   `SERVICE_UNAVAILABLE`
-   `REQUEST_TIMEOUT`
-   `INVALID_ARGUMENT`
-   `OUTPUT_TOO_LARGE`

Only use codes actually defined in the SDK error registry.

### 11.3 Build API

Minimum intent:

``` typescript
interface BuildAPI {
  run(request: BuildRequest): Promise<BuildHandle>;
}

interface BuildRequest {
  target: string;
  configuration?: string;
}

interface BuildHandle {
  readonly id: string;
  readonly output: AsyncIterable<BuildOutputEvent>;
  wait(): Promise<BuildResult>;
  cancel(): Promise<void>;
}
```

The exact contract may differ if the existing build service has a better
established model. Preserve these capabilities:

-   Start a build through the existing service.
-   Return a stable handle only after the service accepts the request.
-   Stream real output while the build runs.
-   Provide structured terminal state.
-   Preserve actionable failure information.
-   Support cancellation where possible.
-   Prevent one extension from cancelling another extension's build.
-   Associate each build with the initiating extension and project.
-   Clean up streams and processes when the extension stops.

Test successful builds, build failures, invalid targets, missing
project, missing runtime/toolchain, output streaming, cancellation, and
permission denial. Do not mark a build successful based only on process
launch or on the absence of a thrown exception.

------------------------------------------------------------------------

## 12. TypeScript package and project scaffold

### 12.1 Generated project structure

The generator should produce:

``` text
RepositoryBuildExtension/
├── swiftcode.json
├── package.json
├── tsconfig.json
├── README.md
├── .gitignore
├── src/
│   ├── index.ts
│   ├── extension.ts
│   └── commands/
│       ├── inspect-repository.ts
│       └── run-build.ts
├── tests/
│   ├── manifest.test.ts
│   └── extension.test.ts
├── schemas/
│   └── swiftcode-extension-v1.schema.json
└── dist/                       # generated build output; not hand-edited
```

The generator must produce a real compilable project using the actual
SDK package and actual supported CLI. It must not include mock
source-control or build implementations.

### 12.2 Proposed package configuration

``` json
{
  "name": "repository-build-extension",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "node --test",
    "validate": "swiftcode validate",
    "dev": "swiftcode dev"
  },
  "dependencies": {
    "@swiftcode/sdk": "USE_THE_ACTUAL_SUPPORTED_SDK_VERSION"
  },
  "devDependencies": {
    "@types/node": "USE_A_VERIFIED_COMPATIBLE_VERSION",
    "typescript": "USE_A_VERIFIED_COMPATIBLE_VERSION"
  }
}
```

The version strings above are intentionally instructions rather than
valid versions. The implementation agent must replace them with actual
compatible versions and ensure package installation is reproducible.
Prefer a lockfile. If the repository uses a local workspace package,
wire it through that workspace and document it. Do not publish or
resolve a fake package.

### 12.3 Proposed TypeScript configuration

``` json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "rootDir": "src",
    "outDir": "dist",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "declaration": true,
    "sourceMap": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["tests", "dist", "node_modules"]
}
```

Align this configuration with the actual runtime module system. If the
runtime uses a bundled format, update the config and entry-point rules
accordingly. Ensure generated `dist/index.js` exists before activation.

### 12.4 Extension entry point

The final implementation should expose the extension using the real
SDK's chosen entry-point contract. Conceptually:

``` typescript
import type {
  SwiftCodeContext,
  SwiftCodeExtension
} from "@swiftcode/sdk";

const registrations: { dispose(): void }[] = [];

const extension: SwiftCodeExtension = {
  id: "com.example.repository-build-extension",

  async activate(context: SwiftCodeContext): Promise<void> {
    try {
      registrations.push(
        context.commands.register({
          id: "inspect-repository",
          title: "Inspect Repository",
          execute: async () => {
            const status = await context.sourceControl.getStatus();
            context.log.info("Repository status retrieved", {
              isRepository: status.isRepository
            });
            return status;
          }
        })
      );

      registrations.push(
        context.commands.register({
          id: "run-build",
          title: "Build Current Project",
          execute: async () => {
            const handle = await context.build.run({
              target: "APPROVED_TARGET_FROM_HOST_PROJECT"
            });

            for await (const event of handle.output) {
              // Send structured output to the extension's registered UI/log surface.
              // Do not fabricate output or silently discard errors.
              context.log.info(event.message);
            }

            return await handle.wait();
          }
        })
      );
    } catch (error) {
      for (const registration of registrations.splice(0)) {
        registration.dispose();
      }
      throw error;
    }
  },

  async deactivate(): Promise<void> {
    for (const registration of registrations.splice(0)) {
      registration.dispose();
    }
  }
};

export default extension;
```

This is illustrative, not copy-and-ship code. The agent must resolve
several contract details before finalizing the example:

-   Command result serialization and display.
-   How the selected project/build target is obtained safely.
-   How streaming and `wait()` interact without consuming the stream
    twice.
-   Whether the build handle is automatically cancelled during
    deactivation.
-   Error reporting and typed errors.
-   Correct command contribution API and disposable lifecycle.

The generated extension must use a real, safe method for selecting a
valid build target from the host project; it must not hardcode a target
that may not exist.

### 12.5 Testing generated projects

Automated tests must:

-   Parse and validate the manifest.
-   Reject invalid capability names.
-   Verify the initial capability set is exactly `source-control.read`
    and `build.execute`.
-   Verify Assist is not requested.
-   Compile the generated project with the supported TypeScript
    compiler.
-   Verify the entry point exists and matches the manifest.
-   Exercise activation and deactivation through the actual runtime test
    harness.
-   Verify command registrations are disposed.
-   Verify missing permissions result in typed denial.
-   Verify real service errors are surfaced instead of converted to fake
    success.
-   Verify package validation rejects path traversal and unsupported
    files.

Use test doubles only at the unit-test boundary where necessary;
integration tests must use real host service adapters and must not claim
to prove real integration if they only use mocks.

------------------------------------------------------------------------

## 13. CLI and developer experience

Provide a consistent CLI, either as a small SwiftCode-managed CLI or
through the existing app/developer tooling. The command names below are
proposed; implement and test them before documenting them as available.

### 13.1 Required workflows

Create an extension:

``` sh
swiftcode create --type extension --language typescript
```

Create a standalone Swift project:

``` sh
swiftcode create --type project --language swift
```

Create a standalone TypeScript project:

``` sh
swiftcode create --type project --language typescript
```

Validate an extension:

``` sh
swiftcode validate
```

Run a local development session:

``` sh
swiftcode dev
```

Build and package the extension:

``` sh
swiftcode package
```

Install a local package:

``` sh
swiftcode install ./dist/repository-build-extension.swiftcode-extension
```

The package suffix is a proposed convention. Define one actual package
format and validate it consistently.

### 13.2 CLI behavior

-   Clear nonzero exit codes on validation/build/package failures.
-   Human-readable errors plus an optional machine-readable mode.
-   No secret values in output.
-   No silent network downloads or arbitrary script execution during
    validation.
-   `dev` watches only intended source/config files, recompiles,
    revalidates, and restarts safely.
-   Avoid duplicate runtime sessions or duplicate command registrations
    during reload.
-   Preserve logs and error correlation IDs.
-   Provide a clean stop mechanism and handle Ctrl-C.
-   Clearly distinguish compile success, manifest validity, runtime
    activation, and permission approval.
-   Never print "installed" or "running" until the host confirms that
    state.

If the app is the only supported interface initially, implement
equivalent workflows through the UI and provide CLI only where it can be
genuinely supported. Do not add dead CLI stubs.

### 13.3 Studio UI & Strict Project Creation Boundaries

SwiftCode Studio (`Studio`) is a dedicated, separate user interface component tailored specifically for platform developers working with the SwiftCode SDK.

#### Exclusive Project Creation Boundary
- **Exclusive Creation Hub:** Studio is the **ONLY** UI surface where users are permitted to create projects targeting the SwiftCode platform and using the SwiftCode SDK.
- **Main Editor Exclusion:** Users **may NOT create SwiftCode platform/SDK projects using the main code editor UI**. The main editor is restricted strictly to editing code, navigating workspaces, and viewing existing active files.
- **Enforcement:** Creation templates, new project wizards, and platform scaffolding options are completely disabled and removed from the main editor file/menu interfaces. Selecting "New SwiftCode Project" or "New Extension" automatically redirects the user to the dedicated SwiftCode Studio UI.

#### Core Studio Capabilities
- **Project & Extension Generation:** Guided creation wizard for SwiftCode SDK extensions and standalone platform projects.
- **Developer API Key Management:** Dedicated UI to generate, manage, scope, and revoke Developer API Keys required for app creation and publishing.
- **Manifest & Capability Inspector:** Visual manifest builder (`swiftcode.json`), capability declaration editor, and grant manager.
- **Extension Lifecycle Console:** Local extension manager to test, enable, disable, update, package, and uninstall extensions.
- **Dual Logging Inspector:** Integrated viewer providing access to user-facing logs and high-verbosity developer logs (`~/.swiftcode/logs/developer-sdk.log`).

Use native macOS SwiftUI/AppKit patterns and existing design language. No decorative buttons that do nothing, fake loading states, fake status, or empty success pages. If a function cannot be completed, do not expose it as working.

------------------------------------------------------------------------

## 14. Standalone projects and language adapters

The SDK platform must support both standalone projects and extensions,
but these are different execution products.

### 14.1 Standalone projects

A standalone project is user-owned code and may use the language's
ordinary development/build workflow. The SDK may provide project
metadata, templates, build adapters, and integration with SwiftCode
services, but it should not impose extension sandbox restrictions on the
user's own application beyond normal product security.

Initial templates:

-   Swift standalone project using SwiftUI/AppKit as appropriate.
-   TypeScript standalone project with a verified toolchain and
    run/build workflow.

### 14.2 Extensions

Extensions are untrusted code running under host-defined capability
controls. Do not equate a standalone project's process privileges with
an extension's privileges.

Initial extension language: TypeScript.

Future extension runtimes must implement the same language-neutral
protocol, capability broker, scope checks, lifecycle, and error
semantics. Each runtime adapter requires independent tests and a
security review.

### 14.3 Swift support

Swift may be used to implement the host and standalone Swift projects.
If native Swift extensions are later allowed in-process, acknowledge
that native code loaded into the host process cannot be reliably
sandboxed from the host's memory and privileges. Do not grant native
extensions untrusted status while claiming a process-level security
boundary that does not exist.

### 14.4 Python support

Python standalone projects can be considered after the core SDK and
TypeScript extension are stable. Do not claim Python extension support
until a runtime adapter, packaging rules, protocol conformance, and
permission-enforcement tests exist.

------------------------------------------------------------------------

## 15. Error model and diagnostics

Implement a centralized error taxonomy with stable codes, user-safe
messages, and optional diagnostic metadata.

Required categories include:

-   Manifest/schema validation.
-   Unsupported SDK or protocol version.
-   Package integrity/trust failure.
-   Permission denied/revoked/expired.
-   Project missing or out of scope.
-   Source-control service unavailable or not a repository.
-   Invalid build target/configuration.
-   Build failed/cancelled/timed out.
-   Runtime launch/activation/deactivation/crash.
-   IPC malformed message/protocol mismatch/request timeout.
-   Resource limit exceeded.
-   Package install/update/uninstall failure.
-   API Key authentication / scope failure.

Each error should have:

-   Stable machine-readable code.
-   Safe message.
-   Optional actionable suggestion.
-   Correlation ID.
-   Structured internal diagnostics where appropriate.
-   No secrets or private user content by default.

Do not catch and suppress errors merely to keep the UI quiet. Surface
actionable errors without dumping secrets or excessive internal details.

------------------------------------------------------------------------

## 16. Dual Error Logging Systems and Audit

The SDK architecture enforces a strict dual error logging system that completely separates end-user logging from developer-facing error logging.

### 16.1 User-Facing Error Logging System

The user-facing error logging system provides clean, actionable, non-technical error reports designed specifically for end users and application creators:

-   **Complete Sanitization:** Automatically strips all internal raw stack traces, memory addresses, host filesystem paths, IPC frame payloads, internal engine exception traces, and security-sensitive tokens.
-   **Actionable & Friendly Messaging:** Replaces raw low-level exception dumps with clear, human-readable explanations and actionable guidance (e.g., *"Build Failed: Target 'App' has syntax errors on line 12. Fix the syntax error in main.swift and rebuild."*).
-   **Unique Correlation IDs:** Generates a short, unique correlation ID (e.g., `ERR-8F3A29`) for every error event. Users can quote this ID when filing support tickets or cross-referencing developer diagnostic logs.
-   **User UI Integration:** Surfaced cleanly in the main SwiftCode workspace status bar, Studio notification popovers, user-facing Activity Console, and lightweight alert banners.

### 16.2 Developer-Facing Error Logging System

The developer-facing error logging system is a dedicated, high-verbosity diagnostic logging pipeline built exclusively for SwiftCode SDK developers, internal maintainers, and extension creators:

-   **Deep Diagnostic Telemetry:** Captures complete unredacted stack traces, unhandled promise rejections, full IPC message envelopes, raw stdin/stdout/stderr streams, exact process exit codes, CPU/RAM resource usage metrics, and runtime sandbox policy enforcement logs.
-   **Isolated Log Storage & Debug Console:** Writes full diagnostic traces to an isolated log file on disk (`~/.swiftcode/logs/developer-sdk.log`) and streams live events to the internal Developer Debug Console tab within Studio and internal builds.
-   **Bi-Directional Correlation Mapping:** Maps every detailed diagnostic log entry back to the user-facing `ERR-*` correlation ID, enabling internal engineers to pinpoint root causes instantly.
-   **Internal SDK Execution Telemetry:** Collects full operational and execution telemetry when running internal SDK tests and sandbox-bypass harness drivers (`SwiftCode/SDK/Internal/`).

### 16.3 Security audit events

Record significant permission, authentication, and trust actions in a durable, tamper-resistant host log:

-   API key creation, rotation, authentication, and scope failures.
-   Permission requested, granted, denied, or revoked.
-   Assist access requests and denials.
-   Package installed, updated, disabled, or uninstalled.
-   Runtime terminated due to policy, crash, or memory violation.

Audit records should be durable enough for troubleshooting,
privacy-conscious, and protected against modification by extensions. The
extension must not be able to delete or rewrite host security records.

------------------------------------------------------------------------

## 17. Packaging, installation, and integrity

Define one deterministic package format for the first release. It may be
a ZIP-like archive with a documented extension suffix, but the exact
format is an implementation decision.

The package must include:

-   Manifest.
-   Compiled runtime entry point.
-   Required runtime assets.
-   Package metadata and, if implemented, a cryptographic digest.
-   No undeclared external paths or required files outside the package.

The packaging process must:

-   Compile from source.
-   Validate the manifest.
-   Validate the entry point and included files.
-   Reject path traversal and unsafe symlinks.
-   Produce reproducible, inspectable package contents.
-   Report the output path and digest only after creation succeeds.
-   Never include developer credentials, local `.env` secrets, caches,
    or `node_modules` unless the runtime/package format explicitly
    requires and validates them.

The installation process must:

-   Inspect and validate before activation.
-   Show the identity and requested capabilities.
-   Install to a controlled extension directory.
-   Record package identity/version/digest.
-   Avoid overwriting another extension with the same ID without an
    explicit update flow.
-   Roll back to the previous package on a failed update where feasible.
-   Revalidate compatibility and permissions after update.
-   Remove registrations and runtime state when uninstalling.

Do not implement a marketplace or remote auto-updater in this phase.

------------------------------------------------------------------------

## 18. Versioning, Compatibility, and Internal `SwiftCodeSDK.json`

Use semantic versioning for public SDK packages where applicable.
Maintain separate version concepts:

-   SwiftCode application version.
-   SDK package version.
-   Manifest schema version.
-   Host/runtime protocol version.
-   Extension package version.

Do not treat these as interchangeable.

### 18.1 Internal `SwiftCodeSDK.json` Manifest & Automatic Propagation

Internal SwiftCode developers update and manage the canonical SDK version metadata via `SwiftCodeSDK.json` located within the Internal SDK configuration path (`SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json`).

#### Structure of `SwiftCodeSDK.json`:

``` json
{
  "sdkVersion": "1.2.0",
  "apiVersion": "2025.1",
  "minimumHostVersion": "1.0.0",
  "protocolVersion": 1,
  "releaseNotes": [
    "Added Developer API Key authentication system.",
    "Introduced dual error logging architecture.",
    "Added internal SDK sandbox-bypass harness for developers."
  ],
  "updateTimestamp": "2025-05-15T08:00:00Z",
  "deprecatedAPIs": []
}
```

#### Automatic Update Propagation to User Projects:

-   **Internal Developer Managed:** Internal developers update `SwiftCodeSDK.json` whenever modifying SDK interfaces, adding capabilities, or issuing release notes.
-   **Automatic Synchronization:** Upon application launch or SDK updates, SwiftCode scans existing user projects created via Studio and checks their local project SDK manifest against `SwiftCodeSDK.json`.
-   **Seamless Upgrade Pipeline:** When a newer SDK version is detected in `SwiftCodeSDK.json`, SwiftCode automatically updates project-level SDK definitions, type declaration files (`@swiftcode/sdk`), and runtime bindings in user projects while displaying release notes in the Studio notification panel.
-   **Backward Compatibility:** Standard breaking change guards apply; non-breaking minor/patch updates propagate automatically, while major breaking updates prompt the user in Studio with release notes before completing migration.

### 18.2 Compatibility Requirements

-   Validate minimum SwiftCode version.
-   Negotiate the host/runtime protocol version.
-   Reject incompatible SDK ranges with a clear error.
-   Keep old manifest parsing tests for supported versions.
-   Define deprecation policy for public APIs.
-   Add compatibility tests before removing or changing public fields.
-   Pin reproducible toolchain/package versions for CI and generated
    projects.

------------------------------------------------------------------------

## 19. Testing and verification

Testing must include unit, integration, lifecycle, security, packaging,
and regression coverage.

### 19.1 Contract tests

-   Manifest valid/invalid cases.
-   Schema version and compatibility.
-   Unknown capability rejection.
-   Duplicate ID rejection.
-   Entry point path traversal.
-   Oversized fields/messages.
-   Protocol version mismatch.
-   Stable error serialization.

### 19.2 Capability tests

-   Granted `source-control.read` succeeds through the real adapter.
-   Missing/revoked `source-control.read` is denied.
-   Granted `build.execute` can start only a valid host-managed build.
-   Missing/revoked `build.execute` is denied.
-   `source-control.read` cannot stage, commit, or mutate a repository.
-   `build.execute` cannot execute an arbitrary shell command.
-   Cross-project access is denied.
-   Extension cannot grant itself permissions.
-   Forged IPC identity is rejected.
-   Permission revocation affects active sessions.
-   Assist access is denied across every exposed route.

### 19.3 Runtime tests

-   Successful startup and activation.
-   Invalid entry point.
-   Activation exception.
-   Runtime crash.
-   Double activation.
-   Deactivation and cleanup.
-   Duplicate command prevention.
-   Timeout and cancellation.
-   Malformed IPC.
-   Message-size limits.
-   Shutdown while a build is active.
-   No orphaned processes/streams after failure.

### 19.4 Real integration tests

-   Open a real test repository and retrieve actual status.
-   Retrieve an actual bounded diff.
-   Run a build through SwiftCode's existing build service.
-   Observe output before terminal completion.
-   Confirm terminal success/failure/cancellation reflects the
    underlying build service.
-   Deny permission and verify the service was not called.
-   Revoke permission during a session and verify subsequent calls fail.
-   Install, activate, disable, update, and uninstall a locally built
    extension.

### 19.5 Regression gates

Run the existing project build and test suite. Exercise project
open/create, source control, existing build workflows, Assist behavior
for normal authorized app use, settings, and navigation. The SDK must
not alter the behavior of existing users or silently route existing
workflows through extension permissions.

Report pre-existing failures separately. Do not claim all tests passed
unless the commands actually ran and passed.

------------------------------------------------------------------------

## 20. Implementation phases

Execute these phases in order, but continue autonomously rather than
stopping after each phase for user approval.

### Phase 0 --- Audit and baseline

-   Read repository instructions and inspect existing architecture.
-   Map existing project, source-control, build, permissions, runtime,
    and Assist services.
-   Build and test the existing application.
-   Record baseline failures.
-   Write/update the architecture decision record.
-   Choose the runtime and IPC strategy based on real platform
    constraints.

**Exit gate:** documented real service entry points, tested baseline, no
guessed service APIs.

### Phase 1 --- Contracts and manifest

-   Define versioned manifest schema.
-   Define public data contracts, error taxonomy, protocol envelopes,
    and compatibility rules.
-   Add schema validator and package path validation.
-   Add unit tests for valid and invalid packages.
-   Add the exact first-extension manifest with only two requested
    capabilities and no Assist request.

**Exit gate:** manifest validation is real, deterministic, and
thoroughly tested.

### Phase 2 --- Capability broker and permission storage

-   Implement registry of supported capabilities.
-   Implement user-facing approval/denial flow.
-   Implement persisted scoped grants and revocation.
-   Enforce authorization at each host API entry point.
-   Add audit events and permission UI.
-   Add tests for forged calls, denial, revocation, scope, and
    unsupported capabilities.

**Exit gate:** no privileged operation can bypass the broker; Assist
remains inaccessible.

### Phase 3 --- Host service adapters

-   Wrap the existing source-control service.
-   Wrap the existing build service.
-   Define stable public models and map errors.
-   Add bounded output streaming and cancellation.
-   Ensure operations are attributed to extension and project identity.
-   Test real services and failure cases.

**Exit gate:** read-only repository inspection and a managed build work
with real data.

### Phase 4 --- Runtime and lifecycle

-   Implement the selected out-of-process TypeScript runtime strategy.
-   Implement versioned IPC and runtime session identity.
-   Implement start/activate/deactivate/stop/crash handling.
-   Implement timeouts, request limits, correlation IDs, and cleanup.
-   Prevent main-thread blocking and orphaned processes.
-   Test runtime lifecycle and malformed messages.

**Exit gate:** extension can be activated and stopped reliably without
exposing internal service objects.

### Phase 5 --- TypeScript SDK and scaffold

-   Implement the real `@swiftcode/sdk` package or verified local
    package equivalent.
-   Implement command registration, source-control reads, build handles,
    streaming, errors, and logging.
-   Implement the generator and a complete TypeScript template.
-   Compile and validate the generated example.
-   Test real activation and cleanup.

**Exit gate:** a newly generated extension compiles and runs against
actual SwiftCode services.

### Phase 6 --- CLI and local package workflow

-   Implement supported `create`, `validate`, `dev`, `package`, and
    `install` workflows (or documented native UI equivalents where
    appropriate).
-   Add deterministic packaging, local installation, update, disable,
    and uninstall.
-   Handle missing runtime/toolchain and package failures cleanly.
-   Add end-to-end tests.

**Exit gate:** a developer can create, compile, validate, install, run,
disable, and remove an extension without hand-editing internal files.

### Phase 7 --- Studio and standalone templates

-   Integrate project/extension creation with existing SwiftCode
    navigation.
-   Add or adapt management, permission, lifecycle, logs, and
    build-output surfaces.
-   Add Swift and TypeScript standalone project templates.
-   Reuse the SDK contracts where meaningful without forcing standalone
    projects into the extension sandbox.
-   Ensure every visible control has real behavior.

**Exit gate:** extension and standalone project flows are coherent,
native, and regression-tested.

### Phase 8 --- Security, compatibility, and release hardening

-   Review every privileged host call.
-   Verify Assist isolation.
-   Test package tampering, path traversal, identity spoofing,
    revocation, and crash cleanup.
-   Validate resource limits and process isolation claims.
-   Run full build/tests and regression suite.
-   Update developer documentation and examples.
-   Provide a concise final report with files changed, real commands
    run, test outcomes, known limitations, and any blocker.

**Exit gate:** all release gates below pass or remaining blockers are
explicitly documented without claiming completion.

------------------------------------------------------------------------

## 21. Definition of done

The SDK is not complete until all applicable items below are true.

### Platform

-   [ ] Public contracts and protocol are versioned and documented.
-   [ ] Manifest schema and validator are implemented.
-   [ ] Unknown/incompatible versions fail clearly.
-   [ ] Runtime lifecycle and cleanup are reliable.
-   [ ] Host/runtime IPC is validated and bounded.
-   [ ] Capability checks are enforced on every privileged call.
-   [ ] Permission grants are scoped, persisted, and revocable.
-   [ ] Security audit events are host-owned.
-   [ ] Assist is inaccessible to the first extension.

### TypeScript extension

-   [ ] Generated project has a valid manifest.
-   [ ] Generated project compiles using verified dependencies.
-   [ ] Source-control status comes from the real SwiftCode service.
-   [ ] Build runs through the real SwiftCode build service.
-   [ ] Build output streams while the operation is running.
-   [ ] Success, failure, timeout, and cancellation are represented
    truthfully.
-   [ ] Commands and subscriptions are disposed on deactivation.
-   [ ] No mocked production responses or placeholder handlers exist.

### Developer experience

-   [ ] Creation, validation, development, packaging, and local install
    workflows are implemented.
-   [ ] Runtime and dependency failures are actionable.
-   [ ] Permission requests are clear and user-controlled.
-   [ ] Enable/disable/uninstall removes runtime state correctly.
-   [ ] Documentation is accurate and tested against actual behavior.
-   [ ] Standalone project support remains distinct from extension
    privileges.

### Security and regression

-   [ ] Permission denial prevents the service call.
-   [ ] Revocation blocks future calls.
-   [ ] Cross-project scope violations are denied.
-   [ ] Arbitrary shell execution is not exposed through
    `build.execute`.
-   [ ] Assist cannot be reached through direct API or malformed IPC.
-   [ ] No credentials are bundled or leaked into logs.
-   [ ] Existing SwiftCode project/build/source-control/Assist workflows
    pass regression tests.
-   [ ] The final report distinguishes completed work, test results,
    pre-existing failures, and known limitations.

------------------------------------------------------------------------

## 22. Expected final report from the implementation agent

At completion, report:

1.  **Architecture implemented:** actual targets/modules and their
    responsibilities.
2.  **Existing services reused:** concrete service names and adapter
    mapping.
3.  **Runtime strategy:** how TypeScript executes, process boundary, and
    limitations.
4.  **Permission model:** grant storage, approval flow, revocation, and
    host enforcement.
5.  **Assist isolation:** tests and evidence that the extension cannot
    access it.
6.  **Developer workflow:** exact commands or UI paths that were
    implemented and verified.
7.  **Files changed:** concise grouped list.
8.  **Build/test commands:** exact commands executed and their results.
9.  **Integration evidence:** real source-control read and real build
    path tested.
10. **Known limitations:** only verified remaining limitations; no vague
    "future work" used to hide incomplete requirements.
11. **Regressions:** any existing failures and any new failures.
12. **Security gaps:** anything not fully enforced; do not label the
    release production-ready if a critical boundary remains
    unimplemented.

------------------------------------------------------------------------

## 23. Final implementation directive

Build the smallest complete, secure, real end-to-end SDK platform rather
than a broad but hollow framework.

The first milestone must prove this full path:

1.  A developer creates a TypeScript extension project.
2.  SwiftCode validates its manifest and package.
3.  SwiftCode explains and requests only `source-control.read` and
    `build.execute`.
4.  The user can approve or deny them.
5.  The extension starts in the selected runtime.
6.  The extension reads real repository status through the
    host-controlled source-control service.
7.  The extension requests a real build through the existing SwiftCode
    build service.
8.  The developer sees live build output and a truthful terminal result.
9.  Denied or revoked capabilities fail at the host boundary.
10. The extension cannot invoke Assist, run arbitrary shell commands, or
    escape its project scope.
11. Disabling or uninstalling it cleans up commands, streams, processes,
    and grants as specified.
12. Existing SwiftCode workflows continue to work.

Use the repository's actual architecture, not assumptions in this
document, to select concrete types and implementation details. Where
this document gives a proposed name or sample interface, treat it as a
design requirement to realize---not evidence that the symbol or service
already exists. Finish implementation, run real tests, update
documentation, and report verified outcomes.
