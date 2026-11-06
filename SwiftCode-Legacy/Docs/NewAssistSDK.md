PROJECT: SwiftCode-Mac
SUBSYSTEM: SwiftCode Assist
INITIATIVE: Assist with Meta + Assist Architecture Modernization
PRIORITY: HIGH
EXECUTION MODE: AUTONOMOUS IMPLEMENTATION
TARGET PLATFORM: macOS
PRIMARY LANGUAGE: Swift
EXTERNAL SDK: Muse Code SDK 1.4
OFFICIAL DOCUMENTATION:
https://meta-models.github.io/muse-code-sdk/1.4/guides/quickstart/

============================================================
0. EXECUTIVE DIRECTIVE
============================================================

You are working directly inside the existing SwiftCode-Mac repository.

Your assignment is to expand SwiftCode Assist by integrating a new
AI provider, restructuring the Assist Settings architecture, and
rebuilding the lifecycle ownership of the Google Cloud SDK Engine.

The new provider must be presented to users as:

    Assist with Meta

It is powered internally by the Muse Code SDK.

The SDK's underlying product name must NEVER appear in the
user-facing application interface. The provider's public identity
is exclusively "Assist with Meta".

This is not a cosmetic change, a provider-picker addition, or a
prototype.

You must deliver a complete integration into the existing Assist
system, including provider registration, authentication, model
discovery, request execution, response streaming, tool execution
where supported, error handling, cancellation, session handling,
settings integration, and runtime lifecycle management.

You must also restructure the existing Assist Settings interface
so its architecture controls are simplified and its independent
configuration options are placed into a separate card.

Finally, the Google Cloud SDK Engine must become a mandatory,
application-managed service that starts automatically during
application startup and cannot be manually disabled or shut down
through user-facing controls.

The final result must be a cohesive, production-oriented Assist
implementation that feels native to SwiftCode rather than an
external tool bolted onto the application.

============================================================
1. THE END GOAL
============================================================

The end goal is to evolve Assist into a more cohesive, extensible,
reliable, and consistently managed coding-agent platform.

After implementation, the following must be true.

1.1 ASSIST WITH META IS A REAL PROVIDER

Users can select "Assist with Meta" through the appropriate
existing Assist provider-selection workflow.

The provider uses the actual Muse Code SDK rather than a
custom imitation of its behavior.

The integration follows the SDK's documented capabilities,
authentication mechanism, runtime requirements, and API
contracts.

It participates in the existing Assist conversation lifecycle
instead of implementing an unrelated chat system.

1.2 AUTHENTICATION IS INTEGRATED INTO THE APPLICATION

The application detects whether the required CLI is installed.

If it is missing, the application can perform the documented
installation procedure when appropriate.

If valid CLI credentials already exist, the application reuses
them through the SDK's supported authentication mechanism.

If authentication is missing or expired, the application can
initiate the documented authentication workflow through a
reusable Swift Process helper.

Users must not be forced to configure a separate API key when
the documented SDK authentication mechanism supports reuse of
their existing CLI credentials.

Authentication must be secure, asynchronous, observable, and
independent of unrelated provider functionality.

1.3 ASSIST SETTINGS HAS A CLEAR ARCHITECTURE

The "Assist System Architecture" card contains exactly two
options:

- Native Assist System
- Assist on Google Cloud

The "Google Cloud SDK Engine" settings card is removed from the
user interface.

The engine nevertheless starts automatically and remains under
application-level lifecycle management.

A separate configuration card contains:

- Assist Toolkit
- Model Routing Strategy
- Use SwiftCloud Models

These options retain their existing behavior and persisted
configuration.

1.4 THE ENGINE IS APPLICATION-MANAGED

The Google Cloud SDK Engine starts automatically on every normal
application launch.

Its startup does not depend on the user opening Assist Settings,
selecting a provider, or sending a message.

Users cannot manually stop, disable, or turn off the engine
through the application.

The application still handles normal termination, crashes,
startup failures, recovery, and resource cleanup correctly.

1.5 THE EXISTING ASSIST SYSTEM REMAINS FUNCTIONAL

Existing providers, conversations, routing behavior, tools,
authentication flows, and settings must remain operational.

The new provider must not break unrelated providers.

The new engine lifecycle must not create duplicate processes.

The settings reorganization must not silently discard valid
user preferences.

