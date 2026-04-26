from fastapi import APIRouter

router = APIRouter(tags=["system"])


@router.get("/health")
def healthcheck():
    """Проверка работоспособности сервера."""
    return {"status": "ok"}
