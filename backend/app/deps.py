"""
FastAPI-зависимости (Depends) для инъекции в роутеры.
"""

from typing import Generator

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db import SessionLocal
from app.security import verify_admin_token, verify_student_token

bearer_scheme = HTTPBearer()


def get_db() -> Generator[Session, None, None]:
    """Зависимость: открыть сессию БД и гарантированно закрыть её после запроса."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> dict:
    """Проверить admin JWT и вернуть payload. Бросает 401 если токен невалиден."""
    payload = verify_admin_token(credentials.credentials)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "INVALID_TOKEN",
                "message": "Невалидный или истёкший токен администратора",
            },
        )
    return payload


def get_current_student(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> dict:
    """
    Проверить student JWT и вернуть payload.

    Помимо стандартной JWT-валидации, проверяем jti в таблице used_tokens —
    студент не может использовать один токен дважды (голосовать повторно).
    """
    # Импорт здесь, чтобы избежать циклического импорта на уровне модуля
    from app.models import UsedToken

    payload = verify_student_token(credentials.credentials)
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "INVALID_TOKEN",
                "message": "Невалидный или истёкший токен ученика",
            },
        )

    # Проверяем что токен ещё не был использован для голосования
    jti = payload.get("jti")
    if jti and db.get(UsedToken, jti) is not None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "TOKEN_ALREADY_USED",
                "message": "Этот токен уже был использован для голосования",
            },
        )

    return payload
