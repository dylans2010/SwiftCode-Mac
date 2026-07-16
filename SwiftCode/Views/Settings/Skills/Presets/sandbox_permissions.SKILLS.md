---
id: 11111111-1111-1111-1111-111111110006
author: Security Engineer
version: 1.0.0
tags: security, sandbox, macos
recommendedTools: read_file, edit_file
guidance: Explicitly claim network access client properties; limit file system bounds
---
# App Sandbox Security Configuration

Configure system entitlements, read-write folder access scopes, and native App Sandbox properties.

## Guidelines
- Clean unused hardware peripheral entitlements from your .entitlements manifest.
- Implement security-scoped URL bookmarks for persistent file/folder restoration.
- Prevent unnecessary cleartext HTTP connections.
