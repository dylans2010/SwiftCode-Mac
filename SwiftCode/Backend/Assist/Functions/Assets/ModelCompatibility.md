# MULTI-PROVIDER MODEL COMPATIBILITY

SwiftCode Assist abstracts differences between model providers while enforcing uniform agentic standards.

---

## 1. Supported Model Families
The Assist runtime supports multiple model providers:
- **Anthropic Claude**: Claude 3.5 Sonnet, Claude 3 Opus, Claude 3.5 Haiku.
- **Google Gemini**: Gemini 1.5 Pro, Gemini 1.5 Flash, Gemini 2.0.
- **OpenAI**: GPT-4o, GPT-4o mini, o1, o3-mini.
- **OpenRouter & Mistral**: DeepSeek, Mistral Large, Qwen, Llama 3 models.
- **Local Models**: Ollama, LM Studio, Apple Foundation Models (AFM).

---

## 2. Universal Agentic Operating Standards
Regardless of which model provider powers the session, the agent operates under strict engineering discipline:
- **Direct Action Over Conversation**: Do not output conversational apologies, fillers, or prospective promises ("I will now edit this file"). Invoke the tool immediately.
- **Zero Speculative Success**: Never assume or report that a command, build, or test passed without physical exit code 0 evidence.
- **Loop Stability & Self-Healing**: When an error occurs, analyze the diagnostic, adjust parameters, and alter strategy. Never repeat identical tool calls with identical arguments in consecutive turns.
- **Relative Paths Only**: File paths must always be workspace-relative.

---

## 3. Capability Negotiation & Seamless Failover
- **Alternative Key Management**: When an API provider returns rate limits (429) or quota exhaustion, `AlternativeKeyManager` and `AssistModelRouter` automatically rotate credentials or failover to alternative provider tiers.
- **Task Continuity Across Failovers**:
  - A model switch or key rotation does **NOT** restart the task from scratch.
  - Inspect current workspace state on disk as ground truth.
  - Reuse the accumulated session trajectory and context history.
  - Continue directly from the last valid checkpoint without repeating completed work.
