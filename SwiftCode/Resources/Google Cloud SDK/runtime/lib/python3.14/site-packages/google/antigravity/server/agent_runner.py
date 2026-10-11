"""
Antigravity SDK Session Runner & Execution Engine.
Manages Google Antigravity Agent lifecycles, streaming chunks, tool execution,
subagents, dynamic SwiftCode tools, and error recovery.
"""

from __future__ import annotations
import asyncio
import os
import sys
import logging
import uuid
from typing import Any, Callable, Dict, List, Optional, Tuple, Awaitable

# Ensure bundled site-packages are available
bridge_dir = os.path.dirname(os.path.abspath(__file__))
sdk_root = os.path.dirname(bridge_dir)
site_packages = os.path.join(sdk_root, "runtime", "lib", "python3.14", "site-packages")
if os.path.isdir(site_packages) and site_packages not in sys.path:
    sys.path.insert(0, site_packages)

if "ANTIGRAVITY_HARNESS_PATH" not in os.environ:
    candidate = os.path.abspath(os.path.join(sdk_root, "runtime", "lib", "python3.14", "site-packages", "google", "antigravity", "bin", "localharness"))
    if os.path.exists(candidate):
        os.environ["ANTIGRAVITY_HARNESS_PATH"] = candidate

from google.antigravity import Agent, LocalAgentConfig, LocalOpenAIAgentConfig, types
try:
    from google.antigravity import LiteRTAgentConfig, LiteRTBackend
except ImportError:
    try:
        from google.antigravity.connections.local.litert_connection_config import LiteRTAgentConfig, LiteRTBackend
    except ImportError:
        LiteRTAgentConfig = None
        LiteRTBackend = None

try:
    from google.antigravity.types import CompactionConfig, VertexEndpoint, GeminiAPIEndpoint
except ImportError:
    try:
        from google.antigravity import CompactionConfig, VertexEndpoint, GeminiAPIEndpoint
    except ImportError:
        CompactionConfig = None
        VertexEndpoint = None
        GeminiAPIEndpoint = None

from google.antigravity.hooks import hooks, policy
from google.antigravity.types import Text, Thought, ToolCall, ToolResult
from google.antigravity.tools.tool_runner import ToolWithSchema

logger = logging.getLogger("AntigravityAgentRunner")


def sanitize_schema(schema: Any) -> Any:
    """Sanitizes JSON schemas from clients to ensure full compliance with Gemini/OpenAPI."""
    if not isinstance(schema, dict):
        return schema

    cleaned = dict(schema)

    # Force lowercase type for strict Anthropic and OpenAI schemas
    if "type" in cleaned and isinstance(cleaned["type"], str):
        cleaned["type"] = cleaned["type"].lower()

    # If type is array, inspect and normalize items
    if cleaned.get("type") == "array":
        if "items" in cleaned:
            items = cleaned["items"]
            if isinstance(items, dict):
                # Check for bad nesting like {'type': {'type': 'string'}} or {'type': {'type': 'object'}}
                if "type" in items and isinstance(items["type"], dict):
                    inner = items["type"]
                    if "type" in inner and isinstance(inner["type"], str):
                        items = dict(inner)
                    else:
                        items = sanitize_schema(inner)
                    cleaned["items"] = items
                elif "type" not in items and len(items) == 1:
                    first_val = next(iter(items.values()))
                    if isinstance(first_val, dict) and "type" in first_val:
                        cleaned["items"] = first_val
                else:
                    cleaned["items"] = sanitize_schema(items)
            elif isinstance(items, str):
                cleaned["items"] = {"type": items.lower()}
        else:
            cleaned["items"] = {"type": "string"}

        if isinstance(cleaned.get("items"), dict):
            cleaned["items"] = sanitize_schema(cleaned["items"])

    # Recursively clean properties
    if "properties" in cleaned and isinstance(cleaned["properties"], dict):
        cleaned["properties"] = {
            k: sanitize_schema(v) for k, v in cleaned["properties"].items()
        }

    return cleaned


