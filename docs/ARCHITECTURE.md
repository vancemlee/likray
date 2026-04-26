# Likray — архитектура и разбор решений

## Для кого этот документ

Это шпаргалка к защите проекта. Здесь объяснено каждое неочевидное решение простым языком — так, чтобы на любой вопрос комиссии можно было ответить уверенно. Читать лучше вместе с кодом, потому что все примеры взяты из реального проекта, а не придуманы для красоты.

---

## Что это за приложение (одним абзацем)

Likray — веб-сервис для анонимного анкетирования школьников о расписании уроков. Ученик получает от завуча одноразовый бумажный код, вводит его в приложение, заполняет анкету из 5 блоков (когда ставить тяжёлые предметы, сколько контрольных в день и т.д.) и нажимает «Отправить». Завуч видит только сводную статистику по классу — кто конкретно что ответил, узнать невозможно даже технически, потому что сервер просто не хранит эту связь.

---

## Главная идея: верифицированная анонимность

**Проблема.** Хочется одновременно:
1. Чтобы каждый ученик мог проголосовать только один раз (верификация).
2. Чтобы нельзя было узнать, кто как проголосовал (анонимность).

На первый взгляд это противоречие: чтобы проверить «не голосовал ли этот ученик раньше», надо его как-то идентифицировать. Но Likray решает это разделяя два события **во времени**.

**Как это работает:**

```
Ученик вводит код ABC-XYZ
       ↓
Сервер помечает код как использованный (commit 1)
       ↓
Сервер выдаёт JWT-токен (class_id=10, session_id=3, jti=uuid)
       ↓
Ученик заполняет анкету и отправляет токен
       ↓
Сервер создаёт Vote(class_id=10) — БЕЗ ССЫЛКИ на код ABC-XYZ (commit 2)
```

Что знает сервер после этого:
- «Код ABC-XYZ был использован» — да, это в таблице `access_codes`.
- «От класса 10В поступил голос» — да, это в таблице `votes`.
- «Кто именно из 10В подал этот голос» — **нет, связи не существует**.

Ключевое: между `access_codes` и `votes` нет никакого внешнего ключа (FK), нет общего поля. Даже имея полный дамп базы данных, следователь не сможет построить таблицу «ученик → голос».

---

## Почему у AccessCode и Vote нет FK друг на друга

Из файла `backend/app/models/__init__.py`, строки 99–128:

```python
class AccessCode(Base):
    __tablename__ = "access_codes"
    id: Mapped[int] = mapped_column(primary_key=True)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"), ...)
    code: Mapped[str] = mapped_column(String(20), unique=True, ...)
    is_used: Mapped[bool] = mapped_column(Boolean, ...)
    used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    # !! НЕТ FK на таблицу votes — это намеренно!
    # Связь «код → голос» не хранится нигде в БД.
```

```python
class Vote(Base):
    __tablename__ = "votes"
    id: Mapped[int] = mapped_column(primary_key=True)
    class_id: Mapped[int] = mapped_column(ForeignKey("classes.id"), ...)
    voting_session_id: Mapped[int] = mapped_column(ForeignKey("voting_sessions.id"), ...)
    # !! НЕТ FK на access_codes — это намеренно! Анонимность гарантируется схемой.
    # !! НЕТ user_id — это намеренно!
```

Чтобы связать код и голос, злоумышленнику потребовалась бы хоть какая-то точка соприкосновения. Её нет. Даже SQL-запрос «найди голос, который отправил ученик с кодом X» технически невозможен:

```sql
-- Этот запрос НИЧЕГО не вернёт — колонки vote_id в access_codes нет:
SELECT v.*
FROM access_codes ac
JOIN votes v ON v.??? = ac.???  -- не существует такой колонки
WHERE ac.code = 'ABC-XYZ';
```

---

## Почему redeem двухэтапный (два коммита)

Из файла `backend/app/routers/auth.py`, строки 22–91:

