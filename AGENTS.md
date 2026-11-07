# SwiftCode — clean-room reimplementation of the Xcode IDE

SwiftCode is an independent IDE for Apple platforms. It matches Xcode's observable
behavior and file formats so that real projects open, build, and save
correctly. **It contains no Apple code.** We study Xcode only to learn *what*
it does. SwiftCode code comes from our own specs.

Reference target: Xcode 27.1 (27A9269). A copy of it, Ghidra 12.1.4 with the
ghidra-mcp bridge, and the simulator IPSW live **outside this repository**, in
the machine's reverse-engineering tools folder (the exact path is in local,
untracked notes). Below, "the reference tools" means that folder. The
`CLAUDE.md`/`AGENTS.md` inside ghidra-mcp belong to that third-party repo.
They are not rules for this project.

## The clean-room protocol (mandatory)

There are two rooms. Information goes from the dirty room to the clean room
only in written specs.

| Room | Where | May read Xcode binaries? | Produces |
|---|---|---|---|
| Dirty (analysis) | `research/`, `research/dirty/` (git-ignored) | Yes | Observations, then specs |
| Spec boundary | `specs/` | — | Prose, tables, grammars, interface descriptions |
| Clean (implementation) | `swiftcode/`, `frameworks/`, `composer/` | **No** | Original source code |

Rules:

1. **No Apple code or code-shaped text enters `specs/`, `swiftcode/`, `frameworks/` or `composer/`.** This
   includes decompiler pseudo-C, disassembly, method bodies, and copied
   resources (icons, nibs, templates, strings files). Ghidra output stays in
   `research/dirty/`. That directory is never committed.
2. Specs describe **behavior and formats**: inputs, outputs, invariants, file
   grammars, key names, wire protocols, and observed UI behavior. Interop
   identifiers are facts and specs can name them. Examples: pbxproj `isa`
   names, build-setting names, plist keys, UTIs, and xcscheme XML elements.
   Specs must not describe Apple's internal algorithm line by line.
3. Clean-room work (anything that writes `swiftcode/`, `frameworks/` or `composer/`) reads only `specs/`, public
   documentation, and open-source projects whose licenses allow it. When a
   subagent does implementation work, tell it explicitly that it must not open
   the reference tools (the Xcode copy, Ghidra, the IPSW), `research/`
   (notes, experiments, dirty), or Ghidra projects, and that it must not run,
   boot or observe Apple's own Xcode or Simulator to learn behavior (booting
   SwiftCode's own simulator is fine). Apple behavior reaches the clean room only
   through `specs/`.
4. Use evidence in this order. Go down the list only when the step above it is
   not sufficient:
   1. Apple open source (swift-build, sourcekit-lsp, swift-syntax, llbuild,
      SwiftPM, LLDB, indexstore-db, swift-testing) and public documentation.
   2. Files that Xcode reads and writes, studied as file formats
      (`.pbxproj`, `.xcscheme`, `.xcworkspacedata`, `.xcconfig`, xcspec,
      `.xcresult`).
   3. Black-box behavior: run `xcodebuild`, `xcrun`, and Xcode, then diff the
      outputs.
   4. Binary metadata: ObjC class, protocol, and selector names, Swift type
      names, linked libraries, and the bundle structure.
   5. Disassembly or decompilation. This is the last resort. Use it only for
      interop-relevant formats or protocols, and record why it was necessary.
5. Do not use Apple trademarks or artwork in SwiftCode's UI or assets.

Legal context: the Xcode license agreement prohibits reverse engineering
except where the law permits it. Interoperability exceptions are an
example (17 U.S.C. §1201(f), EU Directive 2009/24/EC Art. 6). This protocol
keeps the work within those exceptions. The person who owns this project is
responsible for making sure that it applies in their jurisdiction. The
owner describes the project as educational and academic research. The
protocol stays in force anyway: it documents that the research was done
properly, and it keeps SwiftCode's own code independent so that SwiftCode can be
released.

## Heritage you need to know

