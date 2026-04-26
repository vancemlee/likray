"""
Модуль агрегации результатов голосования.

Единственная публичная функция — aggregate_session_results(db, voting_session_id).
Вся логика защиты n<5 живёт здесь, а не дублируется в роутерах.

Правило n<5:
  Если в классе проголосовало МЕНЬШЕ 5 учеников — агрегат не выдаётся.
  Вместо данных возвращается {"suppressed": True, "reason": "n<5"}.
  Это защищает от деанонимизации маленьких классов:
  если проголосовало 2 человека и их ответы совпадают — слишком легко угадать авторов.
"""

import json
from collections import Counter, defaultdict
from typing import Any

from sqlalchemy.orm import Session

from app.models import Class, School, Vote, VotingSession

# Пороговое значение: при строго меньшем количестве голосов данные скрываются
N_MIN = 5


# ---------------------------------------------------------------------------
# Внутренняя агрегация ответов
# ---------------------------------------------------------------------------

def _aggregate_votes(votes: list[Vote]) -> dict[str, Any]:
    """
    Агрегировать список голосов → словарь с распределением ответов по блокам.

    Каждый ответ хранится в VoteAnswer.answer_json (JSON-строка).
    Для каждого блока считаем сколько раз встречается каждое значение.
    """
    # Блок 1: тяжёлые предметы
    heavy: dict[str, Counter] = {
        subj: Counter()
        for subj in ["math", "physics", "chemistry", "cs", "foreign_language"]
    }
    # Блок 2: контрольные
    exams_max: Counter = Counter()
    exams_no_mon: Counter = Counter()
    # Блок 3: окна
    free_choice: Counter = Counter()
    free_prefer: Counter = Counter()
    # Блок 4: физкультура
    pe_pref: Counter = Counter()
    # Блок 5: свободный текст — просто считаем ненулевые ответы
    free_text_count = 0

    for vote in votes:
        for answer in vote.answers:
            data: dict = json.loads(answer.answer_json)
            key = answer.question_key

            if key == "heavy_subjects":
                for subj in heavy:
                    val = data.get(subj)
                    if val is not None:
                        heavy[subj][val] += 1

            elif key == "exams":
                val_max = data.get("max_per_day")
                val_no = data.get("no_mon_fri")
                if val_max is not None:
                    exams_max[str(val_max)] += 1
                if val_no is not None:
                    exams_no_mon[str(val_no)] += 1

            elif key == "free_periods":
                val_choice = data.get("choice")
                val_prefer = data.get("prefer_long")
                if val_choice is not None:
                    free_choice[val_choice] += 1
                if val_prefer is not None:
                    free_prefer[str(val_prefer)] += 1

            elif key == "pe":
                val_pref = data.get("preference")
                if val_pref is not None:
                    pe_pref[val_pref] += 1

            elif key == "free_text":
                if data.get("text"):
                    free_text_count += 1

    return {
        "heavy_subjects": {subj: dict(cnt) for subj, cnt in heavy.items()},
        "exams": {
            "max_per_day": dict(exams_max),
            "no_mon_fri": dict(exams_no_mon),
        },
        "free_periods": {
            "choice": dict(free_choice),
            "prefer_long": dict(free_prefer),
        },
        "pe": {
            "preference": dict(pe_pref),
        },
        "free_text": {
            "responses_count": free_text_count,
        },
    }


# ---------------------------------------------------------------------------
# Публичная функция агрегации
# ---------------------------------------------------------------------------

