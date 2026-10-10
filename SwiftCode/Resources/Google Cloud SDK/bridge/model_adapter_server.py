"""
OpenAI-Compatible Local Adapter Server for Antigravity SDK.
Enables Antigravity's LocalOpenAIAgentConfig to route seamlessly to:
- Anthropic (Claude 3.5 Sonnet, 3.7 Sonnet, Opus, Haiku)
- OpenAI (GPT-4o, GPT-4o-mini, o1, o3-mini)
- OpenRouter
- Mistral (Mistral Large, Codestral)
- Qwen (Qwen 2.5, QwQ via DashScope or vLLM)
- Ollama / LM Studio (Local models)
- Custom OpenAI-compatible endpoints
"""

from __future__ import annotations
import asyncio
import json
import logging
import os
import re
import sys
import time
import uuid
from typing import Any, AsyncGenerator, Dict, List, Optional, Set, Tuple

# Ensure bundled site-packages are accessible even when imported standalone
bridge_dir = os.path.dirname(os.path.abspath(__file__))
sdk_root = os.path.dirname(bridge_dir)
site_packages = os.path.join(sdk_root, "runtime", "lib", "python3.14", "site-packages")
if os.path.isdir(site_packages) and site_packages not in sys.path:
    sys.path.insert(0, site_packages)

import httpx

logger = logging.getLogger("ModelAdapterServer")

_normalized_schema_cache: Dict[str, Any] = {}


def normalize_schema(schema: Any) -> Any:
    """Normalizes JSON schemas to ensure compatibility with strict OpenAI/Anthropic/Mistral validators.
    Converts types to lowercase, sets type='object' for object schemas, sanitizes fields,
    and handles nested structures recursively.
    """
    if not isinstance(schema, dict):
        return {"type": "object", "properties": {}}

    cache_key = None
    try:
        cache_key = json.dumps(schema, sort_keys=True)
        if cache_key in _normalized_schema_cache:
            return dict(_normalized_schema_cache[cache_key])
    except Exception:
        cache_key = None

    cleaned = dict(schema)
    cleaned.pop("$schema", None)

    # Normalize type definition
    if "type" in cleaned:
        t = cleaned["type"]
        if isinstance(t, str):
            cleaned["type"] = t.lower()
            if cleaned["type"] in ("any", "anyvalue"):
                cleaned.pop("type", None)
        elif isinstance(t, list):
            cleaned["type"] = [x.lower() if isinstance(x, str) else x for x in t]

    # If type is omitted, infer from properties or items
    if "type" not in cleaned:
        if "properties" in cleaned:
            cleaned["type"] = "object"
        elif "items" in cleaned:
            cleaned["type"] = "array"
        else:
            cleaned["type"] = "object"

    if cleaned.get("type") == "object":
        if "properties" in cleaned and isinstance(cleaned["properties"], dict):
            cleaned["properties"] = {
                k: normalize_schema(v) for k, v in cleaned["properties"].items()
            }
        else:
            cleaned["properties"] = {}

        if "required" in cleaned:
            if isinstance(cleaned["required"], list):
                cleaned["required"] = [
                    str(r) for r in cleaned["required"] if isinstance(r, (str, int))
                ]
            else:
                cleaned.pop("required", None)

        if "additionalProperties" in cleaned and isinstance(cleaned["additionalProperties"], dict):
            cleaned["additionalProperties"] = normalize_schema(cleaned["additionalProperties"])

    elif cleaned.get("type") == "array":
        if "items" in cleaned:
            items = cleaned["items"]
            if isinstance(items, dict):
                cleaned["items"] = normalize_schema(items)
            elif isinstance(items, str):
                cleaned["items"] = {"type": items.lower()}
        else:
            cleaned["items"] = {"type": "string"}

    for composite in ("allOf", "anyOf", "oneOf"):
        if composite in cleaned and isinstance(cleaned[composite], list):
            cleaned[composite] = [normalize_schema(item) for item in cleaned[composite]]

    if cache_key:
        _normalized_schema_cache[cache_key] = cleaned

    return cleaned


def extract_catalog_tool_names(payload: Dict[str, Any]) -> Set[str]:
    """Extracts registered tool names from OpenAI tools payload."""
    names: Set[str] = set()
    tools = payload.get("tools", [])
    if isinstance(tools, list):
        for t in tools:
            if isinstance(t, dict):
                fn = t.get("function")
                if isinstance(fn, dict) and "name" in fn and isinstance(fn["name"], str):
                    names.add(fn["name"].strip())
                elif "name" in t and isinstance(t["name"], str):
                    names.add(t["name"].strip())
    return names


OPEN_THINK_TAGS = ["<think>", "<thought>", "<reasoning>"]
CLOSE_THINK_TAGS = ["</think>", "</thought>", "</reasoning>"]


class ThinkTagStreamParser:
    """Parses <think>, <thought>, and <reasoning> tags across streaming text deltas.
    Emits thought deltas and prevents reasoning from leaking into visible content.
    Handles tags split across chunk boundaries case-insensitively.
    """
    def __init__(self):
        self.inside_think = False
        self.buffer = ""
        self.has_emitted_content = False

    def process_delta(self, text: str) -> List[Tuple[str, str]]:
        if not text:
            return []

        self.buffer += text
        results: List[Tuple[str, str]] = []

        while self.buffer:
            lower = self.buffer.lower()
            if not self.inside_think:
                earliest_idx = -1
                matched_open = ""
                for tag in OPEN_THINK_TAGS:
                    idx = lower.find(tag)
                    if idx != -1 and (earliest_idx == -1 or idx < earliest_idx):
                        earliest_idx = idx
                        matched_open = tag

                if earliest_idx == -1:
                    max_check = min(12, len(self.buffer))
                    possible_partial = False
                    for i in range(max_check, 0, -1):
                        tail = lower[-i:]
                        if any(t.startswith(tail) for t in OPEN_THINK_TAGS):
                            content = self.buffer[:-i]
                            if content:
                                results.append(("content", content))
                                self.has_emitted_content = True
                            self.buffer = self.buffer[-i:]
                            possible_partial = True
                            break
                    if not possible_partial:
                        results.append(("content", self.buffer))
                        self.has_emitted_content = True
                        self.buffer = ""
                    break
                else:
                    content = self.buffer[:earliest_idx]
                    if content.strip():
                        results.append(("content", content))
                        self.has_emitted_content = True
                    elif self.has_emitted_content and content:
                        results.append(("content", content))
                    self.inside_think = True
                    self.buffer = self.buffer[earliest_idx + len(matched_open):]
            else:
                earliest_close_idx = -1
                matched_close = ""
                for tag in CLOSE_THINK_TAGS:
                    idx = lower.find(tag)
                    if idx != -1 and (earliest_close_idx == -1 or idx < earliest_close_idx):
                        earliest_close_idx = idx
                        matched_close = tag

                if earliest_close_idx == -1:
                    max_check = min(13, len(self.buffer))
                    possible_partial = False
                    for i in range(max_check, 0, -1):
                        tail = lower[-i:]
                        if any(t.startswith(tail) for t in CLOSE_THINK_TAGS):
                            thought = self.buffer[:-i]
                            if thought:
                                results.append(("thought", thought))
                            self.buffer = self.buffer[-i:]
                            possible_partial = True
                            break
                    if not possible_partial:
                        results.append(("thought", self.buffer))
                        self.buffer = ""
                    break
                else:
                    thought = self.buffer[:earliest_close_idx]
                    if thought:
                        results.append(("thought", thought))
                    self.inside_think = False
                    self.buffer = self.buffer[earliest_close_idx + len(matched_close):]

        return results

    def flush(self) -> List[Tuple[str, str]]:
        results: List[Tuple[str, str]] = []
        if self.buffer:
            kind = "thought" if self.inside_think else "content"
            clean = re.sub(
                r"</?(?:think|thought|reasoning)>?",
                "",
                self.buffer,
                flags=re.IGNORECASE,
            )
            if clean:
                results.append((kind, clean))
            self.buffer = ""
        return results


