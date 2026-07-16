---
id: 11111111-1111-1111-1111-111111110005
author: Net Specialist
version: 1.0.0
tags: networking, urlsession, api
recommendedTools: read_file, edit_file
guidance: Implement correct URLRequest timeout intervals; use standard URLCache instances
---
# URLSession Networking Best Practices

Implement highly resilient HTTP networking operations, cache layers, and custom policies.

## Guidelines
- Support automatic retry strategies with exponential delay backoffs.
- Intercept HTTP status codes (such as 401 Unauthorized) to renew access tokens seamlessly.
- Compress large payload bodies before dispatching upstream requests.
