"""
Gemini inference wrapper. Replaces the AWS version's call_bedrock().

Keeps the google-genai SDK usage in one place so routes/services never talk to
the SDK directly — if the model or provider ever changes again, only this file
needs to change.
"""

import time

from google import genai
from google.genai import types
from google.genai.errors import APIError

from app.config import settings
from app.errors import InferenceError
from app.prompt import build_system_prompt

_client: genai.Client | None = None

# Gemini occasionally returns transient capacity/rate errors (503, 429, 500)
# that succeed on a plain retry — this is normal for any hosted LLM API, not
# specific to Gemini or its free tier. Non-transient errors (400 bad request,
# 404 unknown model, invalid key) are not retried since retrying can't fix them.
_RETRYABLE_CODES = {429, 500, 503}
_MAX_ATTEMPTS = 3
_BACKOFF_SECONDS = 2


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=settings.gemini_api_key)
    return _client


def generate_reply(conversation: list[dict], user_message: str) -> str:
    """Call Gemini with conversation history + the new user message, return the reply text."""

    contents = []
    for msg in conversation[-50:]:
        role = "model" if msg["role"] == "assistant" else "user"
        contents.append(types.Content(role=role, parts=[types.Part(text=msg["content"])]))
    contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))

    response = None
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        try:
            response = _get_client().models.generate_content(
                model=settings.gemini_model_id,
                contents=contents,
                config=types.GenerateContentConfig(
                    system_instruction=build_system_prompt(),
                    temperature=0.7,
                    top_p=0.9,
                    max_output_tokens=2000,
                ),
            )
            break
        except APIError as exc:
            if exc.code not in _RETRYABLE_CODES or attempt == _MAX_ATTEMPTS:
                raise InferenceError(f"Gemini error: {exc}") from exc
            time.sleep(_BACKOFF_SECONDS * attempt)

    if not response.text:
        raise InferenceError("Gemini returned an empty response")

    return response.text
