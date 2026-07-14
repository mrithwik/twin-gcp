import shutil
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import settings


@pytest.fixture
def client(monkeypatch):
    tmp_dir = tempfile.mkdtemp()
    monkeypatch.setattr(settings, "memory_backend", "local")
    monkeypatch.setattr(settings, "memory_dir", tmp_dir)

    monkeypatch.setattr(
        "app.routes.chat.generate_reply",
        lambda conversation, user_message: "This is a mocked Gemini reply.",
    )

    from app.main import app

    with TestClient(app) as test_client:
        yield test_client

    shutil.rmtree(tmp_dir, ignore_errors=True)
