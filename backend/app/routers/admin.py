"""
Роутер администратора (фаза 3).

Все эндпоинты требуют admin JWT (зависимость get_current_admin).
Каждый эндпоинт дополнительно проверяет, что запрашиваемые данные
принадлежат школе этого администратора (school_id из токена).

Эндпоинты:
  POST /admin/classes/{class_id}/codes/generate — сгенерировать коды
  GET  /admin/classes/{class_id}/codes          — список кодов класса
  POST /admin/voting-sessions                   — создать сессию
  POST /admin/voting-sessions/{id}/open         — открыть сессию
  POST /admin/voting-sessions/{id}/close        — закрыть сессию
  GET  /admin/voting-sessions/{id}/results      — агрегированные результаты
  GET  /admin/voting-sessions/{id}/export/csv   — экспорт CSV
  GET  /admin/voting-sessions/{id}/export/pdf   — экспорт PDF
"""

import csv
import io
import os
import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.aggregation import aggregate_session_results, flatten_results_for_csv
from app.deps import get_current_admin, get_db
from app.models import AccessCode, Class, VotingSession
from app.schemas.admin import (
    ClassResponse,
    CodeListResponse,
    CodeItem,
    CreateClassRequest,
    CreateVotingSessionRequest,
    GenerateCodesRequest,
    GenerateCodesResponse,
    ResultsResponse,
    VotingSessionResponse,
)

router = APIRouter(prefix="/admin", tags=["admin"])

# Символы без визуально похожих: исключены 0, O, I, 1, l
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def _generate_code() -> str:
    """Сгенерировать читаемый 8-символьный код вида XXXX-XXXX."""
    part1 = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))
    part2 = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))
    return f"{part1}-{part2}"


def _get_class_or_403(db: Session, class_id: int, admin_school_id: int) -> Class:
    """
    Найти класс по id и проверить что он принадлежит школе администратора.
    Бросает 404 если класс не существует, 403 если принадлежит другой школе.
    """
    school_class = db.get(Class, class_id)
    if school_class is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "CLASS_NOT_FOUND", "message": "Класс не найден"},
        )
    if school_class.school_id != admin_school_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "WRONG_SCHOOL",
                "message": "Класс принадлежит другой школе",
            },
        )
    return school_class


def _get_session_or_403(db: Session, session_id: int, admin_school_id: int) -> VotingSession:
    """Аналогично для VotingSession."""
    vs = db.get(VotingSession, session_id)
    if vs is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "SESSION_NOT_FOUND", "message": "Сессия не найдена"},
        )
    if vs.school_id != admin_school_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "WRONG_SCHOOL", "message": "Сессия принадлежит другой школе"},
        )
    return vs


# ---------------------------------------------------------------------------
# GET /admin/classes — список классов школы администратора
# ---------------------------------------------------------------------------

def _class_to_response(c: Class) -> ClassResponse:
    return ClassResponse(
        id=c.id,
        school_id=c.school_id,
        name=c.name,  # computed property "10А"
        grade=c.grade,
        letter=c.letter,
    )


@router.get("/classes", response_model=list[ClassResponse])
def list_classes(
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Список классов школы текущего администратора."""
    school_id = admin_data["school_id"]
    classes = (
        db.query(Class)
        .filter(Class.school_id == school_id)
        .order_by(Class.grade, Class.letter)
        .all()
    )
    return [_class_to_response(c) for c in classes]


# ---------------------------------------------------------------------------
# POST /admin/classes — создать класс в школе администратора
# ---------------------------------------------------------------------------

@router.post(
    "/classes",
    response_model=ClassResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_class(
    payload: CreateClassRequest,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Создать новый класс. Дубликаты (grade, letter) для одной школы запрещены."""
    school_id = admin_data["school_id"]
    letter = payload.letter.strip()

    existing = (
        db.query(Class)
        .filter(
            Class.school_id == school_id,
            Class.grade == payload.grade,
            Class.letter == letter,
        )
        .first()
    )
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "CLASS_ALREADY_EXISTS",
                "message": f"Класс {payload.grade}{letter} уже существует",
            },
        )

    c = Class(school_id=school_id, grade=payload.grade, letter=letter)
    db.add(c)
    db.commit()
    db.refresh(c)
    return _class_to_response(c)


# ---------------------------------------------------------------------------
# POST /admin/classes/{class_id}/codes/generate
# ---------------------------------------------------------------------------

