from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.config import settings

# check_same_thread=False нужен для SQLite, чтобы одна БД могла использоваться
# в нескольких потоках FastAPI (по умолчанию SQLite блокирует это)
engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    """Базовый класс для всех SQLAlchemy-моделей проекта."""
    pass