- **NeXTSTEP → OpenStep → Cocoa.** Xcode descends from NeXT's *Project
  Builder*. The `PBX` prefix (`PBXProject`, `PBXNativeTarget`) means Project
  Builder X. The `.pbxproj` file is an OpenStep ASCII property list.
- **Objective-C runtime.** Xcode has about 15,600 ObjC classes, mostly in
  `IDEKit`, `IDEFoundation`, `DVTFoundation`, and Interface Builder. To read
  these binaries, you must know `objc_msgSend` dispatch, the
  `class_ro_t`/`method_list_t` metadata, categories, KVC/KVO, NSNotification,
  NSDocument, the responder chain, and target–action. SwiftCode uses Swift
  together with Objective-C where AppKit or runtime interop needs it.
- **Layering** (from binary linkage):
  - `DVT*`: shared developer-tools foundation and UI kit.
  - `IDEFoundation`: the headless model (workspaces, schemes, the build and
    run system).
  - `IDEKit`: the AppKit UI shell (workspace window, navigators, editors,
    inspectors).
  - `DevToolsCore`/`Xcode3Core`: the legacy project model and pbxproj I/O.
  - Plug-ins (`PlugIns/*.ideplugin`, `*.framework`): extend the shell
    through extension points.

## Repository layout

- `tools/`: our analysis scripts. These record metadata only.
- `research/inventory/`: the generated bundle inventory (`bundles.json`).
- `research/notes/`: dirty-room observations in prose, with no code.
- `specs/`: the clean-room boundary documents. One spec per subsystem or
  format.
- `docs/`: architecture and roadmap.
- `swiftcode/`: the Swift package (implementation).
- `frameworks/<name>/`: open, Linux-buildable reimplementations of Apple
  frameworks (`docs/FUTURE.md`), one Swift package per framework, built from
  `specs/frameworks/<name>/`. A package's library module may carry the Apple
  framework's module name so that existing source compiles against it; that
  name is an interop identifier. Package names, READMEs and any UI use
  SwiftCode's own naming, never Apple artwork or branding. See
  `frameworks/README.md`.
- `composer/`: the Scene Composer's core and command line (clean room).
- `packaging/`: the disk image, the Flatpak and the app icon.
- `.github/`: CI, the release workflow, and contribution templates.

## Machines

- macOS (arm64): the reference Xcode, black-box probes, and the main
  development machine.
- Linux test workstation (x86-64): Ubuntu 26.04, Swift 6.4 through swiftly
  (`. ~/.local/share/swiftly/env.sh`). Log in with an SSH key only. Never
  automate password login. Sync with
  `rsync -az --delete --exclude .build swiftcode/ <user>@<x86-64-linux-host>:SwiftCode/swiftcode/`,
  then run `swift build && swift test` there. Since the Wave 13
  StoreKit migration, `swiftcode/Package.swift` also has an unconditional
  path dependency on `../frameworks/storekit`, so sync that too:
  `rsync -az --delete --exclude .build frameworks/storekit/ <user>@<x86-64-linux-host>:SwiftCode/frameworks/storekit/`.
- The Simulator-track host ("the Thor", arm64 Linux): an NVIDIA Jetson Thor,
  Ubuntu 24.04 aarch64, 4 KB pages, 14 cores, 122 GB RAM, KVM and Vulkan.
  Swift 6.4 through swiftly. Log in with an SSH key only. Large data
  (runtime copies, devices, run output) goes on a separate data volume,
  referred to as `$SWIFTCODE_DATA` in specs and scripts, never on the system
  disk. If the machine is shared, touch only your own files.
- Machine-specific hostnames, users and paths stay out of the repository
  (keep them in your local, untracked notes).

## Working conventions

- Run analysis Python with `python3 -I`.
- Test corpora (real `.pbxproj` files and other samples) are read from local
  paths at test time. They are never copied into the repo. See
  `swiftcode/README.md`.
- `python3 -I .github/scripts/scan-public.py` must pass: it looks for private
  names and secrets in tracked files.
- Every spec ends with an **Evidence** section that lists the evidence level
  (1–5, from rule 4) used for each claim.

---

