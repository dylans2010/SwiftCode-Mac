---
id: 11111111-1111-1111-1111-111111110015
author: AV Specialist
version: 1.0.0
tags: avfoundation, media, video
recommendedTools: read_file, edit_file
guidance: Initialize capture sessions on background threads; release hardware descriptors properly
---
# AVFoundation Media Processing Scopes

Process rich audio signals, video frames, camera inputs, and system capture flows.

## Guidelines
- Handle real-time hardware interruption callbacks elegantly.
- Utilize hardware-accelerated encoders for file compression.
- Enforce secure microphone and camera permissions flags.
