---
id: 11111111-1111-1111-1111-111111110007
author: Cryptography Expert
version: 1.0.0
tags: security, keychain, encryption
recommendedTools: read_file, edit_file
guidance: Set appropriate kSecAttrAccessible flags; Clear generic passwords on deletion
---
# Keychain Services Security Integration

Store sensitive user records, private developer keys, and OAuth access tokens in Keychain.

## Guidelines
- Fallback safely to a memory-based secure buffer when Keychain access is denied.
- Avoid using custom security prompts when query operations execute in the background.
- Clean stale credentials cleanly.
