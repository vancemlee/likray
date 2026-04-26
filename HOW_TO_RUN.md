# Likray — как запустить с нуля

Простая пошаговая инструкция: берёшь чистый Windows 11, ставишь нужные программы, поднимаешь backend, поднимаешь frontend, проверяешь, что всё работает.

---

## 1. Что в проекте

**Likray** — мобильное приложение для Лицея №131 (Казань), через которое ученики анонимно высказывают пожелания к расписанию на следующую четверть.

Состоит из двух частей:

- **Backend** (`Likray/backend`) — сервер на Python (FastAPI + SQLAlchemy + SQLite). Принимает одноразовые коды от учеников, хранит голоса, выдаёт админу агрегированную статистику. Запускается одной командой `uvicorn`.
- **Frontend** (`Likray/frontend`) — клиент на Flutter (Dart). Один и тот же код собирается под Android, iOS и web. Общается с бэкендом по HTTP-API на `http://localhost:8000/api/v1`.

Главная фича — «верифицированная анонимность»: сервер знает, что ученик класса 10А проголосовал, но **не знает, кто конкретно**. Подробности — в `docs/ARCHITECTURE.md`.

---

## 2. Что должно быть установлено

### Обязательно

- **Python 3.11 или новее** (проверено на 3.13). Скачать: https://www.python.org/downloads/  
  При установке на Windows обязательно поставь галочку **«Add python.exe to PATH»**.  
  Проверка: открой PowerShell и набери `python --version`.

- **Flutter SDK 3.x** (проверено на 3.41.7).  
  Самый простой способ — скачать архив с https://docs.flutter.dev/get-started/install/windows и распаковать в `C:\flutter`. Затем добавить `C:\flutter\bin` в системный PATH (Параметры → Система → Дополнительные параметры → Переменные среды).  
  Проверка: `flutter --version`.

### По желанию

- **Docker Desktop** — если хочешь поднять backend в контейнере одной командой. https://www.docker.com/products/docker-desktop/
- **Android Studio** — если хочешь запускать Flutter-приложение на Android-эмуляторе. https://developer.android.com/studio  
  Без Android Studio можно собрать только web-версию (см. ниже).
- **PyCharm Community** — удобная IDE для Python. https://www.jetbrains.com/pycharm/download/

---

## 3. Запуск backend

В корне проекта уже есть готовый виртуальный venv (`.venv`) рядом с папкой `Likray/`. Он лежит в `C:\Users\MARMOK\PycharmProjects\LIKRAY\.venv`. Если ты переносишь проект в другое место — пересоздай venv: `python -m venv .venv` и поставь зависимости (см. ниже).

Открой PowerShell и выполни:

```powershell
# 1. Перейти в папку backend
cd C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray\backend

# 2. Активировать venv (один раз для текущего окна PowerShell)
..\..\.venv\Scripts\Activate.ps1
# Если PowerShell ругается на «execution policy»:
# Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# 3. Если venv пустой — поставить зависимости:
pip install -r requirements.txt

# 4. Если ещё не сделано — создать .env (уже есть, просто проверь, что файл .env лежит в backend/)
copy .env.example .env
# Открой .env и в SECRET_KEY вставь длинную случайную строку:
# python -c "import secrets; print(secrets.token_hex(32))"

# 5. Применить миграции (создать таблицы в SQLite-базе likray.db)
alembic upgrade head

# 6. Создать первого администратора (Кодировка консоли: важно!)
$env:PYTHONIOENCODING="utf-8"
python cli.py create-superadmin `
    --school-name "Лицей №131" `
    --username admin `
    --password "СильныйПароль123" `
    --full-name "Артемий Веснянкин"

# 7. Запустить сервер
$env:PYTHONIOENCODING="utf-8"
uvicorn app.main:app --reload
```

После запуска открой в браузере:

- **http://localhost:8000/docs** — Swagger UI (интерактивная документация API, можно тыкать прямо из браузера).
- **http://localhost:8000/api/v1/health** — должно вернуть `{"status":"ok"}`.

Логин/пароль администратора, который ты создал на шаге 6, понадобится во фронте.

---

## 4. Запуск frontend (Flutter)

В отдельном окне PowerShell:

```powershell
# 1. Перейти в папку frontend
cd C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray\frontend

# 2. Скачать Dart-зависимости (один раз после клонирования или обновления pubspec.yaml)
flutter pub get

# 3. Посмотреть, какие устройства подключены (эмулятор, телефон, Chrome…)
flutter devices

# 4. Запустить
flutter run
```

Если устройств несколько — Flutter спросит, на каком запускать.