1.6 THE IMPLEMENTATION IS VERIFIED

The final code must be integrated into the actual Xcode project,
build successfully where the environment permits, and pass
relevant tests.

Live SDK behavior must be tested when credentials, network access,
and runtime prerequisites permit.

A successful compilation alone is not sufficient evidence that
the provider works.

============================================================
2. NON-NEGOTIABLE ENGINEERING PRINCIPLES
============================================================

2.1 AUDIT BEFORE EDITING

Read AGENTS.md and all applicable repository instructions.

Inspect the existing architecture before deciding how to
implement the requested changes.

Trace actual execution paths rather than inferring behavior
from filenames or comments.

Do not replace working abstractions without a concrete technical
reason.

2.2 DOCUMENTATION BEFORE SDK IMPLEMENTATION

Read the complete relevant Muse Code SDK 1.4 documentation.

Do not implement against guessed APIs, undocumented assumptions,
or remembered interfaces from another SDK version.

Follow relevant links until the documented installation,
authentication, model, execution, streaming, tool-calling,
configuration, runtime, and troubleshooting surfaces have
been reviewed.

2.3 PLAN, THEN EXECUTE

Create an execution plan using the repository's established
execution-plan mechanism.

If WriteExecutionPlan.md or another required planning asset
exists, follow it.

Once the plan is complete, immediately begin implementation.

Do not pause for user approval between phases.

Maintain agent_notes.md or the repository's required equivalent
if the project requires task-level execution notes.

Do not bundle temporary planning files into the application.

2.4 IMPLEMENT REAL FUNCTIONALITY

Do not substitute mock behavior for production functionality.

Do not create placeholder providers, fake model catalogs,
simulated streaming, fabricated authentication states, or
buttons without working actions.

Do not report success before an operation has actually succeeded.

Do not add empty implementations merely to satisfy the compiler.

2.5 PRESERVE EXISTING BEHAVIOR

Prefer targeted changes that integrate with existing systems.

Do not redesign unrelated portions of SwiftCode.

Preserve valid persisted settings and existing provider behavior.

2.6 VERIFY EVERY CLAIM

Distinguish between code that was implemented, code that compiled,
tests that passed, and functionality verified against the real
SDK.

Never claim successful live integration without evidence.

============================================================
3. PHASE ZERO — REPOSITORY RECONNAISSANCE
============================================================

Before modifying source code, map the existing implementation.

3.1 REPOSITORY INSTRUCTIONS

Locate and read:

- AGENTS.md.
- Any nested AGENTS.md files relevant to Assist.
- Existing implementation guidelines.
- Execution-plan instructions.
- Testing instructions.
- Build and project-configuration conventions.
- Relevant architecture or SDK documentation maintained
  inside the repository.

Follow all applicable repository requirements.

3.2 ASSIST ARCHITECTURE

Identify the concrete source files responsible for:

- Assist's main interface.
- Conversation state.
- Message models.
- Request execution.
- Model-provider abstractions.
- Provider registration.
- Model discovery.
- Model selection.
- Streaming.
- Tool calling.
- Tool execution.
- Execution plans.
- Context management.
- Session persistence.
- Error propagation.
- Provider fallback.
- Cancellation.
- Authentication.
- Model routing.
- Agent Skills.
- Assist Toolkit.
- SwiftCloud model integration.

Document the actual call graph connecting these components.

Determine which components are reusable and which require
modification.

3.3 ENGINE ARCHITECTURE

Locate every implementation associated with the Google Cloud
SDK Engine.

Inspect:

- Engine initialization.
- Process creation.
- Readiness detection.
- Startup triggers.
- Shutdown methods.
- Restart logic.
- Error handling.
- Persisted configuration.
- Settings controls.
- Background tasks.
- Application lifecycle integration.
- Dependency injection.
- Logging.
- Resource cleanup.

Identify every route through which the engine can currently
be started, stopped, disabled, or restarted.

3.4 SETTINGS ARCHITECTURE

Inspect the actual Assist Settings implementation.

Locate the "Assist System Architecture" card, the "Google Cloud
SDK Engine" card, and the existing controls for:

- Assist Toolkit.
- Model Routing Strategy.
- Use SwiftCloud Models.

Determine how each setting is persisted and how it affects
runtime behavior.

Identify reusable card components and layout conventions.

3.5 PROJECT CONFIGURATION