class StreamingThoughtParser:
    """Parses streaming text chunks to separate <think>...</think> and <thought>...</thought>
    reasoning blocks from conversational text, handling split tokens across chunk boundaries."""
    OPEN_TAGS = ["<think>", "<thought>"]
    CLOSE_TAGS = ["</think>", "</thought>"]

    def __init__(self):
        self.in_thought = False
        self.pending = ""

    def feed(self, chunk: str) -> List[Tuple[str, str]]:
        """Processes a chunk and returns a list of (type, text) tuples ('thought' or 'text')."""
        results: List[Tuple[str, str]] = []
        text = self.pending + chunk
        self.pending = ""

        while text:
            if not self.in_thought:
                earliest_idx = -1
                found_tag = None
                for tag in self.OPEN_TAGS:
                    idx = text.find(tag)
                    if idx != -1:
                        if earliest_idx == -1 or idx < earliest_idx:
                            earliest_idx = idx
                            found_tag = tag

                if earliest_idx != -1 and found_tag:
                    if earliest_idx > 0:
                        results.append(("text", text[:earliest_idx]))
                    self.in_thought = True
                    text = text[earliest_idx + len(found_tag):]
                else:
                    match_len = 0
                    for tag in self.OPEN_TAGS:
                        for l in range(min(len(tag) - 1, len(text)), 0, -1):
                            if text.endswith(tag[:l]):
                                if l > match_len:
                                    match_len = l
                    if match_len > 0:
                        self.pending = text[-match_len:]
                        if len(text) > match_len:
                            results.append(("text", text[:-match_len]))
                        text = ""
                    else:
                        results.append(("text", text))
                        text = ""
            else:
                earliest_idx = -1
                found_tag = None
                for tag in self.CLOSE_TAGS:
                    idx = text.find(tag)
                    if idx != -1:
                        if earliest_idx == -1 or idx < earliest_idx:
                            earliest_idx = idx
                            found_tag = tag

                if earliest_idx != -1 and found_tag:
                    if earliest_idx > 0:
                        results.append(("thought", text[:earliest_idx]))
                    self.in_thought = False
                    text = text[earliest_idx + len(found_tag):]
                else:
                    match_len = 0
                    for tag in self.CLOSE_TAGS:
                        for l in range(min(len(tag) - 1, len(text)), 0, -1):
                            if text.endswith(tag[:l]):
                                if l > match_len:
                                    match_len = l
                    if match_len > 0:
                        self.pending = text[-match_len:]
                        if len(text) > match_len:
                            results.append(("thought", text[:-match_len]))
                        text = ""
                    else:
                        results.append(("thought", text))
                        text = ""

        return results

    def flush(self) -> List[Tuple[str, str]]:
        results: List[Tuple[str, str]] = []
        if self.pending:
            kind = "thought" if self.in_thought else "text"
            results.append((kind, self.pending))
            self.pending = ""
        return results


class ToolCallState:
    """Tracks state and identity for a single tool call to guarantee idempotency and stability."""
    def __init__(self, call_id: str, tool_name: str, args: Dict[str, Any]):
        self.call_id = call_id
        self.tool_name = tool_name
        self.args = args
        self.started_emitted = False
        self.finished = False
        self.failed = False
        self.result: Optional[str] = None
        self.error: Optional[str] = None
        self.is_subagent = (tool_name == "start_subagent")


class ActiveSession:
    def __init__(self, session_id: str, agent: Agent, emit_fn: Callable[[str, Dict[str, Any]], None]):
        self.session_id = session_id
        self.agent = agent
        self.emit_fn = emit_fn
        self.active_response: Optional[types.ChatResponse] = None
        self.active_task: Optional[asyncio.Task[Any]] = None
        self.is_closed = False
        # Map call_id -> ToolCallState
        self.active_tools: Dict[str, ToolCallState] = {}
        # Queue of pending call_ids by tool_name
        self.pending_by_name: Dict[str, List[str]] = {}
        # Set of call_ids that have finished (completed or failed) to guarantee deduplication
        self.finished_call_ids: set[str] = set()

    def get_or_create_tool_call(self, call_id: str, tool_name: str, args: Dict[str, Any]) -> ToolCallState:
        if call_id in self.active_tools:
            return self.active_tools[call_id]
        state = ToolCallState(call_id=call_id, tool_name=tool_name, args=args)
        self.active_tools[call_id] = state
        self.pending_by_name.setdefault(tool_name, []).append(call_id)
        return state

    def pop_pending_tool_call(self, tool_name: str, args: Optional[Dict[str, Any]] = None) -> Optional[ToolCallState]:
        pending_list = self.pending_by_name.get(tool_name, [])
        if not pending_list:
            return None

        # 1. Match by exact arguments if provided
        if args is not None:
            for idx, cid in enumerate(pending_list):
                state = self.active_tools.get(cid)
                if state and state.args == args and not state.finished:
                    pending_list.pop(idx)
                    return state

        # 2. Fall back to oldest unfinished call_id in FIFO order
        while pending_list:
            cid = pending_list.pop(0)
            state = self.active_tools.get(cid)
            if state and not state.finished:
                return state

        return None

    def mark_all_tools_failed(self, error_message: str = "Operation cancelled"):
        """Marks all active, unfinished tools as failed and emits failure events over IPC."""
        for call_id, state in list(self.active_tools.items()):
            if not state.finished and call_id not in self.finished_call_ids:
                state.finished = True
                state.failed = True
                state.error = error_message
                self.finished_call_ids.add(call_id)
                self.emit_fn("tool.failed", {
                    "sessionId": self.session_id,
                    "toolCallId": call_id,
                    "toolId": call_id,
                    "toolName": state.tool_name,
                    "error": error_message,
                })
                if state.is_subagent:
                    self.emit_fn("worker.failed", {
                        "sessionId": self.session_id,
                        "workerId": call_id,
                        "error": error_message,
                    })
        self.active_tools.clear()
        self.pending_by_name.clear()


