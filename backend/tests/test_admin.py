"""
Тесты admin-панели (фаза 3):
  - POST /admin/classes/{class_id}/codes/generate
  - GET  /admin/classes/{class_id}/codes
  - POST /admin/voting-sessions
  - POST /admin/voting-sessions/{id}/open
  - POST /admin/voting-sessions/{id}/close
  - GET  /admin/voting-sessions/{id}/results  (с защитой n<5)
  - GET  /admin/voting-sessions/{id}/export/csv
  - GET  /admin/voting-sessions/{id}/export/pdf
  - POST /votes — проверка что закрытая сессия отвергает голоса
"""

import json

import pytest

from app.models import AccessCode, Admin, AdminRole, Class, School, Vote, VoteAnswer, VotingSession
from app.security import create_admin_token, create_anon_student_token, hash_password

# ---------------------------------------------------------------------------
# Вспомогательные фикстуры (дополнительные к conftest.py)
# ---------------------------------------------------------------------------

@pytest.fixture
def admin_token(admin) -> str:
    """JWT для тестового администратора (завуч)."""
    return create_admin_token(
        admin_id=admin.id,
        role=admin.role.value,
        school_id=admin.school_id,
    )


@pytest.fixture
def admin_headers(admin_token) -> dict:
    """Заголовки с токеном администратора."""
    return {"Authorization": f"Bearer {admin_token}"}


@pytest.fixture
def other_school(db_session) -> School:
    """Вторая школа — для проверки 403 при обращении к чужим данным."""
    s = School(name="Другая школа")
    db_session.add(s)
    db_session.commit()
    db_session.refresh(s)
    return s


@pytest.fixture
def other_admin(db_session, other_school) -> Admin:
    """Администратор другой школы."""
    a = Admin(
        school_id=other_school.id,
        username="other@test.ru",
        password_hash=hash_password("secret"),
        full_name="Другой Завуч",
        role=AdminRole.vicerector,
    )
    db_session.add(a)
    db_session.commit()
    db_session.refresh(a)
    return a


@pytest.fixture
def other_admin_headers(other_admin) -> dict:
    """Заголовки с токеном администратора чужой школы."""
    token = create_admin_token(
        admin_id=other_admin.id,
        role=other_admin.role.value,
        school_id=other_admin.school_id,
    )
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Типовой набор ответов для отправки голосов
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
        "exams": {"max_per_day": 2, "no_mon_fri": True},
        "free_periods": {"choice": "max_1", "prefer_long": False},
        "pe": {"preference": "last"},
        "free_text": None,
    }
}


# ---------------------------------------------------------------------------
# 1. test_generate_codes_success
# ---------------------------------------------------------------------------

def test_generate_codes_success(client, admin_headers, school_class, db_session):
    """30 кодов успешно генерируются, все уникальны, все лежат в БД."""
    response = client.post(
        f"/api/v1/admin/classes/{school_class.id}/codes/generate",
        json={"count": 30},
        headers=admin_headers,
    )
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["count"] == 30
    assert len(data["codes"]) == 30
    # Все коды уникальны
    assert len(set(data["codes"])) == 30
    # Все коды реально лежат в БД
    db_codes = db_session.query(AccessCode).filter(AccessCode.class_id == school_class.id).all()
    assert len(db_codes) == 30
    db_code_set = {c.code for c in db_codes}
    for code in data["codes"]:
        assert code in db_code_set
    # Формат XXXX-XXXX
    for code in data["codes"]:
        parts = code.split("-")
        assert len(parts) == 2
        assert len(parts[0]) == 4
        assert len(parts[1]) == 4


# ---------------------------------------------------------------------------
# 2. test_generate_codes_requires_admin_token
# ---------------------------------------------------------------------------

def test_generate_codes_requires_admin_token(client, school_class):
    """Без токена → 401 (или 403 от HTTPBearer)."""
    response = client.post(
        f"/api/v1/admin/classes/{school_class.id}/codes/generate",
        json={"count": 5},
    )
    assert response.status_code in (401, 403)


# ---------------------------------------------------------------------------
# 3. test_generate_codes_wrong_school
# ---------------------------------------------------------------------------

def test_generate_codes_wrong_school(client, other_admin_headers, school_class):
    """Администратор чужой школы → 403 FORBIDDEN."""
    response = client.post(
        f"/api/v1/admin/classes/{school_class.id}/codes/generate",
        json={"count": 5},
        headers=other_admin_headers,
    )
    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "WRONG_SCHOOL"


