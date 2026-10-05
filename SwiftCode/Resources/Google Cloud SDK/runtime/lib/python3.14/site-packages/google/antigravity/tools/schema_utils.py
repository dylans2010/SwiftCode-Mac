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

"""Utilities for JSON Schema normalization and conversion."""

from typing import Any
from google.genai import types as genai_types

_SCHEMA_KEYWORD_MAP: dict[str, str] = {
    "any_of": "anyOf",
    "one_of": "oneOf",
    "all_of": "allOf",
    "additional_properties": "additionalProperties",
    "pattern_properties": "patternProperties",
    "min_items": "minItems",
    "max_items": "maxItems",
    "min_length": "minLength",
    "max_length": "maxLength",
    "min_properties": "minProperties",
    "max_properties": "maxProperties",
    "unique_items": "uniqueItems",
    "multiple_of": "multipleOf",
    "exclusive_minimum": "exclusiveMinimum",
    "exclusive_maximum": "exclusiveMaximum",
    "prefix_items": "prefixItems",
    "property_names": "propertyNames",
    "dependent_required": "dependentRequired",
    "dependent_schemas": "dependentSchemas",
    "unevaluated_properties": "unevaluatedProperties",
    "unevaluated_items": "unevaluatedItems",
}

_UPPERCASE_TYPES: frozenset[str] = frozenset((
    "STRING",
    "NUMBER",
    "INTEGER",
    "BOOLEAN",
    "ARRAY",
    "OBJECT",
    "NULL",
))

# Schema keywords whose dictionary values are named subschemas:
_SUBSCHEMA_DICT_KEYWORDS: frozenset[str] = frozenset((
    "properties",
    "patternProperties",
    "$defs",
    "definitions",
    "dependentSchemas",
))

# Keywords whose values are literal sample data, values, or property lists:
_LITERAL_KEYWORDS: frozenset[str] = frozenset((
    "enum",
    "const",
    "default",
    "example",
    "examples",
    "dependentRequired",
))


def normalize_schema(schema: Any) -> Any:
  """Recursively normalizes JSON Schema dictionaries for universal model compatibility.

  Converts uppercase GenAI/Protobuf type names to lowercase strings, converts
  snake_case JSON Schema keywords to camelCase (e.g. `any_of` -> `anyOf`,
  `multiple_of` -> `multipleOf`), and preserves literal values (`enum`, `const`,
  `default`, `example`, `examples`, `dependentRequired`).

  Args:
      schema: The raw schema dictionary, list, string, or GenAI Type enum.

  Returns:
      A normalized JSON Schema object compatible with strict OpenAPI validators.
  """
  if isinstance(schema, dict):
    normalized = {}
    for k, v in schema.items():
      k = _SCHEMA_KEYWORD_MAP.get(k, k)

      if k == "type":
        if isinstance(v, str):
          normalized[k] = v.lower()
        elif isinstance(v, (list, tuple)):
          normalized[k] = [normalize_schema(item) for item in v]
        elif isinstance(v, genai_types.Type):
          normalized[k] = v.value.lower()
        else:
          normalized[k] = normalize_schema(v)
      elif k in _SUBSCHEMA_DICT_KEYWORDS:
        if isinstance(v, dict):
          normalized[k] = {pk: normalize_schema(pv) for pk, pv in v.items()}
        else:
          normalized[k] = normalize_schema(v)
      elif k in _LITERAL_KEYWORDS:
        normalized[k] = v
      else:
        normalized[k] = normalize_schema(v)
    return normalized
  elif isinstance(schema, (list, tuple)):
    return [normalize_schema(item) for item in schema]
  elif isinstance(schema, genai_types.Type):
    return schema.value.lower()
  elif isinstance(schema, str) and schema in _UPPERCASE_TYPES:
    return schema.lower()
  return schema
