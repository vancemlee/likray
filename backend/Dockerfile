FROM python:3.12-slim

# Шрифт с кириллицей для PDF-экспорта (reportlab ищет DejaVuSans в /usr/share/fonts).
RUN apt-get update \
    && apt-get install -y --no-install-recommends fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DATABASE_URL=sqlite:////data/likray.db \
    ALGORITHM=HS256 \
    ACCESS_TOKEN_EXPIRE_MINUTES=60 \
    PORT=8000

# Сначала только requirements — этот слой кэшируется между сборками.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Затем остальной код.
COPY . .

RUN chmod +x docker-entrypoint.sh \
    && mkdir -p /data

# Том для SQLite-базы, чтобы данные пережили рестарт контейнера.
VOLUME ["/data"]

EXPOSE 8000

# Render инжектит $PORT — uvicorn должен слушать именно его.
# `sh -c` нужен, чтобы переменная развернулась во время старта контейнера, а не в build-time.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