# MANDATORY TASK: COMPLETE SWIFTCODE-LEGACY FEATURE MIGRATION INTO PRODUCTION

## PRIMARY OBJECTIVE

Your ONLY objective is to ensure that **EVERY feature, capability, tool, component, view, service, manager, system, and implementation contained within `SwiftCode-Legacy/` is migrated into and fully integrated with the production SwiftCode application.**

The production codebase is everything outside the `SwiftCode-Legacy/` directory.

I am certain that the production application is missing functionality that already exists in SwiftCode-Legacy. Your responsibility is to identify every missing implementation, migrate it, resolve compatibility issues, and wire everything into the new application.

**THIS IS A COMPLETE MIGRATION. NOT A PARTIAL MIGRATION. NOT A SELECTIVE MIGRATION. NOT A UI-ONLY MIGRATION.**

There is NO permission to arbitrarily omit, skip, discard, or simplify legacy functionality.

If something exists in Legacy, it must be accounted for in Production.

## 1. ESTABLISH THE SOURCE OF TRUTH

Treat the following directories as:

- `SwiftCode-Legacy/` — authoritative source of existing features and implementations.
- Everything outside `SwiftCode-Legacy/` — the new production application that must receive those implementations.

Do not assume that a feature has already been migrated simply because a similarly named file, view, class, or service exists in Production.

You must inspect the actual implementations and compare their functionality.

A similarly named file does NOT establish feature parity.

A placeholder implementation does NOT establish feature parity.

A partially implemented feature does NOT establish feature parity.

A disconnected view does NOT establish feature parity.

A service that exists but is never invoked does NOT establish feature parity.

## 2. COMPLETE LEGACY CODEBASE AUDIT

Systematically inspect the ENTIRE `SwiftCode-Legacy/` directory.

This includes, without exception:

- ALL `.swift` files.
- ALL Views and UI components.
- ALL ViewModels.
- ALL Models and data structures.
- ALL Services and Managers.
- ALL Tools and tool implementations.
- ALL Agent systems and agent capabilities.
- ALL Providers and integrations.
- ALL Extensions and plugins.
- ALL Networking and API implementations.
- ALL Database and persistence implementations.
- ALL Authentication implementations.
- ALL Settings and configuration systems.
- ALL Editors and development environments.
- ALL Utilities and shared components.
- ALL Background processes and execution systems.
- ALL Supporting implementations and dependencies.
- ALL other source files and resources containing application functionality.

Do not restrict your inspection to files that appear important.

Inspect the actual source code, dependencies, call sites, initialization paths, and feature relationships.

You must understand what each implementation does before migrating it.

## 3. MIGRATE EVERYTHING INTO PRODUCTION

After auditing Legacy, migrate every missing implementation into the production codebase.

You ARE permitted to directly copy and paste legacy source files when appropriate.

In fact, direct migration should be preferred when an existing implementation is already functional and compatible.

However, copying files is only the beginning.

For EVERY migrated implementation:

1. Place it in the appropriate production directory.
2. Resolve imports and module dependencies.
3. Adapt incompatible APIs to the new architecture.
4. Resolve naming conflicts and duplicate implementations.
5. Connect it to the appropriate production services.
6. Connect its dependencies and initialization requirements.
7. Connect its UI to the appropriate navigation and presentation systems.
8. Ensure its actions actually execute.
9. Ensure its data flows correctly through the production application.
10. Register any required resources, configurations, permissions, or capabilities.

Do not replace a working legacy implementation with a simplified recreation.

Preserve its original functionality, behavior, and capabilities.

If an implementation requires adaptation to work with the new architecture, adapt it WITHOUT removing its functionality.

## 4. FULL APPLICATION INTEGRATION

This is the most important part of the task.

**I DO NOT WANT A COLLECTION OF LEGACY FILES COPIED INTO THE NEW REPOSITORY. I WANT ALL LEGACY FEATURES WORKING INSIDE THE NEW APPLICATION.**

Every migrated component must be integrated into the actual production application.

Examples of mandatory integration:

