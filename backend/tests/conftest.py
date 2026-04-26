"""
Фикстуры для тестов.

Движок и БД — function-scoped: каждый тест получает свежую in-memory SQLite.
Это гарантирует полную изоляцию — данные одного теста не влияют на другие.

Иерархия зависимостей фикстур:
  engine → db_session → client
                      → school → school_class → access_code
                               → admin        → access_code
                               → voting_session
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base
from app.deps import get_db
from app.main import app
# Импортируем ВСЕ модели, чтобы Base.metadata знал про все таблицы
# перед вызовом create_all (включая UsedToken, Vote, VoteAnswer).
from app.models import (
    AccessCode, Admin, AdminRole, Class, School, UsedToken,
    Vote, VoteAnswer, VotingSession,
)
from app.security import hash_password


# ---------------------------------------------------------------------------
# Движок и сессия
# ---------------------------------------------------------------------------

@pytest.fixture(scope="function")
def engine():
    """
    Создать новый in-memory SQLite и все таблицы для одного теста.
    scope="function" — полная изоляция между тестами.
    """
    # StaticPool критически важен: in-memory SQLite создаёт новый БД на каждое
    # соединение, поэтому без него фикстура и HTTP-запрос видят РАЗНЫЕ базы
    # и тесты падают с "no such table".
    test_engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=test_engine)
    yield test_engine
    test_engine.dispose()


@pytest.fixture(scope="function")
def db_session(engine):
    """Сессия БД для одного теста. После теста — откат незафиксированного."""
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture(scope="function")
def client(db_session):
    """
    HTTP-клиент FastAPI с подменённой зависимостью get_db.
    Все запросы через этот клиент используют ту же db_session, что и фикстуры.
    Это позволяет создать данные в фикстурах и сразу видеть их из HTTP-запросов.
    """
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Доменные фикстуры
# ---------------------------------------------------------------------------

@pytest.fixture
def school(db_session) -> School:
    """Тестовая школа."""
    s = School(name="Лицей №131 (тест)")
    db_session.add(s)
    db_session.commit()
    db_session.refresh(s)
    return s


@pytest.fixture
def school_class(db_session, school) -> Class:
    """Тестовый класс 10В."""
    c = Class(school_id=school.id, grade=10, letter="В")
    db_session.add(c)
    db_session.commit()
    db_session.refresh(c)
    return c


@pytest.fixture
def admin(db_session, school) -> Admin:
    """Тестовый администратор (завуч) с паролем 'secret'."""
    a = Admin(
        school_id=school.id,
        username="zavuch@test.ru",
        password_hash=hash_password("secret"),
        full_name="Тестовый Завуч",
        role=AdminRole.vicerector,
    )
    db_session.add(a)
    db_session.commit()
    db_session.refresh(a)
    return a


@pytest.fixture
def voting_session(db_session, school) -> VotingSession:
    """Открытая сессия голосования для тестовой школы (2-я четверть 2024)."""
    vs = VotingSession(
        school_id=school.id,
        quarter=2,
        year=2024,
        is_open=True,
    )
    db_session.add(vs)
    db_session.commit()
    db_session.refresh(vs)
    return vs


@pytest.fixture
def access_code(db_session, school_class, admin) -> AccessCode:
    """Неиспользованный одноразовый код доступа для класса 10В."""
    code = AccessCode(
        class_id=school_class.id,
        code="TESTCODE1",
        is_used=False,
        created_by_admin_id=admin.id,
    )
    db_session.add(code)
    db_session.commit()
    db_session.refresh(code)
    return code