# ---------------------------------------------------------------------------
# 4. test_list_codes
# ---------------------------------------------------------------------------

def test_list_codes(client, admin_headers, school_class, access_code):
    """GET /codes возвращает список с правильными полями."""
    response = client.get(
        f"/api/v1/admin/classes/{school_class.id}/codes",
        headers=admin_headers,
    )
    assert response.status_code == 200
    data = response.json()
    assert data["class_id"] == school_class.id
    assert data["total"] == 1
    assert len(data["codes"]) == 1
    code_item = data["codes"][0]
    assert code_item["code"] == access_code.code
    assert code_item["is_used"] is False
    assert code_item["used_at"] is None


# ---------------------------------------------------------------------------
# 5. test_create_voting_session_success
# ---------------------------------------------------------------------------

def test_create_voting_session_success(client, admin_headers, school):
    """Успешное создание сессии голосования."""
    response = client.post(
        "/api/v1/admin/voting-sessions",
        json={"quarter": 3, "year": 2025},
        headers=admin_headers,
    )
    assert response.status_code == 201, response.text
    data = response.json()
    assert data["quarter"] == 3
    assert data["year"] == 2025
    assert data["is_open"] is False
    assert data["school_id"] == school.id


# ---------------------------------------------------------------------------
# 6. test_create_voting_session_duplicate_open
# ---------------------------------------------------------------------------

def test_create_voting_session_duplicate_open(client, admin_headers, voting_session):
    """Нельзя создать вторую открытую сессию → 409 CONFLICT."""
    # voting_session уже открытая (is_open=True из conftest)
    response = client.post(
        "/api/v1/admin/voting-sessions",
        json={"quarter": 3, "year": 2025},
        headers=admin_headers,
    )
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "SESSION_ALREADY_OPEN"


# ---------------------------------------------------------------------------
# 7. test_open_close_voting_session
# ---------------------------------------------------------------------------

def test_open_close_voting_session(client, admin_headers, school):
    """Полный цикл: создать → открыть → закрыть."""
    # Создаём закрытую сессию
    create_resp = client.post(
        "/api/v1/admin/voting-sessions",
        json={"quarter": 1, "year": 2025},
        headers=admin_headers,
    )
    assert create_resp.status_code == 201
    session_id = create_resp.json()["id"]
    assert create_resp.json()["is_open"] is False

    # Открываем
    open_resp = client.post(
        f"/api/v1/admin/voting-sessions/{session_id}/open",
        headers=admin_headers,
    )
    assert open_resp.status_code == 200
    assert open_resp.json()["is_open"] is True
    assert open_resp.json()["opened_at"] is not None

    # Закрываем
    close_resp = client.post(
        f"/api/v1/admin/voting-sessions/{session_id}/close",
        headers=admin_headers,
    )
    assert close_resp.status_code == 200
    assert close_resp.json()["is_open"] is False
    assert close_resp.json()["closed_at"] is not None


# ---------------------------------------------------------------------------
# 8. test_cannot_submit_vote_to_closed_session
# ---------------------------------------------------------------------------

def test_cannot_submit_vote_to_closed_session(client, admin_headers, school, school_class, db_session):
    """Закрытая сессия → POST /votes возвращает 400 SESSION_CLOSED."""
    # Создаём уже закрытую сессию напрямую через БД
    vs = VotingSession(
        school_id=school.id,
        quarter=4,
        year=2024,
        is_open=False,
    )
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)

    token = create_anon_student_token(
        class_id=school_class.id,
        voting_session_id=vs.id,
    )
    response = client.post(
        "/api/v1/votes",
        json=VALID_ANSWERS,
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "SESSION_CLOSED"


# ---------------------------------------------------------------------------
# 9. test_results_suppressed_small_class
# ---------------------------------------------------------------------------

def test_results_suppressed_small_class(client, admin_headers, school, school_class, db_session):
    """
    Если в классе проголосовало <5 учеников — данные скрыты.
    Проверяем suppressed=True для класса с 3 голосами.
    """
    vs = VotingSession(school_id=school.id, quarter=2, year=2025, is_open=True)
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)

    # Добавляем 3 голоса (n < 5)
    _add_votes(db_session, school_class, vs, count=3)

    response = client.get(
        f"/api/v1/admin/voting-sessions/{vs.id}/results",
        headers=admin_headers,
    )
    assert response.status_code == 200, response.text
    data = response.json()

    # Находим наш класс в результатах
    class_result = next(
        (c for c in data["classes"] if c["class_id"] == school_class.id), None
    )
    assert class_result is not None
    assert class_result["suppressed"] is True
    assert class_result["reason"] == "n<5"
    assert class_result["results"] is None
    assert class_result["vote_count"] == 3

    # School totals тоже suppressed (3 < 5)
    assert data["school_totals"]["suppressed"] is True


