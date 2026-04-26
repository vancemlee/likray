"""
Роутер аутентификации.

POST /auth/student/redeem  — активация одноразового кода ученика
POST /auth/admin/login     — логин администратора (OAuth2 password flow)
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.deps import get_db
from app.models import AccessCode, Admin, Class, VotingSession
from app.schemas.auth import AdminLoginResponse, StudentRedeemRequest, StudentRedeemResponse
from app.security import create_admin_token, create_anon_student_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/student/redeem", response_model=StudentRedeemResponse)
def student_redeem(payload: StudentRedeemRequest, db: Session = Depends(get_db)):
    """
    Активировать одноразовый код ученика и получить анонимный JWT.

    Порядок намеренно двухэтапный (инвариант анонимности):

    ШАГ 1 — найти и заблокировать код: транзакция завершается коммитом.
             После этого код помечен как использованный — необратимо.

    ШАГ 2 — сгенерировать JWT: происходит ПОСЛЕ первого коммита.
             JWT — это чистое вычисление, не обращение к БД.

    Почему так важно? Если бы оба действия были в одной транзакции,
    в WAL-журнале SQLite находились бы рядом: запись «код N помечен» и
    любые данные о сессии. Разделяя их, мы устраняем даже теоретическую
    возможность временной корреляции между кодом и будущим голосом.
    """
    # Ищем код в БД
    code_record = (
        db.query(AccessCode).filter(AccessCode.code == payload.code).first()
    )
    if code_record is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "CODE_NOT_FOUND", "message": "Код не найден"},
        )

    if code_record.is_used:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "CODE_ALREADY_USED", "message": "Код уже был использован"},
        )

    # Ищем активную сессию голосования для школы этого класса
    school_class = db.get(Class, code_record.class_id)
    voting_session = (
        db.query(VotingSession)
        .filter(
            VotingSession.school_id == school_class.school_id,
            VotingSession.is_open == True,  # noqa: E712
        )
        .first()
    )
    if voting_session is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "NO_ACTIVE_SESSION",
                "message": "Нет активной сессии голосования для вашей школы",
            },
        )

    # ШАГ 1: помечаем код использованным — первый коммит
    code_record.is_used = True
    code_record.used_at = datetime.now(timezone.utc)
    db.commit()

    # ШАГ 2: генерируем JWT — ПОСЛЕ первого коммита, вне транзакции
    # Токен содержит только class_id и voting_session_id — никакого user_id!
    token = create_anon_student_token(
        class_id=code_record.class_id,
        voting_session_id=voting_session.id,
    )

    return StudentRedeemResponse(
        access_token=token,
        voting_session_id=voting_session.id,
        class_name=school_class.name,
    )


@router.post("/admin/login", response_model=AdminLoginResponse)
def admin_login(
    form: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    """Логин администратора (OAuth2 password flow, form data)."""
    admin = db.query(Admin).filter(Admin.username == form.username).first()
    if admin is None or not verify_password(form.password, admin.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "INVALID_CREDENTIALS",
                "message": "Неверный логин или пароль",
            },
        )

    token = create_admin_token(
        admin_id=admin.id,
        role=admin.role.value,
        school_id=admin.school_id,
    )
    return AdminLoginResponse(access_token=token)
