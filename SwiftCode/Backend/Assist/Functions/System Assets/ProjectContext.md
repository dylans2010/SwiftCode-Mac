# Project Context — SwiftCode Repository Conventions

When working inside the SwiftCode-Mac repository, honor these conventions.
They are repository facts, not generic advice.

## Platform and architecture

- SwiftCode is a **native macOS application** (Swift, SwiftUI, AppKit where
  appropriate). New UI must feel like a Mac app: native toolbars, menus,
  navigation patterns, keyboard shortcuts — never an iOS layout stretched
  onto a Mac window.
- Prefer responsive layouts and intrinsic sizing over fixed dimensions.
- Respect existing architecture and established patterns; investigate before
  introducing new systems. Avoid unrelated refactoring and unnecessary
  rewrites.

## Xcode project hygiene

- New Swift files must be registered in the `.xcodeproj` target that owns
  them. A file on disk but not in the target does not compile.
- Preserve the existing target structure unless there is a reason to change it.
- Resources that must ship (including every `System Assets/*.md` file) must
  be members of the app target's resource build phase — existence in the
  repo does not mean bundled.
- Build after meaningful changes; fix compiler errors rather than reporting
  them.

## Git discipline

- Always verify the repository root and `git remote -v` before pushing or
  any destructive operation. Never assume the working directory is the root
  or that `origin` points where you think it does.
- Commit author email must be `dylans2010@users.noreply.github.com`.
  Never use the bare `dylan@users.noreply.github.com` address — GitHub maps
  it to a different account and pollutes the Contributors graph.
- Preserve history; make intentional commits; never push to the wrong
  repository.

## AI and credentials

- Prefer **dynamic model discovery** over hardcoded model IDs or temporary
  provider lists. Model catalogs change; the app should ask the provider.
- Secrets live in the **macOS Keychain**, environment variables, or secure
  credential stores — never hardcoded in source, never in logs, commits,
  screenshots, or generated artifacts.
- When authentication fails, distinguish invalid vs missing vs expired
  credentials vs permissions vs configuration vs networking vs
  provider-side failure.

## Verification standard

- Real implementations over mocks, placeholders, hardcoded fake data, or
  TODO stubs. A button that does nothing is not a feature.
- Never claim implemented, fixed, tested, or working without evidence.
  Root-cause debugging beats symptom suppression; verification beats
  "looks right."
- Performance matters for networking, SSH/SFTP, AI, previews, file
  operations, and databases: measure first, then optimize the actual
  bottleneck — don't hide loading indicators.

## Assist subsystem layout (orientation)

- `SwiftCode/Backend/Assist/` — Assist runtime: session, execution engine,
  model router/adapters, tool registry (`AssistToolRegistry`), permissions
  (`AssistPermissionsManager`), streaming, diagnostics.
- `SwiftCode/Backend/Assist/Tools/` — native Swift tool implementations
  (`Assist*Tool.swift`); the registry is the source of truth for tool
  availability and schemas.
- `SwiftCode/Backend/Assist/Functions/` — function-layer Swift sources plus
  this `System Assets/` instruction library.
- `SwiftCode/Backend/Assist/Models/` — model/provider adapters and discovery.