Determine how the project manages:

- Swift source files.
- Xcode targets.
- Resource bundling.
- External packages.
- Runtime dependencies.
- Embedded scripts.
- Application resources.
- Build configurations.
- Tests.

Do not assume the project uses a particular Xcode project
structure without inspecting it.

3.6 AUDIT DELIVERABLE

Record the relevant files, execution paths, architectural
constraints, existing tests, and implementation risks in the
execution plan.

Then proceed directly to Phase One.

============================================================
4. PHASE ONE — COMPLETE MUSE CODE SDK RESEARCH
============================================================

PRIMARY SOURCE:

https://meta-models.github.io/muse-code-sdk/1.4/guides/quickstart/

The documentation review is mandatory.

You must examine the complete relevant documentation surface,
not merely the quickstart page.

Follow the official documentation navigation and linked
references.

Investigate the following domains.

4.1 INSTALLATION AND RUNTIME

Determine:

- Supported SDK languages.
- Supported runtime versions.
- Installation methods.
- Package dependencies.
- Operating-system requirements.
- Environment prerequisites.
- CLI requirements.
- Runtime startup behavior.
- Distribution constraints.
- Compatibility with a native macOS application.

4.2 AUTHENTICATION

Determine:

- Official CLI executable name.
- Official installation procedure.
- Official authentication command.
- Credential discovery behavior.
- Credential storage mechanism.
- Whether CLI credentials can be reused by the SDK.
- Whether additional configuration is necessary.
- Whether authentication is interactive.
- Whether browser authentication is supported.
- How credential expiration is detected.
- How authenticated sessions are refreshed.
- How authentication failures are reported.

Do not invent commands or credential paths.

4.3 MODEL DISCOVERY

Determine:

- How the SDK discovers available models.
- Whether discovery is dynamic.
- How models are identified.
- How model capabilities are represented.
- How model selection is performed.
- Whether models support different execution methods.
- How unavailable models are reported.
- Whether model metadata includes limits or usage information.

4.4 REQUEST EXECUTION

Determine:

- Request construction.
- Message representation.
- Conversation context.
- System instructions.
- Assistant response representation.
- Streaming interfaces.
- Event ordering.
- Tool-call representation.
- Tool-result handling.
- Multi-step execution.
- Cancellation support.
- Session management.

4.5 ERRORS AND LIMITATIONS

Determine:

- Rate-limit behavior.
- Quota failures.
- Network errors.
- Authentication errors.
- Model availability failures.
- SDK initialization failures.
- Process termination behavior.
- Retry guidance.
- Timeout handling.
- Unsupported capabilities.
- Known compatibility limitations.

4.6 RUNTIME CHOICE

The agent may choose Python or TypeScript.

Evaluate both against the actual documented SDK capabilities and
the existing SwiftCode architecture.

Compare:

- SDK completeness.
- Authentication compatibility.
- Streaming.
- Tool calling.
- Dependency installation.
- Runtime availability.
- Startup latency.
- Process lifecycle.
- Packaging.
- Swift interoperability.
- Error propagation.
- Cancellation.
- Maintenance cost.

Choose the simplest reliable solution that provides the
required functionality.

Do not select a runtime merely because it is familiar.

Do not add both runtimes unless there is a demonstrated
technical requirement.

4.7 DOCUMENTATION AUDIT

Maintain a record of the documentation sections reviewed.

Do not claim that every page was read if some references were
inaccessible.

If the official documentation does not establish a behavior,
inspect official package documentation or source interfaces
where available.

Record unresolved uncertainties explicitly.

Proceed only after establishing a defensible integration strategy.

============================================================
5. PHASE TWO — PROVIDER ARCHITECTURE
============================================================

Implement the new provider as a first-class participant in
SwiftCode Assist.

5.1 PUBLIC IDENTITY

The public provider identity is:

    Assist with Meta

The underlying SDK remains an internal implementation detail.

Never display the SDK's product name in ordinary user-facing UI.

This restriction applies to provider names, settings, onboarding,
tooltips, status messages, and user-facing errors.

Internal source code, dependency declarations, package names,
and developer diagnostics may reference the official SDK name
when necessary.

5.2 PROVIDER REGISTRATION

Integrate with the existing provider registry or equivalent
abstraction.

Do not create an independent provider-selection system.

The provider must participate in the same lifecycle used by
other Assist providers.

