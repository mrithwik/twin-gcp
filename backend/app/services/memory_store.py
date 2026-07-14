"""
Conversation history persistence.

Replaces the AWS version's S3 get/put-JSON pattern. Two backends, selected by
Settings.memory_backend:
  - "local": JSON files on disk under settings.memory_dir (used for local dev).
  - "firestore": one document per session_id in the "conversations" collection
    (used on Cloud Run, where local disk doesn't persist across instances).
"""

import json
from pathlib import Path

from app.config import settings

_firestore_client = None


def _get_firestore_client():
    global _firestore_client
    if _firestore_client is None:
        from google.cloud import firestore

        _firestore_client = firestore.Client(project=settings.gcp_project or None)
    return _firestore_client


def load_conversation(session_id: str) -> list[dict]:
    if settings.memory_backend == "firestore":
        doc = _get_firestore_client().collection("conversations").document(session_id).get()
        return doc.to_dict().get("messages", []) if doc.exists else []

    file_path = Path(settings.memory_dir) / f"{session_id}.json"
    if file_path.exists():
        return json.loads(file_path.read_text(encoding="utf-8"))
    return []


def save_conversation(session_id: str, messages: list[dict]) -> None:
    if settings.memory_backend == "firestore":
        _get_firestore_client().collection("conversations").document(session_id).set(
            {"messages": messages}
        )
        return

    memory_dir = Path(settings.memory_dir)
    memory_dir.mkdir(parents=True, exist_ok=True)
    file_path = memory_dir / f"{session_id}.json"
    file_path.write_text(json.dumps(messages, indent=2), encoding="utf-8")
