---
id: 11111111-1111-1111-1111-111111110001
author: SwiftCode Core Team
version: 1.0.0
tags: swiftui, performance, ui
recommendedTools: read_file, edit_file
guidance: Avoid complex nested lists; use LazyVStack and LazyHStack; profile body evaluations
---
# SwiftUI Performance Tuning

Maximize rendering frame rate and minimize view body updates in complex hierarchy views.

## Guidelines
- Avoid nesting scrollable lists inside Form containers.
- Flatten state bindings and utilize targeted @Observable states to isolate updates.
- Profile view body updates using Xcode Instruments to detect layout feedback loops.