Preserve the existing providers and their configuration.

5.3 PROVIDER RESPONSIBILITIES

Implement the responsibilities required by the actual existing
provider interface.

Depending on the architecture, these may include:

- Provider identity.
- Configuration.
- Authentication state.
- Model discovery.
- Model selection.
- Request construction.
- Response handling.
- Streaming.
- Tool calls.
- Tool results.
- Cancellation.
- Errors.
- Usage information.
- Session integration.
- Availability reporting.

Do not add duplicate responsibilities when they already belong
to a shared provider abstraction.

5.4 MODEL DISCOVERY

Use the SDK's actual documented discovery functionality.

Do not fabricate a model catalog.

Preserve valid model selections across application launches.

Handle unavailable or removed models safely.

If model discovery fails, report the failure without presenting
stale information as confirmed current availability.

5.5 REQUEST EXECUTION

Requests must travel through the real SDK execution interface.

Integrate the SDK's responses into the existing Assist
conversation model.

Preserve message ordering, context, and session state.

Do not create a separate conversation database unless the
existing architecture requires provider-specific persistence.

5.6 STREAMING

If the SDK supports streaming, connect it to Assist's actual
incremental response mechanism.

The interface must receive real response events.

Handle:

- Partial text.
- Event ordering.
- Stream completion.
- Stream errors.
- Cancellation.
- Interrupted connections.
- Duplicate or malformed events.

Do not simulate streaming by splitting a completed response.

5.7 TOOL CALLING

Inspect the SDK's documented tool-calling capabilities.

If supported, integrate tool calls with Assist's established
execution and permission model.

Determine whether tools are executed by the SDK, the host
application, or a combination of both.

Translate tool calls and results correctly.

Preserve authorization checks, project boundaries, and command
execution policies.

Do not grant the provider unrestricted filesystem or terminal
access merely because its SDK supports tools.

5.8 MODEL ROUTING

Integrate the provider with the existing Model Routing Strategy.

Respect the selected routing policy.

Do not bypass routing to force every request through the new
provider.

Do not silently change providers without communicating the
actual execution path.

Preserve conversation state during provider failures.

5.9 FAILURE HANDLING

Handle initialization failures, missing dependencies,
authentication errors, model-discovery failures, rate limits,
quota exhaustion, network failures, stream interruptions,
tool failures, cancellation, and unexpected runtime termination.

Use structured error information wherever possible.

Never include credentials in user-facing errors.

Do not automatically retry permanent errors.

Use bounded retries only where appropriate.

Keep unrelated providers usable when the new provider fails.

============================================================
6. PHASE THREE — CLI INSTALLATION AND AUTHENTICATION
============================================================

Implement a reliable authentication integration suitable for
a native macOS application launched from Finder or the Dock.

6.1 EXECUTABLE DISCOVERY

Determine the official CLI executable from the SDK documentation.

Do not assume that a terminal PATH is identical to the GUI
application's PATH.

Check the appropriate documented installation locations and
existing application conventions.

Do not scan the entire filesystem unnecessarily.

Do not overwrite an existing working installation.

6.2 INSTALLATION

If the CLI is missing, use the official installation procedure.

Do not invent package names, download URLs, commands, or
credential locations.

Verify that installation completed and that the expected
executable can be invoked.

Handle missing package managers and other prerequisites
explicitly.

Do not install unrelated tools automatically.

Do not run privileged commands without a documented,
necessary justification.

6.3 CREDENTIAL REUSE

Reuse existing authenticated CLI credentials when supported
by the SDK.

Verify that the SDK can actually access those credentials.

Do not assume that successful CLI login guarantees successful
SDK authentication.

Do not copy tokens into UserDefaults, source files, project
resources, or logs.

Do not create a second plaintext credential store.

6.4 REUSABLE SWIFT PROCESS HELPER

Implement or extend an appropriate reusable Swift helper
for CLI process execution.

Use Foundation Process and related APIs.

The helper must support:

- Executable discovery.
- Safe argument passing.
- Standard output capture.
- Standard error capture.
- Exit-status inspection.
- Launch-error handling.
- Timeouts where appropriate.
- Cancellation where appropriate.
- Safe termination of owned processes.
- Structured execution results.
- Sanitized diagnostics.

Do not interpolate untrusted values into shell commands.

Prefer direct Process arguments over invoking a shell.

