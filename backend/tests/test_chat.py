def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_chat_round_trip(client):
    response = client.post("/chat", json={"message": "Hello, who are you?"})
    assert response.status_code == 200
    body = response.json()
    assert body["response"] == "This is a mocked Gemini reply."
    assert body["session_id"]


def test_chat_persists_conversation(client):
    first = client.post("/chat", json={"message": "Hi"}).json()
    session_id = first["session_id"]

    client.post("/chat", json={"message": "Follow up", "session_id": session_id})

    conversation = client.get(f"/conversation/{session_id}").json()
    assert conversation["session_id"] == session_id
    assert len(conversation["messages"]) == 4  # 2 user + 2 assistant messages


def test_conversation_not_found(client):
    response = client.get("/conversation/does-not-exist")
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "CONVERSATION_NOT_FOUND"
