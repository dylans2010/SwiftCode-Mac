---
id: 11111111-1111-1111-1111-111111110011
author: iOS Architect
version: 1.0.0
tags: swiftui, state, architecture
recommendedTools: read_file, edit_file
guidance: Isolate state mutations to dedicated @Bindable views; avoid global object binds
---
# SwiftUI State Isolation Patterns

Avoid unnecessary view updates and structural body re-evaluations.

## Guidelines
- Use local @State structs for layout-exclusive toggles.
- Pass model updates through environment scopes to child hierarchies.
- Ensure MainActor compatibility for multi-threaded state pipelines.
