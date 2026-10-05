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

# Ensure bundled site-packages are available
bridge_dir = os.path.dirname(os.path.abspath(__file__))
sdk_root = os.path.dirname(bridge_dir)
site_packages = os.path.join(sdk_root, "runtime", "lib", "python3.14", "site-packages")
if os.path.isdir(site_packages) and site_packages not in sys.path:
    sys.path.insert(0, site_packages)

from google.antigravity import Agent, LocalAgentConfig, types
from google.antigravity.hooks import hooks, policy
from google.antigravity.types import Text, Thought, ToolCall, ToolResult
from google.antigravity.tools.tool_runner import ToolWithSchema

logger = logging.getLogger("AntigravityAgentRunner")


class ActiveSession:
    def __init__(self, session_id: str, agent: Agent, emit_fn: Callable[[str, Dict[str, Any]], None]):
        self.session_id = session_id
        self.agent = agent
        self.emit_fn = emit_fn
        self.active_response: Optional[types.ChatResponse] = None
        self.active_task: Optional[asyncio.Task[Any]] = None
        self.is_closed = False


class AgentRunner:
    def __init__(
        self,
        emit_fn: Callable[[str, Dict[str, Any]], None],
        request_tool_execution_fn: Optional[Callable[[str, str, Dict[str, Any]], Awaitable[Dict[str, Any]]]] = None,
    ):
        self.emit_fn = emit_fn
        self.request_tool_execution_fn = request_tool_execution_fn
        self.sessions: Dict[str, ActiveSession] = {}
        self._lock = asyncio.Lock()

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

            if err_val:
                if tool_name == "start_subagent":
                    emit("worker.failed", {
                        "sessionId": session_id,
                        "workerId": call_id,
                        "error": str(err_val),
                    })
                emit("tool.failed", {
                    "sessionId": session_id,
                    "toolCallId": call_id,
                    "toolName": tool_name,
                    "error": str(err_val),
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
        param_schema = tool_schema.get("parameters", {"type": "object", "properties": {}})

        request_fn = self.request_tool_execution_fn

        async def _execute_swift_tool(**kwargs) -> str:
            if not request_fn:
                raise RuntimeError(f"Tool execution handler not registered for tool '{tool_name}'")
            res = await request_fn(session_id, tool_name, kwargs)
            if res.get("success", False):
                return str(res.get("result", ""))
            else:
                err_msg = res.get("error") or "Unknown tool execution error"
                raise RuntimeError(err_msg)

        wrapper = ToolWithSchema(
            func=_execute_swift_tool,
            input_schema=param_schema,
            name=tool_name,
            doc=tool_desc,
        )
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

            # Construct dynamic Python tool functions from Swift tool schemas
            dynamic_tools = []
            for t_schema in registered_tools_schemas:
                if isinstance(t_schema, dict) and "name" in t_schema:
                    wrapper = self._build_swift_tool_wrapper(session_id, t_schema)
                    dynamic_tools.append(wrapper)

            # Build policies
            session_policies = []
            if workspaces:
                session_policies.append(policy.workspace_only(workspaces))
            session_policies.append(policy.allow_all())

            # Configure capabilities: disable built-in tools (e.g. run_command, edit_file, view_file)
            # and allow ONLY START_SUBAGENT if subagents are enabled. All actual work uses
            # dynamic Swift tools registered from SwiftCode Assist.
            builtin_tools = []
            if enable_subagents:
                builtin_tools.append(types.BuiltinTools.START_SUBAGENT)

            cap_config = types.CapabilitiesConfig(
                enabled_tools=builtin_tools,
                enable_subagents=enable_subagents,
                max_subagent_depth=max_subagent_depth if enable_subagents else None,
                agent_behavior=types.AgentBehavior.AUTONOMOUS,
            )

            # Build LocalAgentConfig
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
            try:
                emit("agent.started", {"sessionId": session_id, "prompt": content})
                response = await session.agent.chat(content)
                session.active_response = response

                accumulated_text = []

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
                    elif isinstance(chunk, ToolCall):
                        tool_id = getattr(chunk, "id", "") or str(getattr(chunk, "step_id", "") or "")
                        tool_name = getattr(chunk, "name", "")
                        if tool_name == "start_subagent":
                            emit("worker.started", {
                                "sessionId": session_id,
                                "workerId": tool_id,
                                "name": tool_name,
                                "args": getattr(chunk, "args", {}) or {},
                            })
                        emit("tool.started", {
                            "sessionId": session_id,
                            "toolCallId": tool_id,
                            "toolName": tool_name,
                            "args": getattr(chunk, "args", {}) or {},
                        })
                    elif isinstance(chunk, ToolResult):
                        tool_id = getattr(chunk, "id", "") or str(getattr(chunk, "step_id", "") or "")
                        tool_name = getattr(chunk, "name", "")
                        res_val = getattr(chunk, "result", None)
                        err_val = getattr(chunk, "error", None)
                        if err_val:
                            if tool_name == "start_subagent":
                                emit("worker.failed", {
                                    "sessionId": session_id,
                                    "workerId": tool_id,
                                    "error": str(err_val),
                                })
                            emit("tool.failed", {
                                "sessionId": session_id,
                                "toolCallId": tool_id,
                                "toolName": tool_name,
                                "error": str(err_val),
                            })
                        else:
                            formatted = str(res_val) if res_val is not None else ""
                            if tool_name == "start_subagent":
                                emit("worker.completed", {
                                    "sessionId": session_id,
                                    "workerId": tool_id,
                                    "result": formatted,
                                })
                            emit("tool.completed", {
                                "sessionId": session_id,
                                "toolCallId": tool_id,
                                "toolName": tool_name,
                                "result": formatted,
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

                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": final_text,
                    "stopReason": stop_reason,
                    "usage": usage,
                })
            except types.AntigravityCancelledError:
                logger.info("Session '%s' turn was cancelled", session_id)
                emit("agent.progress", {
                    "sessionId": session_id,
                    "delta": "\n[Generation cancelled by user]",
                })
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": "[Cancelled]",
                    "stopReason": "cancelled",
                })
            except asyncio.CancelledError:
                logger.info("Session '%s' asyncio task was cancelled", session_id)
                emit("agent.completed", {
                    "sessionId": session_id,
                    "response": "[Cancelled]",
                    "stopReason": "cancelled",
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
