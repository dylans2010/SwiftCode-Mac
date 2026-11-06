---
id: 11111111-1111-1111-1111-111111110003
author: Swift Concurrency Architect
version: 1.1.0
tags: swift6, concurrency, async
recommendedTools: read_file, edit_file
guidance: Isolate UI updates to the @MainActor; Use Sendable collections and value types
---
# Swift 6 Concurrency

Achieve complete compile-time data isolation and eliminate data races safely.

## Guidelines
- Use Task { @MainActor in } blocks for GUI rendering updates.
- Mark immutable parameters and models as Sendable.
- Replace legacy locks and Semaphores with async Actors for unified state access.
