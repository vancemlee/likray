"""Bootstrap admin if missing.

Читает креды из переменных окружения (никаких интерполяций в исходник —
именно из-за них предыдущая версия entrypoint ломалась на спецсимволах
и CRLF-окончаниях):

    LIKRAY_ADMIN_USERNAME       (default: "admin")
    LIKRAY_ADMIN_PASSWORD       (default: "admin")
    LIKRAY_ADMIN_FULL_NAME      (default: "Default Admin")
    LIKRAY_SCHOOL_NAME          (default: "Demo School")
    DATABASE_URL                (берётся из env, если задан)

Идемпотентен: если админ с таким username уже существует, выходит без изменений.
"""
from __future__ import annotations

import os
import sys


def main() -> int:
    # Гарантируем минимально необходимые переменные для импорта app.* модулей.
    os.environ.setdefault("DATABASE_URL", "sqlite:///./likray.db")
    os.environ.setdefault("SECRET_KEY", "change-me")
    os.environ.setdefault("ALGORITHM", "HS256")
    os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "60")

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app.db import Base
    from app.models import Admin

    username  = os.environ.get("LIKRAY_ADMIN_USERNAME",  "admin")
    password  = os.environ.get("LIKRAY_ADMIN_PASSWORD",  "admin")
    full_name = os.environ.get("LIKRAY_ADMIN_FULL_NAME", "Default Admin")
    school    = os.environ.get("LIKRAY_SCHOOL_NAME",     "Demo School")
    db_url    = os.environ["DATABASE_URL"]

    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine)
    db = SessionLocal()
    try:
        existing = db.query(Admin).filter(Admin.username == username).first()
        if existing is not None:
            print(f"[bootstrap] admin '{username}' already exists -- skip")
            return 0
    finally:
        db.close()

    # Создаём через cli.create_superadmin — там вся логика (школа + хеш + роль).
    from cli import create_superadmin

    create_superadmin(
        db_url=db_url,
        school_name=school,
        username=username,
        password=password,
        full_name=full_name,
    )
    print(f"[bootstrap] created superadmin '{username}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
