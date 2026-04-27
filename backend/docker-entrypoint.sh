#!/bin/sh
# Docker entrypoint для Likray.
#
# 1. Гарантирует SECRET_KEY (генерит, если не задан).
# 2. Прогоняет alembic-миграции.
# 3. Создаёт суперадмина через отдельный Python-скрипт, который читает
#    креды из ENV (никаких heredoc-интерполяций — иначе спецсимволы
#    или CRLF-окончания ломают исходник).
# 4. Передаёт управление переданной CMD (uvicorn).
#
# set -e: упасть на первой ошибке. set -u: ругаться на неинициализированные.
# pipefail: -- POSIX sh не поддерживает, поэтому ограничиваемся `-eu`.
set -eu

if [ -z "${SECRET_KEY:-}" ]; then
    SECRET_KEY="$(python -c 'import secrets; print(secrets.token_hex(32))')"
    export SECRET_KEY
    echo "[entrypoint] SECRET_KEY not set -- generated a temporary one"
fi

echo "[entrypoint] Running alembic migrations..."
alembic upgrade head

echo "[entrypoint] Ensuring superadmin..."
python -m app.scripts.ensure_superadmin

echo "[entrypoint] Starting: $*"
exec "$@"
