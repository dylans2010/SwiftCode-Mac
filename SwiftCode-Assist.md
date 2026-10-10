# SwiftCode-Mac: review of Assist and the Antigravity SDK bridge

Repo `dylans2010/SwiftCode-Mac` at HEAD `0888460` (Oct 10, 2026). Read-only review: nothing was built or run.

## Where things are
- The top-level `Assist/` folder is just a link to `SwiftCode/Backend/Assist/Subagents`. The real code is in `SwiftCode/Backend/Assist/` (~33k lines).
- Swift bridge: `SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/` (Process, Transport, Bridge, Runtime, Session, Configuration, LifecycleManager, Tests).
- Python bridge: `SwiftCode/Resources/Google Cloud SDK/bridge/` (`main.py`, `agent_runner.py`, `model_adapter_server.py`, `protocol.py`).
- Bundles `google-antigravity` 0.1.20 (0.1.21 shipped Oct 7). The app spawns Homebrew Python 3.14, talks over a local socket, and runs the SDK `Agent`; a local HTTP adapter handles third-party models.
- App Sandbox off, Hardened Runtime on, only entitlement `com.apple.security.virtualization`.

## Verdict by area
| Area | Verdict |
|---|---|
| Agentic loop | Partial: SDK loop works; no step/token budget, cancel doesn't stop Swift tools |
| Third-party models | Partial: routing and adapter are real, but config keys mismatch and fields get dropped |
| Tool calling / outputs | Broken in the default "System" toolkit |
| Token streaming | Works, but slow per-token work on the main thread and some replies buffered |
| Speed with default models | Partial: no prewarm, prompt sent twice, cold start on first message |
| No hardcoded UI messages | Mostly OK, with some canned/fabricated strings; thinking never shown |
| Dead code / setup | Significant |

