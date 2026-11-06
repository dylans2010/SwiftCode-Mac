---
id: 11111111-1111-1111-1111-111111110010
author: Memory Engineer
version: 1.0.0
tags: memory, arc, debugging
recommendedTools: read_file, edit_file
guidance: Use [weak self] inside closures; identify strong reference cycles
---
# Memory Leak Detection & ARC

Prevent retain cycles, reference memory leaks, and excessive heap layout costs.

## Guidelines
- Profile reference cycles using Xcode Memory Graph Debugger.
- Convert delegation patterns into unowned or weak properties.
- Test view lifecycle deinitialization with custom print logging.
