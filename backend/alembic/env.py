import sys
import os
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

# Добавляем backend/ в sys.path, чтобы импорты вида `from app.xxx` работали
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Импортируем настройки и Base с моделями
from app.config import settings
from app.db import Base
import app.models  # noqa: F401 — нужен для регистрации всех моделей в Base.metadata

# Объект конфигурации Alembic
config = context.config

# Подставляем URL из нашего конфига (перекрывает значение из alembic.ini)
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

# Настройка логирования из alembic.ini
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Метаданные всех наших моделей — нужны для автогенерации миграций
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Офлайн-режим: генерирует SQL без подключения к БД."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Онлайн-режим: применяет миграции к реальной БД."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
