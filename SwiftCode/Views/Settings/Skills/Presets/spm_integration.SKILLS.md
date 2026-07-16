---
id: 11111111-1111-1111-1111-111111110008
author: Build Engineer
version: 1.0.2
tags: spm, build, package
recommendedTools: read_file, edit_file
guidance: Group related features inside modular SPM packages; avoid cyclic circular dependencies
---
# Swift Package Manager Setup

Structure modular monorepo projects, framework targets, and external open-source packages.

## Guidelines
- Define strict target dependency bounds in Package.swift.
- Avoid duplicate external source inclusions.
- Package local resource assets inside .process paths.
