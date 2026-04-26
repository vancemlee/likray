"""
Тесты CLI-команды create-superadmin.

Тесты импортируют функцию create_superadmin напрямую и вызывают её
с временными SQLite-файлами — subprocess не нужен. Это быстро и изолировано.
"""

import pytest

from app.models import AdminRole
from app.security import verify_password


def test_create_superadmin_success(tmp_path):
    """Создать школу и суперадмина — записи должны появиться в БД."""
    from cli import create_superadmin

    db_url = f"sqlite:///{tmp_path / 'test.db'}"
    school, admin = create_superadmin(
        db_url=db_url,
        school_name="Лицей №1",
        username="superadmin",
        password="supersecret",
        full_name="Иван Иванов",
    )

    assert school.name == "Лицей №1"
    assert admin.username == "superadmin"
    assert admin.full_name == "Иван Иванов"
    assert admin.role == AdminRole.superadmin
    # Пароль должен быть захеширован
    assert admin.password_hash != "supersecret"
    assert verify_password("supersecret", admin.password_hash)


def test_create_superadmin_duplicate_username(tmp_path):
    """Повторное создание с тем же username → ValueError."""
    from cli import create_superadmin

    db_url = f"sqlite:///{tmp_path / 'test.db'}"

    create_superadmin(
        db_url=db_url,
        school_name="Школа А",
        username="admin_dup",
        password="pass1",
        full_name="Первый Иван",
    )

    with pytest.raises(ValueError, match="уже существует"):
        create_superadmin(
            db_url=db_url,
            school_name="Школа А",
            username="admin_dup",  # тот же username
            password="pass2",
            full_name="Второй Иван",
        )


def test_create_superadmin_reuses_existing_school(tmp_path):
    """Если школа с таким именем уже существует — создаётся только новый Admin."""
    from cli import create_superadmin

    db_url = f"sqlite:///{tmp_path / 'test.db'}"

    school1, admin1 = create_superadmin(
        db_url=db_url,
        school_name="Лицей №131",
        username="admin_first",
        password="pass1",
        full_name="Первый Завуч",
    )

    school2, admin2 = create_superadmin(
        db_url=db_url,
        school_name="Лицей №131",  # та же школа
        username="admin_second",
        password="pass2",
        full_name="Второй Завуч",
    )

    # Школа та же
    assert school1.id == school2.id
    # Но администраторы разные
    assert admin1.id != admin2.id
    assert admin2.school_id == school1.id