```python
@router.post("/student/redeem")
def student_redeem(payload: StudentRedeemRequest, db: Session = Depends(get_db)):
    """
    Порядок намеренно двухэтапный (инвариант анонимности):

    ШАГ 1 — найти и заблокировать код: транзакция завершается коммитом.
             После этого код помечен как использованный — необратимо.

    ШАГ 2 — сгенерировать JWT: происходит ПОСЛЕ первого коммита.
             JWT — это чистое вычисление, не обращение к БД.
    """
    # ... поиск кода, проверки ...

    # ШАГ 1: первый коммит
    code_record.is_used = True
    code_record.used_at = datetime.now(timezone.utc)
    db.commit()  # ← точка разрыва

    # ШАГ 2: генерация JWT — уже вне транзакции
    token = create_anon_student_token(
        class_id=code_record.class_id,
        voting_session_id=voting_session.id,
    )
```

**Зачем разрывать на два commit?** SQLite использует WAL-журнал (Write-Ahead Log) — файл, куда сначала пишутся изменения до их попадания в основную базу. Если бы оба действия (пометить код + информация о сессии) были в одной транзакции, в WAL оказались бы рядом записи «код N помечен в 14:03:52.001» и «voting_session_id=3 используется». Разделив коммиты, мы разрываем временную близость этих записей и исключаем теоретическую возможность корреляции.

---

## JWT: два типа, два контекста

В проекте два вида токенов, и они намеренно разные.

**Admin Token** (файл `backend/app/security.py`, строки 55–73):
```python
payload = {
    "sub": str(admin_id),   # id администратора
    "role": role,           # "vicerector" или "superadmin"
    "school_id": school_id, # школа — чтобы фильтровать данные
    "type": "admin",
    "exp": expire,
    "jti": str(uuid.uuid4()),
}
```

**Student Token** (строки 76–98):
```python
payload = {
    "class_id": class_id,               # класс — не ученик!
    "voting_session_id": voting_session_id,
    "type": "student",
    "exp": expire,
    "jti": str(uuid.uuid4()),  # уникальный ID токена — для однократного использования
}
```

Обратите внимание: в student-токене **нет** `sub`, нет `user_id`, нет `code_id`. Токен удостоверяет только принадлежность к классу, но не личность ученика. Даже перехватив токен в сети, атакующий не узнает кто его владелец.

`jti` (JWT ID) — случайный UUID, уникальный для каждой выдачи. После голосования он записывается в таблицу `used_tokens`. Следующий запрос с тем же токеном будет отклонён.

---

## Защита от двойного голосования: used_tokens

Модель из `backend/app/models/__init__.py`, строки 200–215:

```python
class UsedToken(Base):
    """Таблица инвалидированных student-токенов."""
    __tablename__ = "used_tokens"

    jti: Mapped[str] = mapped_column(String(36), primary_key=True)
    used_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
```

`jti` — первичный ключ, что означает: один токен = одна запись, коллизии исключены на уровне БД.

Когда ученик успешно голосует (файл `backend/app/routers/votes.py`, строки 60–124):

```python
# Создаём голос и инвалидируем токен в ОДНОЙ транзакции
vote = Vote(class_id=class_id, voting_session_id=voting_session_id)
db.add(vote)
db.flush()
# ... добавляем ответы ...
db.add(UsedToken(jti=jti))
db.commit()  # либо оба записались, либо ни один
```

Атомарность важна: если после записи Vote сервер упадёт до записи UsedToken, ученик смог бы проголосовать повторно. `db.flush()` + единый `db.commit()` гарантируют, что этого не случится.

Зависимость `get_current_student` проверяет `used_tokens` **перед каждым запросом** (файл `backend/app/deps.py`, строки 42–76):

```python
jti = payload.get("jti")
if jti and db.get(UsedToken, jti) is not None:
    raise HTTPException(401, "TOKEN_ALREADY_USED")
```

---

