"""
Тесты голосования:
  - GET /votes/active (структура анкеты)
  - POST /votes (отправка, replay, class_id из токена)
"""

from app.models import Vote
from app.security import create_anon_student_token

# ---------------------------------------------------------------------------
# Валидный набор ответов на анкету v1 (используется во всех тестах)
# ---------------------------------------------------------------------------

VALID_ANSWERS = {
    "answers": {
        "heavy_subjects": {
            "math": "lessons_1_2",
            "physics": "lessons_3_4",
            "chemistry": "any",
            "cs": "lessons_1_2",
            "foreign_language": "any",
        },
        "exams": {
            "max_per_day": 2,
            "no_mon_fri": True,
        },
        "free_periods": {
            "choice": "max_1",
            "prefer_long": False,
        },
        "pe": {
            "preference": "last",
        },
        "free_text": "Хотелось бы математику не на последнем уроке",
    }
}


# ---------------------------------------------------------------------------
# GET /votes/active
# ---------------------------------------------------------------------------

def test_votes_active_requires_student_token(client):
    """Без токена → 401 (HTTPBearer отсутствует — не авторизован)."""
    response = client.get("/api/v1/votes/active")
    # Современные версии FastAPI/Starlette отвечают 401 Unauthorized,
    # когда заголовок Authorization не передан (раньше был 403 Forbidden).
    # 401 семантически точнее: «нет учётных данных» ≠ «запрещено».
    assert response.status_code in (401, 403)


def test_votes_active_returns_questionnaire(client, school_class, voting_session):
    """Успешный запрос → структура анкеты v1 с корректными метаданными."""
    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    response = client.get(
        "/api/v1/votes/active",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["voting_session_id"] == voting_session.id
    assert data["quarter"] == voting_session.quarter
    assert data["class_name"] == "10В"
    assert data["questionnaire"]["version"] == "v1"
    assert len(data["questionnaire"]["blocks"]) == 5


# ---------------------------------------------------------------------------
# POST /votes
# ---------------------------------------------------------------------------

def test_votes_submit_success(client, school_class, voting_session):
    """Полный цикл: получаем токен → отправляем голос → {"status": "accepted"}."""
    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    response = client.post(
        "/api/v1/votes",
        json=VALID_ANSWERS,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    assert response.json() == {"status": "accepted"}


def test_votes_submit_token_replay(client, school_class, voting_session):
    """Повторная отправка тем же токеном → 401 (TOKEN_ALREADY_USED)."""
    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    headers = {"Authorization": f"Bearer {token}"}

    first = client.post("/api/v1/votes", json=VALID_ANSWERS, headers=headers)
    assert first.status_code == 200

    # Тот же токен — должен быть отклонён
    second = client.post("/api/v1/votes", json=VALID_ANSWERS, headers=headers)
    assert second.status_code == 401
    assert second.json()["detail"]["code"] == "TOKEN_ALREADY_USED"


def test_votes_submit_invalid_text_length(client, school_class, voting_session):
    """Свободный текст длиннее 280 символов → 422 Unprocessable Entity."""
    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    bad_answers = {**VALID_ANSWERS}
    bad_answers["answers"] = {
        **VALID_ANSWERS["answers"],
        "free_text": "а" * 281,  # на 1 символ длиннее лимита
    }
    response = client.post(
        "/api/v1/votes",
        json=bad_answers,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 422


def test_votes_submit_class_from_token_not_body(client, db_session, school_class, voting_session):
    """
    class_id в Vote берётся из токена, а не из тела запроса.

    Тест создаёт токен для school_class и проверяет, что Vote.class_id
    совпадает с school_class.id — даже несмотря на то, что тело запроса
    вообще не содержит class_id (это намеренно!).
    """
    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    response = client.post(
        "/api/v1/votes",
        json=VALID_ANSWERS,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200

    # Проверяем запись в БД — class_id должен совпадать с токеном
    db_session.expire_all()  # сбрасываем кэш сессии, перечитываем из БД
    vote = db_session.query(Vote).first()
    assert vote is not None
    assert vote.class_id == school_class.id
    # Убеждаемся: нет поля, по которому можно восстановить связь код → голос
    assert not hasattr(vote, "access_code_id")
    assert not hasattr(vote, "user_id")


def test_votes_submit_stop_word_clears_free_text(client, db_session, school_class, voting_session):
    """
    Если free_text содержит стоп-слово — поле очищается, голос сохраняется.
    """
    from app.models import VoteAnswer
    import json as _json

    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=voting_session.id,
    )
    dirty_answers = {
        **VALID_ANSWERS,
        "answers": {**VALID_ANSWERS["answers"], "free_text": "это мудак придумал"},
    }
    response = client.post(
        "/api/v1/votes",
        json=dirty_answers,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200  # голос принят

    # Проверяем: free_text в БД должен быть null, а не исходной строкой
    db_session.expire_all()
    answer = (
        db_session.query(VoteAnswer)
        .filter(VoteAnswer.question_key == "free_text")
        .first()
    )
    assert answer is not None
    stored = _json.loads(answer.answer_json)
    assert stored["text"] is None  # очищено модерацией
