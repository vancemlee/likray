#!/bin/sh
# Entrypoint для Docker-контейнера Likray:
# 1. Генерирует SECRET_KEY если он не задан (одноразовый — на жизнь контейнера).
# 2. Применяет миграции Alembic.
# 3. Создаёт суперадмина если его ещё нет.
# 4. Запускает переданную команду (по умолчанию uvicorn, см. CMD в Dockerfile).
set -eu

if [ -z "${SECRET_KEY:-}" ]; then
    SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
    export SECRET_KEY
    echo "[entrypoint] SECRET_KEY not set — generated a temporary one"
fi

DEFAULT_ADMIN_USERNAME="${LIKRAY_ADMIN_USERNAME:-admin}"
DEFAULT_ADMIN_PASSWORD="${LIKRAY_ADMIN_PASSWORD:-admin}"
DEFAULT_ADMIN_FULL_NAME="${LIKRAY_ADMIN_FULL_NAME:-Default Admin}"
DEFAULT_SCHOOL_NAME="${LIKRAY_SCHOOL_NAME:-Demo School}"

echo "[entrypoint] Running alembic migrations..."
alembic upgrade head

echo "[entrypoint] Ensuring superadmin '$DEFAULT_ADMIN_USERNAME' exists..."
python - <<PYEOF
import os, sys
os.environ.setdefault("DATABASE_URL", "${DATABASE_URL}")
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db import Base
from app.models import Admin

engine = create_engine(os.environ["DATABASE_URL"], connect_args={"check_same_thread": False})
Base.metadata.create_all(bind=engine)
SessionLocal = sessionmaker(bind=engine)
db = SessionLocal()
exists = db.query(Admin).filter(Admin.username == "${DEFAULT_ADMIN_USERNAME}").first()
db.close()
if exists:
    print("[entrypoint] superadmin already exists — skipping bootstrap")
    sys.exit(0)

from cli import create_superadmin
create_superadmin(
    db_url=os.environ["DATABASE_URL"],
    school_name="${DEFAULT_SCHOOL_NAME}",
    username="${DEFAULT_ADMIN_USERNAME}",
    password="${DEFAULT_ADMIN_PASSWORD}",
    full_name="${DEFAULT_ADMIN_FULL_NAME}",
)
print("[entrypoint] bootstrapped superadmin '${DEFAULT_ADMIN_USERNAME}' (change password!)")
PYEOF

echo "[entrypoint] Starting: $*"
exec "$@"
