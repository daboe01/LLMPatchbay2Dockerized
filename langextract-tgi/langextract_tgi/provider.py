# langextract-tgi/langextract_tgi/provider.py
import os, json, dataclasses
from typing import Any, Iterator, Sequence, Optional, Dict, Type
from urllib.parse import urljoin
import requests
from langextract.core import base_model, exceptions, schema as core_schema, types as core_types
from langextract.providers import registry

@registry.register(r'^tgi::.+$', priority=15)
@dataclasses.dataclass(init=False)
class TgiLanguageModel(base_model.BaseLanguageModel):
    _model: str; _base_url: str; _api_key: Optional[str]; _extra_kwargs: Dict[str, Any]; _chat_template_string: Optional[str]
    @classmethod
    def get_schema_class(cls) -> Optional[Type[core_schema.BaseSchema]]:
        from langextract_tgi.schema import TgiSchema
        return TgiSchema
    def __init__(self, model_id: str, base_url: Optional[str] = None, api_key: Optional[str] = None, chat_template: Optional[str] = None, **kwargs):
        super().__init__()
        if not model_id.startswith('tgi::'): raise ValueError("TgiLanguageModel expects model_id to be prefixed with 'tgi::'")
        self._model = model_id.removeprefix('tgi::')
        self._base_url = (base_url or os.environ.get("TGI_BASE_URL") or "http://inference-api.metal.kn.uniklinik-freiburg.de")
        self._api_key = (api_key or os.environ.get("TGI_API_KEY") or os.environ.get("API_BEARER_TOKEN"))
        self._extra_kwargs = kwargs
        self._chat_template_string = chat_template
    def infer(self, batch_prompts: Sequence[str], **kwargs) -> Iterator[Sequence[core_types.ScoredOutput]]:
        ACCEPTABLE_TGI_PARAMS = {'grammar', 'temperature', 'max_new_tokens', 'top_p', 'top_k', 'repetition_penalty', 'do_sample', 'seed', 'stop', 'watermark', 'details'}
        parameters = {}
        for key, value in self._extra_kwargs.items():
            if key in ACCEPTABLE_TGI_PARAMS: parameters[key] = value
        for key, value in kwargs.items():
            if key in ACCEPTABLE_TGI_PARAMS: parameters[key] = value
        headers = {"Content-Type": "application/json"}
        if self._api_key: headers["Authorization"] = f"Bearer {self._api_key}"
        api_url = urljoin(self._base_url, "generate")
        for prompt in batch_prompts:
            final_prompt = self._chat_template_string.format(prompt=prompt) if self._chat_template_string else prompt
            payload = {"inputs": final_prompt, "parameters": parameters}
            try:
                response = requests.post(api_url, headers=headers, json=payload, timeout=120)
                if not response.ok:
                    print(f"--- SERVER ERROR ({response.status_code}) ---", flush=True)
                    print("Request Payload Sent:", json.dumps(payload, indent=2, default=str), flush=True)
                    print("Server Response:", response.text, flush=True)
                response.raise_for_status()
                generated_text = response.json().get("generated_text", "")
                yield [core_types.ScoredOutput(score=1.0, output=generated_text)]
            except requests.exceptions.RequestException as e: raise exceptions.InferenceRuntimeError(f"TGI request failed: {e}", original=e) from e
            except Exception as e: raise exceptions.InferenceRuntimeError(f"An unexpected error occurred with TGI: {e}", original=e) from e