Do not block the main actor.

Avoid pipe deadlocks by managing output streams and process
termination correctly.

Do not allow a stalled child process to freeze Assist.

Follow existing project abstractions if they already provide
equivalent functionality.

6.5 AUTHENTICATION STATE MACHINE

Represent authentication explicitly.

Account for:

- Checking installation.
- Installing the CLI.
- Checking credentials.
- Authentication required.
- Authentication in progress.
- Authenticated.
- Authentication failure.
- CLI unavailable.

Reuse existing state-management patterns where appropriate.

When valid credentials exist, do not launch an unnecessary
interactive login flow.

When credentials are missing or expired:

1. Detect the condition.
2. Invoke the documented authentication command.
3. Support the documented interactive workflow.
4. Avoid blocking the UI.
5. Verify authentication.
6. Initialize or refresh the SDK session.
7. Enable provider execution only when usable.

If the CLI requires a browser or interactive terminal, use its
documented supported mechanism.

Do not invent an OAuth flow.

Do not request a client secret unless the actual authentication
method requires one.

6.6 AUTHENTICATION ISOLATION

Authentication failure must not prevent SwiftCode from
launching or break unrelated providers.

Do not force users to authenticate with the new provider before
using other Assist functionality.

============================================================
7. PHASE FOUR — ASSIST SYSTEM ARCHITECTURE RECONSTRUCTION
============================================================

Locate the existing "Assist System Architecture" card.

Reconstruct its contents so that it contains exactly two
architecture options:

1. Native Assist System
2. Assist on Google Cloud

No other architecture options may remain in this card.

7.1 REMOVE OBSOLETE CONTENT

Remove obsolete options, redundant descriptions, dead controls,
and unnecessary layout sections.

Do not merely hide the old options while preserving an
unmaintainable collection of dead UI elements.

Use the existing native macOS settings design language.

7.2 PRESERVE NATIVE ASSIST SYSTEM

Preserve the existing Native Assist System implementation.

Inspect its execution path and settings persistence.

Do not break local or native execution capabilities.

7.3 PRESERVE ASSIST ON GOOGLE CLOUD

Preserve the existing Assist on Google Cloud functionality.

Keep architecture selection distinct from provider selection.

Do not conflate:

- Assist architecture.
- Provider identity.
- Model selection.
- Routing strategy.
- Authentication.
- SDK engine lifecycle.

Each concept must retain its appropriate responsibility.

7.4 PERSISTED SETTINGS

Inspect how architecture selection is stored.

Migrate obsolete persisted values safely.

Do not leave the UI in an invalid state if a previously
available option has been removed.

Preserve valid selections.

Do not reset unrelated settings.

Verify that the selected architecture survives application
restarts.

============================================================
8. PHASE FIVE — GOOGLE CLOUD SDK ENGINE LIFECYCLE
============================================================

The existing "Google Cloud SDK Engine" settings card must
disappear from the user interface.

The engine must remain operational and become an
application-managed service.

Hiding the card is not sufficient.

8.1 APPLICATION-LEVEL OWNERSHIP

Move lifecycle ownership into the appropriate application-level
service or dependency-management component.

Inspect the existing SwiftUI application entry point,
application delegate, service manager, and dependency
container.

Choose the correct integration point based on the existing
architecture.

Do not initialize the engine only from a settings view.

Do not initialize it every time a view appears.

8.2 AUTOMATIC STARTUP

The engine must begin initialization during every normal
application launch.

The startup sequence must not depend on:

- Opening Assist Settings.
- Selecting a provider.
- Selecting an architecture.
- Sending a message.
- Clicking a button.

Avoid duplicate initialization caused by SwiftUI view
recreation, multiple scenes, or repeated dependency creation.

8.3 EXPLICIT LIFECYCLE

Use a coherent lifecycle model.

Account for:

- Not initialized.
- Starting.
- Running.
- Recoverable failure.
- Restarting.
- Unrecoverable failure.
- Application termination.

Reuse existing lifecycle state if suitable.

The engine must not report readiness before actual readiness
has been verified.

8.4 REMOVE USER-CONTROLLED SHUTDOWN

Remove user-facing controls that allow the engine to be
stopped or disabled.

Search for:

