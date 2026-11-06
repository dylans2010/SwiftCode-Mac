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

"""Lightweight strategy establishing connection to an external local OpenAI API (Ollama, LM Studio)."""

from typing import Any

from google.antigravity.proto import localharness_pb2
from google.antigravity import types
from google.antigravity.connections.local import local_connection


class LocalOpenAIConnectionStrategy(local_connection.LocalConnectionStrategy):
  """Lightweight strategy establishing connection to an external local OpenAI API (Ollama)."""

  def __init__(
      self,
      *,
      base_url: str,
      model_name: str,
      **kwargs: Any,
  ):
    self._base_url = base_url
    self._model_name = model_name
    super().__init__(**kwargs)

  def _validate_connection(self) -> None:
    """Validates that base_url is specified for OpenAI connection."""
    if not self._base_url:
      raise types.AntigravityValidationError(
          "LocalOpenAIConnectionStrategy requires a non-empty 'base_url'."
      )

  def _build_harness_config(self) -> localharness_pb2.HarnessConfig:
    """Clear Gemini config and populate external Gemma server details."""
    harness_config = super()._build_harness_config()
    model_cfg = localharness_pb2.ModelConfig(
        name=self._model_name,
        types=[localharness_pb2.MODEL_TYPE_TEXT],
        gemma_endpoint=localharness_pb2.GemmaEndpoint(
            base_url=self._base_url,
        ),
    )
    harness_config.models.append(model_cfg)
    return harness_config
