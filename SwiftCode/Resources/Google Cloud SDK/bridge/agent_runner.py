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
from typing import Any, Callable, Dict, List, Optional, Tuple, Awaitable

import uuid

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


class ActiveSession:
    def __init__(self, session_id: str, agent: Agent, emit_fn: Callable[[str, Dict[str, Any]], None]):
        self.session_id = session_id
        self.agent = agent
        self.emit_fn = emit_fn
        self.active_response: Optional[types.ChatResponse] = None
        self.active_task: Optional[asyncio.Task[Any]] = None
        self.is_closed = False
        self.pending_call_ids: Dict[str, List[str]] = {}


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

    def emit_tool_progress(self, session_id: str, tool_id: str, message: str, tool_name: str = ""):
        self.emit_fn("tool.progress", {
            "sessionId": session_id,
            "toolCallId": tool_id,
            "toolId": tool_id,
            "toolName": tool_name,
            "message": message,
        })

    def _create_hooks(self, session_id: str):
        emit = self.emit_fn

        @hooks.on_session_start
        async def on_start():
            emit("agent.started", {"sessionId": session_id, "timestamp": asyncio.get_event_loop().time()})

        @hooks.on_session_end
        async def on_end():
            emit("agent.completed", {"sessionId": session_id, "timestamp": asyncio.get_event_loop().time()})

        @hooks.pre_tool_call_decide
        async def on_pre_tool(call: ToolCall) -> types.HookResult:
            call_id = getattr(call, "id", "") or str(getattr(call, "step_id", "") or "")
            tool_name = getattr(call, "name", "")
            tool_args = getattr(call, "args", {}) or {}
            session = self.sessions.get(session_id)
            if session:
                session.pending_call_ids.setdefault(tool_name, []).append(call_id)

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
                "toolName": tool_name,
                "args": tool_args,
            })
            return types.HookResult(allow=True)

        @hooks.post_tool_call
        async def on_post_tool(res: ToolResult):
            call_id = getattr(res, "id", "") or str(getattr(res, "step_id", "") or "")
            tool_name = getattr(res, "name", "")
            result_val = getattr(res, "result", None)
            err_val = getattr(res, "error", None)

            # Determine whether execution failed (exception or error message string)
            is_failure = bool(err_val)
            error_message = str(err_val) if err_val else ""
            if not is_failure and isinstance(result_val, str) and (result_val.startswith("Error executing ") or result_val.startswith("Error: ")):
                is_failure = True
                error_message = result_val

            if is_failure:
                if tool_name == "start_subagent":
                    emit("worker.failed", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "error": error_message,
                    })
                emit("tool.failed", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolName": tool_name,
                    "error": error_message,
                })
            else:
                formatted_result = str(result_val) if result_val is not None else ""
                if tool_name == "start_subagent":
                    emit("worker.completed", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "result": formatted_result,
                    })
                emit("tool.completed", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolName": tool_name,
                    "result": formatted_result,
                })

        @hooks.on_tool_error
        async def on_tool_err(exc: Exception):
            emit("tool.failed", {
                "sessionId": session_id,
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
            call_id = ""
            if session and session.pending_call_ids.get(tool_name):
                call_id = session.pending_call_ids[tool_name].pop(0)
            if not call_id:
                call_id = str(uuid.uuid4())

            if not request_fn:
                err = f"Tool execution handler not registered for tool '{tool_name}'"
                return f"Error: {err}"

            try:
                # Pass stable SDK call.id to Swift tool execution.
                # Redundant tool.started and tool.completed emissions are omitted here
                # because the SDK on_pre_tool and on_post_tool hooks canonically emit them.
                import inspect
                sig = inspect.signature(request_fn)
                if "call_id" in sig.parameters or len(sig.parameters) >= 4:
                    res = await request_fn(session_id, tool_name, kwargs, call_id)
                else:
                    res = await request_fn(session_id, tool_name, kwargs)

                if isinstance(res, dict):
                    # Surface tool.progress notification if intermediate progress is reported
                    if "progress" in res and res["progress"]:
                        emit("tool.progress", {
                            "sessionId": session_id,
                            "toolCallId": call_id,
                            "toolName": tool_name,
                            "message": str(res["progress"]),
                        })
                    if res.get("success", False):
                        return str(res.get("result", ""))
                    else:
                        err_msg = res.get("error") or "Unknown tool execution error"
                        return f"Error executing {tool_name}: {err_msg}"
                return str(res)
            except Exception as e:
                return f"Error executing {tool_name}: {str(e)}"

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
                raise ValueError(f"Session '{session_id}' already exists")

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
            use_saved_models = params.get("useSavedModels", False)
            base_url = params.get("baseURL") or ""

            is_gemini = (provider in ("gemini", "google")) or (not provider and ("gemini" in model.lower()))

            if is_gemini:
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
                            headers=params.get("headers"),
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
            try:
                emit("agent.started", {"sessionId": session_id, "prompt": content})
                response = await session.agent.chat(content)
                session.active_response = response

                # Stream rich semantic chunks as they arrive from backend
                async for chunk in response.chunks:
                    if isinstance(chunk, Text):
                        accumulated_text.append(chunk.text)
                        emit("agent.progress", {
                            "sessionId": session_id,
                            "delta": chunk.text,
                        })
                    elif isinstance(chunk, Thought):
                        emit("agent.progress", {
                            "sessionId": session_id,
                            "thoughtDelta": chunk.text,
                        })
                    # Tool lifecycle notifications are emitted by the SDK's
                    # pre/post hooks above. Re-emitting ToolCall chunks here
                    # duplicates starts/completions and corrupts retry timing.

                final_text = "".join(accumulated_text)
                usage = None
                if response.usage_metadata:
                    usage = {
                        "promptTokens": getattr(response.usage_metadata, "prompt_token_count", 0),
                        "completionTokens": getattr(response.usage_metadata, "candidates_token_count", 0),
                        "totalTokens": getattr(response.usage_metadata, "total_token_count", 0),
                    }

                stop_reason = str(response.stop_reason) if hasattr(response, "stop_reason") else "end_of_turn"

                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text,
                    "stopReason": stop_reason,
                    "usage": usage,
                })
            except types.AntigravityCancelledError:
                logger.info("Session '%s' turn was cancelled/interrupted", session_id)
                final_text = "".join(accumulated_text)
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text if final_text else "[Interrupted by user]",
                    "stopReason": "interrupted",
                })
            except asyncio.CancelledError:
                logger.info("Session '%s' asyncio task was cancelled/interrupted", session_id)
                final_text = "".join(accumulated_text)
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text if final_text else "[Interrupted by user]",
                    "stopReason": "interrupted",
                })
            except Exception as e:
                logger.exception("Error executing turn in session '%s': %s", session_id, e)
                emit("agent.failed", {
                    "sessionId": session_id,
                    "error": str(e),
                })
            finally:
                session.active_response = None

        task = asyncio.create_task(_run_turn())
        session.active_task = task
        return {"sessionId": session_id, "status": "processing"}

    async def cancel_message(self, session_id: str) -> Dict[str, Any]:
        session = self.sessions.get(session_id)
        if not session:
            raise KeyError(f"Session '{session_id}' not found")

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