### Варианты запуска

| Где | Команда | Что делать с адресом бэкенда |
|---|---|---|
| Chrome (быстро, без эмулятора) | `flutter run -d chrome` | Оставить `localhost` |
| Windows-десктоп | `flutter run -d windows` | Оставить `localhost` |
| Android-эмулятор (AVD) | `flutter run -d emulator-5554` | См. ниже про **10.0.2.2** |
| Реальный Android | `flutter run -d <id>` | См. ниже про IP компьютера |
| Только сборка web без запуска | `flutter build web` → `build\web\index.html` | Открыть статикой |

### Важно про адрес бэкенда

По умолчанию фронт идёт на `http://localhost:8000/api/v1`. Это правильно для Chrome и Windows-десктопа.

Для **Android-эмулятора** localhost = сам эмулятор, не твой компьютер. Замени адрес в файле `frontend/lib/core/api/api_client.dart`:

```dart
const String kApiBaseUrl = 'http://10.0.2.2:8000/api/v1';   // вместо localhost
```

Для **реального телефона** возьми IPv4-адрес компьютера (`ipconfig` в PowerShell, ищи `192.168.x.x`) и пропиши его вместо `localhost`. И запускай бэкенд так, чтобы он слушал не только loopback:

```powershell
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Плюс открой порт 8000 в Брандмауэре (PowerShell от админа):
```powershell
New-NetFirewallRule -DisplayName "Likray (8000)" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

### Полный сценарий проверки

1. На фронте открывается экран ввода кода → перейди в админку (внизу есть кнопка/ссылка) → залогинься (`admin` / тот пароль, что ты задал).
2. В админке нажми FAB **«Новый класс»** → создай класс «10А».
3. Открой меню класса → «Коды» → сгенерируй 5 кодов и сохрани их.
4. Из админки перейди в «Сессии голосования» → создай сессию (например, 2 четверть, 2026 год) → нажми «Открыть».
5. Выйди из админки → введи один из кодов → заполни анкету → отправь.
6. Залогинься обратно в админку → «Результаты» → выбери активную сессию. Если проголосовало ≥ 5 — увидишь графики, иначе — плашку «Данные скрыты (n<5)».

---

## 5. Запуск через Docker (опционально)

Если поставлен Docker Desktop:

```powershell
cd C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray
docker compose up -d --build
```

Что произойдёт:
- Соберётся образ `likray-backend:latest` (Python 3.12-slim + DejaVu Sans для кириллицы в PDF).
- Запустится контейнер на порту **8000**.
- При первом запуске entrypoint сам прогонит миграции и создаст администратора `admin` / `admin` (пароль можно поменять через переменную `LIKRAY_ADMIN_PASSWORD` в `docker-compose.yml`).
- БД сохраняется в named-volume `likray-data` — переживёт рестарт контейнера.

Логи: `docker compose logs -f backend`. Остановить: `docker compose down`. Полный сброс с очисткой БД: `docker compose down -v`.

---

## 6. Тесты

### Backend (pytest)

```powershell
cd C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray\backend
$env:SECRET_KEY="testtesttest"
$env:ACCESS_TOKEN_EXPIRE_MINUTES="60"
$env:ALGORITHM="HS256"
$env:DATABASE_URL="sqlite:///:memory:"
$env:PYTHONIOENCODING="utf-8"
pytest -v
```

Должно быть **30 passed**.

### Frontend (flutter test)

```powershell
cd C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray\frontend
flutter test
```

Должно быть **15 passed** (widget-тесты экранов и виджетов). `flutter analyze` тоже должен пройти без ошибок (могут быть `info`-сообщения про deprecated API — это норма для свежих версий Flutter).

---

## 7. Структура проекта

