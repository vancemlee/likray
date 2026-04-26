"""
Все SQLAlchemy-модели проекта Likray.

Модели определены в одном файле, чтобы избежать проблем с циклическими
импортами — они активно ссылаются друг на друга через relationships.

Ключевой архитектурный инвариант «верифицированной анонимности»:
    AccessCode <──── НЕТ СВЯЗИ ────> Vote

Сервер знает, что ученик класса X использовал код Y.
Сервер знает, что от класса X поступил голос Z.
Но сервер НЕ МОЖЕТ установить связь между Y и Z — её нет ни в одной
таблице, ни в одном поле, ни в одном индексе.
"""

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Boolean, DateTime, Enum, ForeignKey, Integer, String, Text, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


# ---------------------------------------------------------------------------
# School — образовательное учреждение
# ---------------------------------------------------------------------------

class School(Base):
    __tablename__ = "schools"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    classes: Mapped[list["Class"]] = relationship("Class", back_populates="school")
    admins: Mapped[list["Admin"]] = relationship("Admin", back_populates="school")
    voting_sessions: Mapped[list["VotingSession"]] = relationship(
        "VotingSession", back_populates="school"
    )


# ---------------------------------------------------------------------------
# Class — класс (например, «10В»)
# ---------------------------------------------------------------------------

class Class(Base):
    __tablename__ = "classes"

    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("schools.id"), nullable=False)
    grade: Mapped[int] = mapped_column(Integer, nullable=False)   # номер: 10
    letter: Mapped[str] = mapped_column(String(5), nullable=False) # буква: "В"
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    school: Mapped["School"] = relationship("School", back_populates="classes")
    access_codes: Mapped[list["AccessCode"]] = relationship(
        "AccessCode", back_populates="class_"
    )
    votes: Mapped[list["Vote"]] = relationship("Vote", back_populates="class_")

    @property
    def name(self) -> str:
        """Вычисляемое название класса, например «10В»."""
        return f"{self.grade}{self.letter}"


# ---------------------------------------------------------------------------
# Admin — администратор (завуч или суперадмин)
# ---------------------------------------------------------------------------

class AdminRole(str, enum.Enum):
    vicerector = "vicerector"   # завуч — работает с одной школой
    superadmin = "superadmin"   # разработчик/владелец системы


class Admin(Base):
    __tablename__ = "admins"

    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("schools.id"), nullable=False)
    username: Mapped[str] = mapped_column(String(100), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[AdminRole] = mapped_column(Enum(AdminRole), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    school: Mapped["School"] = relationship("School", back_populates="admins")
    # Коды, которые создал этот администратор
    created_codes: Mapped[list["AccessCode"]] = relationship(
        "AccessCode", back_populates="created_by_admin"
    )


# ---------------------------------------------------------------------------
# AccessCode — одноразовый код доступа для ученика
#
# ВАЖНО: эта таблица намеренно НЕ содержит FK на таблицу votes и
# не имеет никакой связи с конкретными голосами.
# Это — ключевой элемент «верифицированной анонимности»:
# зная, что код был использован, невозможно установить,
# какой конкретно голос был подан с его помощью.
# ---------------------------------------------------------------------------

class AccessCode(Base):
    __tablename__ = "access_codes"

    id: Mapped[int] = mapped_column(primary_key=True)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"), nullable=False)
    code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False)
    is_used: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    created_by_admin_id: Mapped[int] = mapped_column(
        ForeignKey("admins.id"), nullable=False
    )

    class_: Mapped["Class"] = relationship("Class", back_populates="access_codes")
    created_by_admin: Mapped["Admin"] = relationship(
        "Admin", back_populates="created_codes"
    )

    # !! НЕТ FK на таблицу votes — это намеренно!
    # Связь «код → голос» не хранится нигде в БД.
    # Даже имея полный дамп БД, невозможно узнать, кто как проголосовал.


# ---------------------------------------------------------------------------
# VotingSession — сессия голосования (четверть + год + статус)
# ---------------------------------------------------------------------------

class VotingSession(Base):
    __tablename__ = "voting_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("schools.id"), nullable=False)
    quarter: Mapped[int] = mapped_column(Integer, nullable=False)  # 1–4
    year: Mapped[int] = mapped_column(Integer, nullable=False)     # напр. 2024
    opened_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    is_open: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    school: Mapped["School"] = relationship("School", back_populates="voting_sessions")
    votes: Mapped[list["Vote"]] = relationship("Vote", back_populates="voting_session")


# ---------------------------------------------------------------------------
# Vote — анонимный голос ученика
#
# ВАЖНО: эта таблица намеренно НЕ содержит FK на таблицу access_codes и
# не имеет поля user_id или любого другого идентификатора ученика.
# Мы знаем только class_id — что голос принадлежит конкретному классу.
# КТО именно голосовал — неизвестно и невосстановимо. Это гарантируется
# на уровне схемы БД: нет поля → нет утечки → нет возможности деанонимизации.
# ---------------------------------------------------------------------------

class Vote(Base):
    __tablename__ = "votes"

    id: Mapped[int] = mapped_column(primary_key=True)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"), nullable=False)
    voting_session_id: Mapped[int] = mapped_column(
        ForeignKey("voting_sessions.id"), nullable=False
    )
    submitted_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

    # !! НЕТ FK на access_codes — это намеренно! (см. docstring выше)
    # !! НЕТ user_id — это намеренно! Анонимность гарантируется схемой.

    class_: Mapped["Class"] = relationship("Class", back_populates="votes")
    voting_session: Mapped["VotingSession"] = relationship(
        "VotingSession", back_populates="votes"
    )
    answers: Mapped[list["VoteAnswer"]] = relationship(
        "VoteAnswer", back_populates="vote", cascade="all, delete-orphan"
    )


# ---------------------------------------------------------------------------
# VoteAnswer — один ответ на один вопрос анкеты
# ---------------------------------------------------------------------------

class VoteAnswer(Base):
    __tablename__ = "vote_answers"

    id: Mapped[int] = mapped_column(primary_key=True)
    vote_id: Mapped[int] = mapped_column(ForeignKey("votes.id"), nullable=False)
    question_key: Mapped[str] = mapped_column(String(100), nullable=False)
    answer_json: Mapped[str] = mapped_column(Text, nullable=False)

    vote: Mapped["Vote"] = relationship("Vote", back_populates="answers")


# ---------------------------------------------------------------------------
# UsedToken — использованные student JWT (защита от двойного голосования)
# ---------------------------------------------------------------------------

class UsedToken(Base):
    """
    Таблица инвалидированных student-токенов.

    После того как ученик успешно проголосовал, jti его токена
    записывается сюда. Зависимость get_current_student проверяет эту
    таблицу перед каждым запросом с student JWT.

    jti — первичный ключ: один токен = одна запись, коллизии невозможны.
    """
    __tablename__ = "used_tokens"

    jti: Mapped[str] = mapped_column(String(36), primary_key=True)
    used_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())


__all__ = [
    "School", "Class", "Admin", "AdminRole",
    "AccessCode", "VotingSession", "Vote", "VoteAnswer",
    "UsedToken",
]
