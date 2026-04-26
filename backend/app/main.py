from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from loguru import logger

from app.routers import admin, auth, health, votes

app = FastAPI(
    title="Likray API",
    description=(
        "Backend для анонимного голосования учеников о школьном расписании. "
        "Гарантирует «верифицированную анонимность»: сервер знает, что голосует "
        "ученик конкретного класса, но не знает кто именно."
    ),
    version="0.1.0",
)

# CORS для Flutter-web и других браузерных клиентов в локальной разработке.
# В продакшене сузить allow_origins до конкретного фронт-домена.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Все роутеры монтируются под единый префикс /api/v1
app.include_router(health.router, prefix="/api/v1")
app.include_router(auth.router,   prefix="/api/v1")
app.include_router(votes.router,  prefix="/api/v1")
app.include_router(admin.router,  prefix="/api/v1")


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Перехватываем необработанные исключения и возвращаем единообразный JSON."""
    logger.exception(f"Необработанная ошибка на {request.method} {request.url}: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "Внутренняя ошибка сервера",
            }
        },
    )