```
LIKRAY/                                  ← корневая папка проекта в PyCharm
├── .venv/                               ← Python virtualenv (общий для бэка)
└── Likray/
    ├── backend/                         ← сервер FastAPI
    │   ├── app/                         ← код приложения
    │   │   ├── routers/                 ← REST-эндпоинты (auth, votes, admin, health)
    │   │   ├── schemas/                 ← Pydantic-модели запросов/ответов
    │   │   ├── models/                  ← SQLAlchemy ORM-модели
    │   │   ├── main.py                  ← точка входа FastAPI
    │   │   └── ...
    │   ├── alembic/versions/            ← миграции БД
    │   ├── tests/                       ← pytest-тесты (30 шт.)
    │   ├── cli.py                       ← создание админа из командной строки
    │   ├── requirements.txt             ← зависимости Python
    │   ├── Dockerfile                   ← сборка контейнера
    │   ├── docker-entrypoint.sh         ← скрипт запуска в контейнере
    │   ├── likray.db                    ← SQLite-база (создаётся при первом запуске)
    │   └── .env                         ← локальные настройки (SECRET_KEY и пр.)
    │
    ├── frontend/                        ← Flutter-клиент
    │   ├── lib/
    │   │   ├── main.dart                ← точка входа
    │   │   ├── app.dart                 ← корневой виджет
    │   │   ├── core/                    ← API-клиент, роутер, тема, токен-хранилище
    │   │   └── features/
    │   │       ├── student/             ← поток ученика (ввод кода → анкета → спасибо)
    │   │       └── admin/               ← поток администратора (классы, сессии, результаты)
    │   ├── test/                        ← widget-тесты (15 шт.)
    │   ├── integration_test/            ← полный e2e-сценарий ученика
    │   └── pubspec.yaml                 ← зависимости Dart
    │
    ├── docs/
    │   ├── ARCHITECTURE.md              ← как устроена анонимность (для защиты)
    │   └── DOD.md                       ← Definition of Done — что готово
    │
    ├── docker-compose.yml               ← запуск backend в контейнере
    ├── README.md                        ← оригинальный README проекта
    └── HOW_TO_RUN.md                    ← этот файл
```

---

## 8. Как открыть в PyCharm

1. **File → Open** → выбери папку `C:\Users\MARMOK\PycharmProjects\LIKRAY` (корень с `.venv` и `Likray/`). Не открывай отдельно `backend` — PyCharm не увидит venv.

2. PyCharm спросит про интерпретатор. **File → Settings → Project: LIKRAY → Python Interpreter** → шестерёнка → **Add Interpreter → Add Local Interpreter → Existing** → выбери:
   ```
   C:\Users\MARMOK\PycharmProjects\LIKRAY\.venv\Scripts\python.exe
   ```
   Внизу справа в статус-баре должно появиться `Python 3.13 (.venv)`.

3. **Запустить uvicorn кнопкой Run:**
   - Открой `Likray/backend/app/main.py` (любым способом — в дереве слева или через `Ctrl+Shift+N`).
   - Сверху справа кнопка ▶ → **Edit Configurations…** → **+ → Python**.
   - Заполни:
     - **Name:** `uvicorn`
     - **Module name:** `uvicorn` (не Script path)
     - **Parameters:** `app.main:app --reload`
     - **Working directory:** `C:\Users\MARMOK\PycharmProjects\LIKRAY\Likray\backend`
     - **Environment variables:** `PYTHONIOENCODING=utf-8`
   - OK → нажми ▶ Run. В нижней панели должно появиться `Uvicorn running on http://127.0.0.1:8000`.

4. **Запустить тесты** — правый клик на папке `Likray/backend/tests` → **Run 'pytest in tests'**.

5. **Flutter в PyCharm** работает через плагин «Flutter» (Settings → Plugins → Marketplace → Flutter). После установки PyCharm подхватит SDK из PATH (или укажешь путь руками: `C:\flutter`). Дальше так же — открыть `Likray/frontend/lib/main.dart`, ▶ → выбрать устройство.

   Удобнее, конечно, открыть `Likray/frontend` отдельно в **Android Studio** или **VS Code** — у них поддержка Flutter «из коробки». Но и в PyCharm заработает.

---

## Если что-то не работает

- **`python` не найден** — переустанови с галочкой «Add to PATH» либо отключи Microsoft Store-заглушку (Параметры → Приложения → Дополнительные параметры приложений → Псевдонимы выполнения).
- **`flutter` не найден** — закрой PowerShell и открой заново после правки PATH; либо проверь, что `C:\flutter\bin` есть в `$env:Path`.
- **Порт 8000 занят** — `Get-NetTCPConnection -LocalPort 8000 | Select OwningProcess | ForEach { Stop-Process -Id $_.OwningProcess -Force }` или запусти uvicorn на другом порту (`--port 8001` + поправь `kApiBaseUrl` во фронте).
- **`alembic upgrade head` ругается «no such table»** — удали `likray.db` и прогони alembic ещё раз (`Remove-Item likray.db; alembic upgrade head; python cli.py create-superadmin ...`).
- **Кириллица в консоли — кракозябры** — всегда задавай `$env:PYTHONIOENCODING="utf-8"` перед запуском Python-команд, которые что-то печатают по-русски.
- **Android-эмулятор не видит сервер** — это норма, замени `localhost` на `10.0.2.2` (см. раздел 4).

Полный список частых проблем — в основном `README.md`.
