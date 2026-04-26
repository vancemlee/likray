# Definition of Done — Likray

Пункты из ТЗ §14. Статусы: `[x]` готово, `[~]` частично, `[ ]` не готово / не проверено.

---

## Чек-лист по ТЗ §14

- [~] **`docker-compose up` (или `make run`) поднимает backend на `localhost:8000`** с пустой БД и одним тестовым админом.
  - `uvicorn app.main:app --reload` поднимает backend корректно (проверено).
  - Создание первого админа: `python cli.py create-superadmin ...`
  - Почему [~]: Docker-файлы не написаны. Используется `uvicorn` напрямую, а не `docker-compose`. Для прототипа достаточно, но критерий ТЗ формально требует docker-compose.
  - Что сделать: создать `Dockerfile` + `docker-compose.yml` для бэкенда.

- [ ] **`flutter run` на эмуляторе Android запускает приложение**, которое успешно общается с локальным backend.
  - Код Flutter-клиента написан полностью (`frontend/`).
  - Почему [ ]: Flutter SDK не установлен на машине разработки (`flutter --version` → command not found).
  - Что сделать (Windows 11, PowerShell от администратора):
    ```powershell
    choco install flutter -y
    # закрыть и снова открыть PowerShell
    flutter doctor
    flutter doctor --android-licenses    # принять все лицензии
    cd frontend
    flutter pub get
    flutter run
    ```
  - Внутри Android-эмулятора бэкенд по `localhost` недоступен — использовать `10.0.2.2` (см. `README.md`, раздел «Настройка URL бэкенда»).

- [ ] **Полный сценарий end-to-end:** админ → создаёт класс → генерирует 5 кодов → открывает голосование → 5 раз с эмулятора проходит голосование (каждый раз новым кодом) → админ видит дашборд с агрегатами → экспортирует PDF.
  - Бэкенд-логика готова и покрыта pytest-тестами.
  - Flutter-экраны написаны (student flow + admin dashboard + charts).
  - Почему [ ]: требует Flutter SDK + эмулятор Android. Ручная проверка не проводилась.
  - Дополнительно: экспорт PDF на устройство частично — бэкенд генерирует файл, Flutter скачивает байты, но сохранение в Downloads не реализовано (TODO в `results_screen.dart`).

- [x] **Повторная активация уже использованного кода возвращает понятную ошибку.**
  - `POST /auth/student/redeem` с использованным кодом → `409 CODE_ALREADY_USED`.
  - Тест: `backend/tests/test_auth.py::test_redeem_code_already_used` — зелёный.

- [x] **В БД невозможно установить связь между конкретным голосом и конкретным кодом** (проверяется ручным SQL-запросом, описанным в `backend/README.md`).
  - Таблицы `access_codes` и `votes` не имеют общих полей и FK — по архитектурному решению.
  - SQL-запрос из `backend/README.md`: `PRAGMA table_info(votes);` — нет полей `access_code_id` / `user_id`.
  - Подробно: `docs/ARCHITECTURE.md` → «Верифицированная анонимность», «Почему нет FK».

- [x] **Все тесты из §11 проходят зелёным.**
  - 30 тестов, 0 ошибок: `pytest -x -q` → `30 passed in 5.38s`
  - Покрытие: `test_auth.py`, `test_votes.py`, `test_admin.py`, `test_cli.py`, `test_healthcheck.py`
  - Команда для проверки (Windows 11, PowerShell):
    ```powershell
    cd backend
    $env:SECRET_KEY="testtesttest"
    $env:ACCESS_TOKEN_EXPIRE_MINUTES="60"
    $env:ALGORITHM="HS256"
    $env:DATABASE_URL="sqlite:///:memory:"
    python -m pytest -x -q
    ```

- [x] **README объясняет запуск с нуля за ≤ 10 шагов.**
  - `README.md` в корне репозитория: backend (8 шагов) + flutter (5 шагов).

---

## Итог

| Критерий ТЗ §14 | Статус |
|---|---|
| docker-compose / make run | [~] uvicorn работает, Docker не написан |
| flutter run на эмуляторе | [ ] нет Flutter SDK |
| Полный end-to-end сценарий | [ ] требует Flutter + эмулятор |
| Повторный код → 409 | [x] готово |
| Нет связи голос ↔ код в БД | [x] готово |
| Все тесты зелёные (30/30) | [x] готово |
| README ≤ 10 шагов | [x] готово |

**4 из 7 критериев выполнены полностью.** 2 требуют установки Flutter SDK. 1 требует Docker (или засчитывается uvicorn).

**Следующий шаг перед защитой (Windows 11, PowerShell от администратора):**
```powershell
choco install flutter -y
# закрыть и снова открыть PowerShell
flutter doctor
flutter doctor --android-licenses
cd frontend
flutter pub get
flutter test          # widget-тесты
flutter run           # на эмуляторе (внутри AVD бэкенд — 10.0.2.2:8000)
```
