from fastapi import APIRouter

from app.config import settings

router = APIRouter()


@router.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "environment": settings.environment,
        "memory_backend": settings.memory_backend,
    }
