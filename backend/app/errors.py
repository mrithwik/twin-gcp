"""
Custom exception hierarchy.

Every application error extends AppError, which carries an HTTP status code and
a machine-readable error code. main.py registers a single exception handler for
AppError so every route returns the same JSON error shape regardless of which
error was raised: {"error": {"code": "...", "message": "..."}}.
"""


class AppError(Exception):
    def __init__(self, message: str, status_code: int = 500, error_code: str = "INTERNAL_ERROR"):
        self.message = message
        self.status_code = status_code
        self.error_code = error_code
        super().__init__(self.message)


class ValidationError(AppError):
    def __init__(self, message: str = "Invalid request data"):
        super().__init__(message=message, status_code=422, error_code="VALIDATION_ERROR")


class InferenceError(AppError):
    """Raised when the Gemini API call fails."""

    def __init__(self, message: str = "Inference failed"):
        super().__init__(message=message, status_code=502, error_code="INFERENCE_ERROR")


class ConversationNotFoundError(AppError):
    def __init__(self, session_id: str):
        self.session_id = session_id
        super().__init__(
            message=f"Conversation not found: {session_id}",
            status_code=404,
            error_code="CONVERSATION_NOT_FOUND",
        )