@router.post(
    "/classes/{class_id}/codes/generate",
    response_model=GenerateCodesResponse,
    status_code=status.HTTP_201_CREATED,
)
def generate_codes(
    class_id: int,
    payload: GenerateCodesRequest,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    Сгенерировать одноразовые коды для класса.

    Генерация криптографически безопасная (secrets.choice).
    Коды уникальны в рамках всей БД — при коллизии пробуем снова.
    Возвращает плейн-коды ОДИН РАЗ — больше восстановить нельзя.
    """
    school_class = _get_class_or_403(db, class_id, admin_data["school_id"])
    admin_id = int(admin_data["sub"])

    generated_codes: list[str] = []
    # Генерируем коды по одному, проверяя уникальность в БД
    while len(generated_codes) < payload.count:
        code_str = _generate_code()

        # Проверяем что такого кода ещё нет в БД
        if db.query(AccessCode).filter(AccessCode.code == code_str).first() is not None:
            continue  # коллизия — крайне редко, но обрабатываем

        db.add(AccessCode(
            class_id=school_class.id,
            code=code_str,
            is_used=False,
            created_by_admin_id=admin_id,
        ))
        generated_codes.append(code_str)

    db.commit()

    return GenerateCodesResponse(codes=generated_codes, count=len(generated_codes))


# ---------------------------------------------------------------------------
# GET /admin/classes/{class_id}/codes
# ---------------------------------------------------------------------------

@router.get("/classes/{class_id}/codes", response_model=CodeListResponse)
def list_codes(
    class_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Список всех кодов класса с их статусом — для аудита."""
    _get_class_or_403(db, class_id, admin_data["school_id"])

    codes = (
        db.query(AccessCode)
        .filter(AccessCode.class_id == class_id)
        .order_by(AccessCode.created_at)
        .all()
    )

    return CodeListResponse(
        class_id=class_id,
        codes=[CodeItem.model_validate(c) for c in codes],
        total=len(codes),
    )


# ---------------------------------------------------------------------------
# GET /admin/voting-sessions — список сессий школы
# ---------------------------------------------------------------------------

@router.get("/voting-sessions", response_model=list[VotingSessionResponse])
def list_voting_sessions(
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Все сессии голосования школы администратора (от новых к старым)."""
    school_id = admin_data["school_id"]
    sessions = (
        db.query(VotingSession)
        .filter(VotingSession.school_id == school_id)
        .order_by(VotingSession.id.desc())
        .all()
    )
    return [VotingSessionResponse.model_validate(s) for s in sessions]


# ---------------------------------------------------------------------------
# POST /admin/voting-sessions
# ---------------------------------------------------------------------------

@router.post(
    "/voting-sessions",
    response_model=VotingSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_voting_session(
    payload: CreateVotingSessionRequest,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    Создать новую сессию голосования.

    Нельзя создать вторую открытую сессию для той же школы:
    это запутает учеников и нарушит логику активации кодов.
    """
    school_id = admin_data["school_id"]

    # Проверяем что нет уже открытой сессии
    existing_open = (
        db.query(VotingSession)
        .filter(
            VotingSession.school_id == school_id,
            VotingSession.is_open == True,  # noqa: E712
        )
        .first()
    )
    if existing_open is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": "SESSION_ALREADY_OPEN",
                "message": "Уже есть открытая сессия голосования для этой школы",
            },
        )

    vs = VotingSession(
        school_id=school_id,
        quarter=payload.quarter,
        year=payload.year,
        is_open=False,
    )
    db.add(vs)
    db.commit()
    db.refresh(vs)

    return VotingSessionResponse.model_validate(vs)


# ---------------------------------------------------------------------------
# POST /admin/voting-sessions/{id}/open
# ---------------------------------------------------------------------------

@router.post("/voting-sessions/{session_id}/open", response_model=VotingSessionResponse)
def open_voting_session(
    session_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Открыть сессию голосования (is_open=True, opened_at=now)."""
    vs = _get_session_or_403(db, session_id, admin_data["school_id"])

    if vs.is_open:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "ALREADY_OPEN", "message": "Сессия уже открыта"},
        )

    vs.is_open = True
    vs.opened_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(vs)

    return VotingSessionResponse.model_validate(vs)


# ---------------------------------------------------------------------------
# POST /admin/voting-sessions/{id}/close
# ---------------------------------------------------------------------------

@router.post("/voting-sessions/{session_id}/close", response_model=VotingSessionResponse)
def close_voting_session(
    session_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Закрыть сессию голосования (is_open=False, closed_at=now)."""
    vs = _get_session_or_403(db, session_id, admin_data["school_id"])

    if not vs.is_open:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"code": "ALREADY_CLOSED", "message": "Сессия уже закрыта"},
        )

    vs.is_open = False
    vs.closed_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(vs)

    return VotingSessionResponse.model_validate(vs)


# ---------------------------------------------------------------------------
# GET /admin/voting-sessions/{id}/results
# ---------------------------------------------------------------------------

@router.get("/voting-sessions/{session_id}/results", response_model=ResultsResponse)
def get_session_results(
    session_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    Агрегированные результаты сессии с защитой n<5.

    Если в классе проголосовало <5 учеников — данные скрыты,
    возвращается {"suppressed": true, "reason": "n<5"}.
    """
    _get_session_or_403(db, session_id, admin_data["school_id"])

    aggregated = aggregate_session_results(db, session_id)
    if aggregated is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "SESSION_NOT_FOUND", "message": "Сессия не найдена"},
        )

    return ResultsResponse(**aggregated)


# ---------------------------------------------------------------------------
# GET /admin/voting-sessions/{id}/export/csv
# ---------------------------------------------------------------------------

@router.get("/voting-sessions/{session_id}/export/csv")
def export_csv(
    session_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    Экспорт агрегированных результатов в CSV.

    Колонки: class_name, question_key, answer_value, count.
    Для suppressed-классов строка с answer_value="[suppressed]".
    """
    _get_session_or_403(db, session_id, admin_data["school_id"])

    aggregated = aggregate_session_results(db, session_id)
    if aggregated is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "SESSION_NOT_FOUND", "message": "Сессия не найдена"},
        )

    rows = flatten_results_for_csv(aggregated)

    # Собираем CSV в памяти через io.StringIO → StreamingResponse
    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=["class_name", "question_key", "answer_value", "count"],
        lineterminator="\r\n",
    )
    writer.writeheader()
    writer.writerows(rows)

    meta = aggregated["voting_session"]
    filename = f"likray_q{meta['quarter']}_{meta['year']}.csv"

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


