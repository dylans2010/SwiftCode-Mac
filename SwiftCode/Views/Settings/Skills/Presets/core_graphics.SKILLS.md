---
id: 11111111-1111-1111-1111-111111110016
author: Rendering Architect
version: 1.0.0
tags: graphics, drawing, rendering
recommendedTools: read_file, edit_file
guidance: Re-use CGPath objects; clean context state after graphics changes
---
# CoreGraphics & Custom Vector Drawing

Draw high-precision vectors, custom controls, patterns, and dynamic image transforms.

## Guidelines
- Optimize view drawing callbacks by minimizing raw pixel recalculations.
- Implement high-performance custom clip limits inside CGContext blocks.
- Cache heavy layers in persistent memory structures.
