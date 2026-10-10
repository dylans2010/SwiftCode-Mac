#!/usr/bin/env python3
"""
SwiftCode Antigravity Bridge Daemon.
Bidirectional structured IPC server bridging SwiftCode to the Google Antigravity SDK.

Framing: newline-delimited JSON-RPC 2.0 over a Unix domain socket (or stdio).
The daemon serves exactly one SwiftCode client and exits when that client
disconnects, when the parent process disappears, or on SIGTERM/SIGINT, so it
never outlives the app.
"""

from __future__ import annotations
import argparse
import asyncio
import os
import signal
import sys
import logging
import uuid
from typing import Any, Dict, Optional, Set

# Add bundled site-packages to sys.path before any library imports
bridge_dir = os.path.dirname(os.path.abspath(__file__))
sdk_root = os.path.dirname(bridge_dir)
site_packages = os.path.join(sdk_root, "runtime", "lib", "python3.14", "site-packages")
if os.path.isdir(site_packages) and site_packages not in sys.path:
    sys.path.insert(0, site_packages)
if bridge_dir not in sys.path:
    sys.path.insert(0, bridge_dir)

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("AntigravityBridge")

# Resolve (and if necessary unpack outside the app bundle) the localharness
# binary before the SDK is imported.
from harness import ensure_harness  # noqa: E402

ensure_harness(site_packages)

from protocol import (  # noqa: E402
    ProtocolMessage,
    PARSE_ERROR,
    INVALID_REQUEST,
    METHOD_NOT_FOUND,
    INVALID_PARAMS,
    INTERNAL_ERROR,
    SESSION_NOT_FOUND,
)
from agent_runner import AgentRunner, SessionNotFoundError  # noqa: E402
from model_adapter_server import ModelAdapterServer  # noqa: E402

DEFAULT_TOOL_TIMEOUT_SECONDS = 1800.0
SHUTDOWN_GRACE_SECONDS = 5.0


def resolve_sdk_version() -> str:
    """Reads the installed google-antigravity version instead of hardcoding it."""
    try:
        from importlib import metadata

        return metadata.version("google-antigravity")
    except Exception:
        pass
    try:
        import glob

        for dist in glob.glob(os.path.join(site_packages, "google_antigravity-*.dist-info")):
            name = os.path.basename(dist)
            return name[len("google_antigravity-"):-len(".dist-info")]
    except Exception:
        pass
    return "unknown"


SDK_VERSION = resolve_sdk_version()