- Settings cards.
- Toggles.
- Start and stop buttons.
- Context menus.
- Toolbar actions.
- Persisted enable/disable flags.
- Alternative settings screens.
- Indirect user-controlled configuration.
- Public UI actions that call engine shutdown.

The application must not expose a user-accessible way to
manually shut down the engine during normal operation.

The lifecycle manager must retain the ability to perform
necessary cleanup during normal application termination.

Do not confuse mandatory operation with ignoring operating
system termination.

8.5 FAILURE RECOVERY

Handle startup failure truthfully.

If the engine fails:

- Record the actual failure.
- Expose an appropriate internal diagnostic.
- Retry only when appropriate.
- Use bounded retry behavior.
- Prevent restart loops.
- Avoid duplicate processes.
- Verify existing process health before reusing it.
- Clean up stale resources safely.
- Preserve application responsiveness.

Do not claim the engine is running when it is not.

Do not make unrelated providers unusable unless a real
architectural dependency requires it.

8.6 PROCESS OWNERSHIP

If the engine runs in a subprocess, track the process owned
by the application.

Handle process termination, unexpected exits, cancellation,
and cleanup correctly.

Do not terminate unrelated processes.

Avoid orphaned subprocesses.

8.7 STARTUP PERFORMANCE

Engine initialization must not block the main actor.

Use asynchronous operations for process startup, readiness
checks, and network-dependent initialization.

Keep startup state observable without repeatedly initializing
the engine.

============================================================
9. PHASE SIX — SEPARATE ASSIST CONFIGURATION CARD
============================================================

Move the following existing options into a separate card:

- Assist Toolkit
- Model Routing Strategy
- Use SwiftCloud Models

Use a clear title consistent with the existing settings design.

"Assist Configuration" is an acceptable title if appropriate.

9.1 ASSIST TOOLKIT

Preserve its current implementation and behavior.

Move the existing controls rather than creating a duplicate
toolkit system.

Ensure its actions remain functional.

9.2 MODEL ROUTING STRATEGY

Preserve all currently supported routing strategies.

Ensure that changing the setting still affects actual
provider/model selection.

Do not present unsupported routing options.

Preserve valid persisted values.

Do not silently change routing behavior during the move.

9.3 USE SWIFTCLOUD MODELS

Move the existing option into the new card.

Preserve its state and actual runtime behavior.

Do not confuse SwiftCloud models with Assist with Meta.

They are separate integration concepts.

9.4 UI QUALITY

The card must:

- Follow the native macOS design conventions already used.
- Reuse appropriate settings components.
- Avoid duplicate controls.
- Avoid empty layout sections.
- Preserve accessibility.
- Fit the supported window sizes.
- Keep labels and descriptions concise.
- Avoid unnecessary visual effects.

Do not introduce an unrelated design-system rewrite.

============================================================
10. PHASE SEVEN — PROVIDER AND SETTINGS INTEGRATION
============================================================

Integrate the new provider and revised settings into the
existing Assist experience.

10.1 PROVIDER PICKER

Users must be able to select "Assist with Meta" through the
appropriate existing provider-selection workflow.

Do not add a disconnected demo view or an independent chat
window unless required by the existing architecture.

10.2 PROVIDER AVAILABILITY

Represent actual provider readiness.

Distinguish between:

- Runtime unavailable.
- CLI missing.
- Authentication required.
- Authentication in progress.
- Provider initializing.
- Provider ready.
- Model unavailable.
- Request in progress.
- Provider failure.

Use the existing Assist state architecture where possible.

Do not duplicate state systems unnecessarily.

10.3 SESSION PRESERVATION

Preserve conversation history and session state during
provider changes and recoverable failures.

Do not serialize credentials into conversation data.

If the SDK exposes session identifiers, integrate them only
where consistent with the existing session model.

Do not accidentally submit an existing conversation to
another provider without the intended behavior.

10.4 MODEL ROUTING

Integrate with the existing routing strategy.

Respect user-selected routing behavior.

Do not bypass routing because the SDK has its own execution
mechanism.

If fallback is supported, preserve session state and report
the provider that actually handled the request.

10.5 UI STATUS

Display only meaningful status information.

Do not add fake progress messages or fabricated readiness.

Use the existing Assist loading and progress conventions.

Keep technical SDK details out of ordinary user-facing UI.

============================================================
11. PHASE EIGHT — SECURITY AND DISTRIBUTION
============================================================

Treat the application as a distributed macOS product, not
a development-only script.

