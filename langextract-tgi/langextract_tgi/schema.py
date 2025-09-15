# langextract-tgi/langextract_tgi/schema.py

from __future__ import annotations
from typing import Any, Iterable

from langextract.core import schema
from langextract import data as lx_data

# This line will prove the correct file is being loaded

class TgiSchema(schema.BaseSchema):
    """
    Schema support for TGI that provides a raw JSON schema object,
    as required by the target TGI endpoint.
    """

    def __init__(self, schema_dict: dict[str, Any]):
        self._schema_dict = schema_dict

    @property
    def schema_dict(self) -> dict[str, Any]:
        return self._schema_dict

    @classmethod
    def from_examples(
        cls,
        examples_data: Iterable[lx_data.ExampleData],
        attribute_suffix: str = '_attributes',
    ) -> TgiSchema:
        """
        Builds a detailed JSON schema from the provided langextract examples.
        """
        properties = {}
        required = set()

        for example in examples_data:
            for extraction in example.extractions:
                class_name = extraction.extraction_class
                properties[class_name] = {"type": "string"}
                required.add(class_name)

                if extraction.attributes:
                    attr_name = f"{class_name}{attribute_suffix}"
                    attr_properties = {
                        key: {"type": "string"}
                        for key in extraction.attributes.keys()
                    }
                    properties[attr_name] = {
                        "type": "object",
                        "properties": attr_properties,
                    }
                    required.add(attr_name)

        final_schema = {
            "type": "object",
            "properties": {
                "extractions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": properties,
                        "required": sorted(list(required)),
                    },
                }
            },
            "required": ["extractions"],
        }
        return cls(final_schema)

    def to_provider_config(self) -> dict[str, Any]:
        """
        Converts the generated schema into the TGI-specific `grammar` parameter
        with the type 'json', as required by the server.
        """
        return {
            "grammar": {
                "type": "json",
                "value": self.schema_dict,
            }
        }

    @property
    def supports_strict_mode(self) -> bool:
        """Returns True as TGI's grammar enforces a valid structure."""
        return True
