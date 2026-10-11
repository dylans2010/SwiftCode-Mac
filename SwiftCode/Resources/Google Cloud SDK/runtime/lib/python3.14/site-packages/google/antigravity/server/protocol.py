"""
JSON-RPC 2.0 protocol specifications and message framing for the SwiftCode <-> Antigravity bridge.
"""

from __future__ import annotations
import json
from typing import Any, Dict, Optional, Union

# JSON-RPC Standard Error Codes
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603

# Application-Specific Error Codes
SESSION_NOT_FOUND = -32001
SESSION_ALREADY_EXISTS = -32002
RUNTIME_NOT_READY = -32003
TOOL_EXECUTION_FAILED = -32004
CANCELLATION_FAILED = -32005
AUTHENTICATION_FAILED = -32006


class ProtocolMessage:
    @staticmethod
    def request(id_: Union[str, int], method: str, params: Optional[Dict[str, Any]] = None) -> str:
        payload = {
            "jsonrpc": "2.0",
            "id": id_,
            "method": method,
            "params": params or {},
        }
        return json.dumps(payload) + "\n"

    @staticmethod
    def success(id_: Union[str, int, None], result: Any) -> str:
        payload = {
            "jsonrpc": "2.0",
            "id": id_,
            "result": result,
        }
        return json.dumps(payload) + "\n"

    @staticmethod
    def error(
        id_: Union[str, int, None],
        code: int,
        message: str,
        data: Optional[Any] = None,
    ) -> str:
        err_payload: Dict[str, Any] = {"code": code, "message": message}
        if data is not None:
            err_payload["data"] = data
        payload = {
            "jsonrpc": "2.0",
            "id": id_,
            "error": err_payload,
        }
        return json.dumps(payload) + "\n"

    @staticmethod
    def notification(method: str, params: Optional[Dict[str, Any]] = None) -> str:
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params or {},
        }
        return json.dumps(payload) + "\n"

    @staticmethod
    def parse(raw_line: str) -> Dict[str, Any]:
        line = raw_line.strip()
        if not line:
            raise ValueError("Empty message line")
        data = json.loads(line)
        if not isinstance(data, dict):
            raise ValueError("Message must be a JSON object")
        return data