11.1 CREDENTIAL PROTECTION

Never commit credentials.

Never bundle authentication tokens.

Never log raw credentials.

Never expose secrets through exception messages.

Never store access tokens in ordinary settings preferences.

Do not create an insecure credential cache to simplify
integration.

11.2 RUNTIME MANAGEMENT

If the SDK requires Python or TypeScript execution, account
for the actual application runtime environment.

Do not assume a globally installed runtime exists.

Investigate whether the runtime can be bundled or whether
a documented external runtime is required.

Provide reliable runtime discovery and actionable failures.

Ensure runtime paths work after the application is installed,
not only when launched from the repository.

11.3 IPC SECURITY

If a local HTTP server, socket, or other IPC bridge is used:

- Bind to the narrowest appropriate interface.
- Avoid unnecessary network exposure.
- Validate incoming messages.
- Validate response schemas.
- Apply sensible message-size limits.
- Avoid arbitrary command execution through bridge messages.
- Preserve existing Assist permission boundaries.

11.4 DEPENDENCY MANAGEMENT

Use the repository's established dependency-management
conventions.

Pin or constrain dependencies appropriately.

Avoid overwriting unrelated packages or machine configuration.

Do not bundle local caches, credentials, or temporary files.

11.5 PROJECT INTEGRATION

Add every new Swift file and required resource to the
appropriate Xcode target and project structure.

Ensure runtime assets are accessible after packaging.

Do not rely on source-tree-relative paths in the installed
application unless the packaging architecture guarantees them.

============================================================
12. PHASE NINE — TESTING AND VERIFICATION
============================================================

Testing is a required implementation phase.

12.1 BUILD

Identify the actual project or workspace, scheme, and
build configuration.

Build the relevant application target.

Fix compilation errors introduced by the implementation.

Inspect warnings caused by the changes.

Do not remove functionality merely to obtain a successful build.

12.2 PROVIDER TESTS

Where practical, test:

- Provider registration.
- Configuration.
- Model discovery.
- Model selection.
- Request construction.
- Streaming event translation.
- Message ordering.
- Tool-call translation.
- Error handling.
- Cancellation.
- Session preservation.
- Authentication state.

Mocks are acceptable for isolated unit tests when appropriate.

The production provider must use the actual SDK.

12.3 AUTHENTICATION TESTS

Test:

- Missing CLI.
- Existing CLI.
- Successful process execution.
- Nonzero exit status.
- Standard output and standard error.
- Process launch failure.
- Timeout.
- Cancellation.
- Missing credentials.
- Valid existing credentials.
- Authentication failure.
- Invalid SDK initialization.

Do not expose actual credentials during testing.

Do not invalidate existing credentials simply to simulate
an unauthenticated state.

12.4 ENGINE TESTS

Verify:

- Automatic startup.
- Startup independent of settings views.
- Duplicate-start prevention.
- Readiness verification.
- Failure reporting.
- Bounded recovery.
- Removal of user-accessible shutdown controls.
- Handling of obsolete persisted preferences.
- Correct termination cleanup.

12.5 SETTINGS TESTS

Verify the exact card contents.

ASSIST SYSTEM ARCHITECTURE:

- Native Assist System
- Assist on Google Cloud

GOOGLE CLOUD SDK ENGINE:

- No user-facing settings card.

ASSIST CONFIGURATION:

- Assist Toolkit
- Model Routing Strategy
- Use SwiftCloud Models

Confirm that moved settings remain functional and persist
correctly across application restarts.

12.6 LIVE SDK TEST

Where the environment permits, exercise the real integration.

Verify the complete sequence:

1. Locate the CLI.
2. Install it if necessary.
3. Detect authentication.
4. Reuse existing credentials.
5. Initiate authentication if necessary.
6. Initialize the SDK.
7. Discover actual models.
8. Submit a real request.
9. Receive a real response.
10. Verify streaming where supported.
11. Handle cancellation and errors.

Do not claim live verification when credentials, network
access, or runtime prerequisites are unavailable.

Record the exact limitation.

============================================================
13. PHASE TEN — FINAL IMPLEMENTATION AUDIT
============================================================

Before completion, review the actual final diff.

Search for obsolete architecture controls, the removed engine
settings card, shutdown actions, enable/disable preferences,
provider registration, authentication paths, runtime references,
and new resource paths.