## Анкета v1: 5 блоков вопросов

Структура анкеты определена в `backend/app/schemas/votes.py`. Блоки:

| № | Ключ | Что спрашиваем | Тип ответа |
|---|------|-----------------|------------|
| 1 | `heavy_subjects` | Когда ставить математику, физику, химию, информатику, иностранный | Выбор из 4 вариантов (1–2 урок / 3–4 / 5–6 / не важно) |
| 2 | `exams` | Сколько контрольных в день, нужны ли свободные пн/пт | Число 1–4 + да/нет |
| 3 | `free_periods` | Допустимое количество окон в расписании | Выбор + чекбокс |
| 4 | `pe` | Когда ставить физкультуру | Выбор из 4 вариантов |
| 5 | `free_text` | Свободное пожелание | Текст до 280 символов |

Каждый голос хранится как набор записей в таблице `vote_answers`. На каждый блок — одна запись:

```
vote_answers:
  vote_id=42, question_key="heavy_subjects",
    answer_json='{"math":"lessons_1_2","physics":"any",...}'
  vote_id=42, question_key="exams",
    answer_json='{"max_per_day":2,"no_mon_fri":true}'
  ...
```

Такая денормализация позволяет добавлять новые блоки в анкету v2 без изменения схемы БД.

Блок 5 проходит **модерацию** (файл `backend/app/moderation.py`): если текст содержит стоп-слово — поле очищается, но голос сохраняется. Ученик об этом не узнаёт.

---

## Защита n<5 в агрегаторе

**Атака:** если в классе из 3 учеников проголосовали двое, и один из них — ты, то ты знаешь, что второй ответ принадлежит одному из двух конкретных одноклассников. При достаточной корреляции это деанонимизация.

**Решение:** если в классе проголосовало строго меньше 5 учеников, данные по этому классу **не выдаются вообще**. Вместо них — маркер:

```python
# backend/app/aggregation.py, строки ~80–90
N_MIN = 5

if vote_count < N_MIN:
    class_results.append({
        "class_id": cls.id,
        "class_name": cls.name,
        "vote_count": vote_count,
        "suppressed": True,
        "reason": "n<5",
        "results": None,
    })
```

Это правило одинаково работает в JSON-ответе (`GET /results`), CSV-экспорте и PDF-отчёте — логика живёт в одном модуле `app/aggregation.py`, а не дублируется по роутерам.

---

## Структура проекта (дерево папок с пояснением)

```
Likray/
└── backend/
    ├── app/
    │   ├── main.py          — создание FastAPI, подключение роутеров
    │   ├── config.py        — настройки из .env (SECRET_KEY и т.д.)
    │   ├── db.py            — SQLAlchemy engine + Base + SessionLocal
    │   ├── deps.py          — FastAPI Depends: get_db, get_current_admin, get_current_student
    │   ├── security.py      — bcrypt (хеш паролей) + JWT (создание / проверка)
    │   ├── moderation.py    — фильтр стоп-слов для блока free_text
    │   ├── aggregation.py   — подсчёт результатов голосования + правило n<5
    │   ├── models/
    │   │   └── __init__.py  — все SQLAlchemy-модели (School, Class, Admin, ...)
    │   ├── schemas/
    │   │   ├── auth.py      — Pydantic-схемы для /auth/*
    │   │   ├── votes.py     — схемы для /votes/* + определение QUESTIONNAIRE_V1
    │   │   └── admin.py     — схемы для /admin/* (генерация кодов, результаты)
    │   └── routers/
    │       ├── health.py    — GET /health
    │       ├── auth.py      — POST /auth/student/redeem, POST /auth/admin/login
    │       ├── votes.py     — GET /votes/active, POST /votes
    │       └── admin.py     — все эндпоинты администратора
    ├── alembic/             — миграции базы данных
    ├── tests/
    │   ├── conftest.py      — фикстуры pytest (engine, db_session, client, school, ...)
    │   ├── test_admin.py    — тесты admin-панели
    │   ├── test_auth.py     — тесты аутентификации
    │   ├── test_votes.py    — тесты голосования
    │   ├── test_cli.py      — тесты CLI
    │   └── test_healthcheck.py
    ├── cli.py               — create-superadmin команда
    └── requirements.txt
```