def aggregate_session_results(db: Session, voting_session_id: int) -> dict | None:
    """
    Собрать агрегированные результаты голосования.

    Возвращает структуру:
    {
        "voting_session": { ... метаданные ... },
        "classes": [
            {"class_id": 1, "class_name": "10В", "vote_count": 12,
             "suppressed": False, "results": { ... }},
            {"class_id": 2, "class_name": "8А", "vote_count": 3,
             "suppressed": True, "reason": "n<5"},
        ],
        "school_totals": { ... итого по школе ... }
    }

    Возвращает None если сессия не найдена.
    """
    session = db.get(VotingSession, voting_session_id)
    if session is None:
        return None

    school = db.get(School, session.school_id)

    # Загружаем все голоса сессии
    all_votes: list[Vote] = (
        db.query(Vote)
        .filter(Vote.voting_session_id == voting_session_id)
        .all()
    )

    # Группируем голоса по class_id
    votes_by_class: dict[int, list[Vote]] = defaultdict(list)
    for vote in all_votes:
        votes_by_class[vote.class_id].append(vote)

    # Получаем все классы школы (в порядке: старшие первые)
    classes: list[Class] = (
        db.query(Class)
        .filter(Class.school_id == session.school_id)
        .order_by(Class.grade, Class.letter)
        .all()
    )

    class_results = []
    for cls in classes:
        class_votes = votes_by_class.get(cls.id, [])
        vote_count = len(class_votes)

        if vote_count < N_MIN:
            # Данные скрыты — защита от деанонимизации
            class_results.append({
                "class_id": cls.id,
                "class_name": cls.name,
                "vote_count": vote_count,
                "suppressed": True,
                "reason": "n<5",
                "results": None,
            })
        else:
            class_results.append({
                "class_id": cls.id,
                "class_name": cls.name,
                "vote_count": vote_count,
                "suppressed": False,
                "reason": None,
                "results": _aggregate_votes(class_votes),
            })

    total_votes = len(all_votes)

    # Итого по школе
    if total_votes >= N_MIN:
        school_totals = {
            "vote_count": total_votes,
            "suppressed": False,
            "reason": None,
            "results": _aggregate_votes(all_votes),
        }
    else:
        school_totals = {
            "vote_count": total_votes,
            "suppressed": True,
            "reason": "n<5",
            "results": None,
        }

    closed_at = session.closed_at
    return {
        "voting_session": {
            "id": session.id,
            "quarter": session.quarter,
            "year": session.year,
            "school_name": school.name,
            "closed_at": closed_at.isoformat() if closed_at else None,
            "total_votes": total_votes,
        },
        "classes": class_results,
        "school_totals": school_totals,
    }


# ---------------------------------------------------------------------------
# Вспомогательная функция: развернуть результаты в плоский список строк для CSV
# ---------------------------------------------------------------------------

def flatten_results_for_csv(aggregated: dict) -> list[dict]:
    """
    Превратить вложенный словарь агрегатов в плоский список строк для CSV.

    Каждая строка: {"class_name", "question_key", "answer_value", "count"}.
    Для suppressed-классов: одна строка с answer_value="[suppressed]" и count="".
    """
    rows = []
    for cls in aggregated["classes"]:
        class_name = cls["class_name"]
        if cls["suppressed"]:
            rows.append({
                "class_name": class_name,
                "question_key": "[suppressed]",
                "answer_value": cls.get("reason", "n<5"),
                "count": "",
            })
            continue

        results = cls["results"]

        # Блок 1: тяжёлые предметы
        for subj, dist in results["heavy_subjects"].items():
            for answer_val, cnt in dist.items():
                rows.append({
                    "class_name": class_name,
                    "question_key": f"heavy_subjects.{subj}",
                    "answer_value": answer_val,
                    "count": cnt,
                })

        # Блок 2: контрольные
        for field, dist in results["exams"].items():
            for answer_val, cnt in dist.items():
                rows.append({
                    "class_name": class_name,
                    "question_key": f"exams.{field}",
                    "answer_value": answer_val,
                    "count": cnt,
                })

        # Блок 3: окна
        for field, dist in results["free_periods"].items():
            for answer_val, cnt in dist.items():
                rows.append({
                    "class_name": class_name,
                    "question_key": f"free_periods.{field}",
                    "answer_value": answer_val,
                    "count": cnt,
                })

        # Блок 4: физкультура
        for answer_val, cnt in results["pe"]["preference"].items():
            rows.append({
                "class_name": class_name,
                "question_key": "pe.preference",
                "answer_value": answer_val,
                "count": cnt,
            })

        # Блок 5: свободный текст (просто счётчик)
        rows.append({
            "class_name": class_name,
            "question_key": "free_text.responses_count",
            "answer_value": "non_empty",
            "count": results["free_text"]["responses_count"],
        })

    return rows
