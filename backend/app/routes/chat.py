import uuid
from datetime import datetime

from fastapi import APIRouter

from app.errors import ConversationNotFoundError
from app.schemas import ChatRequest, ChatResponse, ConversationResponse
from app.services import memory_store
from app.services.gemini_client import generate_reply

router = APIRouter()


@router.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    session_id = request.session_id or str(uuid.uuid4())
    conversation = memory_store.load_conversation(session_id)

    assistant_response = generate_reply(conversation, request.message)

    conversation.append(
        {"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()}
    )
    conversation.append(
        {"role": "assistant", "content": assistant_response, "timestamp": datetime.now().isoformat()}
    )
    memory_store.save_conversation(session_id, conversation)

    return ChatResponse(response=assistant_response, session_id=session_id)


@router.get("/conversation/{session_id}", response_model=ConversationResponse)
async def get_conversation(session_id: str):
    conversation = memory_store.load_conversation(session_id)
    if not conversation:
        raise ConversationNotFoundError(session_id)
    return ConversationResponse(session_id=session_id, messages=conversation)