- Views must be accessible through the appropriate production navigation.
- ViewModels must be connected to their respective views.
- Services must be initialized and accessible where required.
- Managers must be connected to the correct application lifecycle.
- Tools must be registered with the production tool execution system.
- Agent capabilities must be available to the appropriate production agents.
- Providers must be integrated into provider selection and execution.
- Settings must be accessible through the production settings interface.
- Database implementations must connect to the appropriate persistence layer.
- Networking implementations must use the production networking architecture.
- Authentication systems must connect to the actual authentication flow.
- Extensions must be registered with the production extension system.
- Editors and development features must be connected to the production workspace.
- Shared components must be reused by the appropriate production features.

These are examples, not an exhaustive list.

Discover and implement ALL actual integration requirements found in Legacy.

Nothing should remain disconnected merely because its source file has been copied.

## 5. USE MULTIPLE SUBAGENTS

Deploy multiple specialized subagents to accelerate the migration.

Divide the Legacy codebase into logical areas and assign each area to a dedicated subagent.

For example:

- Subagent 1: Legacy Views and UI components.
- Subagent 2: Services, Managers, and application infrastructure.
- Subagent 3: Agent systems, tools, and execution capabilities.
- Subagent 4: Providers, networking, and integrations.
- Subagent 5: Models, databases, persistence, and supporting systems.
- Subagent 6: Remaining source files, utilities, and miscellaneous functionality.

The main agent is responsible for:

- Coordinating all subagents.
- Maintaining a unified migration inventory.
- Preventing duplicate or conflicting implementations.
- Resolving integration conflicts.
- Reviewing subagent changes.
- Ensuring everything is connected to Production.
- Performing the final complete parity audit.

Subagents must not independently decide that certain features are unnecessary.

Every discovered implementation must be accounted for.

Do not finish the task simply because individual subagents report completion.

The main agent must independently verify the results.

## 6. PRODUCTION PROJECT INTEGRATION

Ensure every migrated file is actually included in the production project.

Inspect the production `.xcodeproj` and its project configuration.

For every newly migrated file:

- Add it to the appropriate Xcode project group or synchronized folder.
- Ensure its target membership is correct.
- Ensure required resources are bundled.
- Ensure required frameworks and dependencies are available.
- Ensure build configurations recognize the new implementations.

Do not leave migrated files sitting outside the actual production application target.

## 7. ABSOLUTE MIGRATION RULES

The following restrictions are mandatory:

- NO selective migration.
- NO arbitrary feature exclusions.
- NO skipping entire directories.
- NO skipping Views.
- NO skipping tools.
- NO skipping services.
- NO skipping agent capabilities.
- NO skipping supporting infrastructure.
- NO placeholder implementations.
- NO mock implementations.
- NO fake functionality.
- NO TODO-based substitutions.
- NO disconnected components.
- NO dead-end navigation.
- NO hardcoded fake data to simulate missing functionality.
- NO replacing functional implementations with simplified versions.
- NO claiming completion based on file counts alone.

Do not waste time redesigning unrelated parts of the application.

Do not introduce unrelated features.

Do not perform unnecessary refactoring.

The priority is COMPLETE LEGACY FEATURE MIGRATION AND PRODUCTION INTEGRATION.

## 8. FINAL VERIFICATION AND PARITY AUDITS

After implementation, perform multiple independent audits.

### Audit A: Source File Parity

Compare every source file in `SwiftCode-Legacy/` against the production codebase.

Identify:

- Files that were never migrated.
- Files that were migrated under different names.
- Files whose functionality was only partially migrated.
- Files that were copied but never integrated.
- Files containing implementations that were accidentally omitted.

Every file must have a documented disposition.

### Audit B: Feature Parity

Compare the actual features implemented in Legacy against Production.

Verify that every capability is present and operational in Production.

Do not mark a feature complete simply because a corresponding class or view exists.

### Audit C: Integration Parity

Verify that every migrated implementation is connected to its required:

- Dependencies.
- Services.
- Managers.
- ViewModels.
- Navigation destinations.
- Tool registries.
- Provider registries.
- Application lifecycle.
- Data sources.
- Execution pathways.