Verify that:

- No obsolete UI remains in alternative settings screens.
- The provider is registered in the real Assist architecture.
- The user-facing provider name is consistently "Assist with Meta".
- The actual SDK is used for production requests.
- CLI credentials are reused through the documented mechanism.
- Authentication does not block unrelated providers.
- The engine starts automatically.
- Duplicate engine initialization is prevented.
- Users cannot manually disable or stop the engine.
- Normal application termination still performs cleanup.
- The three configuration options have been moved correctly.
- Existing settings persistence remains valid.
- All new files belong to the correct targets.
- No unrelated changes were introduced unnecessarily.

Run the relevant build and tests again after the final edits.

Do not rely on an earlier successful build if subsequent
changes have been made.

============================================================
14. DEFINITION OF DONE
============================================================

The task is complete only when the following conditions hold.

PROVIDER:

[ ] Assist with Meta is registered in the existing Assist system.

[ ] It uses the actual documented SDK.

[ ] Model discovery and selection work.

[ ] Real requests execute successfully where the environment permits.

[ ] Streaming works where supported.

[ ] Tool calling works where supported and respects permissions.

[ ] Cancellation, errors, and session state are handled.

AUTHENTICATION:

[ ] Existing CLI installations are detected.

[ ] Installation occurs only when necessary.

[ ] Existing valid credentials are reused.

[ ] The documented authentication workflow works.

[ ] A reusable Swift Process helper exists or an appropriate
    existing helper has been extended.

[ ] Credential handling is secure.

SETTINGS:

[ ] Assist System Architecture contains exactly two options.

[ ] The Google Cloud SDK Engine card is absent.

[ ] The three configuration options are in a separate card.

[ ] Existing functionality and persisted preferences are preserved.

ENGINE:

[ ] The engine starts automatically during application startup.

[ ] Startup does not depend on opening a particular view.

[ ] Duplicate initialization is prevented.

[ ] Readiness is verified.

[ ] Users cannot manually disable or shut down the engine.

[ ] Failures are handled accurately.

[ ] Normal application termination performs appropriate cleanup.

QUALITY:

[ ] The relevant application target builds successfully, or
    environmental/pre-existing blockers are documented.

[ ] Relevant tests pass.

[ ] The actual SDK has been exercised where feasible.

[ ] New files and resources are integrated correctly.

[ ] The final implementation contains no fake production behavior.

[ ] Remaining limitations are documented honestly.

============================================================
15. REQUIRED FINAL REPORT
============================================================

Provide a final report containing:

A. EXECUTIVE SUMMARY

Explain what was delivered and how it changes Assist.

B. ARCHITECTURAL CHANGES

Explain how the new provider integrates with the existing
provider, conversation, and routing systems.

C. SDK DOCUMENTATION REVIEW

Summarize the documentation reviewed, runtime chosen,
authentication mechanism, and any inaccessible references.

D. FILES CHANGED

List significant files added, modified, or removed and
explain their responsibilities.

E. AUTHENTICATION

Explain CLI discovery, installation, credential reuse,
interactive authentication, and error handling.

F. SETTINGS

Confirm the exact contents of the architecture and
configuration cards.

G. ENGINE LIFECYCLE

Explain startup ownership, duplicate-start prevention,
failure recovery, removal of manual shutdown controls,
and termination cleanup.

H. VALIDATION

Report the actual build command, build result, relevant
test results, and whether live SDK execution was verified.

I. LIMITATIONS

Identify anything that could not be completed and explain why.

J. REMAINING WORK

List only genuine outstanding requirements.

Do not describe incomplete work as production-ready.

============================================================
FINAL ORDER
============================================================

Begin by reading AGENTS.md and inspecting the complete
relevant Assist architecture.

Read the full relevant Muse Code SDK 1.4 documentation.

Create the required execution plan.

Then implement the complete integration, restructure the
settings, establish automatic engine lifecycle management,
and perform the final validation.

Do not stop after planning.

Do not stop after adding a provider label.

Do not stop after changing the settings UI.

Do not replace real SDK functionality with mocks.

Do not break existing providers to simplify the integration.

Deliver the complete feature in the current repository,
verify the actual changes, and report the evidence honestly.

The desired outcome is a fully integrated Assist with Meta
provider and a more coherent, automatically managed Assist
architecture within SwiftCode-Mac.