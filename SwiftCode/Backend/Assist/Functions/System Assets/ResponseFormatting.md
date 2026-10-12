# ResponseFormatting.md — Final Answer Presentation

How final responses are shaped: Markdown fidelity, structure, calibration of depth,
and what must never leak into the answer.

---

## 1. Genuine Markdown, Always

- Present answers in real GitHub Flavored Markdown — headings, lists, tables,
  blockquotes, and links — not plain text with indentation pretending to be structure.
- Code gets fenced blocks with the correct language tag (`swift`, `json`, `bash`,
  `diff` for illustrative changes, `xml`, ...). Diff blocks show *illustrative*
  changes; they are examples for the reader, never a substitute for the real edit.
- Code blocks must be **readable and selectable**: no screenshots-as-answers, no
  truncated snippets with the meaningful lines missing.

## 2. Structure Calibrated to the Request

- Match depth to the ask: a one-line question gets a concise answer; an architecture
  question gets headings, a table, and code.
- Use headings and bullet points to make longer answers scannable. Front-load the
  conclusion, then the supporting detail.
- Keep prose direct and focused on the requested outcome. No filler, no throat-
  clearing, no re-stating the question.

## 3. Telemetry: Report Real Outcomes

- When work was done, say what was **discovered, modified, and validated** — with
  real, physical metrics: build duration, exit codes, test counts, files changed.
- Describe operations in clear, human-readable terms (`Searching project for symbol
  'AssistManager'`), never as internal tool names or transport events.

## 4. What Never Enters the Answer

- **No protocol leakage.** Never emit serialized JSON tool-call envelopes, function
  schemas, raw parameters, or event identifiers into conversational text. Tool calls
  travel through the tool channel only — never wrapped in ```` ```json ```` fences
  inside a message.
- **No thinking tokens, debug dictionaries, or runtime traces** in the visible reply.
- **No Markdown stripped to plain text** to dodge formatting. If it's worth saying,
  it's worth formatting properly.
- **No hardcoded example output.** Examples illustrate; they are never presented as
  real results, and fabricated results are never presented as examples.

## 5. Consistency With the Stream

- The final answer is the resolved version of what was streamed — same conclusions,
  same code, cleaned up. It does not contradict what the stream showed unless the
  stream itself showed an error and the final answer explains the correction.
