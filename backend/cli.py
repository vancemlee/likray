"""
CLI-утилита для администрирования Likray.

Использование:
  python cli.py create-superadmin \\
      --school-name "Лицей №131" \\
      --username admin \\
      --password XXX \\
      --full-name "Иван Иванов"

Команда создаёт запись School и Admin с ролью superadmin.
Если школа с таким именем уже существует — она будет переиспользована.
Если username занят — будет выведена ошибка.
"""

import argparse
import sys

# Настраиваем DATABASE_URL по умолчанию если не задан в окружении.
# При прямом запуске (не через pytest) используем реальную SQLite-базу.
import os
os.environ.setdefault("DATABASE_URL", "sqlite:///./likray.db")
os.environ.setdefault("SECRET_KEY", "change-me-in-production")
os.environ.setdefault("ALGORITHM", "HS256")
os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "60")

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db import Base
from app.models import Admin, AdminRole, School
from app.security import hash_password


def create_superadmin(
    db_url: str,
    school_name: str,
    username: str,
    password: str,
    full_name: str,
) -> tuple[School, Admin]:
    """
    Создать (или найти) школу и создать суперадмина для неё.

    Функция выделена отдельно, чтобы её можно было тестировать
    без запуска subprocess — тест просто импортирует и вызывает её.

    Возвращает кортеж (school, admin).
    Бросает ValueError если username уже занят.
    """
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()

    try:
        # Ищем школу или создаём новую
        school = db.query(School).filter(School.name == school_name).first()
        if school is None:
            school = School(name=school_name)
            db.add(school)
            db.flush()  # получаем school.id

        # Проверяем что username свободен
        existing = db.query(Admin).filter(Admin.username == username).first()
        if existing is not None:
            raise ValueError(f"Пользователь с username '{username}' уже существует")

        admin = Admin(
            school_id=school.id,
            username=username,
            password_hash=hash_password(password),
            full_name=full_name,
            role=AdminRole.superadmin,
        )
        db.add(admin)
        db.commit()
        db.refresh(school)
        db.refresh(admin)
        return school, admin

    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Утилита администрирования Likray",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Команда create-superadmin
    cs = subparsers.add_parser(
        "create-superadmin",
        help="Создать суперадмина (и школу если нужно)",
    )
    cs.add_argument("--school-name", required=True, help='Название школы, например "Лицей №131"')
    cs.add_argument("--username", required=True, help="Логин администратора")
    cs.add_argument("--password", required=True, help="Пароль (будет захеширован bcrypt)")
    cs.add_argument("--full-name", required=True, help='Полное имя, например "Иван Иванов"')
    cs.add_argument(
        "--db-url",
        default=os.environ.get("DATABASE_URL", "sqlite:///./likray.db"),
        help="URL базы данных (по умолчанию из DATABASE_URL или sqlite:///./likray.db)",
    )

    args = parser.parse_args()

    if args.command == "create-superadmin":
        try:
            school, admin = create_superadmin(
                db_url=args.db_url,
                school_name=args.school_name,
                username=args.username,
                password=args.password,
                full_name=args.full_name,
            )
            print(f"✓ Школа: {school.name} (id={school.id})")
            print(f"✓ Суперадмин: {admin.full_name} / {admin.username} (id={admin.id})")
        except ValueError as e:
            print(f"Ошибка: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