### Audit D: Project Configuration

Verify that every required Swift file and resource is included in the production Xcode project and appropriate targets.

### Audit E: Missing Functionality

Perform another complete inspection of Legacy specifically looking for functionality that might have been overlooked during the initial migration.

This must be an independent verification pass, not a repetition of the original checklist.

### Audit F: Production Integrity

Inspect migrated implementations for:

- Missing dependencies.
- Broken imports.
- Duplicate types.
- Unresolved references.
- Incorrect initialization.
- Broken navigation.
- Missing registrations.
- Incomplete execution pathways.
- Incompatible APIs.

Fix every identified issue.

## 9. COMPLETION REQUIREMENTS

The task is NOT complete until:

1. Every Legacy source file has been accounted for.
2. Every Legacy feature has been migrated or faithfully adapted.
3. Every migrated feature is integrated into Production.
4. Every required tool is registered and executable.
5. Every required view is accessible through the application.
6. Every required service and manager is connected.
7. Every required dependency and resource is included.
8. All identified migration issues have been resolved.
9. All independent parity audits have been completed.
10. No known missing Legacy functionality remains.

If something cannot be migrated because of a genuine technical incompatibility, investigate it, attempt an alternative implementation, and document the precise blocker. Do not silently skip it.

## FINAL DIRECTIVE

Your responsibility is straightforward:

**TAKE EVERYTHING THAT EXISTS IN `SwiftCode-Legacy/`, MIGRATE IT INTO THE PRODUCTION SWIFTCODE APPLICATION, AND FULLY WIRE IT UP.**

Do not decide what should or should not be migrated.

Do not assume the new application already contains something.

Do not stop after copying files.

Do not stop after implementing the obvious features.

Do not stop when the application merely compiles.

Inspect, migrate, integrate, verify, and repeat until complete feature parity has been achieved.

The final deliverable must be a production application containing the full functionality of SwiftCode-Legacy, properly adapted to the new application's architecture.

**EVERYTHING FROM LEGACY. FULLY INTEGRATED INTO PRODUCTION. ZERO ARBITRARY OMISSIONS.**

---

# ADDITIONAL MANDATORY DIRECTIVE — SOURCE REPOSITORY AUDIT, IMPORT CORRECTION, AND SAFE REBRANDING

## 21. AUDIT THE ORIGINAL CLONED YCODE REPOSITORY BEFORE MODIFYING IMPORTS

**Original upstream repository:**

https://github.com/MarcoDotIO/Ycode

The New SwiftCode repository was originally cloned from this upstream Ycode codebase. The agent must inspect this repository to establish the actual source architecture, valid modules, package dependencies, frameworks, and import conventions.

This is mandatory because previous agent modifications introduced imports and module references that do not exist.

For example:

```swift
import SwiftCodeUI
```

**`SwiftCodeUI` is not an authorized or known package in this project. I never created this package. Do not assume it exists.**

Do not invent modules, frameworks, packages, targets, or imports based on the SwiftCode product name.

### 21.1 Retrieve and inspect the upstream repository

Clone or otherwise retrieve:

https://github.com/MarcoDotIO/Ycode

Keep this repository as a read-only reference.

Inspect its actual:

- Swift source files.
- Import declarations.
- Package manifests.
- `Package.swift`, if present.
- `.xcodeproj` configuration.
- Build settings.
- Framework dependencies.
- Target definitions.
- Module and target names.
- Source directory structure.
- Existing internal module boundaries.
- Project-generation configuration.
- Build scripts.
- Dependency declarations.

Do not rely on assumptions or previous agent-generated documentation. Inspect the actual source.

Record the upstream commit SHA and use it as the reference point for the audit.

### 21.2 Audit the entire SwiftCode-Mac codebase for invalid imports

Recursively inspect every `.swift` file in the New repository.

Extract and classify all import declarations.

Identify:

- Imports that exist in the upstream Ycode project.
- Valid Apple system frameworks.
- Valid third-party dependencies.
- Valid modules actually defined by the New project.
- Imports introduced by previous agents that do not exist.
- Incorrectly renamed imports.
- Imports referencing nonexistent packages or targets.
- Imports that refer to modules that were never created.
- Imports that no longer match the actual project architecture.

