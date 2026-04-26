"""
Роутер голосования.

GET  /votes/active  — получить активную анкету (требует student JWT)
POST /votes         — отправить голос (требует student JWT, инвалидирует токен)
"""

import json

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.deps import get_current_student, get_db
from app.moderation import has_stop_word
from app.models import Class, UsedToken, Vote, VoteAnswer, VotingSession
from app.schemas.votes import (
    QUESTIONNAIRE_V1,
    ActiveVotingSessionResponse,
    VoteSubmitRequest,
    VoteSubmitResponse,
)

router = APIRouter(prefix="/votes", tags=["votes"])


@router.get("/active", response_model=ActiveVotingSessionResponse)
def get_active_vote(
    token_data: dict = Depends(get_current_student),
    db: Session = Depends(get_db),
):
    """
    Вернуть информацию об активной сессии голосования и структуру анкеты.

    class_id и voting_session_id берутся из JWT — клиент не передаёт их явно.
    """
    class_id = token_data["class_id"]
    voting_session_id = token_data["voting_session_id"]

    voting_session = db.get(VotingSession, voting_session_id)
    if voting_session is None or not voting_session.is_open:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "SESSION_CLOSED",
                "message": "Сессия голосования закрыта или не существует",
            },
        )

    school_class = db.get(Class, class_id)

    return ActiveVotingSessionResponse(
        voting_session_id=voting_session.id,
        quarter=voting_session.quarter,
        year=voting_session.year,
        class_name=school_class.name,
        questionnaire=QUESTIONNAIRE_V1,
    )


@router.post("", response_model=VoteSubmitResponse)
def submit_vote(
    payload: VoteSubmitRequest,
    token_data: dict = Depends(get_current_student),
    db: Session = Depends(get_db),
):
    """
    Принять голос ученика.

    ИНВАРИАНТЫ АНОНИМНОСТИ (не нарушать!):
    1. class_id берётся ТОЛЬКО из токена — никогда из тела запроса.
       Даже если клиент пришлёт «чужой» class_id, голос запишется
       для того класса, на который выдан токен.
    2. Vote создаётся БЕЗ ссылки на AccessCode — связь между кодом
       и голосом не существует ни в одном поле БД.
    3. UsedToken создаётся в той же транзакции, что и Vote —
       либо оба запишутся, либо ни один (атомарность).
    """
    # Все данные о принадлежности — только из токена
    class_id = token_data["class_id"]
    voting_session_id = token_data["voting_session_id"]
    jti = token_data["jti"]

    # Проверяем что сессия ещё открыта
    voting_session = db.get(VotingSession, voting_session_id)
    if voting_session is None or not voting_session.is_open:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "SESSION_CLOSED", "message": "Сессия голосования уже закрыта"},
        )

    answers = payload.answers

    # Модерация блока 5: при нахождении стоп-слова очищаем текст,
    # но голос сохраняем — отказа нет, ученик не узнаёт о фильтрации
    free_text = answers.free_text
    if free_text and has_stop_word(free_text):
        free_text = None

    # Создаём голос — БЕЗ ССЫЛКИ на AccessCode, БЕЗ user_id
    vote = Vote(class_id=class_id, voting_session_id=voting_session_id)
    db.add(vote)
    db.flush()  # получаем vote.id не делая полный коммит

    # Сохраняем ответы по блокам (один VoteAnswer на блок)
    answer_blocks = [
        ("heavy_subjects", answers.heavy_subjects.model_dump()),
        ("exams",          answers.exams.model_dump()),
        ("free_periods",   answers.free_periods.model_dump()),
        ("pe",             answers.pe.model_dump()),
        ("free_text",      {"text": free_text}),
    ]
    for question_key, data in answer_blocks:
        db.add(VoteAnswer(
            vote_id=vote.id,
            question_key=question_key,
            answer_json=json.dumps(data, ensure_ascii=False),
        ))

    # Инвалидируем токен — в той же транзакции, что и голос
    db.add(UsedToken(jti=jti))

    db.commit()

    return VoteSubmitResponse()