# ---------------------------------------------------------------------------
# 10. test_results_visible_big_class
# ---------------------------------------------------------------------------

def test_results_visible_big_class(client, admin_headers, school, school_class, db_session):
    """
    n=10 голосов → данные видны, структура корректна.
    """
    vs = VotingSession(school_id=school.id, quarter=3, year=2025, is_open=True)
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)

    _add_votes(db_session, school_class, vs, count=10)

    response = client.get(
        f"/api/v1/admin/voting-sessions/{vs.id}/results",
        headers=admin_headers,
    )
    assert response.status_code == 200
    data = response.json()

    class_result = next(
        (c for c in data["classes"] if c["class_id"] == school_class.id), None
    )
    assert class_result is not None
    assert class_result["suppressed"] is False
    assert class_result["vote_count"] == 10
    results = class_result["results"]
    # Проверяем структуру — все блоки присутствуют
    assert "heavy_subjects" in results
    assert "exams" in results
    assert "free_periods" in results
    assert "pe" in results
    assert "free_text" in results
    # В блоке heavy_subjects есть ключ math с 10 голосами
    assert results["heavy_subjects"]["math"].get("lessons_1_2", 0) == 10

    # School totals — не suppressed
    assert data["school_totals"]["suppressed"] is False
    assert data["school_totals"]["vote_count"] == 10


# ---------------------------------------------------------------------------
# 11. test_export_csv_contains_suppression
# ---------------------------------------------------------------------------

def test_export_csv_contains_suppression(client, admin_headers, school, school_class, db_session):
    """CSV-экспорт содержит строку [suppressed] для маленького класса."""
    vs = VotingSession(school_id=school.id, quarter=1, year=2026, is_open=False)
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)

    # 2 голоса — suppressed
    _add_votes(db_session, school_class, vs, count=2)

    response = client.get(
        f"/api/v1/admin/voting-sessions/{vs.id}/export/csv",
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert "text/csv" in response.headers["content-type"]
    content = response.text
    assert "[suppressed]" in content


# ---------------------------------------------------------------------------
# 12. test_export_pdf_returns_pdf_content
# ---------------------------------------------------------------------------

def test_export_pdf_returns_pdf_content(client, admin_headers, school, school_class, db_session):
    """PDF-экспорт начинается с магических байтов %PDF."""
    vs = VotingSession(school_id=school.id, quarter=2, year=2026, is_open=False)
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)

    response = client.get(
        f"/api/v1/admin/voting-sessions/{vs.id}/export/pdf",
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert "application/pdf" in response.headers["content-type"]
    # Проверяем магические байты PDF
    assert response.content[:4] == b"%PDF"


# ---------------------------------------------------------------------------
# Вспомогательная функция: создать N голосов в БД напрямую
# ---------------------------------------------------------------------------

def _add_votes(db_session, school_class, voting_session, count: int) -> None:
    """
    Добавить N анонимных голосов в БД напрямую (без HTTP-запроса).
    Используется для настройки тестовых данных.
    """
    answer_blocks = [
        ("heavy_subjects", {
            "math": "lessons_1_2", "physics": "lessons_3_4",
            "chemistry": "any", "cs": "lessons_1_2", "foreign_language": "any",
        }),
        ("exams", {"max_per_day": 2, "no_mon_fri": True}),
        ("free_periods", {"choice": "max_1", "prefer_long": False}),
        ("pe", {"preference": "last"}),
        ("free_text", {"text": None}),
    ]

    for _ in range(count):
        vote = Vote(
            class_id=school_class.id,
            voting_session_id=voting_session.id,
        )
        db_session.add(vote)
        db_session.flush()  # получаем vote.id

        for question_key, data in answer_blocks:
            db_session.add(VoteAnswer(
                vote_id=vote.id,
                question_key=question_key,
                answer_json=json.dumps(data, ensure_ascii=False),
            ))

    db_session.commit()
