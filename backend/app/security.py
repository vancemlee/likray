"""
Модуль безопасности: JWT-токены и хеширование паролей.

Два типа токенов:
  1. AdminToken  — для администраторов (содержит admin_id, role).
  2. AnonStudentToken — для учеников (содержит class_id + voting_session_id + jti).

ВАЖНО: student-токен намеренно НЕ содержит user_id или code_id.
Токен удостоверяет только принадлежность к классу — не личность ученика.
jti (JWT ID) уникален для каждой выдачи и используется для инвалидации
токена после голосования (защита от двойного голосования).
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
from jose import JWTError, jwt

from app.config import settings


# ---------------------------------------------------------------------------
# Хеширование паролей
# ---------------------------------------------------------------------------
# Используем bcrypt напрямую (не через passlib) — passlib не обновлялся
# с 2020 года и несовместим с bcrypt>=4.0 из-за удалённого __about__.
# bcrypt сам по себе — проверенная временем библиотека, API простой.
# Лимит bcrypt: пароль не может быть длиннее 72 байт. Обрезаем явно.

_BCRYPT_MAX_LEN = 72


def hash_password(password: str) -> str:
    """Вернуть bcrypt-хеш пароля в виде строки."""
    pwd_bytes = password.encode("utf-8")[:_BCRYPT_MAX_LEN]
    return bcrypt.hashpw(pwd_bytes, bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Проверить пароль против bcrypt-хеша. True если совпадает."""
    pwd_bytes = plain_password.encode("utf-8")[:_BCRYPT_MAX_LEN]
    hash_bytes = hashed_password.encode("utf-8")
    try:
        return bcrypt.checkpw(pwd_bytes, hash_bytes)
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# Создание токенов
# ---------------------------------------------------------------------------

def create_admin_token(admin_id: int, role: str, school_id: int) -> str:
    """
    Создать JWT-токен для администратора.

    Payload: sub=admin_id, role, school_id, type="admin", exp, jti.
    school_id нужен для фильтрации данных по школе в фазе 3.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "sub": str(admin_id),
        "role": role,
        "school_id": school_id,
        "type": "admin",
        "exp": expire,
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


def create_anon_student_token(class_id: int, voting_session_id: int) -> str:
    """
    Создать анонимный JWT-токен для ученика.

    Payload: class_id, voting_session_id, type="student", exp, jti.

    ВАЖНО: в токене нет user_id и нет code_id.
    Это намеренно — даже перехватив токен, невозможно установить
    личность ученика или связать его с конкретным кодом доступа.
    jti используется для однократного использования токена:
    после успешного голосования jti вносится в revoked_tokens.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES
    )
    payload = {
        "class_id": class_id,
        "voting_session_id": voting_session_id,
        "type": "student",
        "exp": expire,
        "jti": str(uuid.uuid4()),
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)


# ---------------------------------------------------------------------------
# Проверка токенов
# ---------------------------------------------------------------------------

def verify_admin_token(token: str) -> Optional[dict]:
    """
    Декодировать и проверить admin-токен.
    Возвращает payload-словарь или None при невалидном/истёкшем токене.
    """
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        if payload.get("type") != "admin":
            return None
        return payload
    except JWTError:
        return None


def verify_student_token(token: str) -> Optional[dict]:
    """
    Декодировать и проверить student-токен.
    Возвращает payload-словарь или None при невалидном/истёкшем токене.
    """
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
        )
        if payload.get("type") != "student":
            return None
        return payload
    except JWTError:
        return None
