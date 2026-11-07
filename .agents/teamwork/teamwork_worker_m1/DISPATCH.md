# Worker M1 Dispatch

## Mission
Implement Milestone 1: Baseline Compiler Fixes & Code Comment Removal Script.

## Write Ownership
You exclusively own:
- `swiftcode/Sources/SwiftCodeCollaboration/PeerSessionManager.swift`
- `swiftcode/Sources/SwiftCodeBuild/Resolution/BuildDestinationResolver.swift`
- `swiftcode/Sources/SwiftCodeBuild/Management/XcodeBuildManager.swift`
- `swiftcode/Sources/SwiftCodeGitHub/Views/GitHubWorkflowsSidebarView.swift` (move/relocate or fix)
- `swiftcode/Sources/SwiftCodeUI/CI/GitHubWorkflowsSidebarView.swift`
- `tools/strip_comments.py`
- `tools/check_comment_policy.py`
- All source files repository-wide modified by `tools/strip_comments.py`

## Instructions & Hand-offs
Read:
- `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/ORIGINAL_REQUEST.md`
- `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/PROJECT.md`
- `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_1/handoff.md` (exact patch code for compiler fixes)
- `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_2/handoff.md` (exact code for `tools/strip_comments.py`)
- `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_3/handoff.md` (exact code for `tools/check_comment_policy.py`)

## Implementation Steps
1. Apply baseline compiler fixes:
   - In `swiftcode/Sources/SwiftCodeCollaboration/PeerSessionManager.swift`: add `public nonisolated func` to the 11 delegate methods.
   - In `swiftcode/Sources/SwiftCodeBuild/Resolution/BuildDestinationResolver.swift` and `XcodeBuildManager.swift`: add `import SwiftCodeSubprocess`.
   - In `swiftcode/Sources/SwiftCodeGitHub/Views/GitHubWorkflowsSidebarView.swift`: relocate to `swiftcode/Sources/SwiftCodeUI/CI/GitHubWorkflowsSidebarView.swift` with appropriate imports (`SwiftCodeIDEShell`), removing the duplicate/cyclic copy in `SwiftCodeGitHub`.
   - Run `cd swiftcode && swift build` to verify the package compiles cleanly.
2. Create `tools/strip_comments.py`:
   - Implement the complete FST multi-language comment stripper from `teamwork_explorer_m1_2/handoff.md`.
   - Preserve line 1 shebangs (`#!/...`).
   - Preserve strings, raw strings, regexes, and nested block comments.
   - Preserve `.pbxproj` OpenStep structural comments (`/* Begin PBXBuildFile section */`).
   - Execute `python3 -I tools/strip_comments.py` repository-wide.
3. Create `tools/check_comment_policy.py`:
   - Implement the policy checker from `teamwork_explorer_m1_3/handoff.md`.
   - Run `python3 -I tools/check_comment_policy.py --all` to verify zero violations of the max 2-line comment rule.
4. Verify:
   - `python3 -m py_compile tools/strip_comments.py tools/check_comment_policy.py`
   - `cd swiftcode && swift build` succeeds with exit code 0.
   - Document commands, outputs, and diff statistics in `handoff.md`.

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Working Directory
/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m1/

## Output
Write completion report to `/Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m1/handoff.md`.

## 2026-11-07T01:05:34Z
[Message] timestamp=2026-11-07T01:05:34Z sender=d5b41c16-417f-423a-b7f8-eea4f0706fc5 priority=MESSAGE_PRIORITY_HIGH content=You are teamwork_worker_m1.
Your working directory is: /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m1/
Read your task assignment in: /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m1/DISPATCH.md
Also read:
- /Users/dylan/Downloads/SwiftCode/.agents/teamwork/ORIGINAL_REQUEST.md
- /Users/dylan/Downloads/SwiftCode/.agents/teamwork/PROJECT.md
- /Users/dylan/Downloads/SwiftCode/AGENTS.md
- /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_1/handoff.md
- /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_2/handoff.md
- /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_explorer_m1_3/handoff.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Task:
1. Apply the baseline compiler fixes in swiftcode:
   - PeerSessionManager.swift (add public nonisolated func to 11 delegate methods)
   - BuildDestinationResolver.swift and XcodeBuildManager.swift (import SwiftCodeSubprocess)
   - Relocate GitHubWorkflowsSidebarView.swift from SwiftCodeGitHub/Views/ to SwiftCodeUI/CI/ and resolve scope
   - Verify `cd swiftcode && swift build` succeeds cleanly.
2. Implement tools/strip_comments.py and execute repository-wide:
   - FST multi-language comment stripper preserving shebangs, strings, raw strings, regexes, and .pbxproj OpenStep comments.
   - Run python3 -I tools/strip_comments.py.
3. Implement tools/check_comment_policy.py:
   - Validate comment block length <= 2 lines.
   - Run python3 -I tools/check_comment_policy.py --all.
4. Run verification:
   - Compile python tools (py_compile).
   - Re-run `cd swiftcode && swift build` post-strip to verify zero syntax breakages.
5. Write your comprehensive handoff report to /Users/dylan/Downloads/SwiftCode/.agents/teamwork/teamwork_worker_m1/handoff.md.

Update your progress.md periodically for liveness. When finished, send a message to orchestrator.

## 2026-11-07T01:21:26Z
[Message] timestamp=2026-11-07T01:21:26Z sender=d5b41c16-417f-423a-b7f8-eea4f0706fc5 priority=MESSAGE_PRIORITY_HIGH content=**Context**: Checking build and strip status
**Content**: Heartbeat check: It has been ~11 minutes since progress.md was updated during `swift build` (task-85). Has the build completed, and what is your current status?
**Action**: Please update your progress.md with your latest status and proceed with Task 2 (tools/strip_comments.py) and Task 3 (tools/check_comment_policy.py).
