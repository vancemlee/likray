"""Bootstrap or refresh admin from environment variables.

Читает креды из ENV (никаких интерполяций в исходник):

    LIKRAY_ADMIN_USERNAME       (default: "admin")
    LIKRAY_ADMIN_PASSWORD       (default: "admin")
    LIKRAY_ADMIN_FULL_NAME      (default: "Default Admin")
    LIKRAY_SCHOOL_NAME          (default: "Demo School")
    DATABASE_URL                (берётся из env)

Поведение:
    * нет админа с таким username        → создаётся через cli.create_superadmin
    * админ есть и пароль уже совпадает  → пропуск
    * админ есть, но пароль НЕ совпадает → обновляется password_hash, full_name
                                          и school переподвязывается

То есть после правки `LIKRAY_ADMIN_PASSWORD` в Render Environment и редеплоя
контейнера логин начнёт работать с новым паролем -- независимо от того,
сохранилась ли БД (Postgres) или была сброшена (ephemeral SQLite).
"""
from __future__ import annotations

import os
import sys


def main() -> int:
    os.environ.setdefault("DATABASE_URL", "sqlite:///./likray.db")
    os.environ.setdefault("SECRET_KEY", "change-me")
    os.environ.setdefault("ALGORITHM", "HS256")
    os.environ.setdefault("ACCESS_TOKEN_EXPIRE_MINUTES", "60")

    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app.db import Base
    from app.models import Admin, AdminRole, School
    from app.security import hash_password, verify_password

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
        if existing is None:
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

        # Админ уже есть -- проверяем пароль и при необходимости обновляем.
        if verify_password(password, existing.password_hash):
            print(f"[bootstrap] admin '{username}' password matches env -- skip")
            return 0

        # Пароль изменился: обновляем hash + full_name (могло измениться).
        existing.password_hash = hash_password(password)
        existing.full_name = full_name
        # Школу не двигаем -- если имя школы поменяли, пусть остаётся прежняя
        # привязка, иначе случайный rename сломает FK у access_codes/sessions.
        db.commit()
        print(f"[bootstrap] updated password for existing admin '{username}'")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
