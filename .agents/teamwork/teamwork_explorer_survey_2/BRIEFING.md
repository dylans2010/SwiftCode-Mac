# BRIEFING — 2026-11-07T00:51:00Z

## Mission
Survey Assist system (R3) and Code Comments (R1): investigate existing Assistant architecture, legacy Assist tools/training assets, MCP integration, and design comment-removal strategy.

## 🔒 My Identity
- Archetype: explorer
- Roles: survey, synthesis, analysis
- Working directory: /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_2
- Original parent: d5b41c16-417f-423a-b7f8-eea4f0706fc5
- Milestone: Survey Phase

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Clean-room protocol: No Apple code in specs/ or clean room; observe clean-room boundaries
- No file writes outside own folder `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_survey_2/`
- Report to handoff.md and send message back to parent agent upon completion

## Current Parent
- Conversation ID: d5b41c16-417f-423a-b7f8-eea4f0706fc5
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `swiftcode/Sources/SwiftCodeAssistant/` (Providers, Runtime, Models, Tools, Reverse, Resources)
  - `swiftcode/Sources/SwiftCodeIDECore/Assistant/` (`CodingAssistantModel`, `CodingAssistantServices`)
  - `swiftcode/Sources/SwiftCodeMCP/` (`SwiftCodeMCPHost`, `SwiftCodeTools`, `AssistToolRegistry+MCPTools`)
  - `SwiftCode-Legacy/SwiftCode/Backend/Assist/` (Tools, Functions, System Assets, `AssistToolRegistry`)
  - Repository-wide code files (.swift, .py, .ts, .js, .h, .c, .m, .sh, etc.)
- **Key findings**:
  - Production Assistant is centered in `SwiftCodeAssistant` module + `CodingAssistantModel` (IDECore) + `SwiftCodeMCPHost` (MCP). Powers 13 backends (Ollama, llama.cpp, OpenAI, Anthropic, Claude Code, Codex, Antigravity, ACP, OpenRouter, OpenCode, Hermes, FoundationModels, SCCloud, MetaAssist) via `AssistantProvider` & `AssistantBackends`.
  - SwiftCode-Legacy Assist contains exactly 291 tools registered in `AssistToolRegistry.swift` across `Tools/` and `Functions/`. Validated via `validate_tools.py` with 0 errors.
  - SwiftCode-Legacy System Assets contains exactly 33 Markdown files (authoritative behavioral training data), indexed via `SystemIndex.swift`.
  - MCP integration currently registers 433 tools in `SwiftCodeMCPHost.swift`. To satisfy R3, Assist must be restricted across MCP exclusively to the 291 Legacy tools and 33 System Assets.
  - Repository contains 12,221 code files with 4,143,446 total lines and 620,098 comment lines (15.0%).
  - Safe comment removal strategy designed using language-specific lexer/FST engines preserving string literals, raw strings, multiline strings, regexes, shebangs, and nested Swift comments.
- **Unexplored areas**: None for survey scope.

## Key Decisions Made
- Cataloged all 291 legacy tools and 33 system assets with exact file paths and class names.
- Formulated complete Assist realignment plan (naming, legacy tool porting, training asset injection, and MCP restriction).
- Formulated multi-language AST/FST-based comment removal architecture with safety verifications and 2-line comment policy enforcement.

## Artifact Index
- DISPATCH.md — Task assignment and incoming messages
- BRIEFING.md — Situational awareness and identity
- progress.md — Heartbeat and activity log
- handoff.md — Final 5-component handoff report
