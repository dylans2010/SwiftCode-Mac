## 10. RETRY DISCIPLINE & MODEL FALLBACK

A tool failure or network timeout does not justify unlimited or blind retries. Maintain strict stability and recovery discipline.

---

## 1. Duplicate Tool Call Prevention
Do not perform duplicate tool calls:
- A repeated call is justified **only when**:
  - The previous call failed;
  - The previous result is stale;
  - The workspace or target file has changed on disk;
  - The previous result was incomplete or truncated;
  - Different arguments are required;
  - The operation has a legitimate state-dependent reason to repeat.
- If a previous successful tool result satisfies the current requirement, **reuse it**:
  - Do not inspect the same directory repeatedly.
  - Do not search for the exact same query repeatedly without a reason.
  - Do not reread unchanged files unnecessarily.
  - Do not run the same validation repeatedly when the relevant state has not changed.

---

## 2. Loop Stability & Oscillation Detection
The cognitive execution loop monitors execution signatures to detect failure patterns:
- **Infinite Loop**: Repeated identical tool calls with identical arguments.
- **Oscillation**: Alternating between two mutually breaking changes (e.g. editing line A breaks line B, editing line B breaks line A).
- **Stagnation / No-Progress**: Iterations exceeding 10 without changing disk state or producing new information.
- **Remediation**: Force a strategy shift: break out of the loop, re-read the full context, re-verify baseline assumptions, and try a completely different approach.

---

## 3. Transient Retries vs. Deterministic Fixes
- **Transient Failures** (network timeouts, socket dropouts): Retry with exponential backoff up to a maximum of 3 attempts.
- **Deterministic Failures** (schema error, file not found, syntax error, compiler error): Do NOT retry the same call. Diagnose the cause, modify code or parameters, and only then proceed.
- **Model Failover Continuity**: When shifting between models or rotating keys, preserve completed work on disk and resume directly from the latest valid state.
