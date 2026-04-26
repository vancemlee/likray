"""
Pydantic-схемы для голосования.

Анкета v1 состоит из 5 блоков (см. ТЗ §7).
Структура анкеты также хранится в QUESTIONNAIRE_V1 —
статический словарь, который возвращает GET /votes/active,
чтобы Flutter-клиент мог динамически отрисовать форму.
"""

from typing import Literal, Optional

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Допустимые значения для перечислимых полей (Literal вместо Enum —
# проще читать и даёт хорошие сообщения об ошибках в Pydantic v2)
# ---------------------------------------------------------------------------

SubjectTime = Literal["lessons_1_2", "lessons_3_4", "lessons_5_6", "any"]
FreePeriodChoice = Literal["max_1", "max_3", "any"]
PEPreference = Literal["first", "last", "middle", "any"]


# ---------------------------------------------------------------------------
# Блок 1: Тяжёлые предметы — желаемое время дня
# ---------------------------------------------------------------------------

class HeavySubjectsAnswer(BaseModel):
    math: SubjectTime
    physics: SubjectTime
    chemistry: SubjectTime
    cs: SubjectTime
    foreign_language: SubjectTime


# ---------------------------------------------------------------------------
# Блок 2: Распределение контрольных по дням недели
# ---------------------------------------------------------------------------

class ExamsAnswer(BaseModel):
    max_per_day: int = Field(..., ge=1, le=4, description="Максимум контрольных в день")
    no_mon_fri: bool = Field(..., description="Понедельник и пятница без контрольных")


# ---------------------------------------------------------------------------
# Блок 3: Окна в расписании
# ---------------------------------------------------------------------------

class FreePeriodsAnswer(BaseModel):
    choice: FreePeriodChoice
    prefer_long: bool = Field(..., description="Предпочесть одно длинное окно нескольким коротким")


# ---------------------------------------------------------------------------
# Блок 4: Физкультура
# ---------------------------------------------------------------------------

class PEAnswer(BaseModel):
    preference: PEPreference


# ---------------------------------------------------------------------------
# Итоговые схемы запроса/ответа
# ---------------------------------------------------------------------------

class SurveyAnswers(BaseModel):
    heavy_subjects: HeavySubjectsAnswer
    exams: ExamsAnswer
    free_periods: FreePeriodsAnswer
    pe: PEAnswer
    free_text: Optional[str] = Field(
        None,
        max_length=280,
        description="Свободное пожелание (опционально, до 280 символов)",
    )


class VoteSubmitRequest(BaseModel):
    answers: SurveyAnswers


class VoteSubmitResponse(BaseModel):
    status: str = "accepted"


class ActiveVotingSessionResponse(BaseModel):
    voting_session_id: int
    quarter: int
    year: int
    class_name: str
    questionnaire: dict  # QUESTIONNAIRE_V1 — описание блоков для Flutter


# ---------------------------------------------------------------------------
# Статическое описание анкеты v1 (передаётся клиенту через GET /votes/active)
# ---------------------------------------------------------------------------

QUESTIONNAIRE_V1: dict = {
    "version": "v1",
    "blocks": [
        {
            "key": "heavy_subjects",
            "title": "Тяжёлые предметы — желаемое время дня",
            "description": "Для каждого предмета выбери, когда лучше его поставить",
            "type": "subjects_time",
            "subjects": [
                {"key": "math",            "label": "Математика"},
                {"key": "physics",         "label": "Физика"},
                {"key": "chemistry",       "label": "Химия"},
                {"key": "cs",              "label": "Информатика"},
                {"key": "foreign_language","label": "Иностранный язык"},
            ],
            "options": [
                {"value": "lessons_1_2", "label": "1–2 урок"},
                {"value": "lessons_3_4", "label": "3–4 урок"},
                {"value": "lessons_5_6", "label": "5–6 урок"},
                {"value": "any",         "label": "Не важно"},
            ],
        },
        {
            "key": "exams",
            "title": "Контрольные по дням недели",
            "type": "exams",
            "fields": [
                {
                    "key": "max_per_day",
                    "label": "Максимум контрольных в один день",
                    "type": "slider",
                    "min": 1,
                    "max": 4,
                },
                {
                    "key": "no_mon_fri",
                    "label": "Понедельник и пятница — желательно без контрольных",
                    "type": "checkbox",
                },
            ],
        },
        {
            "key": "free_periods",
            "title": "Окна в расписании",
            "type": "free_periods",
            "options": [
                {"value": "max_1", "label": "Допускаю максимум 1 окно в неделю"},
                {"value": "max_3", "label": "Допускаю до 3 окон"},
                {"value": "any",   "label": "Не важно"},
            ],
            "extra_field": {
                "key": "prefer_long",
                "label": "Лучше одно длинное окно, чем несколько коротких",
                "type": "checkbox",
            },
        },
        {
            "key": "pe",
            "title": "Физкультура",
            "type": "radio",
            "options": [
                {"value": "first",  "label": "Первым уроком"},
                {"value": "last",   "label": "Последним уроком"},
                {"value": "middle", "label": "В середине дня"},
                {"value": "any",    "label": "Не важно"},
            ],
        },
        {
            "key": "free_text",
            "title": "Свободное пожелание (необязательно)",
            "type": "text",
            "max_length": 280,
            "placeholder": "Напиши одно пожелание по расписанию...",
        },
    ],
}
