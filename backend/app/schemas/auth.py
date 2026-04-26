from pydantic import BaseModel, Field


class StudentRedeemRequest(BaseModel):
    """Запрос на активацию одноразового кода ученика."""
    code: str = Field(..., min_length=1, max_length=20, description="Одноразовый код доступа")


class StudentRedeemResponse(BaseModel):
    """Ответ на успешную активацию кода — анонимный JWT без user_id."""
    access_token: str
    token_type: str = "bearer"
    voting_session_id: int
    class_name: str  # например "10В"


class AdminLoginResponse(BaseModel):
    """Ответ на успешный логин администратора."""
    access_token: str
    token_type: str = "bearer"
