"""
OpenAI-Compatible Local Adapter Server for Antigravity SDK.
Enables Antigravity's LocalOpenAIAgentConfig to route seamlessly to:
- Anthropic (Claude 3.5 Sonnet, 3.7 Sonnet, Opus, Haiku)
- OpenAI (GPT-4o, GPT-4o-mini, o1, o3-mini)
- OpenRouter
- Custom OpenAI-compatible endpoints
"""

from __future__ import annotations
import asyncio
import json
import logging
import time
import uuid
from typing import Any, AsyncGenerator, Dict, List, Optional, Tuple

import httpx

logger = logging.getLogger("ModelAdapterServer")


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
            self._http_client = httpx.AsyncClient(timeout=120.0)
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
        # Also register normalized lowercase and prefix-stripped keys
        self.targets[model_name.lower()] = cfg
        logger.info("Registered adapter target for model '%s' via provider '%s'", model_name, provider)

    def find_target(self, model_name: str) -> Optional[TargetModelConfig]:
        if model_name in self.targets:
            return self.targets[model_name]
        lower = model_name.lower()
        if lower in self.targets:
            return self.targets[lower]
        # Partial match if any target is contained
        for k, v in self.targets.items():
            if k in lower or lower in k:
                return v
        return None

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
            # Read HTTP request header
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

            # Read headers
            headers: Dict[str, str] = {}
            while True:
                header_line = await reader.readline()
                if not header_line or header_line == b"\r\n" or header_line == b"\n":
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

    async def _handle_chat_completions(self, body: Data, writer: asyncio.StreamWriter):
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception as e:
            err_body = json.dumps({"error": f"Invalid JSON payload: {e}"}).encode("utf-8")
            writer.write(f"HTTP/1.1 400 Bad Request\r\nContent-Length: {len(err_body)}\r\n\r\n".encode("utf-8") + err_body)
            await writer.drain()
            writer.close()
            return

        model_name = payload.get("model", "")
        stream = payload.get("stream", False)
        target = self.find_target(model_name)

        if not target:
            # Fallback target if any target is registered
            if self.targets:
                target = next(iter(self.targets.values()))
            else:
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
            # Default OpenAI
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

        # Translate system message
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
                # Convert OpenAI tool response to Anthropic tool_result
                tool_call_id = m.get("tool_call_id", "")
                claude_messages.append({
                    "role": "user",
                    "content": [{
                        "type": "tool_result",
                        "tool_use_id": tool_call_id,
                        "content": str(content),
                    }]
                })

        # Translate tools
        claude_tools: List[Dict[str, Any]] = []
        for t in tools:
            if t.get("type") == "function" and "function" in t:
                fn = t["function"]
                claude_tools.append({
                    "name": fn.get("name", ""),
                    "description": fn.get("description", ""),
                    "input_schema": fn.get("parameters", {"type": "object", "properties": {}}),
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

        url = "https://api.anthropic.com/v1/messages"

        if stream:
            chat_id = f"chatcmpl_{uuid.uuid4().hex}"
            created_ts = int(time.time())

            async with client.stream("POST", url, headers=headers, json=req_body, timeout=120.0) as resp:
                if resp.status_code >= 400:
                    err_content = await resp.aread()
                    writer.write(f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(err_content)}\r\n\r\n".encode("utf-8") + err_content)
                    await writer.drain()
                    writer.close()
                    return

                # Send initial SSE HTTP response headers after verifying success
                writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n")
                await writer.drain()

                current_tool_id = ""
                current_tool_name = ""
                current_tool_args = ""
                tool_index = 0

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
                                                "arguments": "",
                                            },
                                        }]
                                    },
                                    "finish_reason": None,
                                }],
                            }
                            writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                            await writer.drain()

                    elif ev_type == "content_block_delta":
                        delta = event_data.get("delta", {})
                        delta_type = delta.get("type")
                        if delta_type == "text_delta":
                            text = delta.get("text", "")
                            chunk = {
                                "id": chat_id,
                                "object": "chat.completion.chunk",
                                "created": created_ts,
                                "model": model,
                                "choices": [{
                                    "index": 0,
                                    "delta": {"content": text},
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
                                        },
                                        "finish_reason": None,
                                    }],
                                }
                                writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                                await writer.drain()
                        elif delta_type == "input_json_delta":
                            partial_json = delta.get("partial_json", "")
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
                                            "function": {"arguments": partial_json},
                                        }]
                                    },
                                    "finish_reason": None,
                                }],
                            }
                            writer.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                            await writer.drain()

                    elif ev_type == "content_block_stop":
                        if current_tool_name:
                            tool_index += 1
                            current_tool_name = ""

                    elif ev_type == "message_stop":
                        stop_chunk = {
                            "id": chat_id,
                            "object": "chat.completion.chunk",
                            "created": created_ts,
                            "model": model,
                            "choices": [{
                                "index": 0,
                                "delta": {},
                                "finish_reason": "tool_calls" if tool_index > 0 else "stop",
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
            for item in c_json.get("content", []):
                if item.get("type") == "text":
                    content_text += item.get("text", "")
                elif item.get("type") == "tool_use":
                    tool_calls.append({
                        "id": item.get("id"),
                        "type": "function",
                        "function": {
                            "name": item.get("name"),
                            "arguments": json.dumps(item.get("input", {})),
                        },
                    })

            msg_obj: Dict[str, Any] = {"role": "assistant", "content": content_text or None}
            if tool_calls:
                msg_obj["tool_calls"] = tool_calls

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

    # MARK: - OpenAI / OpenRouter / Custom Forwarder
    async def _forward_to_openai(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = (target.base_url.rstrip("/") if target.base_url else "https://api.openai.com/v1") + "/chat/completions"
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
        headers.update(target.headers)
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_openrouter(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = "https://openrouter.ai/api/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://swiftcode.app",
            "X-Title": "SwiftCode",
        }
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_local_openai(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        base = target.base_url.rstrip("/") if target.base_url else "http://localhost:11434/v1"
        url = base if base.endswith("/chat/completions") else f"{base}/chat/completions"
        headers = {"Content-Type": "application/json"}
        if target.api_key:
            headers["Authorization"] = f"Bearer {target.api_key}"
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_custom(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        base = target.base_url.rstrip("/")
        url = base if base.endswith("/chat/completions") else f"{base}/chat/completions"
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
        url = "https://api.mistral.ai/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
        await self._pipe_openai_request(url, headers, payload, stream, writer, client)

    async def _forward_to_qwen(
        self,
        payload: Dict[str, Any],
        target: TargetModelConfig,
        stream: bool,
        writer: asyncio.StreamWriter,
        client: httpx.AsyncClient,
    ):
        url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        headers = {
            "Authorization": f"Bearer {target.api_key}",
            "Content-Type": "application/json",
        }
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
        if stream:
            async with client.stream("POST", url, headers=headers, json=payload, timeout=120.0) as resp:
                if resp.status_code >= 400:
                    err_content = await resp.aread()
                    writer.write(f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(err_content)}\r\n\r\n".encode("utf-8") + err_content)
                    await writer.drain()
                    writer.close()
                    return

                writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n")
                await writer.drain()

                async for line in resp.aiter_lines():
                    if not line:
                        writer.write(b"\n")
                        await writer.drain()
                        continue
                    if not line.startswith("data: "):
                        writer.write((line + "\n").encode("utf-8"))
                        await writer.drain()
                        continue
                    raw_data = line[6:].strip()
                    if raw_data == "[DONE]":
                        writer.write(b"data: [DONE]\n\n")
                        await writer.drain()
                        break
                    try:
                        chunk_obj = json.loads(raw_data)
                        choices = chunk_obj.get("choices", [])
                        if choices:
                            delta = choices[0].get("delta", {})
                            if "reasoning_content" in delta:
                                rc = delta["reasoning_content"]
                                if rc:
                                    if "reasoning" not in delta:
                                        delta["reasoning"] = rc
                                    if "thought" not in delta:
                                        delta["thought"] = rc
                                    if "thinking" not in delta:
                                        delta["thinking"] = rc
                        line = f"data: {json.dumps(chunk_obj)}"
                    except Exception:
                        pass
                    writer.write((line + "\n\n").encode("utf-8"))
                    await writer.drain()
            writer.close()
        else:
            resp = await client.post(url, headers=headers, json=payload, timeout=120.0)
            writer.write(
                f"HTTP/1.1 {resp.status_code} {resp.reason_phrase}\r\nContent-Type: application/json\r\nContent-Length: {len(resp.content)}\r\n\r\n".encode("utf-8")
                + resp.content
            )
            await writer.drain()
            writer.close()
