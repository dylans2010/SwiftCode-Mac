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

"""Unit tests for schema_utils."""

import unittest
from google.genai import types as genai_types
import pydantic
from google.antigravity.tools import schema_utils


class SchemaUtilsTest(unittest.TestCase):

  def test_normalize_primitive_types(self):
    self.assertEqual(schema_utils.normalize_schema("STRING"), "string")
    self.assertEqual(schema_utils.normalize_schema("INTEGER"), "integer")
    self.assertEqual(schema_utils.normalize_schema("NUMBER"), "number")
    self.assertEqual(schema_utils.normalize_schema("BOOLEAN"), "boolean")
    self.assertEqual(schema_utils.normalize_schema("ARRAY"), "array")
    self.assertEqual(schema_utils.normalize_schema("OBJECT"), "object")
    self.assertEqual(schema_utils.normalize_schema("NULL"), "null")

  def test_normalize_genai_type_enums(self):
    self.assertEqual(
        schema_utils.normalize_schema(genai_types.Type.STRING), "string"
    )
    self.assertEqual(
        schema_utils.normalize_schema(genai_types.Type.OBJECT), "object"
    )
    self.assertEqual(
        schema_utils.normalize_schema(genai_types.Type.INTEGER), "integer"
    )
    self.assertEqual(
        schema_utils.normalize_schema(genai_types.Type.BOOLEAN), "boolean"
    )

  def test_normalize_dict_keywords_and_types(self):
    input_schema = {
        "type": "OBJECT",
        "properties": {
            "name": {"type": "STRING", "description": "User name"},
            "age": {"type": "INTEGER"},
            "scores": {
                "type": "ARRAY",
                "items": {"type": "NUMBER"},
            },
        },
        "required": ["name"],
    }
    expected = {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "User name"},
            "age": {"type": "integer"},
            "scores": {
                "type": "array",
                "items": {"type": "number"},
            },
        },
        "required": ["name"],
    }
    self.assertEqual(schema_utils.normalize_schema(input_schema), expected)

  def test_normalize_combiners_and_keywords(self):
    input_schema = {
        "any_of": [{"type": "STRING"}, {"type": "INTEGER"}],
        "one_of": [{"type": "BOOLEAN"}],
        "all_of": [{"type": "OBJECT"}],
        "additional_properties": {"type": "STRING"},
        "pattern_properties": {"^[a-z]+$": {"type": "INTEGER"}},
        "min_items": 1,
        "max_items": 10,
        "min_length": 2,
        "max_length": 50,
        "min_properties": 1,
        "max_properties": 5,
        "unique_items": True,
        "$defs": {"CustomNode": {"type": "OBJECT"}},
        "definitions": {"LegacyNode": {"type": "ARRAY"}},
        "type": ["STRING", "NULL", genai_types.Type.BOOLEAN],
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertIn("anyOf", normalized)
    self.assertIn("oneOf", normalized)
    self.assertIn("allOf", normalized)
    self.assertIn("additionalProperties", normalized)
    self.assertIn("patternProperties", normalized)
    self.assertIn("minItems", normalized)
    self.assertIn("maxItems", normalized)
    self.assertIn("minLength", normalized)
    self.assertIn("maxLength", normalized)
    self.assertIn("minProperties", normalized)
    self.assertIn("maxProperties", normalized)
    self.assertIn("uniqueItems", normalized)
    self.assertEqual(normalized["anyOf"][0]["type"], "string")
    self.assertEqual(normalized["anyOf"][1]["type"], "integer")
    self.assertEqual(normalized["oneOf"][0]["type"], "boolean")
    self.assertEqual(normalized["allOf"][0]["type"], "object")
    self.assertEqual(normalized["additionalProperties"]["type"], "string")
    self.assertEqual(
        normalized["patternProperties"]["^[a-z]+$"]["type"], "integer"
    )
    self.assertEqual(normalized["$defs"]["CustomNode"]["type"], "object")
    self.assertEqual(normalized["definitions"]["LegacyNode"]["type"], "array")
    self.assertEqual(normalized["type"], ["string", "null", "boolean"])

  def test_preserve_literal_values(self):
    input_schema = {
        "type": "STRING",
        "enum": ["ACTIVE", "INACTIVE", "PENDING"],
        "const": "UPPERCASE_CONST",
        "default": "DEFAULT_VAL",
        "example": "STRING",
        "examples": ["STRING", "OBJECT", "NULL"],
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertEqual(normalized["type"], "string")
    self.assertEqual(normalized["enum"], ["ACTIVE", "INACTIVE", "PENDING"])
    self.assertEqual(normalized["const"], "UPPERCASE_CONST")
    self.assertEqual(normalized["default"], "DEFAULT_VAL")
    self.assertEqual(normalized["example"], "STRING")
    self.assertEqual(normalized["examples"], ["STRING", "OBJECT", "NULL"])

  def test_normalize_extended_keywords_and_subschemas(self):
    input_schema = {
        "multiple_of": 5,
        "exclusive_minimum": 0,
        "exclusive_maximum": 100,
        "prefix_items": [{"type": "STRING"}, {"type": "INTEGER"}],
        "property_names": {"pattern": "^[a-z]+$"},
        "dependent_required": {"credit_card": ["billing_address"]},
        "dependent_schemas": {
            "credit_card": {
                "properties": {
                    "billing_address": {"type": "STRING"},
                },
            },
        },
        "unevaluated_properties": False,
        "unevaluated_items": {"type": "STRING"},
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertEqual(normalized["multipleOf"], 5)
    self.assertEqual(normalized["exclusiveMinimum"], 0)
    self.assertEqual(normalized["exclusiveMaximum"], 100)
    self.assertEqual(normalized["prefixItems"][0]["type"], "string")
    self.assertEqual(normalized["prefixItems"][1]["type"], "integer")
    self.assertEqual(normalized["propertyNames"], {"pattern": "^[a-z]+$"})
    self.assertEqual(
        normalized["dependentRequired"], {"credit_card": ["billing_address"]}
    )
    self.assertEqual(
        normalized["dependentSchemas"]["credit_card"]["properties"][
            "billing_address"
        ]["type"],
        "string",
    )
    self.assertFalse(normalized["unevaluatedProperties"])
    self.assertEqual(normalized["unevaluatedItems"]["type"], "string")

  def test_dependent_required_property_preservation(self):
    input_schema = {
        "type": "OBJECT",
        "properties": {
            "type": {"type": "STRING"},
            "min_items": {"type": "INTEGER"},
            "STATUS": {"type": "STRING"},
        },
        "dependent_required": {
            "type": ["min_items", "properties"],
            "STATUS": ["STRING", "OBJECT", "NULL"],
            "schema_key": ["another_prop"],
        },
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertEqual(normalized["type"], "object")
    self.assertIn("dependentRequired", normalized)
    self.assertEqual(
        normalized["dependentRequired"]["type"], ["min_items", "properties"]
    )
    self.assertEqual(
        normalized["dependentRequired"]["STATUS"], ["STRING", "OBJECT", "NULL"]
    )
    self.assertEqual(
        normalized["dependentRequired"]["schema_key"], ["another_prop"]
    )

  def test_complex_nested_example_preservation(self):
    complex_example = {
        "type": "CUSTOM_RECORD",
        "data": {
            "STRING": "VALUE",
            "flags": ["BOOLEAN", "NULL"],
            "nested": {"format": "INTEGER"},
        },
    }
    input_schema = {
        "type": "OBJECT",
        "example": complex_example,
        "examples": [complex_example, {"code": "ARRAY"}],
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertEqual(normalized["example"], complex_example)
    self.assertEqual(normalized["examples"][0], complex_example)
    self.assertEqual(normalized["examples"][1], {"code": "ARRAY"})

  def test_deeply_nested_subschema_composition(self):
    input_schema = {
        "type": "OBJECT",
        "$defs": {
            "SubRecord": {
                "type": "OBJECT",
                "properties": {"tag": {"type": "STRING"}},
            }
        },
        "properties": {
            "data_tuple": {
                "type": "ARRAY",
                "prefix_items": [
                    genai_types.Type.STRING,
                    {"type": "INTEGER", "multiple_of": 2.5},
                    {"type": "OBJECT", "additional_properties": False},
                ],
            }
        },
        "dependent_schemas": {
            "has_auth": {
                "properties": {
                    "token": {"type": genai_types.Type.STRING},
                    "scope": {"type": "STRING", "enum": ["READ", "WRITE"]},
                },
                "dependent_required": {"token": ["scope"]},
            }
        },
    }
    normalized = schema_utils.normalize_schema(input_schema)
    self.assertEqual(normalized["$defs"]["SubRecord"]["type"], "object")
    self.assertEqual(
        normalized["$defs"]["SubRecord"]["properties"]["tag"]["type"], "string"
    )
    prefix_items = normalized["properties"]["data_tuple"]["prefixItems"]
    self.assertEqual(prefix_items[0], "string")
    self.assertEqual(prefix_items[1]["type"], "integer")
    self.assertEqual(prefix_items[1]["multipleOf"], 2.5)
    self.assertEqual(prefix_items[2]["type"], "object")
    self.assertFalse(prefix_items[2]["additionalProperties"])

    auth_schema = normalized["dependentSchemas"]["has_auth"]
    self.assertEqual(auth_schema["properties"]["token"]["type"], "string")
    self.assertEqual(auth_schema["properties"]["scope"]["type"], "string")
    self.assertEqual(
        auth_schema["properties"]["scope"]["enum"], ["READ", "WRITE"]
    )
    self.assertEqual(auth_schema["dependentRequired"], {"token": ["scope"]})

  def test_pydantic_v2_model_schema_normalization(self):
    class TestPayload(pydantic.BaseModel):
      name: str = pydantic.Field(
          min_length=2, max_length=50, examples=["sample_name"]
      )
      count: int = pydantic.Field(multiple_of=5, gt=0, lt=100)
      tags: list[str] = pydantic.Field(min_length=1, max_length=10)

    raw_schema = TestPayload.model_json_schema()
    normalized = schema_utils.normalize_schema(raw_schema)
    self.assertEqual(normalized["type"], "object")
    self.assertIn("properties", normalized)
    count_prop = normalized["properties"]["count"]
    self.assertEqual(count_prop["multipleOf"], 5)
    self.assertEqual(count_prop["exclusiveMinimum"], 0)
    self.assertEqual(count_prop["exclusiveMaximum"], 100)
    self.assertEqual(
        normalized["properties"]["name"]["examples"], ["sample_name"]
    )

  def test_empty_and_edge_case_schemas(self):
    self.assertEqual(schema_utils.normalize_schema({}), {})
    self.assertEqual(schema_utils.normalize_schema([]), [])
    self.assertEqual(schema_utils.normalize_schema({"type": []}), {"type": []})
    self.assertEqual(
        schema_utils.normalize_schema(
            {"additional_properties": True, "unevaluated_properties": False}
        ),
        {"additionalProperties": True, "unevaluatedProperties": False},
    )

  def test_passthrough_non_schema_values(self):
    self.assertEqual(schema_utils.normalize_schema(42), 42)
    self.assertEqual(schema_utils.normalize_schema(3.14), 3.14)
    self.assertTrue(schema_utils.normalize_schema(True))
    self.assertIsNone(schema_utils.normalize_schema(None))
    self.assertEqual(
        schema_utils.normalize_schema("custom_literal"), "custom_literal"
    )


if __name__ == "__main__":
  unittest.main()