## Critical issues (fix first)
1. **Model never sees tool results in `data`.** `GoogleCloudSDKRuntime.swift:144` returns only `result.output`. `file_read` returns `.success("Successfully read file: \(path)", data: ["content": content])` (`Tools/AssistReadFileTool.swift:39`), so the model never gets file contents. Same for `tree_view`, `env_info`, `env_capture_logs`, `compiler_diagnostics_engine`, `project_changelog`, `autonomous_review_engine`, `capture_memory`, and others. The UI shows the same useless sentence.
2. **Terminal tool always denied.** `AssistPermissionsManager.swift:35-41` substring-matches "rm", "delete", etc., with `requiresApproval` always false. `use_terminal` (te**rm**inal) and `code_format` (fo**rm**at) contain "rm", so they, `file_delete` and `dir_delete` always fail with "Permission denied" (called from `GoogleCloudSDKRuntime.swift:99`). The alias `run_command` gets through.
3. **Read-only result cache returns wrong/stale data** (`GoogleCloudSDKRuntime.swift:114-124`; key in `AssistEventNormalizer.swift:23` is tool + path/query/cmd only). `plan-AskUser` and `execution_plan` replay the first answer; `project_diff`, `env_capture_logs`, `code_review`, `safe_validate_changes` go stale; terminal/Cloud-tool edits never invalidate it.
4. **Non-ASCII can kill the connection.** `main.py:243` decodes each 4096-byte read separately; a split multi-byte char raises and exits the loop (`:265-267`). System prompts contain lots of non-ASCII (e.g. `AgentSystemAsset.md`). Fix: buffer bytes and split on `b"\n"`, or `reader.readline()`.
5. **Shutdown deadlock + orphaned processes.** `agent_runner.py:930-933` `stop_all` holds the lock while `close_session` (`:911`) re-acquires it (asyncio locks aren't reentrant). `runtime.stop` (`main.py:154`) and SIGTERM (`:324`) hang with any session. Socket mode keeps serving after Swift disconnects (`:288`). Swift never calls `GoogleCloudSDKProcess.kill()`; `applicationWillTerminate` doesn't stop the bridge.
6. **Prompt sent twice every turn.** `AssistManager.swift:907` builds `"# TASK OBJECTIVE\n\(content)\n\n\(basePrompt)"` and `basePrompt == content` with no extras.

## Agent loop and cancellation
- Python times out Swift tools at 120s (`main.py:100`), but terminal approval waits forever and builds run long.
- Cancel never reaches in-flight Swift tools (`Transport.executeTool`).
- `interruptActiveSessionAndSend` sleeps 150 ms then resends (`AssistManager.swift:536`); can hit "currently processing another turn" (`agent_runner.py:811`) and trigger model failover.
- Crashes undetected: `runtime.stopped` never sent/handled, `isRunning` stays true, event subscription not recreated, stale session id leads to failover. `LifecycleManager.startMonitoring()` never called.
- Restart race: old process termination handler deletes the current `socketPath` (`GoogleCloudSDKProcess.swift:226`).
- `session.resume` just creates a new session (`main.py:179`).

## Third-party models
- LiteRT key mismatch: Swift sends `litertModelPath` (`GoogleCloudSDKConfiguration.swift:336`), Python reads `modelPath`/`model_path` (`agent_runner.py:656`).
- `AssistModelRouter.buildSDKConfiguration` (`AssistModelRouter.swift:447-477`) drops LiteRT fields and re-resolves the API key, discarding the alternative-key choice (`GoogleCloudSDKConfiguration.swift:197-201`).
- Ignored by Python: `serviceTier`, `allowedSubagents`, `useSavedModels`, `attachments`. Vertex hardcoded off; `maxSubagentDepth` fixed at 3.
- Adapter `find_target` falls back to the first target (`model_adapter_server.py:525-564`), can misroute with the wrong provider's key.
- With tools registered, replies starting with `{`, `` ` ``, `<`, `[` are buffered to the end (`:910-948`, also `_pipe_openai_request`).
- Adapter on 127.0.0.1 has no auth while holding API keys.
- `AssistManager.swift:1265` masks any Gemini error as "All configured Gemini API keys are currently unavailable."

## Tool calling (other)
- Broken aliases in `AssistToolRegistry.swift:179-187` (`directory_read`, `search`, `directory_create`, `directory_delete` vs real `dir_read`, `search_text`, `dir_create`, `dir_delete`).
- All ~68 tool schemas sent every session in System mode.
- Subagent tracking: `UUID(uuidString: workerId) ?? UUID()` (`GoogleCloudSDKRuntime.swift:315/337/351/365`) with `call_xxx` IDs gives random UUIDs, so workers never complete; `parentTaskID: UUID()` at `:322`.
- `reportTool*` / `reportWorker*` target `messages.indices.last` (`AssistManager.swift:1302` etc.); fallback observer at `:160` can insert a System message mid-turn.
- Cloud toolkit uses `policy.allow_all()` (`agent_runner.py:633`), bypassing terminal approval; `:634-636` redundant.
- `sanitize_schema` uses `json.dumps` without importing `json` in `agent_runner.py`; caching silently skipped.
- Attachments sent as base64 (`AssistManager.swift:819-821`) but `send_message` only calls `agent.chat(content)`.

## Streaming and UI performance
- Per delta on MainActor: `firstIndex` search + full `@Published messages` replace (`AssistManager.swift:946-976`), ~17-regex `AssistSanitizer.sanitize`, `AssistToolPayloadStreamFilter.append` re-lowercasing up to 256KB (`:1528-1529`), roughly quadratic.
- View: full Markdown re-parse per render (`AssistMainView.swift:1283`), non-lazy `VStack` (`:176`), animated `scrollTo` on every status change (`:243-251`).
- Leak filter suppresses legit prose with `"name"`+`"arguments"` or `"jsonrpc"`+`"method"` (`:1683-1687`), triggers retry, then "invalid tool-call format…" (`:1107`); final sanitize (`:1812`) strips JSON-RPC examples.
- Blocking `Darwin.read` in `Task.detached` (`GoogleCloudSDKTransport.swift:233-238`); fd closed from another thread; no SIGPIPE guard.
- `session.create` runs inline in Python's read loop (`main.py:258`) under a 30s Swift timeout (`GoogleCloudSDKBridge.swift:87`).

## Speed with default models
- `prewarm()` and `startMonitoring()` never called; first message pays Python start, SDK import, possible 37MB harness unpack, socket polling, session start.
- `isAvailable` set async in `init` (`GoogleCloudSDKRuntime.swift:32-36`), read immediately in `sendMessage` (`AssistManager.swift:209`); can fall through to the old native loop.
- Config rebuilt twice per turn with Keychain reads and directory creation.
- Sleeps: 150 ms on interrupt, 2s on Gemini key rotation.

## Hardcoded / fabricated user-facing strings
- `agent_runner.py:864`, `:874` inject "[Interrupted by user]" as model output; `:850`, `:884` "Turn completed without explicit tool completion" / "Turn finished" as tool failures.
- `GoogleCloudSDKRuntime.swift:343/357/371` "Subagent Progress/Completed/Failed".
- `AssistEventNormalizer.swift:57-70` generic errors ("Search failed", "File read failed"…); `:296` "Streaming output…".
- `AssistManager.swift` `:920`, `:1028`, `:1078`, `:1107`, `:1147`+`:1152` (back-to-back, first never visible), `:1166`, `:1198`, `:1265`, `:1468` ("Worker completed").
- `ToolExecutionView.swift:72` "Building project…", `:106` "Generating response…".
- SDK version "0.1.20" hardcoded in `GoogleCloudSDKRuntime.swift:22`, `GoogleCloudSDKBridge.swift:17`, `GoogleCloudSDKTransport.swift:353`, `main.py:147/163/226/312`.
- `AssistActivityView.swift:207` prefers streamed output over final result; tool headers use template labels.
- `thinkingContent` collected (`AssistManager.swift:958`) but never rendered.

## Dead code
- Old autonomous engine: `AssistAgent.processIntent` never called (`AssistManager.swift:152`, `:218`). Makes `_AssistCriticalAutonomousEngine` (TODO stubs at `:204`, `:207`, `:317`) and ~2.9k lines in `Assist Frameworks/*.swift` unused: `_AssistCritical{Execution,Validation,TaskOrchestrator,CodebaseAnalyzer}`, `AssistGoalExpansion`, `AssistLoopStabilityRegulator`, `AssistResourceUsageMonitor`, `AssistOptimizationEngine`, `AssistMemoryConsistencyValidator`, `AssistContextDriftDetector`, `AssistRiskAssessmentEngine`, `AssistCodeIntegrityScanner`, `AssistExecutionContextPersistenceStore`, `AssistRuntimeBehaviorMonitor`, `AssistPerformanceProfilingEngine`, `AssistTaskContinuationEngine`, `AssistProgressEvaluator`, `AssistFailureRootCauseAnalyzer`, `AssistRecoveryStrategyGenerator`, `AssistOutputVerificationEngine`, `AssistExecutionTraceEngine`, `AssistAutonomousDecisionEngine`.
- Unreferenced: `WorkerTaskDecomposer`, `WorkerRecapGenerator`, `AssistSkillsCheck`, `AssistFileFunctions`, `GoogleCloudSDKMessage`/`GoogleCloudSDKRole` (tests only), `GoogleCloudSDKServiceTier`, `LiteRTBackendType`, `prewarm()`, `startMonitoring()`, `Process.kill()`, `.workerProgress`/`.runtimeStopped` events.
- Test suites compiled into the app: `GoogleCloudSDKTests`, `AssistRuntimeTestSuite`, `AssistModelRouterTests`, `AssistPromptOptimizerTests`, `SystemAssetLoaderTests` (`--run-assist-tests`).
- Parallel non-SDK loops: `AssistAgentSession` and chat via `LLMService`.

## Setup problems
- Needs Homebrew/system Python 3.14 (cpython-314 modules only); harness arm64 only.
- Harness unpacked from `localharness.gz` into the app bundle at runtime (`main.py:25-36`), breaking code signing; fails silently if `/Applications` isn't writable.
- 2,307 `__pycache__` files committed; SDK folder 126MB.
- Xcode build script (~`project.pbxproj:10482`) runs `rm -rf /Applications/SwiftCode.app` every build.
- `Package.swift` declares no resources, so SwiftPM builds lack the SDK.

## Prioritized fixes
1. Return the full tool payload (merge `data` or send structured JSON) in `executeSwiftTool`.
2. Fix `authorizeOperation`: exact tool IDs / risk levels, wired to a real approval flow.
3. Fix or remove the read-only cache (all args in key, exclude interactive/planning tools, invalidate after edits).
4. Fix UTF-8 framing in `main.py` and the `stop_all`/`close_session` deadlock.
5. Exit Python on Swift disconnect, stop bridge on quit, kill on hang, fix socket-delete race.
6. Remove the duplicated prompt; call `prewarm()`; start `startMonitoring()`; make `isAvailable` synchronous.
7. Handle `runtime.stopped`, recreate session on not-found, use SDK conversation resume.
8. Map worker IDs as strings; target events at `targetAssistantMessageId`.
9. Propagate tool cancellation to Swift; align the 120s timeout or send heartbeats.
10. Streaming UI: coalesce deltas every 30-50 ms into a separate observable, `LazyVStack`, incremental Markdown, filter only new text, drop the broad `"name"`+`"arguments"` heuristic, sanitize once at the end.
11. Config: fix `litertModelPath`; keep LiteRT/alt-key settings in `buildSDKConfiguration`; pass `budget_config`, `retry_config`, `compaction_config`, attachments; consider MCP servers; read SDK version dynamically; auth token on the adapter; stop masking errors.
12. Delete dead `AssistAgent`/`Assist Frameworks` chain, unused types and in-app tests; fix aliases; remove `__pycache__`; bundle Python; update to SDK 0.1.21.