class BridgeServer:
    def __init__(self, socket_path: Optional[str] = None, parent_pid: Optional[int] = None):
        self.socket_path = socket_path
        self.parent_pid = parent_pid
        self.writer: Optional[asyncio.StreamWriter] = None
        self.pending_requests: Dict[str, asyncio.Future[Dict[str, Any]]] = {}
        self.adapter_server = ModelAdapterServer()
        self.runner = AgentRunner(
            self.emit_notification,
            self.request_tool_execution,
            adapter_server=self.adapter_server,
            request_approval_fn=self.request_approval,
        )
        self.is_running = True
        self.server: Optional[asyncio.Server] = None
        self.shutdown_event: Optional[asyncio.Event] = None
        self._background_tasks: Set[asyncio.Task[Any]] = set()
        self._has_served_client = False
        try:
            self.tool_timeout = float(os.environ.get("SWIFTCODE_TOOL_TIMEOUT_SECONDS", DEFAULT_TOOL_TIMEOUT_SECONDS))
        except ValueError:
            self.tool_timeout = DEFAULT_TOOL_TIMEOUT_SECONDS

    # MARK: - Output

    def _spawn(self, coro: Any) -> asyncio.Task[Any]:
        task = asyncio.get_running_loop().create_task(coro)
        self._background_tasks.add(task)
        task.add_done_callback(self._background_tasks.discard)
        return task

    def _write(self, raw: str) -> None:
        if self.writer and not self.writer.is_closing():
            self.writer.write(raw.encode("utf-8"))
            self._spawn(self._safe_drain())

    def emit_notification(self, method: str, params: Dict[str, Any]):
        self._write(ProtocolMessage.notification(method, params))

    async def _safe_drain(self):
        try:
            if self.writer and not self.writer.is_closing():
                await self.writer.drain()
        except Exception as e:
            logger.debug("Error draining writer: %s", e)

    # MARK: - Python -> Swift tool execution

    async def request_tool_execution(self, session_id: str, tool_name: str, arguments: Dict[str, Any], call_id: Optional[str] = None) -> Dict[str, Any]:
        if not self.writer or self.writer.is_closing():
            raise RuntimeError("Connection to SwiftCode is closed")

        req_id = f"tool_exec_{uuid.uuid4().hex}"
        loop = asyncio.get_running_loop()
        future: asyncio.Future[Dict[str, Any]] = loop.create_future()
        self.pending_requests[req_id] = future

        params: Dict[str, Any] = {
            "sessionId": session_id,
            "toolName": tool_name,
            "arguments": arguments,
        }
        if call_id:
            params["callId"] = call_id

        self.writer.write(ProtocolMessage.request(req_id, "tool.execute", params).encode("utf-8"))
        await self._safe_drain()

        try:
            return await asyncio.wait_for(future, timeout=self.tool_timeout)
        except asyncio.TimeoutError:
            logger.error("Timed out waiting for SwiftCode tool execution of '%s'", tool_name)
            self._notify_tool_cancel(req_id, session_id, call_id, "timeout")
            return {"success": False, "error": f"Tool execution of '{tool_name}' timed out after {int(self.tool_timeout)}s"}
        except asyncio.CancelledError:
            # Propagate the cancellation to SwiftCode so the native tool stops too.
            self._notify_tool_cancel(req_id, session_id, call_id, "cancelled")
            raise
        finally:
            self.pending_requests.pop(req_id, None)

    async def request_approval(self, session_id: str, tool_name: str, arguments: Dict[str, Any]) -> bool:
        """Asks SwiftCode's approval UI whether an SDK built-in tool call may run."""
        if not self.writer or self.writer.is_closing():
            return False
        req_id = f"tool_approve_{uuid.uuid4().hex}"
        future: asyncio.Future[Dict[str, Any]] = asyncio.get_running_loop().create_future()
        self.pending_requests[req_id] = future
        self.writer.write(ProtocolMessage.request(req_id, "tool.approve", {
            "sessionId": session_id,
            "toolName": tool_name,
            "arguments": arguments,
        }).encode("utf-8"))
        await self._safe_drain()
        try:
            result = await asyncio.wait_for(future, timeout=self.tool_timeout)
        except asyncio.TimeoutError:
            return False
        finally:
            self.pending_requests.pop(req_id, None)
        return bool(result.get("approved", False))

    def _notify_tool_cancel(self, req_id: str, session_id: str, call_id: Optional[str], reason: str) -> None:
        params: Dict[str, Any] = {"requestId": req_id, "sessionId": session_id, "reason": reason}
        if call_id:
            params["callId"] = call_id
        self.emit_notification("tool.cancel", params)

    # MARK: - Dispatch

    def _handle_response(self, message: Dict[str, Any]) -> None:
        req_id = str(message.get("id"))
        future = self.pending_requests.get(req_id)
        if not future or future.done():
            return
        if "error" in message and message["error"]:
            err_obj = message["error"]
            err_msg = err_obj.get("message") if isinstance(err_obj, dict) else str(err_obj)
            future.set_result({"success": False, "error": err_msg})
        else:
            res = message.get("result", {})
            if not isinstance(res, dict):
                res = {"result": str(res), "success": True}
            future.set_result(res)

    async def handle_request(self, message: Dict[str, Any]) -> Optional[str]:
        msg_id = message.get("id")
        method = message.get("method")
        params = message.get("params", {}) or {}

        if not method:
            return ProtocolMessage.error(msg_id, INVALID_REQUEST, "Missing 'method' field in JSON-RPC request")

        logger.debug("Dispatching method: %s, id: %s", method, msg_id)

        try:
            if method == "runtime.start":
                adapter_port = await self.adapter_server.start()
                return ProtocolMessage.success(msg_id, {
                    "status": "ready",
                    "sdkVersion": SDK_VERSION,
                    "engine": "google-antigravity",
                    "adapterPort": adapter_port,
                })

            elif method == "runtime.stop":
                # Respond first, then shut down asynchronously.
                self._spawn(self.request_shutdown("runtime.stop"))
                return ProtocolMessage.success(msg_id, {"status": "stopping"})

            elif method == "runtime.status":
                return ProtocolMessage.success(msg_id, {
                    "status": "running" if self.is_running else "stopped",
                    "activeSessions": len(self.runner.sessions),
                    "sdkVersion": SDK_VERSION,
                })

            elif method == "session.create":
                session_id = params.get("sessionId")
                if not session_id:
                    return ProtocolMessage.error(msg_id, INVALID_PARAMS, "Missing required parameter 'sessionId'")
                result = await self.runner.create_session(session_id, params)
                return ProtocolMessage.success(msg_id, result)

            elif method == "session.resume":
                session_id = params.get("sessionId")
                if not session_id:
                    return ProtocolMessage.error(msg_id, INVALID_PARAMS, "Missing required parameter 'sessionId'")
                if session_id in self.runner.sessions:
                    existing = self.runner.sessions[session_id]
                    return ProtocolMessage.success(msg_id, {
                        "sessionId": session_id,
                        "conversationId": existing.agent.conversation_id,
                        "status": "resumed",
                    })
                result = await self.runner.create_session(session_id, params, resume=True)
                return ProtocolMessage.success(msg_id, result)

            elif method == "session.close":
                session_id = params.get("sessionId")
                if not session_id:
                    return ProtocolMessage.error(msg_id, INVALID_PARAMS, "Missing required parameter 'sessionId'")
                result = await self.runner.close_session(session_id)
                return ProtocolMessage.success(msg_id, result)

            elif method == "message.send":
                session_id = params.get("sessionId")
                content = params.get("content", "")
                attachments = params.get("attachments", [])
                if not session_id:
                    return ProtocolMessage.error(msg_id, INVALID_PARAMS, "Missing required parameter 'sessionId'")
                result = await self.runner.send_message(session_id, content, attachments)
                return ProtocolMessage.success(msg_id, result)

            elif method == "message.cancel":
                session_id = params.get("sessionId")
                if not session_id:
                    return ProtocolMessage.error(msg_id, INVALID_PARAMS, "Missing required parameter 'sessionId'")
                result = await self.runner.cancel_message(session_id)
                return ProtocolMessage.success(msg_id, result)

            elif method == "event.subscribe":
                return ProtocolMessage.success(msg_id, {"subscribed": True})

            else:
                return ProtocolMessage.error(msg_id, METHOD_NOT_FOUND, f"Unknown method '{method}'")

        except SessionNotFoundError as snf:
            return ProtocolMessage.error(msg_id, SESSION_NOT_FOUND, str(snf))
        except Exception as e:
            logger.exception("Error handling method '%s': %s", method, e)
            return ProtocolMessage.error(msg_id, INTERNAL_ERROR, f"Internal bridge error: {str(e)}")

    async def _dispatch_request(self, parsed: Dict[str, Any]) -> None:
        resp = await self.handle_request(parsed)
        if resp:
            self._write(resp)

    async def _handle_connection(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        if self._has_served_client:
            # One client per daemon: reject late connections.
            writer.close()
            return
        self._has_served_client = True
        logger.info("SwiftCode connected to Antigravity bridge")
        self.writer = writer

        adapter_port = await self.adapter_server.start()

        writer.write(ProtocolMessage.notification("runtime.ready", {
            "version": SDK_VERSION,
            "sdk": "google-antigravity",
            "status": "ready",
            "pid": os.getpid(),
            "adapterPort": adapter_port,
        }).encode("utf-8"))
        await writer.drain()

        # Byte-level framing: only decode complete newline-terminated lines so a
        # multi-byte UTF-8 character split across reads never breaks decoding.
        buffer = bytearray()
        while self.is_running:
            try:
                chunk = await reader.read(65536)
                if not chunk:
                    logger.info("Connection closed by peer")
                    break

                buffer.extend(chunk)
                while True:
                    newline = buffer.find(b"\n")
                    if newline < 0:
                        break
                    raw_line = bytes(buffer[:newline])
                    del buffer[: newline + 1]
                    if not raw_line.strip():
                        continue

                    try:
                        parsed = ProtocolMessage.parse(raw_line.decode("utf-8"))
                    except Exception as pe:
                        self._write(ProtocolMessage.error(None, PARSE_ERROR, f"Malformed JSON: {pe}"))
                        continue

                    if "id" in parsed and ("result" in parsed or "error" in parsed) and not parsed.get("method"):
                        # Response to a Python-initiated request (tool.execute).
                        self._handle_response(parsed)
                    else:
                        # Requests run concurrently so a slow session.create never
                        # blocks tool responses or cancellation for other work.
                        self._spawn(self._dispatch_request(parsed))

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.exception("Error in connection loop: %s", e)
                break

        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        self.writer = None
        logger.info("Client connection terminated")
        # The daemon only ever serves the SwiftCode instance that launched it.
        await self.request_shutdown("client disconnected")

    # MARK: - Lifecycle

    async def request_shutdown(self, reason: str) -> None:
        if self.shutdown_event is not None and not self.shutdown_event.is_set():
            logger.info("Shutdown requested: %s", reason)
            self.is_running = False
            self.shutdown_event.set()

    async def _watch_parent(self) -> None:
        if not self.parent_pid:
            return
        while self.is_running:
            await asyncio.sleep(2.0)
            if os.getppid() != self.parent_pid:
                await self.request_shutdown("parent process exited")
                return

    async def _cleanup(self) -> None:
        for future in list(self.pending_requests.values()):
            if not future.done():
                future.set_result({"success": False, "error": "Bridge is shutting down"})
        try:
            await asyncio.wait_for(self.runner.stop_all(), timeout=SHUTDOWN_GRACE_SECONDS)
        except Exception as e:
            logger.warning("Session cleanup did not finish cleanly: %s", e)
        try:
            await asyncio.wait_for(self.adapter_server.stop(), timeout=2.0)
        except Exception as e:
            logger.debug("Adapter stop error: %s", e)
        if self.server is not None:
            self.server.close()

    async def run_socket_server(self):
        if not self.socket_path:
            raise ValueError("Socket path required for socket server")

        self.shutdown_event = asyncio.Event()
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass

        old_umask = os.umask(0o077)
        try:
            self.server = await asyncio.start_unix_server(self._handle_connection, path=self.socket_path)
        finally:
            os.umask(old_umask)
        logger.info("Antigravity Bridge listening on Unix domain socket: %s", self.socket_path)

        self._spawn(self._watch_parent())
        await self.shutdown_event.wait()
        await self._cleanup()

    async def run_stdio_server(self):
        logger.info("Antigravity Bridge running in stdio mode")
        self.shutdown_event = asyncio.Event()
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin)

        w_transport, w_protocol = await loop.connect_write_pipe(asyncio.streams.FlowControlMixin, sys.stdout)
        writer = asyncio.StreamWriter(w_transport, w_protocol, reader, loop)

        self._spawn(self._watch_parent())
        self._spawn(self._handle_connection(reader, writer))
        await self.shutdown_event.wait()
        await self._cleanup()