---

## Как запустить у себя (Windows 11, PowerShell)

Целевая машина — Windows 11 + PowerShell. Нужен Python 3.11/3.12 ([python.org](https://www.python.org/downloads/windows/), при установке отметить «Add python.exe to PATH») и Git for Windows.

```powershell
# 1. Склонировать репозиторий
git clone <url>
cd Likray\backend

# 2. Создать виртуальное окружение и активировать
python -m venv .venv
.\.venv\Scripts\Activate.ps1
# Если PowerShell блокирует выполнение — один раз:
# Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# 3. Установить зависимости
pip install -r requirements.txt

# 4. Создать файл с настройками
copy .env.example .env
# Отредактировать .env (notepad .env): задать SECRET_KEY, DATABASE_URL

# 5. Создать базу данных (применить миграции)
alembic upgrade head

# 6. Создать первого администратора (` — перенос строки в PowerShell)
python cli.py create-superadmin `
    --school-name "Лицей №131" `
    --username admin `
    --password "сильныйПароль123" `
    --full-name "Иван Иванов"

# 7. Запустить сервер
uvicorn app.main:app --reload

# 8. Открыть документацию API в браузере
# http://127.0.0.1:8000/docs

# 9. Запустить тесты — переменные окружения через $env: (PowerShell)
$env:SECRET_KEY="testtesttest"
$env:ACCESS_TOKEN_EXPIRE_MINUTES="60"
$env:ALGORITHM="HS256"
$env:DATABASE_URL="sqlite:///:memory:"
pytest
```

> **Если запускаешь для Android-эмулятора или реального телефона** — стартуй сервер с `--host 0.0.0.0 --port 8000` и используй адрес `10.0.2.2` (для AVD) или IP компьютера из `ipconfig` (для реального устройства, не забыть открыть порт в Брандмауэре). Подробности — в корневом `README.md` («Частые проблемы на Windows»).

---

## Тонкий момент: StaticPool в тестах

При тестировании хочется изолировать каждый тест: чтобы данные одного теста не влияли на другой. Для этого используется **in-memory SQLite** (`sqlite:///:memory:`) — база живёт только в оперативной памяти и исчезает при закрытии соединения.

Но здесь есть подводный камень: SQLite создаёт **новую** in-memory базу для **каждого нового подключения**. FastAPI открывает своё подключение для обработки запроса, а pytest-фикстура — своё. Если не принять меры, фикстура создаёт таблицы в «своей» базе, а HTTP-запрос видит пустую «свою» базу (без таблиц → ошибка «no such table»).

Решение — `StaticPool` из SQLAlchemy (файл `backend/tests/conftest.py`, строки 44–49):

```python
from sqlalchemy.pool import StaticPool

test_engine = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,   # ← все соединения используют одно физическое подключение
)
```

`StaticPool` гарантирует, что все запросы к engine — и из фикстуры, и из HTTP-запроса — идут через **одно и то же физическое соединение**. Значит, они видят одну и ту же in-memory базу, и тест работает корректно.

> **Правило:** эту настройку нельзя трогать — без неё все тесты, которые создают данные через фикстуры и проверяют их через HTTP, упадут с «no such table».

---

## Клиент: Flutter

### Стек

| Компонент | Библиотека |
|---|---|
| UI | Flutter 3.x + Material 3 |
| Управление состоянием | flutter_riverpod 2.x |
| HTTP | dio 5.x + перехватчики |
| Навигация | go_router 14.x |
| Хранение JWT | flutter_secure_storage 9.x (Keychain / EncryptedSharedPreferences) |
| Графики | fl_chart 0.68.x (BarChart + PieChart) |

### Структура `lib/`

Организация по принципу **feature-first**: каждая фича (`student`, `admin`) — самостоятельный модуль с тремя слоями.

```
lib/
  main.dart              # Точка входа: ProviderContainer + async initialize()
  app.dart               # MaterialApp.router, подключает go_router + тему
  core/
    api/
      api_client.dart         # Singleton Dio, kApiBaseUrl = 'http://localhost:8000/api/v1'
      auth_interceptor.dart   # Добавляет Bearer-токен в Authorization
      api_exceptions.dart     # ApiException(statusCode, code, message) + mapper
    storage/
      token_storage.dart      # FlutterSecureStorage: отдельные ключи student/admin
    router/
      app_router.dart         # GoRouter: маршруты + redirect для /admin/**
    theme/
      app_theme.dart          # Material 3, seedColor = #3B5BDB
  features/
    student/
      data/student_repository.dart     # StudentRepository + impl
      domain/models/                   # RedeemResponse, ActiveVoteResponse,
                                       # QuestionnaireAnswers
      presentation/
        providers/student_providers.dart  # activeVoteProvider, surveyAnswersProvider,
                                          # voteSubmitProvider
        screens/                          # CodeEntryScreen, QuestionnaireScreen,
                                          # ThankYouScreen
        widgets/question_block.dart       # Динамический рендер блоков анкеты
    admin/
      data/admin_repository.dart       # AdminRepository + impl
      domain/models/                   # AdminLoginResponse, ClassModel,
                                       # VotingSessionModel, ResultsModel
      presentation/
        providers/admin_providers.dart    # AuthNotifier, AdminLoginNotifier,
                                          # adminClassesProvider, ...
        screens/                          # AdminLoginScreen, AdminDashboardScreen,
                                          # CodesScreen, SessionsScreen, ResultsScreen
        widgets/results_chart.dart        # ClassResultsCard (BarChart + PieChart + плашка n<5)
```

### Роль Riverpod

Riverpod используется как единственный механизм управления состоянием и DI:

- **`Provider`** — сервисы-синглтоны: `dioProvider`, `tokenStorageProvider`, `studentRepositoryProvider`, `adminRepositoryProvider`.
- **`StateNotifierProvider`** — изменяемое состояние: `authNotifierProvider` (auth-статус администратора), `surveyAnswersProvider` (текущие ответы в анкете).
- **`FutureProvider`** — асинхронная загрузка: `activeVoteProvider`, `adminClassesProvider`, `adminSessionsProvider`, `adminResultsProvider`.
- **`AsyncNotifierProvider`** — мутации: `voteSubmitProvider`, `adminLoginProvider`, `generateCodesProvider`, `sessionActionProvider`.
- **`autoDispose`** — все экранные провайдеры освобождают память при уходе с экрана.

Riverpod позволяет подменять зависимости через `ProviderScope.overrides` в тестах без моков фреймворка.

### Как организован `api_client` и interceptors

```
dioProvider
  └── Dio(BaseOptions(baseUrl: kApiBaseUrl, timeouts: 10s))
       └── AuthInterceptor
             читает tokenStorage.readStudentToken() или readAdminToken()
             в зависимости от пути запроса:
               /admin/** → adminToken
               остальные → studentToken
             добавляет заголовок: Authorization: Bearer <token>
```

Единственный `kApiBaseUrl` находится в `core/api/api_client.dart` — меняется в одном месте.

Все запросы обёрнуты в `try { ... } on DioException catch (e) { throw mapDioException(e); }`. Функция `mapDioException` разбирает формат бэка `{"detail": {"code": "...", "message": "..."}}` и преобразует в типизированный `ApiException`.

### Хранение JWT

JWT хранится в `flutter_secure_storage`:

- iOS/macOS → **Keychain** (зашифровано системой)
- Android → **EncryptedSharedPreferences** (AES-256 через Android Keystore)

Два отдельных ключа: `student_token` и `admin_token`. После успешного голосования `student_token` удаляется (инвалидация токена на клиенте).

Альтернатива — `SharedPreferences` — не используется намеренно: она хранит данные в открытом виде и доступна root-пользователям устройства.

### Flow ученика (экраны)

```
CodeEntryScreen
   │  ввод кода → POST /auth/student/redeem
   │  → save student_token
   ↓
QuestionnaireScreen
   │  GET /votes/active (JWT) → рендер 5 блоков
   │  пользователь заполняет
   │  → POST /votes (JWT) → delete student_token
   ↓
ThankYouScreen
   │  «На главную» →
   ↓
CodeEntryScreen
```

### Flow администратора (экраны)

```
AdminLoginScreen
   │  POST /auth/admin/login (form data!) → save admin_token
   ↓
AdminDashboardScreen
   │  GET /admin/classes → список классов
   │  для каждого класса: кнопки Коды / Сессии
   ├──▶ CodesScreen ─ POST /admin/classes/:id/codes → список кодов
   └──▶ SessionsScreen
           │  GET /admin/sessions → список сессий
           │  POST /admin/sessions/:id/open или /close
           └──▶ ResultsScreen
                    GET /admin/voting-sessions/:id/results
                    → ClassResultsCard × N
```

> **Важно:** `POST /auth/admin/login` ожидает **form data** (OAuth2 PasswordRequestForm), а не JSON. Dio отправляет `Content-Type: application/x-www-form-urlencoded`.

### Динамический рендер анкеты

`GET /votes/active` возвращает `questionnaire: {blocks: [...]}` — описание структуры анкеты v1. Виджет `QuestionBlock` рендерит каждый блок по полю `"type"`:

| type | Компонент |
|---|---|
| `subjects_time` | ChoiceChip-группы на каждый предмет |
| `exams` | Slider (1–4) + Checkbox |
| `free_periods` | RadioListTile + Checkbox |
| `radio` | RadioListTile-группа |
| `text` | TextField с maxLength и счётчиком |

Это позволяет бэку добавлять новые типы блоков без изменения клиента — достаточно добавить новый `case` в `QuestionBlock._buildBlockContent`.

### Результаты и n<5 (клиентская сторона)

`ClassResultsCard` проверяет `classResults.hiddenDueToSmallCount`:

```
hiddenDueToSmallCount == true
  → _HiddenDataPlaceholder (серый блок, ключ 'hidden_data_placeholder')

hiddenDueToSmallCount == false
  → _ResultsCharts
       → _HeavySubjectsChart (BarChart, ключ 'heavy_subjects_chart')
       → _PEChart (PieChart)
```

Защита работает на **двух уровнях** (бэк и клиент): бэк не передаёт агрегаты при `n < 5`; клиент показывает плашку при `hiddenDueToSmallCount == true` — даже если агрегаты случайно попали в ответ, они не отрисовываются.

---

## Flutter-тесты

4 widget-теста в `frontend/test/`:
- `code_entry_screen_test.dart` — рендер, кнопка disabled/enabled, ошибки.
- `questionnaire_screen_test.dart` — 5 блоков, мок репозитория через ProviderScope.
- `admin_login_screen_test.dart` — валидация полей формы.
- `results_chart_test.dart` — плашка n<5, отрисовка графика при n≥5.

1 integration-тест `frontend/integration_test/full_flow_test.dart`:
- Полный флоу ученика с `_FakeTokenStorage` и `_MockStudentRepository`.

Зависимости подменяются через `ProviderScope.overrides` — без мок-фреймворков, только стандартный Riverpod.

> **Важно:** тесты написаны, но на машине разработки Flutter не установлен (`flutter --version` → command not found). Перед защитой на Windows 11 — `choco install flutter -y` (или см. инструкцию в корневом `README.md`), затем `flutter pub get` и `flutter test` в директории `frontend\`.