# ---------------------------------------------------------------------------
# GET /admin/voting-sessions/{id}/export/pdf
# ---------------------------------------------------------------------------

def _get_cyrillic_font() -> str:
    """
    Найти шрифт с поддержкой кириллицы на системе.
    Возвращает имя зарегистрированного шрифта (или встроенный Times-Roman).
    """
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    # Кандидаты на разных ОС (Linux, macOS, Windows)
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
        "/opt/homebrew/share/fonts/dejavu-fonts/DejaVuSans.ttf",
        "C:\\Windows\\Fonts\\arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                pdfmetrics.registerFont(TTFont("CyrillicFont", path))
                return "CyrillicFont"
            except Exception:
                continue
    # Fallback: встроенный Helvetica (кириллица не отобразится, но PDF валиден)
    return "Helvetica"


@router.get("/voting-sessions/{session_id}/export/pdf")
def export_pdf(
    session_id: int,
    admin_data: dict = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """
    Экспорт PDF-отчёта с агрегированными результатами.

    Поддержка кириллицы: пробуем DejaVuSans/Arial, fallback на Helvetica.
    Структура: заголовок → school/четверть/дата → по каждому классу таблица.
    """
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.lib.units import cm
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    _get_session_or_403(db, session_id, admin_data["school_id"])

    aggregated = aggregate_session_results(db, session_id)
    if aggregated is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "SESSION_NOT_FOUND", "message": "Сессия не найдена"},
        )

    font_name = _get_cyrillic_font()
    styles = getSampleStyleSheet()

    # Переопределяем шрифт в стилях под кириллицу
    for style in styles.byName.values():
        style.fontName = font_name

    meta = aggregated["voting_session"]
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, rightMargin=2 * cm, leftMargin=2 * cm)

    story = []

    # Заголовок
    story.append(Paragraph(
        f"Отчёт о голосовании — {meta['school_name']}",
        styles["Title"],
    ))
    story.append(Paragraph(
        f"Четверть {meta['quarter']}, {meta['year']} г. "
        f"| Закрыта: {meta['closed_at'] or 'не закрыта'} "
        f"| Голосов: {meta['total_votes']}",
        styles["Normal"],
    ))
    story.append(Spacer(1, 0.5 * cm))

    # Данные по каждому классу
    for cls in aggregated["classes"]:
        story.append(Paragraph(f"Класс {cls['class_name']} — голосов: {cls['vote_count']}", styles["Heading2"]))

        if cls["suppressed"]:
            story.append(Paragraph("Данные скрыты (n&lt;5) — недостаточно участников", styles["Normal"]))
            story.append(Spacer(1, 0.3 * cm))
            continue

        # Таблица по блокам
        results = cls["results"]
        table_data = [["Вопрос", "Ответ", "Кол-во"]]

        # Блок 1: тяжёлые предметы
        for subj, dist in results["heavy_subjects"].items():
            for val, cnt in sorted(dist.items()):
                table_data.append([f"heavy_subjects.{subj}", val, str(cnt)])

        # Блок 2: контрольные
        for field, dist in results["exams"].items():
            for val, cnt in sorted(dist.items()):
                table_data.append([f"exams.{field}", val, str(cnt)])

        # Блок 3: окна
        for field, dist in results["free_periods"].items():
            for val, cnt in sorted(dist.items()):
                table_data.append([f"free_periods.{field}", val, str(cnt)])

        # Блок 4: физкультура
        for val, cnt in sorted(results["pe"]["preference"].items()):
            table_data.append(["pe.preference", val, str(cnt)])

        # Блок 5: свободный текст
        table_data.append([
            "free_text.responses_count",
            "non_empty",
            str(results["free_text"]["responses_count"]),
        ])

        tbl = Table(table_data, colWidths=[9 * cm, 5 * cm, 3 * cm])
        tbl.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
            ("TEXTCOLOR",  (0, 0), (-1, 0), colors.whitesmoke),
            ("FONTNAME",   (0, 0), (-1, -1), font_name),
            ("FONTSIZE",   (0, 0), (-1, -1), 9),
            ("GRID",       (0, 0), (-1, -1), 0.5, colors.black),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.lightgrey]),
        ]))
        story.append(tbl)
        story.append(Spacer(1, 0.5 * cm))

    doc.build(story)
    buffer.seek(0)

    filename = f"likray_q{meta['quarter']}_{meta['year']}.pdf"
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
