# Likray — Backend

FastAPI-бэкенд для анонимного голосования учеников о школьном расписании.

## Ключевая идея: «верифицированная анонимность»

Система знает, что голосует ученик **конкретного класса**, но не знает **кто именно**.
Это достигается на уровне схемы БД: между таблицами `access_codes` и `votes`
**нет никакой связи** — ни FK, ни общих полей.

Проверить это вручную:
```sql
-- Открыть БД
sqlite3 likray.db

-- Эти две таблицы не имеют общих столбцов:
.schema access_codes
.schema votes

-- Убедиться, что в votes нет поля access_code_id или user_id:
PRAGMA table_info(votes);
```

---

## Быстрый старт (Windows 11, PowerShell — 10 шагов)

Нужен Python 3.11 или 3.12 ([скачать](https://www.python.org/downloads/windows/) — при установке отметить **«Add python.exe to PATH»**).

```powershell
# 1. Перейти в папку backend
cd backend

# 2. Создать виртуальное окружение
python -m venv .venv

# 3. Активировать окружение (PowerShell)
.\.venv\Scripts\Activate.ps1
# Если PowerShell блокирует выполнение — один раз:
# Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# В cmd.exe вместо этого: .\.venv\Scripts\activate.bat

# 4. Установить зависимости
pip install -r requirements.txt

# 5. Создать файл с настройками
copy .env.example .env
# Отредактировать .env (notepad .env): сгенерировать SECRET_KEY
# python -c "import secrets; print(secrets.token_hex(32))"

# 6. Применить миграции (создаёт файл likray.db)
alembic upgrade head

# 7. Запустить dev-сервер (--host 0.0.0.0 — чтобы был доступен с телефона/эмулятора)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 8. Открыть документацию API в браузере
# http://localhost:8000/docs

# 9. Запустить тесты (переменные окружения для PowerShell)
$env:SECRET_KEY="testtesttest"
$env:ACCESS_TOKEN_EXPIRE_MINUTES="60"
$env:ALGORITHM="HS256"
$env:DATABASE_URL="sqlite:///:memory:"
pytest tests/ -v

# 10. Проверить покрытие
pytest tests/ --cov=app --cov-report=term-missing
```

> **Брандмауэр Windows.** Если бэкенд должен быть доступен реальному Android-телефону по Wi-Fi — открыть порт 8000 (PowerShell от администратора):
> ```powershell
> New-NetFirewallRule -DisplayName "Likray backend (8000)" `
>     -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
> ```
> IP компьютера — через `ipconfig` (поле «IPv4-адрес»).

---

## Структура проекта

```
backend/
├── app/
│   ├── main.py          # FastAPI-приложение, роутеры
│   ├── config.py        # Настройки через pydantic-settings (.env)
│   ├── db.py            # SQLAlchemy engine, SessionLocal, Base
│   ├── security.py      # JWT (admin + anon student), bcrypt
│   ├── deps.py          # FastAPI Depends: get_db, get_current_admin, get_current_student
│   ├── models/
│   │   └── __init__.py  # Все SQLAlchemy-модели (School, Class, Admin, Vote, ...)
│   ├── schemas/
│   │   └── __init__.py  # Pydantic-схемы (добавляются в фазе 2–3)
│   └── routers/
│       ├── health.py    # GET /api/v1/health
│       ├── auth.py      # /api/v1/auth/* (TODO фаза 2)
│       ├── votes.py     # /api/v1/votes/* (TODO фаза 2)
│       └── admin.py     # /api/v1/admin/* (TODO фаза 3)
├── alembic/
│   ├── env.py           # Конфигурация Alembic (читает наш config.py)
│   └── versions/        # Файлы миграций
├── tests/
│   ├── conftest.py      # Фикстуры: in-memory SQLite, TestClient
│   └── test_healthcheck.py
├── alembic.ini
├── requirements.txt
└── .env.example
```

---

## Модели БД

| Таблица | Назначение |
|---|---|
| `schools` | Школы |
| `classes` | Классы (10В, 11А, …) |
| `admins` | Администраторы (завуч, суперадмин) |
| `access_codes` | Одноразовые коды для учеников |
| `voting_sessions` | Сессии голосования (четверть + год) |
| `votes` | Анонимные голоса (**без** FK на `access_codes`) |
| `vote_answers` | Ответы на вопросы анкеты |

---

## API (текущее состояние)

| Метод | Путь | Статус |
|---|---|---|
| GET | `/api/v1/health` | ✅ Реализовано |
| POST | `/api/v1/auth/student/redeem` | ✅ Реализовано |
| POST | `/api/v1/auth/admin/login` | ✅ Реализовано |
| GET | `/api/v1/votes/active` | ✅ Реализовано |
| POST | `/api/v1/votes` | ✅ Реализовано |
| GET/POST | `/api/v1/admin/*` | 🔜 Фаза 3 |

---

## Фронт (Flutter)

### Требования

- Flutter SDK 3.x — на Windows ставится через [Chocolatey](https://chocolatey.org/install): `choco install flutter -y`
- Android Studio + настроенный AVD-эмулятор (либо физическое Android-устройство), при необходимости — Windows desktop target
- Запущенный бэкенд на `localhost:8000`

### Запуск (PowerShell)

```powershell
# 1. Перейти в папку фронта
cd frontend

# 2. Установить зависимости
flutter pub get

# 3. Список устройств
flutter devices

# 4. Запустить на эмуляторе / устройстве
flutter run

# 5. Запустить widget-тесты
flutter test

# 6. Запустить integration-тест (нужен запущенный эмулятор)
flutter test integration_test/full_flow_test.dart
```

### Структура

```
frontend/
  lib/
    main.dart                    # точка входа
    app.dart                     # MaterialApp.router
    core/
      api/                       # Dio + AuthInterceptor + ApiException
      storage/                   # FlutterSecureStorage wrapper
      router/                    # GoRouter
      theme/                     # Material 3 (#3B5BDB)
    features/
      student/                   # Флоу ученика: ввод кода → анкета → спасибо
      admin/                     # Флоу администратора: логин → дашборд → результаты
  test/                          # 4 widget-теста
  integration_test/              # 1 integration-тест (полный флоу ученика)
  pubspec.yaml
```

### Настройка baseUrl

Единственный URL бэкенда задаётся в одном месте:

```dart
// frontend/lib/core/api/api_client.dart
const String kApiBaseUrl = 'http://localhost:8000/api/v1';
```

Для запуска на реальном Android-устройстве замените `localhost` на IP компьютера в локальной сети.
