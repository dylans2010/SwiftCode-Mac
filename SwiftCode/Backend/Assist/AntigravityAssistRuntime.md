# Antigravity Assist Runtime Architecture

This document details the ownership boundary and integration pattern between **Google Antigravity SDK** and **SwiftCode Assist**.

---

## 1. Ownership Boundary

### Antigravity (Agent Framework & Model Runtime)
Antigravity owns:
- Model execution and LLM inference loop
- Agentic reasoning, planning, and turn management
- Dynamic tool selection and argument generation
- Subagent and worker execution orchestration
- Context handling required by the Antigravity runtime
- Output streaming (text, thoughts, tool calls, and results)

### SwiftCode (Native Application Environment)
SwiftCode owns:
- Native Swift tool implementations (`SwiftCode/Backend/Assist/Tools/`)
- Local tool permissions (`AssistPermissionsManager`) and user approval workflows
- System prompts (`AgentSystemAsset.md`), instructions, and repository rules (`AGENTS.md`)
- User Interface (`AssistMainView`, native Markdown rendering, subtle tool activity disclosure)
- Session state, transcript management, and workspace state
- Worker/subagent visual presentation (`WorkerRuntimeState`, `WorkerEventBus`)
- End-to-end task cancellation and developer takeover

---

## 2. Integration & Data Flow Architecture

```
                       SWIFTCODE
               Native Application Layer
                          │
       ┌──────────────────┼──────────────────┐
       │                  │                  │
   Training             Tools                UI
       │                  │                  │
AgentSystemAsset.md   Assist Tools     AssistMainView
AGENTS.md            Permissions       Markdown
Memory Graph         Native APIs       Workers
Project Context      Project APIs      Tool Activity
       │                  │                  │
       └──────────────────┼──────────────────┘
                          │
                          ▼
                     ANTIGRAVITY
                   Agent Framework
                          │
               ┌──────────┼──────────┐
               │          │          │
             Model      Agent     Subagents
                        Loop     / Workers
               │          │          │
               └──────────┼──────────┘
                          │
                          ▼
                IPC / Unix Socket Bridge
                          │
                          ▼
                 SwiftCode Tools
                          │
                          ▼
                     macOS Host
```

---

## 3. Dynamic Tool Discovery & Execution

1. When an Antigravity session starts, SwiftCode serializes JSON schemas for all registered Swift tools from `AssistToolRegistry.shared.getToolSchemas()`.
2. Antigravity dynamically registers these schemas as executable tool functions inside its agent loop.
3. When Antigravity decides to execute a tool, it emits a `tool.execute` JSON-RPC request back over the IPC socket to SwiftCode.
4. SwiftCode validates input arguments, checks local permissions (`AssistPermissionsManager`), executes the Swift tool asynchronously, and returns structured results to Antigravity.
5. Antigravity receives the result and continues its iterative reasoning turn.

---

## 4. System Prompt Composition

The effective instruction context passed to Antigravity is composed hierarchically:

```
SwiftCode System Prompt (AgentSystemAsset.md)
  + Repository Rules (AGENTS.md)
  + Active Project / Workspace Structure
  + Active Session Transcript & Memory
  = Effective Antigravity Session Instructions
```

---

## 5. Event Pipeline & UI Representation

Antigravity events (`agent.progress`, `tool.started`, `tool.completed`, `tool.failed`, `worker.started`, `worker.completed`) are translated at the IPC transport boundary into native SwiftCode models:
- Streaming Markdown content is parsed incrementally via `MarkdownParser.shared`.
- Tool execution is displayed as compact, non-intrusive activity items in `AssistMessage.activityGroup`.
- Worker events update `WorkerRuntimeState` and publish to `WorkerEventBus`.