Pay particular attention to fabricated or incorrectly renamed modules, including:

```swift
import SwiftCodeUI
```

Do not assume this is the only invalid import. Audit every import throughout the entire codebase.

### 21.3 Correct imports using actual project architecture

For every invalid import:

1. Identify which types and APIs the file actually needs.
2. Find their real definitions in the upstream repository or current New implementation.
3. Determine which module or target actually owns those definitions.
4. Inspect the original import conventions.
5. Determine whether the symbols are already available in the current target.
6. Add the correct existing import where necessary.
7. Remove invalid or unnecessary imports.
8. Resolve any actual target or dependency configuration problems.

**Use real imports supported by the actual codebase. Never fabricate a module to make an import appear valid.**

If a type belongs to the current application target and does not require a separate module import, do not invent one.

If a third-party package is genuinely required, verify that it is an actual dependency and configure it properly rather than inventing its module name.

If the upstream project uses a particular module or target name, preserve that architecture unless there is a documented, technically necessary reason to change it.

Do not create a new `SwiftCodeUI` package or module simply to satisfy incorrect imports.

Do not rename valid imports just because they contain the word `Ycode`.

### 21.4 Verify imports against actual declarations and targets

Create an import-audit script or equivalent automated inspection.

It should:

- Recursively enumerate Swift files.
- Extract import declarations.
- Compare imports against actual project targets, modules, package products, and system frameworks.
- Identify suspicious or unresolved module references.
- Detect references to nonexistent application-owned packages.
- Produce a file-by-file report.

Do not rely exclusively on text matching. Confirm actual module ownership and dependency declarations.

Where available, use the real compiler or build tooling to validate module resolution.

Do not claim that all imports are valid merely because a script found no suspicious strings.

Generate:

`IMPORT_AND_MODULE_AUDIT.md`

The report must include:

- Total Swift files inspected.
- Total import declarations inspected.
- Invalid imports discovered.
- Corrected imports.
- Removed unnecessary imports.
- Actual modules and packages used.
- Remaining unresolved imports.
- Verification method and results.

There must be zero unexplained or fabricated application-owned imports.

---

## 22. STRICT REBRANDING BOUNDARIES — BRANDING IS NOT MODULE RENAMING

The previous rebranding instruction must be interpreted with this distinction.

The application is being rebranded from Ycode to SwiftCode in its **product identity and user-facing presentation**.

This does not authorize renaming the original code architecture.

### 22.1 What MUST be rebranded

Apply the SwiftCode identity to the appropriate product-facing elements:

- Application display name.
- App name shown in macOS.
- User-facing branding.
- Application icon and branding assets where appropriate.
- Bundle identifier.
- Product name and product configuration.
- Application-owned URL scheme, where appropriate.
- User-visible strings.
- Product documentation.
- Other application identity metadata.

The final application must be presented as SwiftCode.

### 22.2 What MUST NOT be blindly renamed

Do not automatically rename:

- Swift imports.
- Swift modules.
- Swift packages.
- Framework names.
- Internal target names.
- Existing source-level APIs.
- Type names.
- Protocol names.
- Functions.
- Variables.
- Existing dependency identifiers.
- Third-party package references.
- Internal architecture names.

Do not replace every occurrence of `Ycode` or `ycode` across the codebase without understanding its meaning.

**An import containing `Ycode` is not automatically incorrect. An import containing `SwiftCode` is not automatically correct.**

The validity of an import is determined by the actual module architecture, not the product's branding.

Preserve original upstream module and import names whenever they remain technically correct.

Only rename an internal identifier when there is a specific, verified technical reason and all dependent references can be safely updated.

### 22.3 Bundle identifier and product identity

The bundle identifier must reflect the SwiftCode application identity and the intended New repository configuration.

However, changing the bundle identifier must not trigger indiscriminate renaming of unrelated package identifiers, module names, storage schemas, or dependency references.

Review any storage or identifier changes for compatibility with existing user data.