def strip_think_tags(text: str) -> Tuple[str, Optional[str]]:
    """Extracts thinking from text and returns (clean_content, extracted_thinking)."""
    if not text:
        return "", None
    thoughts: List[str] = []
    pattern = re.compile(
        r"<(think|thought|reasoning)>([\s\S]*?)(?:</\1>|$)",
        re.IGNORECASE,
    )

    def replacer(match: re.Match) -> str:
        thoughts.append(match.group(2))
        return ""

    clean = pattern.sub(replacer, text)
    clean = re.sub(r"</?(?:think|thought|reasoning)>", "", clean, flags=re.IGNORECASE)
    thought_str = "\n\n".join(t.strip() for t in thoughts if t.strip()) if thoughts else None
    return clean.strip(), thought_str


def find_json_objects(text: str) -> List[Tuple[int, int, str]]:
    """Finds balanced top-level JSON objects in text (start_idx, end_idx, json_str)."""
    results: List[Tuple[int, int, str]] = []
    start = -1
    depth = 0
    in_string = False
    escape = False

    for i, char in enumerate(text):
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif char == "}":
                if depth > 0:
                    depth -= 1
                    if depth == 0 and start != -1:
                        results.append((start, i + 1, text[start:i + 1]))
                        start = -1

    return results


class ParsedOutput:
    def __init__(
        self,
        tool_calls: List[Dict[str, Any]],
        final_response: Optional[str] = None,
        explanation: Optional[str] = None,
        clean_content: str = "",
        has_unvalidated_tool: bool = False,
    ):
        self.tool_calls = tool_calls
        self.final_response = final_response
        self.explanation = explanation
        self.clean_content = clean_content
        self.has_unvalidated_tool = has_unvalidated_tool


def parse_model_output(
    text: str,
    valid_tool_names: Optional[Set[str]] = None,
) -> ParsedOutput:
    """Parses model output text to extract structured tool calls or finalResponse.
    Prevents raw protocol JSON or tool envelopes from leaking into content or
    triggering unvalidated commands.
    """
    if not text or not text.strip():
        return ParsedOutput([], clean_content="")

    tool_calls: List[Dict[str, Any]] = []
    final_response: Optional[str] = None
    explanation: Optional[str] = None
    has_unvalidated_tool = False
    spans_to_remove: List[Tuple[int, int]] = []

    # 1. XML tags: <tool_call>...</tool_call> or <function_call>...</function_call>
    xml_matches = list(
        re.finditer(
            r"<(?:tool_call|function_call)>\s*([\s\S]*?)\s*</(?:tool_call|function_call)>",
            text,
            re.IGNORECASE,
        )
    )
    xml_spans: List[Tuple[int, int]] = []
    for m in xml_matches:
        spans_to_remove.append((m.start(), m.end()))
        xml_spans.append((m.start(), m.end()))
        raw_inner = m.group(1).strip()
        try:
            cand = json.loads(raw_inner)
            candidates = cand if isinstance(cand, list) else [cand]
            for c in candidates:
                if isinstance(c, dict):
                    name = c.get("name") or c.get("toolId") or c.get("tool")
                    args = c.get("arguments") or c.get("input") or c.get("parameters") or {}
                    if name and isinstance(name, str):
                        name = name.strip()
                        if valid_tool_names is not None and name not in valid_tool_names:
                            has_unvalidated_tool = True
                            logger.warning("Rejected unvalidated XML tool call: %s", name)
                            continue
                        if not isinstance(args, dict):
                            args = json.loads(args) if isinstance(args, str) else {}
                        tool_calls.append({
                            "id": f"call_xml_{uuid.uuid4().hex[:8]}",
                            "type": "function",
                            "function": {"name": name, "arguments": json.dumps(args)},
                        })
        except Exception:
            pass

    # 2. JSON Objects in text
    json_objs = find_json_objects(text)
    for start_idx, end_idx, json_str in json_objs:
        if any(xs <= start_idx and end_idx <= xe for xs, xe in xml_spans):
            continue
        try:
            parsed = json.loads(json_str)
            if not isinstance(parsed, (dict, list)):
                continue

            candidates = parsed if isinstance(parsed, list) else [parsed]
            matched_candidate = False
            for cand in candidates:
                if not isinstance(cand, dict):
                    continue

                # Check finalResponse
                f_resp = cand.get("finalResponse") or cand.get("final_response")
                if f_resp is not None:
                    final_response = str(f_resp)
                    if "explanation" in cand and not explanation:
                        explanation = str(cand["explanation"])
                    matched_candidate = True

                # Check tool call
                name = cand.get("toolId") or cand.get("name") or cand.get("tool") or cand.get("action")
                args = cand.get("input") or cand.get("arguments") or cand.get("args") or cand.get("parameters") or cand.get("action_input")
                if name and isinstance(name, str):
                    name = name.strip()
                    matched_candidate = True
                    if "explanation" in cand and not explanation:
                        explanation = str(cand["explanation"])

                    if valid_tool_names is not None and name not in valid_tool_names:
                        has_unvalidated_tool = True
                        logger.warning("Rejected unvalidated fallback tool call: %s", name)
                        continue

                    if not isinstance(args, dict):
                        try:
                            args = json.loads(args) if isinstance(args, str) else {}
                        except Exception:
                            args = {}
                    tool_calls.append({
                        "id": f"call_fallback_{uuid.uuid4().hex[:8]}",
                        "type": "function",
                        "function": {"name": name, "arguments": json.dumps(args)},
                    })

            if matched_candidate:
                # Expand span to remove surrounding markdown code block if present
                before = text[:start_idx]
                after = text[end_idx:]
                block_start = start_idx
                block_end = end_idx
                fence_before = re.search(r"```(?:json)?\s*$", before)
                fence_after = re.match(r"^\s*```", after)
                if fence_before and fence_after:
                    block_start = fence_before.start()
                    block_end = end_idx + fence_after.end()
                spans_to_remove.append((block_start, block_end))
        except Exception:
            pass

    # Reconstruct clean_content by slicing out matched envelopes
    spans_to_remove = sorted(spans_to_remove, key=lambda x: x[0], reverse=True)
    clean_text = text
    for s_start, s_end in spans_to_remove:
        clean_text = clean_text[:s_start] + clean_text[s_end:]

    # Clean leftover empty markdown blocks or tags
    clean_text = re.sub(r"```(?:json)?\s*```", "", clean_text)
    clean_text = re.sub(
        r"<(?:tool_call|function_call)>[\s\S]*?</(?:tool_call|function_call)>",
        "",
        clean_text,
        flags=re.IGNORECASE,
    )
    clean_text = clean_text.strip()

    if final_response is not None and not clean_text:
        clean_text = final_response

    return ParsedOutput(
        tool_calls=tool_calls,
        final_response=final_response,
        explanation=explanation,
        clean_content=clean_text,
        has_unvalidated_tool=has_unvalidated_tool,
    )