class AgentRunner:
    def __init__(
        self,
        emit_fn: Callable[[str, Dict[str, Any]], None],
        request_tool_execution_fn: Optional[Callable[..., Awaitable[Dict[str, Any]]]] = None,
        adapter_server: Optional[Any] = None,
    ):
        self.emit_fn = emit_fn
        self.request_tool_execution_fn = request_tool_execution_fn
        self.adapter_server = adapter_server
        self.sessions: Dict[str, ActiveSession] = {}
        self._lock = asyncio.Lock()

    def emit_tool_progress(self, session_id: str, call_id: str, message: str, tool_name: str = ""):
        """Emits tool.progress notification over IPC with preserved call_id."""
        self.emit_fn("tool.progress", {
            "sessionId": session_id,
            "toolCallId": call_id,
            "toolId": call_id,
            "toolName": tool_name,
            "message": message,
        })

    def _create_hooks(self, session_id: str):
        emit = self.emit_fn

        @hooks.on_session_start
        async def on_start():
            logger.debug("Antigravity session '%s' initialized", session_id)

        @hooks.on_session_end
        async def on_end():
            logger.debug("Antigravity session '%s' ended", session_id)

        @hooks.pre_tool_call_decide
        async def on_pre_tool(call: ToolCall) -> types.HookResult:
            raw_id = getattr(call, "id", None) or getattr(call, "call_id", None) or getattr(call, "tool_call_id", None) or getattr(call, "step_id", None)
            if raw_id:
                call_id = str(raw_id)
            else:
                call_id = f"call_{uuid.uuid4().hex[:12]}"
            call.id = call_id
            if hasattr(call, "call_id"):
                try:
                    call.call_id = call_id
                except Exception:
                    pass

            tool_name = getattr(call, "name", "") or ""
            tool_args = getattr(call, "args", {}) or {}
            if not isinstance(tool_args, dict):
                tool_args = {}

            session = self.sessions.get(session_id)
            state = None
            if session:
                state = session.get_or_create_tool_call(call_id, tool_name, tool_args)

            # Emit canonical start notifications once per tool call
            if not state or not state.started_emitted:
                if state:
                    state.started_emitted = True
                if tool_name == "start_subagent":
                    emit("worker.started", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "name": tool_name,
                        "args": tool_args,
                    })
                emit("tool.started", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolId": call_id,
                    "toolName": tool_name,
                    "args": tool_args,
                })
            return types.HookResult(allow=True)

        @hooks.post_tool_call
        async def on_post_tool(res: ToolResult):
            raw_id = getattr(res, "id", None) or getattr(res, "call_id", None) or getattr(res, "tool_call_id", None) or getattr(res, "step_id", None)
            call_id = str(raw_id) if raw_id else ""
            tool_name = getattr(res, "name", "") or ""
            result_val = getattr(res, "result", None)
            err_val = getattr(res, "error", None)

            session = self.sessions.get(session_id)
            if session and call_id and call_id in session.finished_call_ids:
                # Already finalized: suppress duplicate completion/failure event
                return

            state: Optional[ToolCallState] = None

            if session:
                if call_id and call_id in session.active_tools:
                    state = session.active_tools.get(call_id)
                else:
                    # Match by tool_name with an unfinished active tool
                    for cid, t_state in list(session.active_tools.items()):
                        if t_state.tool_name == tool_name and not t_state.finished:
                            state = t_state
                            call_id = cid
                            break

            if session and call_id and call_id in session.finished_call_ids:
                return

            if not call_id:
                call_id = getattr(state, "call_id", "") or f"call_{uuid.uuid4().hex[:12]}"

            if state and state.finished:
                if session and call_id:
                    session.finished_call_ids.add(call_id)
                return

            if state:
                state.finished = True
                if session:
                    session.active_tools.pop(call_id, None)
                    session.finished_call_ids.add(call_id)
            elif session and call_id:
                session.finished_call_ids.add(call_id)

            # Determine whether execution failed (exception or error message string)
            is_failure = bool(err_val)
            error_message = str(err_val) if err_val else ""
            if not is_failure and isinstance(result_val, str) and (result_val.startswith("Error executing ") or result_val.startswith("Error: ")):
                is_failure = True
                error_message = result_val

            if is_failure:
                final_err = (state.error if state and state.error else "") or error_message or "Tool execution failed"
                if state:
                    state.failed = True
                    state.error = final_err
                if tool_name == "start_subagent":
                    emit("worker.failed", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "error": final_err,
                    })
                emit("tool.failed", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolId": call_id,
                    "toolName": tool_name,
                    "error": final_err,
                })
            else:
                formatted_result = str(result_val) if result_val is not None else (state.result if state and state.result else "")
                if state:
                    state.result = formatted_result
                if tool_name == "start_subagent":
                    emit("worker.completed", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "result": formatted_result,
                    })
                emit("tool.completed", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolId": call_id,
                    "toolName": tool_name,
                    "result": formatted_result,
                })

        @hooks.on_tool_error
        async def on_tool_err(exc: Exception):
            tool_name = getattr(exc, "tool_name", "") or ""
            raw_id = getattr(exc, "id", None) or getattr(exc, "call_id", None) or getattr(exc, "tool_call_id", None) or getattr(exc, "step_id", None)
            call_id = str(raw_id) if raw_id else ""
            session = self.sessions.get(session_id)

            if session and call_id and call_id in session.finished_call_ids:
                return None

            state: Optional[ToolCallState] = None

            if session:
                if call_id and call_id in session.active_tools:
                    state = session.active_tools.get(call_id)
                elif tool_name:
                    for cid, t_state in list(session.active_tools.items()):
                        if t_state.tool_name == tool_name and not t_state.finished:
                            state = t_state
                            call_id = cid
                            break
                if not call_id:
                    for cid, t_state in list(session.active_tools.items()):
                        if not t_state.finished:
                            state = t_state
                            call_id = cid
                            tool_name = t_state.tool_name
                            break

            if session and call_id and call_id in session.finished_call_ids:
                return None

            if state and state.finished:
                if session and call_id:
                    session.finished_call_ids.add(call_id)
                return None

            if state:
                state.finished = True
                state.failed = True
                state.error = str(exc)
                if session:
                    session.active_tools.pop(call_id, None)
                    session.finished_call_ids.add(call_id)
            elif session and call_id:
                session.finished_call_ids.add(call_id)

            final_id = call_id or f"call_{uuid.uuid4().hex[:12]}"
            emit("tool.failed", {
                "sessionId": session_id,
                "toolCallId": final_id,
                "toolId": final_id,
                "toolName": tool_name,
                "error": str(exc),
            })
            if tool_name == "start_subagent":
                emit("worker.failed", {
                    "sessionId": session_id,
                    "workerId": final_id,
                    "error": str(exc),
                })
            return None

        return [on_start, on_end, on_pre_tool, on_post_tool, on_tool_err]

    def _build_swift_tool_wrapper(self, session_id: str, tool_schema: Dict[str, Any]) -> ToolWithSchema:
        tool_name = tool_schema.get("name", "unknown_tool")
        tool_desc = tool_schema.get("description", "")
        param_schema = tool_schema.get("parameters")
        if not isinstance(param_schema, dict):
            param_schema = {"type": "object", "properties": {}}
        param_schema = sanitize_schema(param_schema)

        request_fn = self.request_tool_execution_fn
        emit = self.emit_fn

        async def _execute_swift_tool(**kwargs) -> str:
            session = self.sessions.get(session_id)
            state: Optional[ToolCallState] = None
            call_id = ""

            if session:
                state = session.pop_pending_tool_call(tool_name, kwargs)
                if state:
                    call_id = state.call_id

            if not call_id:
                call_id = f"call_{uuid.uuid4().hex[:12]}"
                if session:
                    state = session.get_or_create_tool_call(call_id, tool_name, kwargs)

            # Ensure tool.started was emitted with this exact stable call_id
            if state and not state.started_emitted:
                state.started_emitted = True
                if state.is_subagent:
                    emit("worker.started", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "name": tool_name,
                        "args": kwargs,
                    })
                emit("tool.started", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolId": call_id,
                    "toolName": tool_name,
                    "args": kwargs,
                })

            if not request_fn:
                err = f"Tool execution handler not registered for tool '{tool_name}'"
                if state:
                    state.error = err
                return f"Error: {err}"

            def _on_progress(chunk: Any):
                chunk_str = str(chunk)
                if chunk_str:
                    self.emit_tool_progress(session_id, call_id, chunk_str, tool_name)

            try:
                import inspect
                sig = inspect.signature(request_fn)
                call_kwargs: Dict[str, Any] = {}
                if "progress_callback" in sig.parameters:
                    call_kwargs["progress_callback"] = _on_progress
                elif "on_progress" in sig.parameters:
                    call_kwargs["on_progress"] = _on_progress

                if "call_id" in sig.parameters or len(sig.parameters) >= 4:
                    res = await request_fn(session_id, tool_name, kwargs, call_id, **call_kwargs)
                else:
                    res = await request_fn(session_id, tool_name, kwargs, **call_kwargs)

                # Handle async generator / generator streaming chunks
                if inspect.isasyncgen(res) or hasattr(res, "__aiter__"):
                    chunks = []
                    async for item in res:
                        item_str = str(item)
                        chunks.append(item_str)
                        self.emit_tool_progress(session_id, call_id, item_str, tool_name)
                    final_result = "".join(chunks)
                    if state:
                        state.result = final_result
                    return final_result
                elif inspect.isgenerator(res):
                    chunks = []
                    for item in res:
                        item_str = str(item)
                        chunks.append(item_str)
                        self.emit_tool_progress(session_id, call_id, item_str, tool_name)
                    final_result = "".join(chunks)
                    if state:
                        state.result = final_result
                    return final_result

                if isinstance(res, dict):
                    # Surface tool.progress notification if intermediate progress or chunks are reported
                    prog = res.get("progress") or res.get("progressMessage") or res.get("message")
                    if prog:
                        if isinstance(prog, list):
                            for p in prog:
                                self.emit_tool_progress(session_id, call_id, str(p), tool_name)
                        else:
                            self.emit_tool_progress(session_id, call_id, str(prog), tool_name)
                    if "chunks" in res and isinstance(res["chunks"], list):
                        for c in res["chunks"]:
                            self.emit_tool_progress(session_id, call_id, str(c), tool_name)

                    if res.get("success", False):
                        out_val = str(res.get("result", ""))
                        if state:
                            state.result = out_val
                        return out_val
                    else:
                        err_msg = res.get("error") or "Unknown tool execution error"
                        if state:
                            state.error = err_msg
                        return f"Error executing {tool_name}: {err_msg}"

                out_val = str(res)
                if state:
                    state.result = out_val
                return out_val

            except asyncio.CancelledError:
                if state and not state.finished:
                    state.finished = True
                    state.failed = True
                    state.error = "Tool execution was cancelled"
                    if session:
                        session.finished_call_ids.add(call_id)
                        session.active_tools.pop(call_id, None)
                    emit("tool.failed", {
                        "sessionId": session_id,
                        "toolCallId": call_id,
                        "toolId": call_id,
                        "toolName": tool_name,
                        "error": "Tool execution was cancelled",
                    })
                    if state.is_subagent:
                        emit("worker.failed", {
                            "sessionId": session_id,
                            "workerId": call_id,
                            "error": "Worker execution was cancelled",
                        })
                raise
            except Exception as e:
                err_str = f"Error executing {tool_name}: {str(e)}"
                if state:
                    state.error = str(e)
                return err_str

        _execute_swift_tool.__name__ = tool_name
        _execute_swift_tool.__doc__ = tool_desc

        wrapper = ToolWithSchema(
            fn=_execute_swift_tool,
            input_schema=param_schema,
        )
        wrapper.__name__ = tool_name
        wrapper.__doc__ = tool_desc
        return wrapper

    async def create_session(self, session_id: str, params: Dict[str, Any]) -> Dict[str, Any]:
        async with self._lock:
            if session_id in self.sessions:
                existing_session = self.sessions[session_id]
                if not existing_session.is_closed:
                    logger.info("Maintaining and reusing active Antigravity session '%s'", session_id)
                    return {
                        "sessionId": session_id,
                        "conversationId": getattr(existing_session.agent, "conversation_id", None),
                        "status": "ready",
                        "model": params.get("model", getattr(existing_session.agent, "model", "gemini-3.8-flash")),
                        "toolCount": len(params.get("tools", [])),
                    }
                else:
                    self.sessions.pop(session_id, None)

            model = params.get("model", "gemini-3.8-flash")
            api_key = params.get("apiKey") or os.environ.get("GEMINI_API_KEY")
            system_instructions = params.get("systemInstructions", "")
            skills_paths = params.get("skillsPaths", [])
            workspaces = params.get("workspaces", [])
            app_data_dir = params.get("appDataDir")
            save_dir = params.get("saveDir")
            vertex = params.get("vertex", False)
            project = params.get("project")
            location = params.get("location")
            enable_subagents = params.get("enableSubagents", True)
            max_subagent_depth = params.get("maxSubagentDepth", 3)
            registered_tools_schemas = params.get("tools", [])
            toolkit = (params.get("toolkit") or "System").strip()

            # Dynamic tools & Built-in tools depending on Assist Toolkit setting
            dynamic_tools = []
            builtin_tools = []

            if toolkit.lower() == "cloud":
                # Cloud mode: use Antigravity SDK's built-in tools (view_file, edit_file, run_command, etc.)
                builtin_tools = list(types.BuiltinTools.default())
                if not enable_subagents and types.BuiltinTools.START_SUBAGENT in builtin_tools:
                    builtin_tools.remove(types.BuiltinTools.START_SUBAGENT)

                cloud_instruction = (
                    "\n\n[ASSIST TOOLKIT: Antigravity Cloud Tools]\n"
                    "You are operating with Google Antigravity Cloud tools.\n"
                    "- Use built-in tools (view_file, edit_file, create_file, run_command, list_directory, search_directory) to inspect and modify the project.\n"
                    "- Complete the requested changes autonomously."
                )
                system_instructions = (system_instructions + cloud_instruction).strip()
            else:
                # System mode (Default): use SwiftCode native tools passed over the bridge
                if enable_subagents:
                    builtin_tools.append(types.BuiltinTools.START_SUBAGENT)

                for t_schema in registered_tools_schemas:
                    if isinstance(t_schema, dict) and "name" in t_schema:
                        wrapper = self._build_swift_tool_wrapper(session_id, t_schema)
                        dynamic_tools.append(wrapper)

                system_instruction = (
                    "\n\n[ASSIST TOOLKIT: SwiftCode System Tools]\n"
                    "You are operating with SwiftCode's native System tools.\n"
                    "- Use the provided tools (file_write, file_read, code_replace, file_create, use_terminal, etc.) to inspect, modify, and build the project.\n"
                    "- When specifying file paths, use relative paths from the workspace root (e.g., 'Sources/App.swift').\n"
                    "- Modify code directly using tools; do not output code blocks without saving them.\n"
                    "- Act autonomously and verify your changes."
                )
                system_instructions = (system_instructions + system_instruction).strip()

            # Build policies
            session_policies = []
            if workspaces:
                session_policies.append(policy.workspace_only(workspaces))
            session_policies.append(policy.allow_all())
            session_policies.append(policy.allow("run_command"))
            session_policies.append(policy.allow("edit_file"))
            session_policies.append(policy.allow("create_file"))

            cap_config = types.CapabilitiesConfig(
                enabled_tools=builtin_tools,
                enable_subagents=enable_subagents,
                max_subagent_depth=max_subagent_depth if enable_subagents else None,
                agent_behavior=types.AgentBehavior.AUTONOMOUS,
            )

            logger.info(
                "Creating %s toolkit session: instructions=%d chars, dynamic_tools=%d, builtin_tools=%d",
                toolkit,
                len(system_instructions or ""),
                len(dynamic_tools),
                len(builtin_tools),
            )

            # Determine provider & routing strategy
            provider = (params.get("provider") or "").lower()
            model_lower = str(model).lower()
            model_path_param = str(params.get("modelPath") or params.get("model_path") or params.get("litertModelPath") or "")
            base_url = params.get("baseURL") or ""

            # Extract optional OAuth token and headers
            oauth_token = params.get("oauthToken") or params.get("oauth_token")
            http_headers = dict(params.get("headers") or {})
            if oauth_token:
                http_headers["Authorization"] = f"Bearer {oauth_token}"

            is_litert = (
                provider == "litert"
                or model_lower.endswith(".litertlm")
                or ".litertlm" in model_lower
                or model_path_param.lower().endswith(".litertlm")
                or bool(params.get("litertModelPath"))
            )
            is_gemini = not is_litert and ((provider in ("gemini", "google")) or (not provider and ("gemini" in model_lower)))

            if is_litert:
                if LiteRTAgentConfig is None:
                    raise RuntimeError("LiteRTAgentConfig is not available in the installed google.antigravity SDK.")

                resolved_model_path = params.get("litertModelPath") or model_path_param or model
                if resolved_model_path:
                    resolved_model_path = os.path.expanduser(str(resolved_model_path))

                backend_str = str(params.get("litertBackend") or params.get("backend") or "gpu").strip().lower()
                if LiteRTBackend is not None:
                    if backend_str == "npu":
                        backend_val = LiteRTBackend.NPU
                    elif backend_str == "cpu":
                        backend_val = getattr(LiteRTBackend, "CPU", "cpu")
                    else:
                        backend_val = LiteRTBackend.GPU
                else:
                    backend_val = backend_str

                speculative_decoding = bool(
                    params.get("enableSpeculativeDecoding", params.get("enable_speculative_decoding", False))
                )
                download_missing = bool(
                    params.get("downloadIfMissing", params.get("download_if_missing", False))
                )

                litert_kwargs: Dict[str, Any] = {
                    "model_path": resolved_model_path,
                    "backend": backend_val,
                    "enable_speculative_decoding": speculative_decoding,
                    "download_if_missing": download_missing,
                    "capabilities": cap_config,
                    "policies": session_policies,
                    "hooks": self._create_hooks(session_id),
                }

                if CompactionConfig is not None:
                    litert_kwargs["compaction_config"] = CompactionConfig(token_threshold=40960)

                if params.get("cacheDir") or params.get("cache_dir"):
                    litert_kwargs["cache_dir"] = params.get("cacheDir") or params.get("cache_dir")

                if "port" in params:
                    litert_kwargs["port"] = int(params["port"])

                if dynamic_tools:
                    litert_kwargs["tools"] = dynamic_tools
                if system_instructions:
                    litert_kwargs["system_instructions"] = system_instructions
                if skills_paths:
                    litert_kwargs["skills_paths"] = skills_paths
                if workspaces:
                    litert_kwargs["workspaces"] = workspaces
                if app_data_dir and os.path.isabs(app_data_dir):
                    litert_kwargs["app_data_dir"] = app_data_dir
                if save_dir and os.path.isabs(save_dir):
                    litert_kwargs["save_dir"] = save_dir

                agent_config = LiteRTAgentConfig(**litert_kwargs)

            elif is_gemini:
                config_kwargs: Dict[str, Any] = {
                    "model": model,
                    "capabilities": cap_config,
                    "policies": session_policies,
                    "hooks": self._create_hooks(session_id),
                }

                if dynamic_tools:
                    config_kwargs["tools"] = dynamic_tools

                if api_key:
                    config_kwargs["api_key"] = api_key
                if vertex:
                    config_kwargs["vertex"] = True
                    if project:
                        config_kwargs["project"] = project
                    if location:
                        config_kwargs["location"] = location

                # Configure VertexEndpoint / GeminiAPIEndpoint when http_headers or oauthToken is present
                if http_headers:
                    if vertex and VertexEndpoint is not None:
                        endpoint = VertexEndpoint(
                            project=project,
                            location=location,
                            api_key=api_key,
                            http_headers=http_headers,
                        )
                        config_kwargs["models"] = [
                            types.ModelTarget(
                                name=model,
                                types=[types.ModelType.TEXT],
                                endpoint=endpoint,
                            )
                        ]
                    elif GeminiAPIEndpoint is not None:
                        endpoint = GeminiAPIEndpoint(
                            api_key=api_key,
                            http_headers=http_headers,
                        )
                        config_kwargs["models"] = [
                            types.ModelTarget(
                                name=model,
                                types=[types.ModelType.TEXT],
                                endpoint=endpoint,
                            )
                        ]

                if system_instructions:
                    config_kwargs["system_instructions"] = system_instructions
                if skills_paths:
                    config_kwargs["skills_paths"] = skills_paths
                if workspaces:
                    config_kwargs["workspaces"] = workspaces
                if app_data_dir and os.path.isabs(app_data_dir):
                    config_kwargs["app_data_dir"] = app_data_dir
                if save_dir and os.path.isabs(save_dir):
                    config_kwargs["save_dir"] = save_dir

                agent_config = LocalAgentConfig(**config_kwargs)

            else:
                # Use LocalOpenAIAgentConfig with direct local endpoint or bridge adapter
                resolved_base_url = base_url
                if provider in ("ollama", "lmstudio") and not resolved_base_url:
                    resolved_base_url = "http://localhost:11434/v1" if provider == "ollama" else "http://localhost:1234/v1"

                if not resolved_base_url or provider in ("anthropic", "claude", "openai", "openrouter", "mistral", "qwen", "custom"):
                    if self.adapter_server and self.adapter_server.actual_port > 0:
                        self.adapter_server.register_target(
                            model_name=model,
                            provider=provider,
                            api_key=api_key,
                            base_url=base_url,
                            headers=http_headers if http_headers else None,
                        )
                        resolved_base_url = f"http://127.0.0.1:{self.adapter_server.actual_port}/v1"
                    elif not resolved_base_url:
                        resolved_base_url = "http://127.0.0.1:11434/v1"

                openai_config_kwargs: Dict[str, Any] = {
                    "model": model,
                    "base_url": resolved_base_url,
                    "capabilities": cap_config,
                    "policies": session_policies,
                    "hooks": self._create_hooks(session_id),
                }

                if dynamic_tools:
                    openai_config_kwargs["tools"] = dynamic_tools
                if system_instructions:
                    openai_config_kwargs["system_instructions"] = system_instructions
                if skills_paths:
                    openai_config_kwargs["skills_paths"] = skills_paths
                if workspaces:
                    openai_config_kwargs["workspaces"] = workspaces
                if app_data_dir and os.path.isabs(app_data_dir):
                    openai_config_kwargs["app_data_dir"] = app_data_dir
                if save_dir and os.path.isabs(save_dir):
                    openai_config_kwargs["save_dir"] = save_dir

                agent_config = LocalOpenAIAgentConfig(**openai_config_kwargs)

            agent = Agent(config=agent_config)

            # Enter agent async context
            await agent.__aenter__()

            session = ActiveSession(session_id, agent, self.emit_fn)
            self.sessions[session_id] = session

            logger.info("Created Antigravity session '%s' with model '%s' and %d dynamic Swift tools", session_id, model, len(dynamic_tools))
            return {
                "sessionId": session_id,
                "conversationId": agent.conversation_id,
                "status": "ready",
                "model": model,
                "toolCount": len(dynamic_tools),
            }

    async def send_message(self, session_id: str, content: str, attachments: Optional[List[Dict[str, Any]]] = None) -> Dict[str, Any]:
        session = self.sessions.get(session_id)
        if not session or session.is_closed:
            raise KeyError(f"Session '{session_id}' not found or closed")

        if session.active_task and not session.active_task.done():
            raise RuntimeError(f"Session '{session_id}' is currently processing another turn")

        emit = self.emit_fn

        async def _run_turn():
            accumulated_text = []
            thought_parser = StreamingThoughtParser()
            try:
                emit("agent.started", {"sessionId": session_id, "prompt": content})
                response = await session.agent.chat(content)
                session.active_response = response

                # Stream rich semantic chunks as they arrive from backend
                async for chunk in response.chunks:
                    is_thought = isinstance(chunk, Thought) or type(chunk).__name__ == "Thought" or hasattr(chunk, "signature")
                    if is_thought:
                        thought_val = getattr(chunk, "text", None) or getattr(chunk, "thought", None) or str(chunk)
                        if thought_val:
                            emit("agent.progress", {
                                "sessionId": session_id,
                                "thoughtDelta": str(thought_val),
                            })
                    elif isinstance(chunk, Text) or type(chunk).__name__ == "Text":
                        raw_text = getattr(chunk, "text", "")
                        for kind, seg in thought_parser.feed(raw_text):
                            if kind == "thought" and seg:
                                emit("agent.progress", {
                                    "sessionId": session_id,
                                    "thoughtDelta": seg,
                                })
                            elif kind == "text" and seg:
                                accumulated_text.append(seg)
                                emit("agent.progress", {
                                    "sessionId": session_id,
                                    "delta": seg,
                                })

                for kind, seg in thought_parser.flush():
                    if kind == "thought" and seg:
                        emit("agent.progress", {
                            "sessionId": session_id,
                            "thoughtDelta": seg,
                        })
                    elif kind == "text" and seg:
                        accumulated_text.append(seg)
                        emit("agent.progress", {
                            "sessionId": session_id,
                            "delta": seg,
                        })

                final_text = "".join(accumulated_text)
                usage = None
                if response.usage_metadata:
                    usage = {
                        "promptTokens": getattr(response.usage_metadata, "prompt_token_count", 0),
                        "completionTokens": getattr(response.usage_metadata, "candidates_token_count", 0),
                        "totalTokens": getattr(response.usage_metadata, "total_token_count", 0),
                    }

                stop_reason = str(response.stop_reason) if hasattr(response, "stop_reason") else "end_of_turn"

                # Mark any orphaned tools before finalizing turn
                session.mark_all_tools_failed("Turn completed without explicit tool completion")

                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text,
                    "stopReason": stop_reason,
                    "usage": usage,
                })
            except types.AntigravityCancelledError:
                logger.info("Session '%s' turn was cancelled/interrupted", session_id)
                session.mark_all_tools_failed("Turn was cancelled by user")
                final_text = "".join(accumulated_text)
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text if final_text else "[Interrupted by user]",
                    "stopReason": "interrupted",
                })
            except asyncio.CancelledError:
                logger.info("Session '%s' asyncio task was cancelled/interrupted", session_id)
                session.mark_all_tools_failed("Turn was cancelled by user")
                final_text = "".join(accumulated_text)
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text if final_text else "[Interrupted by user]",
                    "stopReason": "interrupted",
                })
            except Exception as e:
                logger.exception("Error executing turn in session '%s': %s", session_id, e)
                session.mark_all_tools_failed(f"Turn execution error: {str(e)}")
                emit("agent.failed", {
                    "sessionId": session_id,
                    "error": str(e),
                })
            finally:
                session.mark_all_tools_failed("Turn finished")
                session.active_response = None

        task = asyncio.create_task(_run_turn())
        session.active_task = task
        return {"sessionId": session_id, "status": "processing"}

    async def cancel_message(self, session_id: str) -> Dict[str, Any]:
        session = self.sessions.get(session_id)
        if not session:
            raise KeyError(f"Session '{session_id}' not found")

        # Mark all in-flight tools as cancelled immediately so the UI does not hang
        session.mark_all_tools_failed("Tool execution was cancelled by user")

        if session.active_response:
            try:
                await session.active_response.cancel()
            except Exception as e:
                logger.warning("Error calling response.cancel() on session '%s': %s", session_id, e)

        if session.active_task and not session.active_task.done():
            session.active_task.cancel()

        return {"sessionId": session_id, "status": "cancelling"}

    async def close_session(self, session_id: str) -> Dict[str, Any]:
        async with self._lock:
            session = self.sessions.pop(session_id, None)
            if not session:
                return {"sessionId": session_id, "status": "already_closed"}

            session.is_closed = True
            session.mark_all_tools_failed("Session closed")

            if session.active_task and not session.active_task.done():
                session.active_task.cancel()

            try:
                await session.agent.__aexit__(None, None, None)
            except Exception as e:
                logger.warning("Error exiting agent context for session '%s': %s", session_id, e)

            logger.info("Closed Antigravity session '%s'", session_id)
            return {"sessionId": session_id, "status": "closed"}

    async def stop_all(self):
        async with self._lock:
            for session_id in list(self.sessions.keys()):
                await self.close_session(session_id)
