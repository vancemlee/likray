"""
Pydantic-схемы для эндпоинтов администратора (фаза 3).

Покрывает: генерацию кодов, управление сессиями голосования,
агрегированные результаты.
"""

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Классы
# ---------------------------------------------------------------------------

class CreateClassRequest(BaseModel):
    grade: int = Field(..., ge=1, le=11, description="Номер класса (1–11)")
    letter: str = Field(..., min_length=1, max_length=5, description="Буква класса, например «А»")


class ClassResponse(BaseModel):
    id: int
    school_id: int
    name: str  # вычисляемое поле «10А» из grade+letter
    grade: int
    letter: str

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Коды доступа
# ---------------------------------------------------------------------------

class GenerateCodesRequest(BaseModel):
    count: int = Field(..., ge=1, le=500, description="Сколько кодов сгенерировать")


class GenerateCodesResponse(BaseModel):
    codes: list[str]
    count: int


class CodeItem(BaseModel):
    id: int
    code: str
    is_used: bool
    used_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}


class CodeListResponse(BaseModel):
    class_id: int
    codes: list[CodeItem]
    total: int


# ---------------------------------------------------------------------------
# Сессии голосования
# ---------------------------------------------------------------------------

class CreateVotingSessionRequest(BaseModel):
    quarter: int = Field(..., ge=1, le=4, description="Номер четверти (1-4)")
    year: int = Field(..., ge=2020, le=2100, description="Учебный год")


class VotingSessionResponse(BaseModel):
    id: int
    school_id: int
    quarter: int
    year: int
    is_open: bool
    opened_at: Optional[datetime]
    closed_at: Optional[datetime]

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Результаты голосования
# ---------------------------------------------------------------------------

class ClassResultItem(BaseModel):
    """Результат для одного класса — либо данные, либо suppressed."""
    class_id: int
    class_name: str
    vote_count: int
    suppressed: bool
    reason: Optional[str] = None          # «n<5» если suppressed=True
    results: Optional[dict[str, Any]] = None  # данные если suppressed=False


class SchoolTotals(BaseModel):
    """Итого по школе."""
    vote_count: int
    suppressed: bool
    reason: Optional[str] = None
    results: Optional[dict[str, Any]] = None


class VotingSessionMeta(BaseModel):
    id: int
    quarter: int
    year: int
    school_name: str
    closed_at: Optional[datetime]
    total_votes: int


class ResultsResponse(BaseModel):
    voting_session: VotingSessionMeta
    classes: list[ClassResultItem]
    school_totals: SchoolTotals
