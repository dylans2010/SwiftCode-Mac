# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Utilities for converting between LocalHarness wire protobufs and SDK types."""

from google.antigravity.proto import localharness_pb2
from google.antigravity import types

_STOP_REASON_MAP: dict[int, types.StopReason] = {
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_MAX_MODEL_CALLS_EXCEEDED: (
        types.StopReason.MAX_MODEL_CALLS_EXCEEDED
    ),
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_MAX_TOOL_CALLS_EXCEEDED: (
        types.StopReason.MAX_TOOL_CALLS_EXCEEDED
    ),
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_MAX_INPUT_TOKENS_EXCEEDED: (
        types.StopReason.MAX_INPUT_TOKENS_EXCEEDED
    ),
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_MAX_OUTPUT_TOKENS_EXCEEDED: (
        types.StopReason.MAX_OUTPUT_TOKENS_EXCEEDED
    ),
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_MAX_TOTAL_TOKENS_EXCEEDED: (
        types.StopReason.MAX_TOTAL_TOKENS_EXCEEDED
    ),
    localharness_pb2.TrajectoryStateUpdate.StopReason.STOP_REASON_QUOTA_EXHAUSTED: (
        types.StopReason.QUOTA_EXHAUSTED
    ),
}


def _parse_stop_reason(
    reason: localharness_pb2.TrajectoryStateUpdate.StopReason | int,
) -> types.StopReason:
  """Extracts StopReason SDK enum from a proto enum or integer."""
  return _STOP_REASON_MAP.get(reason, types.StopReason.UNSPECIFIED)
