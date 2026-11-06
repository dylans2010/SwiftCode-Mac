---
id: 11111111-1111-1111-1111-111111110004
author: Refactoring Specialist
version: 1.0.0
tags: concurrency, thread, legacy
recommendedTools: read_file, edit_file
guidance: Do not mix DispatchGroup with structured tasks; Use TaskGroup instead of DispatchGroup
---
# Grand Central Dispatch vs Async-Await

Migrate legacy DispatchQueues safely into Structured Async-Await tasks.

## Guidelines
- Avoid callback blocks using escaping closures; wrap them inside withCheckedContinuation.
- Group concurrent service requests inside an withTaskGroup scope.
- Enforce strict structured task cancellation handling.