def _terminate_process_group() -> None:
    """Terminates any harness children left in this process group."""
    try:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        os.killpg(os.getpgrp(), signal.SIGTERM)
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(description="SwiftCode Antigravity Bridge Daemon")
    parser.add_argument("--socket-path", type=str, default=None, help="Path to Unix domain socket")
    parser.add_argument("--stdio", action="store_true", help="Run over stdin/stdout")
    parser.add_argument("--parent-pid", type=int, default=None, help="Exit when this parent process goes away")
    parser.add_argument("--log-level", type=str, default="INFO", help="Logging level")
    parser.add_argument("--version", action="store_true", help="Print version and exit")
    args = parser.parse_args()

    if args.version:
        print(SDK_VERSION)
        sys.exit(0)

    logging.getLogger().setLevel(getattr(logging, args.log_level.upper(), logging.INFO))

    # Lead our own process group so SDK harness children can be torn down together.
    owns_process_group = False
    try:
        os.setpgid(0, 0)
        owns_process_group = True
    except Exception:
        pass

    server = BridgeServer(socket_path=args.socket_path, parent_pid=args.parent_pid)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _on_signal() -> None:
        loop.create_task(server.request_shutdown("signal"))

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _on_signal)
        except NotImplementedError:
            pass

    try:
        if args.socket_path:
            loop.run_until_complete(server.run_socket_server())
        else:
            loop.run_until_complete(server.run_stdio_server())
    except KeyboardInterrupt:
        pass
    finally:
        if args.socket_path and os.path.exists(args.socket_path):
            try:
                os.unlink(args.socket_path)
            except OSError:
                pass
        logging.shutdown()
        if owns_process_group:
            _terminate_process_group()
        os._exit(0)


if __name__ == "__main__":
    main()
