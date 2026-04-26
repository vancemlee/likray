"""
Тесты аутентификации:
  - student redeem (success / already used / no session / not found)
  - admin login (success / wrong password)
"""


def test_auth_student_redeem_success(client, access_code, voting_session):
    """Успешная активация кода → получаем токен с class_name и voting_session_id."""
    response = client.post(
        "/api/v1/auth/student/redeem",
        json={"code": access_code.code},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["class_name"] == "10В"
    assert data["voting_session_id"] == voting_session.id


def test_auth_student_redeem_already_used(client, access_code, voting_session):
    """Повторная активация того же кода → 409 Conflict."""
    # Первый редем должен пройти
    first = client.post(
        "/api/v1/auth/student/redeem",
        json={"code": access_code.code},
    )
    assert first.status_code == 200

    # Второй — должен вернуть 409
    second = client.post(
        "/api/v1/auth/student/redeem",
        json={"code": access_code.code},
    )
    assert second.status_code == 409
    assert second.json()["detail"]["code"] == "CODE_ALREADY_USED"


def test_auth_student_redeem_no_session(client, access_code):
    """Нет активной сессии голосования → 400 Bad Request."""
    # voting_session fixture не подключена — в БД нет открытой сессии
    response = client.post(
        "/api/v1/auth/student/redeem",
        json={"code": access_code.code},
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "NO_ACTIVE_SESSION"


def test_auth_student_redeem_code_not_found(client):
    """Несуществующий код → 404 Not Found."""
    response = client.post(
        "/api/v1/auth/student/redeem",
        json={"code": "NONEXISTENT"},
    )
    assert response.status_code == 404
    assert response.json()["detail"]["code"] == "CODE_NOT_FOUND"


def test_auth_admin_login_success(client, admin):
    """Успешный логин администратора → получаем токен."""
    response = client.post(
        "/api/v1/auth/admin/login",
        data={"username": admin.username, "password": "secret"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"


def test_auth_admin_login_wrong_password(client, admin):
    """Неверный пароль → 401 Unauthorized."""
    response = client.post(
        "/api/v1/auth/admin/login",
        data={"username": admin.username, "password": "неверный"},
    )
    assert response.status_code == 401
    assert response.json()["detail"]["code"] == "INVALID_CREDENTIALS"


def test_auth_admin_login_unknown_user(client):
    """Несуществующий пользователь → 401 Unauthorized."""
    response = client.post(
        "/api/v1/auth/admin/login",
        data={"username": "ghost@test.ru", "password": "secret"},
    )
    assert response.status_code == 401
