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

from absl.testing import absltest
from google.antigravity.proto import localharness_pb2
from google.antigravity import types
from google.antigravity.connections.local import proto_converters


class ProtoConvertersTest(absltest.TestCase):

  def test_parse_stop_reason(self):
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_MAX_MODEL_CALLS_EXCEEDED
        ),
        types.StopReason.MAX_MODEL_CALLS_EXCEEDED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_MAX_TOOL_CALLS_EXCEEDED
        ),
        types.StopReason.MAX_TOOL_CALLS_EXCEEDED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_MAX_INPUT_TOKENS_EXCEEDED
        ),
        types.StopReason.MAX_INPUT_TOKENS_EXCEEDED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_MAX_OUTPUT_TOKENS_EXCEEDED
        ),
        types.StopReason.MAX_OUTPUT_TOKENS_EXCEEDED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_MAX_TOTAL_TOKENS_EXCEEDED
        ),
        types.StopReason.MAX_TOTAL_TOKENS_EXCEEDED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_QUOTA_EXHAUSTED
        ),
        types.StopReason.QUOTA_EXHAUSTED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(
            localharness_pb2.TrajectoryStateUpdate.STOP_REASON_UNSPECIFIED
        ),
        types.StopReason.UNSPECIFIED,
    )
    self.assertEqual(
        proto_converters._parse_stop_reason(9999),
        types.StopReason.UNSPECIFIED,
    )


if __name__ == "__main__":
  absltest.main()
