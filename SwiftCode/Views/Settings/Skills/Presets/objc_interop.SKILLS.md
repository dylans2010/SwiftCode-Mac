---
id: 11111111-1111-1111-1111-111111110020
author: Refactoring Specialist
version: 1.0.0
tags: objc, legacy, interoperability
recommendedTools: read_file, edit_file
guidance: Expose Swift API classes with @objc annotations; enforce strict nullability declarations
---
# Objective-C & Swift Interoperability

Bridge older codebase headers, pointers, types, and modern Swift codeblocks.

## Guidelines
- Define clear bridging configuration pathways in your project header files.
- Resolve any unsafe C-pointer parameters cleanly inside typed Swift contexts.
- Isolate legacy Objective-C dependencies behind clean, modern protocols.
