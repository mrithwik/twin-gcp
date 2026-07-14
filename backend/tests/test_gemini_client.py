from unittest.mock import MagicMock

import pytest
from google.genai.errors import APIError

from app.errors import InferenceError
from app.services import gemini_client


def _api_error(code: int) -> APIError:
    return APIError(code=code, response_json={"error": {"status": "ERR", "message": "boom"}})


def _fake_client(responses):
    client = MagicMock()
    client.models.generate_content.side_effect = responses
    return client


def test_retries_transient_error_then_succeeds(monkeypatch):
    success = MagicMock(text="a real reply")
    client = _fake_client([_api_error(503), success])
    monkeypatch.setattr(gemini_client, "_get_client", lambda: client)
    monkeypatch.setattr(gemini_client.time, "sleep", lambda _: None)

    result = gemini_client.generate_reply([], "hi")

    assert result == "a real reply"


def test_gives_up_after_max_attempts(monkeypatch):
    monkeypatch.setattr(
        gemini_client,
        "_get_client",
        lambda: _fake_client([_api_error(503), _api_error(503), _api_error(503)]),
    )
    monkeypatch.setattr(gemini_client.time, "sleep", lambda _: None)

    with pytest.raises(InferenceError):
        gemini_client.generate_reply([], "hi")


def test_does_not_retry_non_transient_error(monkeypatch):
    client = _fake_client([_api_error(404)])
    monkeypatch.setattr(gemini_client, "_get_client", lambda: client)
    monkeypatch.setattr(gemini_client.time, "sleep", lambda _: None)

    with pytest.raises(InferenceError):
        gemini_client.generate_reply([], "hi")

    assert client.models.generate_content.call_count == 1