def extract_fallback_tool_calls(
    text: str,
    valid_tool_names: Optional[Set[str]] = None,
) -> List[Dict[str, Any]]:
    """Extracts fallback JSON tool calls from markdown code blocks or raw JSON.
    Validates tool names against registered tools catalog if provided.
    """
    parsed = parse_model_output(text, valid_tool_names)
    return parsed.tool_calls


def resolve_chat_url(base_url: Optional[str], default_base: str) -> str:
    """Resolves target base URL into a clean chat/completions endpoint."""
    raw = (base_url or "").strip() or default_base
    raw = raw.rstrip("/")
    if raw.endswith("/chat/completions"):
        return raw
    return f"{raw}/chat/completions"


class TargetModelConfig:
    def __init__(
        self,
        model_name: str,
        provider: str,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
    ):
        self.model_name = model_name
        self.provider = provider.lower()
        self.api_key = api_key or ""
        self.base_url = base_url or ""
        self.headers = headers or {}


class ModelAdapterServer:
    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self.host = host
        self.requested_port = port
        self.actual_port: int = 0
        self.server: Optional[asyncio.Server] = None
        self.targets: Dict[str, TargetModelConfig] = {}
        self._lock = asyncio.Lock()
        self._http_client: Optional[httpx.AsyncClient] = None

    async def get_client(self) -> httpx.AsyncClient:
        if self._http_client is None or self._http_client.is_closed:
            limits = httpx.Limits(max_keepalive_connections=50, max_connections=200)
            headers = {"Connection": "keep-alive"}
            self._http_client = httpx.AsyncClient(limits=limits, headers=headers, timeout=120.0)
        return self._http_client

    def register_target(
        self,
        model_name: str,
        provider: str,
        api_key: Optional[str] = None,
        base_url: Optional[str] = None,
        headers: Optional[Dict[str, str]] = None,
    ):
        cfg = TargetModelConfig(
            model_name=model_name,
            provider=provider,
            api_key=api_key,
            base_url=base_url,
            headers=headers,
        )
        self.targets[model_name] = cfg
        self.targets[model_name.lower()] = cfg
        logger.info("Registered adapter target for model '%s' via provider '%s'", model_name, provider)

    def find_target(self, model_name: str) -> Optional[TargetModelConfig]:
        if not model_name:
            if self.targets:
                return next(iter(self.targets.values()))
            return None

        if model_name in self.targets:
            return self.targets[model_name]
        lower = model_name.lower().strip()
        if lower in self.targets:
            return self.targets[lower]

        # Strip provider prefix if present (e.g., 'openai/gpt-4o', 'anthropic/claude-3-7-sonnet')
        if "/" in lower:
            bare_model = lower.split("/", 1)[1]
            if bare_model in self.targets:
                return self.targets[bare_model]

        # Substring search
        for k, v in self.targets.items():
            if k in lower or lower in k:
                return v

        # Smart provider inference from model name
        if any(c in lower for c in ("claude", "anthropic")):
            return TargetModelConfig(model_name=model_name, provider="anthropic")
        elif any(c in lower for c in ("mistral", "codestral")):
            return TargetModelConfig(model_name=model_name, provider="mistral")
        elif any(c in lower for c in ("qwen", "dashscope")):
            return TargetModelConfig(model_name=model_name, provider="qwen")
        elif any(c in lower for c in ("ollama", "lmstudio")):
            return TargetModelConfig(model_name=model_name, provider="ollama")
        elif "openrouter" in lower:
            return TargetModelConfig(model_name=model_name, provider="openrouter")

        # Fallback target if any target is registered
        if self.targets:
            return next(iter(self.targets.values()))

        return TargetModelConfig(model_name=model_name, provider="openai")

    async def start(self) -> int:
        if self.server is not None:
            return self.actual_port

        self.server = await asyncio.start_server(
            self._handle_client,
            self.host,
            self.requested_port,
        )
        sockets = self.server.sockets
        if sockets:
            self.actual_port = sockets[0].getsockname()[1]
        logger.info("ModelAdapterServer started at http://%s:%d", self.host, self.actual_port)
        return self.actual_port

    async def stop(self):
        if self.server is not None:
            self.server.close()
            await self.server.wait_closed()
            self.server = None
        if self._http_client is not None and not self._http_client.is_closed:
            await self._http_client.aclose()
            self._http_client = None
        logger.info("ModelAdapterServer stopped")

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            line = await reader.readline()
            if not line:
                writer.close()
                return

            req_line = line.decode("utf-8", errors="replace").strip()
            parts = req_line.split(" ")
            if len(parts) < 2:
                writer.close()
                return

            method, path = parts[0], parts[1]

            headers: Dict[str, str] = {}
            while True:
                header_line = await reader.readline()
                if not header_line or header_line in (b"\r\n", b"\n"):
                    break
                decoded = header_line.decode("utf-8", errors="replace").strip()
                if ":" in decoded:
                    k, v = decoded.split(":", 1)
                    headers[k.strip().lower()] = v.strip()

            content_len = int(headers.get("content-length", "0"))
            body = b""
            if content_len > 0:
                body = await reader.readexactly(content_len)

            if method == "POST" and (path.endswith("/chat/completions") or path.endswith("/completions")):
                await self._handle_chat_completions(body, writer)
            elif method == "GET" and path.endswith("/models"):
                await self._handle_list_models(writer)
            else:
                resp = b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
                writer.write(resp)
                await writer.drain()
                writer.close()

        except Exception as e:
            logger.error("Error handling HTTP request in ModelAdapterServer: %s", e)
            try:
                err_resp = f"HTTP/1.1 500 Internal Server Error\r\nContent-Type: application/json\r\n\r\n{{\"error\": {json.dumps(str(e))}}}"
                writer.write(err_resp.encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
            writer.close()

    async def _handle_list_models(self, writer: asyncio.StreamWriter):
        model_list = [
            {"id": k, "object": "model", "created": int(time.time()), "owned_by": v.provider}
            for k, v in self.targets.items()
        ]
        body = json.dumps({"object": "list", "data": model_list}).encode("utf-8")
        resp = (
            f"HTTP/1.1 200 OK\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"\r\n"
        ).encode("utf-8") + body
        writer.write(resp)
        await writer.drain()
        writer.close()

    async def _handle_chat_completions(self, body: bytes, writer: asyncio.StreamWriter):
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception as e:
            err_body = json.dumps({"error": f"Invalid JSON payload: {e}"}).encode("utf-8")
            writer.write(
                f"HTTP/1.1 400 Bad Request\r\nContent-Length: {len(err_body)}\r\n\r\n".encode("utf-8")
                + err_body
            )
            await writer.drain()
            writer.close()
            return

        model_name = payload.get("model", "")
        stream = payload.get("stream", False)

        # Normalize all tool parameter schemas in payload to ensure lowercase types and strict schema
        tools = payload.get("tools")
        if tools and isinstance(tools, list):
            normalized_tools = []
            for t in tools:
                if isinstance(t, dict):
                    t_copy = dict(t)
                    if "function" in t_copy and isinstance(t_copy["function"], dict):
                        fn = dict(t_copy["function"])
                        if "parameters" in fn:
                            fn["parameters"] = normalize_schema(fn["parameters"])
                        else:
                            fn["parameters"] = {"type": "object", "properties": {}}
                        t_copy["function"] = fn
                    elif "parameters" in t_copy:
                        t_copy["parameters"] = normalize_schema(t_copy["parameters"])
                    normalized_tools.append(t_copy)
                else:
                    normalized_tools.append(t)
            payload["tools"] = normalized_tools

        target = self.find_target(model_name)
        if not target:
            target = TargetModelConfig(model_name=model_name, provider="openai")

        client = await self.get_client()

        if target.provider in ("anthropic", "claude"):
            await self._forward_to_anthropic(payload, target, stream, writer, client)
        elif target.provider == "openrouter":
            await self._forward_to_openrouter(payload, target, stream, writer, client)
        elif target.provider == "mistral":
            await self._forward_to_mistral(payload, target, stream, writer, client)
        elif target.provider == "qwen":
            await self._forward_to_qwen(payload, target, stream, writer, client)
        elif target.provider in ("ollama", "lmstudio"):
            await self._forward_to_local_openai(payload, target, stream, writer, client)
        elif target.provider == "custom":
            await self._forward_to_custom(payload, target, stream, writer, client)
        else:
            await self._forward_to_openai(payload, target, stream, writer, client)

    # MARK: - Anthropic Adapter
    async def _forward_to_anthropic(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        model = payload.get("model", target.model_name)
        messages = payload.get("messages", [])
        tools = payload.get("tools", [])

        # Extract system content and translate messages
        system_content = ""
        claude_messages: List[Dict[str, Any]] = []

        for m in messages:
            role = m.get("role")
            content = m.get("content", "")
            if role == "system":
                if system_content:
                    system_content += "\n\n" + str(content)
                else:
                    system_content = str(content)
            elif role == "user":
                claude_messages.append({"role": "user", "content": content})
            elif role == "assistant":
                tool_calls = m.get("tool_calls", [])
                if tool_calls:
                    content_blocks: List[Dict[str, Any]] = []
                    if content:
                        content_blocks.append({"type": "text", "text": str(content)})
                    for tc in tool_calls:
                        fn = tc.get("function", {})
                        fn_args = fn.get("arguments", "{}")
                        try:
                            parsed_args = json.loads(fn_args) if isinstance(fn_args, str) else fn_args
                        except Exception:
                            parsed_args = {}
                        content_blocks.append({
                            "type": "tool_use",
                            "id": tc.get("id", f"toolu_{uuid.uuid4().hex[:12]}"),
                            "name": fn.get("name", "unknown"),
                            "input": parsed_args,
                        })
                    claude_messages.append({"role": "assistant", "content": content_blocks})
                else:
                    claude_messages.append({"role": "assistant", "content": content or ""})
            elif role == "tool":
                tool_call_id = m.get("tool_call_id", "")
                claude_messages.append({
                    "role": "user",
                    "content": [{
                        "type": "tool_result",
                        "tool_use_id": tool_call_id,
                        "content": str(content),
                    }],
                })

        # Anthropic requires messages to alternate between 'user' and 'assistant'
        merged_messages: List[Dict[str, Any]] = []
        for m in claude_messages:
            if merged_messages and merged_messages[-1]["role"] == m["role"]:
                prev = merged_messages[-1]
                prev_content = prev["content"]
                curr_content = m["content"]
                if isinstance(prev_content, str) and isinstance(curr_content, str):
                    prev["content"] = prev_content + "\n\n" + curr_content
                else:
                    prev_blocks = prev_content if isinstance(prev_content, list) else [{"type": "text", "text": str(prev_content)}]
                    curr_blocks = curr_content if isinstance(curr_content, list) else [{"type": "text", "text": str(curr_content)}]
                    prev["content"] = prev_blocks + curr_blocks
            else:
                merged_messages.append(m)

        claude_messages = merged_messages
        # Ensure first message is user
        if not claude_messages or claude_messages[0]["role"] != "user":
            claude_messages.insert(0, {"role": "user", "content": "Begin task."})

        # Translate tools to Anthropic format
        claude_tools: List[Dict[str, Any]] = []
        for t in tools:
            fn = t.get("function", t) if isinstance(t, dict) else {}
            name = fn.get("name") or t.get("name")
            desc = fn.get("description") or t.get("description") or ""
            input_schema = fn.get("parameters") or t.get("parameters") or t.get("input_schema")
            input_schema = normalize_schema(input_schema)
            if not isinstance(input_schema, dict) or input_schema.get("type") != "object":
                input_schema = {"type": "object", "properties": {}}

            if name:
                claude_tools.append({
                    "name": name,
                    "description": desc,
                    "input_schema": input_schema,
                })

        req_body: Dict[str, Any] = {
            "model": model,
            "messages": claude_messages,
            "max_tokens": payload.get("max_tokens", 8192),
            "stream": stream,
        }
        if system_content:
            req_body["system"] = system_content
        if claude_tools:
            req_body["tools"] = claude_tools

        headers = {
            "x-api-key": target.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        }
        headers.update(target.headers)

        base = (target.base_url.rstrip("/") if target.base_url else "https://api.anthropic.com")
        url = base if base.endswith("/messages") else f"{base}/v1/messages"

        if stream:
            chat_id = f"chatcmpl_{uuid.uuid4().hex}"
            created_ts = int(time.time())

            async with client.stream("POST", url, headers=headers, json=req_body, timeout=120.0) as resp:
                if resp.status_code >= 400:
                    err_content = await resp.aread()
                    writer.write(
                        f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(err_content)}\r\n\r\n".encode("utf-8")
                        + err_content
                    )
                    await writer.drain()
                    writer.close()
                    return

                writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n")
                await writer.drain()

                current_tool_id = ""
                current_tool_name = ""
                current_tool_args = ""
                tool_index = 0
                tool_calls_emitted = False
                accumulated_content: List[str] = []
                buffered_content_deltas: List[str] = []
                registered_tool_names = extract_catalog_tool_names(payload)
                is_buffering_potential_tool = bool(registered_tool_names)
                think_parser = ThinkTagStreamParser()

                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    raw_data = line[6:].strip()
                    if raw_data == "[DONE]":
                        break
                    try:
                        event_data = json.loads(raw_data)
                    except Exception:
                        continue

                    ev_type = event_data.get("type")
                    if ev_type == "content_block_start":
                        cb = event_data.get("content_block", {})
                        if cb.get("type") == "tool_use":
                            current_tool_id = cb.get("id", f"toolu_{uuid.uuid4().hex[:12]}")
                            current_tool_name = cb.get("name", "")
                            current_tool_args = ""

                    elif ev_type == "content_block_delta":
                        delta = event_data.get("delta", {})
                        delta_type = delta.get("type")
                        if delta_type == "text_delta":
                            text = delta.get("text", "")
                            for kind, piece in think_parser.process_delta(text):
                                if kind == "thought":
                                    chunk = {
                                        "id": chat_id,
                                        "object": "chat.completion.chunk",
                                        "created": created_ts,
                                        "model": model,
                                        "choices": [{
                                            "index": 0,
                                            "delta": {
                                                "thought": piece,
                                                "thinking": piece,
                                                "reasoning": piece,
                                                "reasoning_content": piece,
                                            },
                                            "finish_reason": None,
                                        }],
                                    }
                                    writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                                    await writer.drain()
                                else:
                                    accumulated_content.append(piece)
                                    if is_buffering_potential_tool:
                                        buffered_content_deltas.append(piece)
                                        combined = "".join(buffered_content_deltas).lstrip()
                                        if combined and not (
                                            combined.startswith("{")
                                            or combined.startswith("`")
                                            or combined.startswith("<")
                                            or combined.startswith("[")
                                        ):
                                            is_buffering_potential_tool = False
                                            for b_piece in buffered_content_deltas:
                                                c_chunk = {
                                                    "id": chat_id,
                                                    "object": "chat.completion.chunk",
                                                    "created": created_ts,
                                                    "model": model,
                                                    "choices": [{
                                                        "index": 0,
                                                        "delta": {"content": b_piece},
                                                        "finish_reason": None,
                                                    }],
                                                }
                                                writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                            await writer.drain()
                                            buffered_content_deltas = []
                                    else:
                                        chunk = {
                                            "id": chat_id,
                                            "object": "chat.completion.chunk",
                                            "created": created_ts,
                                            "model": model,
                                            "choices": [{
                                                "index": 0,
                                                "delta": {"content": piece},
                                                "finish_reason": None,
                                            }],
                                        }
                                        writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                                        await writer.drain()

                        elif delta_type == "thinking_delta":
                            thought = delta.get("thinking", "")
                            if thought:
                                chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": thought,
                                            "thinking": thought,
                                            "reasoning": thought,
                                            "reasoning_content": thought,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                                await writer.drain()

                        elif delta_type == "input_json_delta":
                            partial_json = delta.get("partial_json", "")
                            if partial_json:
                                current_tool_args += partial_json

                    elif ev_type == "content_block_stop":
                        if current_tool_name:
                            # Validate tool name against registered catalog if provided
                            if not registered_tool_names or current_tool_name in registered_tool_names:
                                chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "tool_calls": [{
                                                "index": tool_index,
                                                "id": current_tool_id,
                                                "type": "function",
                                                "function": {
                                                    "name": current_tool_name,
                                                    "arguments": current_tool_args,
                                                },
                                            }]
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                                await writer.drain()
                                tool_index += 1
                                tool_calls_emitted = True
                            current_tool_name = ""
                            current_tool_id = ""
                            current_tool_args = ""

                    elif ev_type == "message_stop":
                        for kind, piece in think_parser.flush():
                            if kind == "thought":
                                t_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": piece,
                                            "thinking": piece,
                                            "reasoning": piece,
                                            "reasoning_content": piece,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(t_chunk)}\n\n".encode("utf-8"))
                            elif kind == "content":
                                accumulated_content.append(piece)

                        if not tool_calls_emitted and accumulated_content:
                            full_text = "".join(accumulated_content)
                            parsed_out = parse_model_output(full_text, registered_tool_names)
                            if parsed_out.explanation:
                                t_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": parsed_out.explanation,
                                            "thinking": parsed_out.explanation,
                                            "reasoning": parsed_out.explanation,
                                            "reasoning_content": parsed_out.explanation,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(t_chunk)}\n\n".encode("utf-8"))
                                await writer.drain()

                            if parsed_out.tool_calls:
                                complete_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"tool_calls": parsed_out.tool_calls},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(complete_chunk)}\n\n".encode("utf-8"))
                                tool_calls_emitted = True
                            elif parsed_out.final_response is not None:
                                c_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"content": parsed_out.final_response},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                buffered_content_deltas = []
                            elif buffered_content_deltas:
                                if not parsed_out.has_unvalidated_tool:
                                    for b_piece in buffered_content_deltas:
                                        c_chunk = {
                                            "id": chat_id,
                                            "object": "chat.completion.chunk",
                                            "created": created_ts,
                                            "model": model,
                                            "choices": [{
                                                "index": 0,
                                                "delta": {"content": b_piece},
                                                "finish_reason": None,
                                            }],
                                        }
                                        writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                elif parsed_out.clean_content:
                                    c_chunk = {
                                        "id": chat_id,
                                        "object": "chat.completion.chunk",
                                        "created": created_ts,
                                        "model": model,
                                        "choices": [{
                                            "index": 0,
                                            "delta": {"content": parsed_out.clean_content},
                                            "finish_reason": None,
                                        }],
                                    }
                                    writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                buffered_content_deltas = []

                        stop_chunk = {
                            "id": chat_id,
                            "object": "chat.completion.chunk",
                            "created": created_ts,
                            "model": model,
                            "choices": [{
                                "index": 0,
                                "delta": {},
                                "finish_reason": "tool_calls" if tool_calls_emitted else "stop",
                            }],
                        }
                        writer.write(f"data: {json.dumps(stop_chunk)}\n\n".encode("utf-8"))
                        writer.write(b"data: [DONE]\n\n")
                        await writer.drain()

            writer.close()
        else:
            # Non-streaming
            resp = await client.post(url, headers=headers, json=req_body, timeout=120.0)
            c_json = resp.json()

            tool_calls = []
            content_text = ""
            reasoning_text = ""
            for item in c_json.get("content", []):
                i_type = item.get("type")
                if i_type == "text":
                    content_text += item.get("text", "")
                elif i_type == "thinking":
                    t_text = item.get("thinking", "")
                    if t_text:
                        reasoning_text = (reasoning_text + "\n\n" + t_text).strip() if reasoning_text else t_text
                elif i_type == "tool_use":
                    tool_calls.append({
                        "id": item.get("id"),
                        "type": "function",
                        "function": {
                            "name": item.get("name"),
                            "arguments": json.dumps(item.get("input", {})),
                        },
                    })

            clean_text, think_text = strip_think_tags(content_text)
            if think_text:
                reasoning_text = (reasoning_text + "\n\n" + think_text).strip() if reasoning_text else think_text

            registered_tool_names = extract_catalog_tool_names(payload)
            if tool_calls:
                if registered_tool_names:
                    tool_calls = [tc for tc in tool_calls if tc.get("function", {}).get("name") in registered_tool_names]
                content_text = clean_text or None
            elif clean_text:
                parsed = parse_model_output(clean_text, registered_tool_names)
                if parsed.tool_calls:
                    tool_calls = parsed.tool_calls
                    content_text = None
                    if parsed.explanation:
                        reasoning_text = (reasoning_text + "\n\n" + parsed.explanation).strip() if reasoning_text else parsed.explanation
                elif parsed.final_response is not None:
                    content_text = parsed.final_response
                    if parsed.explanation:
                        reasoning_text = (reasoning_text + "\n\n" + parsed.explanation).strip() if reasoning_text else parsed.explanation
                else:
                    content_text = parsed.clean_content or None

            msg_obj: Dict[str, Any] = {"role": "assistant", "content": content_text}
            if tool_calls:
                msg_obj["tool_calls"] = tool_calls
            if reasoning_text:
                msg_obj["reasoning_content"] = reasoning_text

            openai_resp = {
                "id": f"chatcmpl_{uuid.uuid4().hex}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [{
                    "index": 0,
                    "message": msg_obj,
                    "finish_reason": "tool_calls" if tool_calls else "stop",
                }],
                "usage": {
                    "prompt_tokens": c_json.get("usage", {}).get("input_tokens", 0),
                    "completion_tokens": c_json.get("usage", {}).get("output_tokens", 0),
                    "total_tokens": c_json.get("usage", {}).get("input_tokens", 0) + c_json.get("usage", {}).get("output_tokens", 0),
                },
            }
            body_bytes = json.dumps(openai_resp).encode("utf-8")
            writer.write(
                f"HTTP/1.1 {resp.status_code} OK\r\nContent-Type: application/json\r\nContent-Length: {len(body_bytes)}\r\n\r\n".encode("utf-8")
                + body_bytes
            )
            await writer.drain()
            writer.close()

    # MARK: - OpenAI / OpenRouter / Custom Forwarders
    async def _forward_to_openai(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = resolve_chat_url(target.base_url, "https://api.openai.com/v1")
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
        headers.update(target.headers)

        # Adapt payload for OpenAI reasoning models (o1, o3, o3-mini)
        model_name = (payload.get("model") or target.model_name).lower()
        if model_name.startswith(("o1", "o3")):
            if "max_tokens" in payload:
                payload["max_completion_tokens"] = payload.pop("max_tokens")
            if "temperature" in payload and payload["temperature"] != 1.0:
                payload.pop("temperature", None)

        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_openrouter(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = resolve_chat_url(target.base_url, "https://openrouter.ai/api/v1")
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://swiftcode.app",
            "X-Title": "SwiftCode",
        }
        headers.update(target.headers)
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_local_openai(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        default_base = "http://localhost:11434/v1" if target.provider == "ollama" else "http://localhost:1234/v1"
        url = resolve_chat_url(target.base_url, default_base)
        headers = {"Content-Type": "application/json"}
        if target.api_key:
            headers["Authorization"] = f"Bearer {target.api_key}"
        headers.update(target.headers)

        if "tools" in payload and not payload["tools"]:
            payload.pop("tools", None)

        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_custom(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = resolve_chat_url(target.base_url, "http://127.0.0.1:8000/v1")
        headers = {"Content-Type": "application/json"}
        if target.api_key:
            headers["Authorization"] = f"Bearer {target.api_key}"
        headers.update(target.headers)
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_mistral(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = resolve_chat_url(target.base_url, "https://api.mistral.ai/v1")
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
        headers.update(target.headers)

        if "tools" in payload and not payload["tools"]:
            payload.pop("tools", None)

        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_qwen(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = resolve_chat_url(target.base_url, "https://dashscope.aliyuncs.com/compatible-mode/v1")
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
        headers.update(target.headers)

        if "tools" in payload and not payload["tools"]:
            payload.pop("tools", None)

        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _pipe_openai_request(
        self,
        url: str,
        headers: Dict[str, str],
        payload: Dict[str, Any],
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        registered_tool_names = extract_catalog_tool_names(payload)

        if stream:
            async with client.stream("POST", url, headers=headers, json=payload, timeout=120.0) as resp:
                if resp.status_code >= 400:
                    err_content = await resp.aread()
                    writer.write(
                        f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(err_content)}\r\n\r\n".encode("utf-8")
                        + err_content
                    )
                    await writer.drain()
                    writer.close()
                    return

                writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n")
                await writer.drain()

                chat_id = f"chatcmpl_{uuid.uuid4().hex}"
                created_ts = int(time.time())
                model_name = payload.get("model", "")
                active_tool_calls: Dict[int, Dict[str, Any]] = {}
                tool_calls_emitted = False
                accumulated_content: List[str] = []
                think_parser = ThinkTagStreamParser()
                buffered_content_deltas: List[str] = []
                is_buffering_potential_tool = bool(registered_tool_names)

                async for line in resp.aiter_lines():
                    if not line:
                        continue
                    if not line.startswith("data: "):
                        continue
                    raw_data = line[6:].strip()
                    if raw_data == "[DONE]":
                        # Process any remaining thought or content in think_parser buffer
                        for kind, piece in think_parser.flush():
                            if kind == "thought":
                                thought_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": piece,
                                            "thinking": piece,
                                            "reasoning": piece,
                                            "reasoning_content": piece,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(thought_chunk)}\n\n".encode("utf-8"))
                            elif kind == "content":
                                accumulated_content.append(piece)

                        # Emit active native tool calls if accumulated
                        if active_tool_calls and not tool_calls_emitted:
                            tc_list = []
                            for idx in sorted(active_tool_calls.keys()):
                                t_info = active_tool_calls[idx]
                                t_name = t_info["name"]
                                if registered_tool_names and t_name not in registered_tool_names:
                                    logger.warning("Filtering out unregistered native tool: %s", t_name)
                                    continue
                                tc_list.append({
                                    "index": len(tc_list),
                                    "id": t_info["id"],
                                    "type": "function",
                                    "function": {
                                        "name": t_name,
                                        "arguments": t_info["arguments"],
                                    },
                                })
                            if tc_list:
                                complete_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"tool_calls": tc_list},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(complete_chunk)}\n\n".encode("utf-8"))
                                stop_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {},
                                        "finish_reason": "tool_calls",
                                    }],
                                }
                                writer.write(f"data: {json.dumps(stop_chunk)}\n\n".encode("utf-8"))
                                tool_calls_emitted = True

                        # If native tool calls were not present, inspect accumulated_content for fallback tools or finalResponse
                        elif not tool_calls_emitted and accumulated_content:
                            full_text = "".join(accumulated_content)
                            parsed_out = parse_model_output(full_text, registered_tool_names)

                            if parsed_out.explanation:
                                t_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": parsed_out.explanation,
                                            "thinking": parsed_out.explanation,
                                            "reasoning": parsed_out.explanation,
                                            "reasoning_content": parsed_out.explanation,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(t_chunk)}\n\n".encode("utf-8"))
                                await writer.drain()

                            if parsed_out.tool_calls:
                                complete_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"tool_calls": parsed_out.tool_calls},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(complete_chunk)}\n\n".encode("utf-8"))
                                stop_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {},
                                        "finish_reason": "tool_calls",
                                    }],
                                }
                                writer.write(f"data: {json.dumps(stop_chunk)}\n\n".encode("utf-8"))
                                tool_calls_emitted = True
                            elif parsed_out.final_response is not None:
                                c_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"content": parsed_out.final_response},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                stop_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {},
                                        "finish_reason": "stop",
                                    }],
                                }
                                writer.write(f"data: {json.dumps(stop_chunk)}\n\n".encode("utf-8"))
                                buffered_content_deltas = []
                            elif buffered_content_deltas:
                                if not parsed_out.has_unvalidated_tool:
                                    for b_piece in buffered_content_deltas:
                                        c_chunk = {
                                            "id": chat_id,
                                            "object": "chat.completion.chunk",
                                            "created": created_ts,
                                            "model": model_name,
                                            "choices": [{
                                                "index": 0,
                                                "delta": {"content": b_piece},
                                                "finish_reason": None,
                                            }],
                                        }
                                        writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                elif parsed_out.clean_content:
                                    c_chunk = {
                                        "id": chat_id,
                                        "object": "chat.completion.chunk",
                                        "created": created_ts,
                                        "model": model_name,
                                        "choices": [{
                                            "index": 0,
                                            "delta": {"content": parsed_out.clean_content},
                                            "finish_reason": None,
                                        }],
                                    }
                                    writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                buffered_content_deltas = []

                        writer.write(b"data: [DONE]\n\n")
                        await writer.drain()
                        break

                    try:
                        chunk_obj = json.loads(raw_data)
                    except Exception:
                        continue

                    choices = chunk_obj.get("choices", [])
                    if not choices:
                        continue

                    choice = choices[0]
                    delta = choice.get("delta", {})
                    finish_reason = choice.get("finish_reason")

                    if chunk_obj.get("id"):
                        chat_id = chunk_obj["id"]
                    if chunk_obj.get("created"):
                        created_ts = chunk_obj["created"]
                    if chunk_obj.get("model"):
                        model_name = chunk_obj["model"]

                    # Buffer fragmented incoming native tool calls
                    incoming_tc = delta.get("tool_calls")
                    if incoming_tc and isinstance(incoming_tc, list):
                        for tc in incoming_tc:
                            t_idx = tc.get("index", 0)
                            if t_idx not in active_tool_calls:
                                active_tool_calls[t_idx] = {
                                    "id": tc.get("id") or f"call_{uuid.uuid4().hex[:8]}",
                                    "name": tc.get("function", {}).get("name", ""),
                                    "arguments": "",
                                }
                            if tc.get("id"):
                                active_tool_calls[t_idx]["id"] = tc.get("id")
                            if tc.get("function", {}).get("name"):
                                active_tool_calls[t_idx]["name"] = tc.get("function", {}).get("name")
                            arg_delta = tc.get("function", {}).get("arguments", "")
                            if arg_delta:
                                active_tool_calls[t_idx]["arguments"] += arg_delta
                        continue

                    # Pass through explicit reasoning / thinking deltas from provider
                    reasoning_piece = delta.get("reasoning_content") or delta.get("reasoning") or delta.get("thinking")
                    if reasoning_piece:
                        chunk = {
                            "id": chat_id,
                            "object": "chat.completion.chunk",
                            "created": created_ts,
                            "model": model_name,
                            "choices": [{
                                "index": 0,
                                "delta": {
                                    "thought": reasoning_piece,
                                    "reasoning": reasoning_piece,
                                    "thinking": reasoning_piece,
                                    "reasoning_content": reasoning_piece,
                                },
                                "finish_reason": None,
                            }],
                        }
                        writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                        await writer.drain()

                    # Process content deltas through ThinkTagStreamParser
                    raw_content = delta.get("content")
                    if raw_content:
                        parsed_pieces = think_parser.process_delta(str(raw_content))
                        for kind, piece in parsed_pieces:
                            if kind == "thought":
                                thought_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {
                                            "thought": piece,
                                            "thinking": piece,
                                            "reasoning": piece,
                                            "reasoning_content": piece,
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(thought_chunk)}\n\n".encode("utf-8"))
                                await writer.drain()
                            elif kind == "content":
                                accumulated_content.append(piece)
                                if is_buffering_potential_tool:
                                    buffered_content_deltas.append(piece)
                                    combined = "".join(buffered_content_deltas).lstrip()
                                    if combined and not (
                                        combined.startswith("{")
                                        or combined.startswith("`")
                                        or combined.startswith("<")
                                        or combined.startswith("[")
                                    ):
                                        is_buffering_potential_tool = False
                                        for b_piece in buffered_content_deltas:
                                            c_chunk = {
                                                "id": chat_id,
                                                "object": "chat.completion.chunk",
                                                "created": created_ts,
                                                "model": model_name,
                                                "choices": [{
                                                    "index": 0,
                                                    "delta": {"content": b_piece},
                                                    "finish_reason": None,
                                                }],
                                            }
                                            writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                        await writer.drain()
                                        buffered_content_deltas = []
                                else:
                                    c_chunk = {
                                        "id": chat_id,
                                        "object": "chat.completion.chunk",
                                        "created": created_ts,
                                        "model": model_name,
                                        "choices": [{
                                            "index": 0,
                                            "delta": {"content": piece},
                                            "finish_reason": None,
                                        }],
                                    }
                                    writer.write(f"data: {json.dumps(c_chunk)}\n\n".encode("utf-8"))
                                    await writer.drain()

                    # Handle intermediate finish_reason chunk
                    if finish_reason and not (delta.get("content") or incoming_tc):
                        if (finish_reason == "tool_calls" or active_tool_calls) and not tool_calls_emitted:
                            tc_list = []
                            for idx in sorted(active_tool_calls.keys()):
                                t_info = active_tool_calls[idx]
                                t_name = t_info["name"]
                                if registered_tool_names and t_name not in registered_tool_names:
                                    continue
                                tc_list.append({
                                    "index": len(tc_list),
                                    "id": t_info["id"],
                                    "type": "function",
                                    "function": {
                                        "name": t_name,
                                        "arguments": t_info["arguments"],
                                    },
                                })
                            if tc_list:
                                complete_chunk = {
                                    "id": chat_id,
                                    "object": "chat.completion.chunk",
                                    "created": created_ts,
                                    "model": model_name,
                                    "choices": [{
                                        "index": 0,
                                        "delta": {"tool_calls": tc_list},
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(complete_chunk)}\n\n".encode("utf-8"))
                                tool_calls_emitted = True
                        line = f"data: {json.dumps(chunk_obj)}"
                        writer.write((line + "\n\n").encode("utf-8"))
                        await writer.drain()

            writer.close()
        else:
            resp = await client.post(url, headers=headers, json=payload, timeout=120.0)
            if resp.status_code == 200:
                try:
                    resp_json = resp.json()
                    choices = resp_json.get("choices", [])
                    if choices:
                        msg = choices[0].get("message", {})
                        raw_content = msg.get("content") or ""
                        reasoning = msg.get("reasoning_content") or msg.get("reasoning") or ""

                        clean_content, think_text = strip_think_tags(raw_content)
                        if think_text:
                            reasoning = (reasoning + "\n\n" + think_text).strip() if reasoning else think_text
                        if reasoning:
                            msg["reasoning_content"] = reasoning

                        native_tc = msg.get("tool_calls")
                        if native_tc:
                            if registered_tool_names:
                                valid_tc = [
                                    tc for tc in native_tc
                                    if tc.get("function", {}).get("name") in registered_tool_names
                                ]
                                msg["tool_calls"] = valid_tc if valid_tc else None
                                if not valid_tc:
                                    choices[0]["finish_reason"] = "stop"
                            msg["content"] = clean_content or None
                        else:
                            parsed = parse_model_output(clean_content, registered_tool_names)
                            if parsed.tool_calls:
                                msg["tool_calls"] = parsed.tool_calls
                                msg["content"] = None
                                choices[0]["finish_reason"] = "tool_calls"
                                if parsed.explanation:
                                    current_rc = msg.get("reasoning_content")
                                    msg["reasoning_content"] = (current_rc + "\n\n" + parsed.explanation).strip() if current_rc else parsed.explanation
                            elif parsed.final_response is not None:
                                msg["content"] = parsed.final_response
                                choices[0]["finish_reason"] = "stop"
                                if parsed.explanation:
                                    current_rc = msg.get("reasoning_content")
                                    msg["reasoning_content"] = (current_rc + "\n\n" + parsed.explanation).strip() if current_rc else parsed.explanation
                            else:
                                msg["content"] = parsed.clean_content or None

                    body_bytes = json.dumps(resp_json).encode("utf-8")
                    writer.write(
                        f"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {len(body_bytes)}\r\n\r\n".encode("utf-8")
                        + body_bytes
                    )
                    await writer.drain()
                    writer.close()
                    return
                except Exception as e:
                    logger.error("Error processing non-streaming response: %s", e)

            writer.write(
                f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(resp.content)}\r\n\r\n".encode("utf-8")
                + resp.content
            )
            await writer.drain()
            writer.close()