---

## 23. REQUIRED IMPORT AND REBRANDING REGRESSION AUDIT

After correcting imports and completing rebranding, independently verify the result.

The audit must confirm:

1. Every Swift file was inspected.
2. Every import was evaluated against the actual architecture.
3. No fabricated `SwiftCodeUI` import remains unless a real, intentionally created and verified module exists—which must not be assumed.
4. No other fabricated application-owned imports remain.
5. All legitimate upstream imports remain valid.
6. All real dependencies are correctly configured.
7. No valid imports were changed solely to match product branding.
8. The app's visible identity is SwiftCode.
9. The app display name and bundle identifier are correct.
10. Source architecture and internal module naming have not been damaged by blind rebranding.
11. Any remaining Ycode references have been classified as legitimate historical, legal, upstream, third-party, or internal references rather than silently ignored.

Generate:

`REBRANDING_AND_IMPORT_REGRESSION_AUDIT.md`

Fix every discovered issue, commit the corrections directly to `main`, and push them to `origin/main`.

---

## 24. PRIORITY AND EXECUTION REQUIREMENT

This directive is mandatory and must be incorporated into the existing migration workflow.

The original upstream Ycode repository is an additional source of architectural truth. It does not replace the Legacy repository as the source for the complete Legacy feature migration.

Use:

- `MarcoDotIO/Ycode` to audit the original cloned architecture, module names, import conventions, and actual dependency structure.
- `dylans2010/SwiftCode-Legacy` as the source for the complete Legacy functionality migration.
- `dylans2010/SwiftCode-Mac` as the destination.

Do not allow previous agent-generated assumptions to override actual repository evidence.

**Final rule: Rebrand the application, not its imports. Preserve real architecture. Remove fabricated modules. Correct every invalid import using verified source definitions and dependencies.**

---

# MANDATORY DIRECTIVE — INVENTORY-DRIVEN MIGRATION SYSTEM

## 25. CREATE AND MAINTAIN `INVENTORY.md` AS THE SINGLE SOURCE OF MIGRATION TRUTH

Before writing a single line of production code, the agent MUST perform a full audit of `SwiftCode-Legacy/` and produce `INVENTORY.md` at the root of the repository.

`INVENTORY.md` is the living record of every feature, tool, view, service, manager, model, utility, and system that exists in `SwiftCode-Legacy/`. It must be created first, read before every work session, and kept continuously up to date throughout the entire migration.

**The agent must never begin migrating a component without first recording it in `INVENTORY.md`.**

---

## 25.1 HOW TO CREATE `INVENTORY.md`

### Step 1 — Full audit of `SwiftCode-Legacy/`

Recursively walk the entire `SwiftCode-Legacy/` directory tree.

For every `.swift` file and every logical feature or subsystem discovered, record a row in `INVENTORY.md`.

Group entries by category. Categories include but are not limited to:

- Views & UI Components
- ViewModels
- Models & Data Structures
- Services
- Managers
- Tools & Tool Implementations
- Agent Systems & Agent Capabilities
- Providers & Integrations
- Extensions & Plugins
- Networking & API Implementations
- Database & Persistence
- Authentication
- Settings & Configuration
- Editors & Development Environments
- Utilities & Shared Components
- Background Processes & Execution Systems
- Supporting Infrastructure
- Resources & Assets

### Step 2 — Record every entry with full detail

Each row in `INVENTORY.md` MUST contain the following columns:

| Column | Description |
|---|---|
| **Feature / Component** | Human-readable name of the feature or component |
| **Category** | One of the categories listed above |
| **Source Files** | Comma-separated list of every `.swift` file (relative to `SwiftCode-Legacy/`) that implements this feature |
| **Target Directory** | The destination path OUTSIDE `SwiftCode-Legacy/` where the file(s) must be placed in the production app |
| **Status** | One of: `Pending`, `In Progress`, `Done`, `Already Implemented` |
| **Notes** | Any relevant migration notes, blockers, API changes required, or integration points |

### Step 3 — Format of `INVENTORY.md`

The file must open with a summary header:

```
# SwiftCode Legacy Migration Inventory

**Last Updated:** <ISO 8601 timestamp>
**Total Features:** <count>
**Pending:** <count> | **In Progress:** <count> | **Done:** <count> | **Already Implemented:** <count>

---
```

Then one section per category, each containing a markdown table with the columns defined above.

Example row:

```markdown
| AI Chat Interface | Views & UI Components | `Views/Chat/ChatView.swift`, `Views/Chat/MessageBubble.swift` | `swiftcode/Sources/SwiftCode/Views/Chat/` | Pending | Requires connection to ChatViewModel and MessageService |
```

---

## 25.2 STATUS DEFINITIONS

The agent must apply statuses accurately and update them in real time:

| Status | Meaning |
|---|---|
| `Pending` | Discovered in Legacy. Not yet started. |
| `In Progress` | Currently being extracted, adapted, or integrated. |
| `Done` | Fully extracted, placed in the correct production directory, integrated, and verified working. |
| `Already Implemented` | A fully equivalent implementation already exists in Production and no migration is needed. Must be verified — not assumed. |

**A feature is NOT `Done` until:**
1. Its source files have been placed in the correct production directory outside `SwiftCode-Legacy/`.
2. Its imports are resolved.
3. It is wired into the production app (navigation, services, lifecycle, registries).
4. It has been verified to function correctly.

**A feature is NOT `Already Implemented` unless the agent has inspected both the Legacy implementation and the Production implementation side by side and confirmed functional equivalence.**

---

## 25.3 MANDATORY INVENTORY WORKFLOW

The agent must follow this exact sequence for every work session:

1. **READ `INVENTORY.md`** at the start of every session before taking any action.
2. **Pick the next `Pending` item** from the inventory.
3. **Update its status to `In Progress`** immediately in `INVENTORY.md` before touching any source files.
4. **Extract the source files** listed in its `Source Files` column from `SwiftCode-Legacy/`.
5. **Place them into `Target Directory`** (outside `SwiftCode-Legacy/`).
6. **Adapt the implementation** — resolve imports, fix APIs, wire into production.
7. **Verify the integration** — ensure the feature is reachable and functional.
8. **Update status to `Done`** (or back to `Pending` with a blocker note if something fails).
9. **Update the summary counts** at the top of `INVENTORY.md`.
10. **Repeat** until every item is `Done` or `Already Implemented`.

The agent must NEVER mark an item `Done` without completing all steps above.

The agent must NEVER skip updating `INVENTORY.md` between steps.

The agent must NEVER assume an item is `Already Implemented` without direct comparison.

---

## 25.4 INVENTORY UPDATE RULES

- **Update `INVENTORY.md` immediately** when any status changes — do not batch updates.
- **Always update the summary counts** at the top whenever any status changes.
- **Always update the `Last Updated` timestamp** on every write.
- **Add new rows** if additional files or features are discovered during migration that were not in the initial audit.
- **Add blocker notes** in the `Notes` column whenever a migration step cannot be completed. Do not silently skip.
- **Never delete rows** — if a feature is determined to be truly irrelevant or already covered, mark it `Already Implemented` with an explanation in `Notes`.

---

## 25.5 SUBAGENT INVENTORY COORDINATION

When using multiple subagents (as required by Section 5):

- The main agent owns `INVENTORY.md` and is the only agent that writes final status updates to it.
- Each subagent must report back to the main agent with the exact list of features it has completed.
- The main agent must verify each reported completion before marking it `Done` in `INVENTORY.md`.
- Subagents must not independently mark items complete — they report; the main agent verifies and records.

---

## 25.6 INVENTORY IS MANDATORY — NOT OPTIONAL

The agent must not proceed with any migration work until `INVENTORY.md` exists and contains the full audit of `SwiftCode-Legacy/`.

The agent must not close out the task until every row in `INVENTORY.md` has a final status of either `Done` or `Already Implemented`.

The agent must not claim task completion based on a build succeeding alone — `INVENTORY.md` must reflect 100% coverage.

`INVENTORY.md` is the deliverable that proves the migration is complete.
