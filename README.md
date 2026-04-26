# Likray — анонимное голосование о расписании

## Что это такое

Likray — мобильное приложение, которое позволяет ученикам анонимно высказать пожелания к расписанию на следующую четверть. Ученик получает от классного руководителя одноразовый код, вводит его в приложение, заполняет короткую анкету из 5 блоков (тяжёлые предметы, контрольные, окна, физкультура, свободное пожелание) и нажимает «Отправить». Завуч видит только сводную статистику по классу — связать конкретного ученика с его ответом технически невозможно.

**Шпаргалка к защите:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

---

## Структура репозитория

```
Likray/
├── backend/          # FastAPI + SQLAlchemy + SQLite — REST API
├── frontend/         # Flutter-клиент (iOS, Android, macOS)
├── docs/
│   ├── ARCHITECTURE.md   # Объяснение всех архитектурных решений (для защиты)
│   └── DOD.md            # Definition of Done — что готово, что осталось
└── README.md             # этот файл
```

---

## Запуск бэкенда (Windows 11, PowerShell)

Нужен Python 3.11 или 3.12 ([скачать](https://www.python.org/downloads/windows/) — при установке отметить **«Add python.exe to PATH»**).

```powershell
# 1. Перейти в папку backend
cd backend

# 2. Создать виртуальное окружение
python -m venv .venv

# 3. Активировать окружение (PowerShell)
.\.venv\Scripts\Activate.ps1
# Если PowerShell ругается на политику выполнения — один раз для текущего пользователя:
# Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# В cmd.exe вместо Activate.ps1 используется: .\.venv\Scripts\activate.bat

# 4. Установить зависимости
pip install -r requirements.txt

# 5. Создать файл настроек
copy .env.example .env
# Открыть .env (notepad .env) и задать SECRET_KEY:
# python -c "import secrets; print(secrets.token_hex(32))"

# 6. Создать базу данных (применить миграции)
alembic upgrade head

# 7. Создать первого администратора (обратные кавычки `  — перенос строки в PowerShell)
python cli.py create-superadmin `
    --school-name "Лицей №131" `
    --username admin `
    --password "СильныйПароль123" `
    --full-name "Иван Петрович Иванов"

# 8. Запустить сервер
uvicorn app.main:app --reload

# 9. Открыть документацию API в браузере
# http://localhost:8000/docs
```

### Запуск тестов бэкенда (PowerShell)

В PowerShell переменные окружения задаются через `$env:VAR="value"`:

```powershell
cd backend
$env:SECRET_KEY="testtesttest"
$env:ACCESS_TOKEN_EXPIRE_MINUTES="60"
$env:ALGORITHM="HS256"
$env:DATABASE_URL="sqlite:///:memory:"
pytest -v
```

В cmd.exe — через `set` (без кавычек вокруг значения):

```cmd
cd backend
set SECRET_KEY=testtesttest
set ACCESS_TOKEN_EXPIRE_MINUTES=60
set ALGORITHM=HS256
set DATABASE_URL=sqlite:///:memory:
pytest -v
```

Все тесты должны быть зелёными (30+ тестов: auth, votes, admin, cli, health).

---

## Запуск Flutter-клиента (Windows 11, PowerShell)

**Требования:** Flutter SDK 3.x, запущенный бэкенд на `localhost:8000`, Android Studio с настроенным эмулятором (для запуска под Android).

### Установка Flutter через Chocolatey

Самый быстрый способ — пакетный менеджер [Chocolatey](https://chocolatey.org/install). Открыть PowerShell **от имени администратора** и выполнить:

```powershell
# 1. Установить Chocolatey (если ещё не стоит)
Set-ExecutionPolicy Bypass -Scope Process -Force; `
[System.Net.ServicePointManager]::SecurityProtocol = `
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; `
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 2. Установить Flutter SDK
choco install flutter -y

# 3. Закрыть и снова открыть PowerShell, проверить:
flutter --version
flutter doctor
```

Альтернатива — ручная установка по [официальной инструкции](https://docs.flutter.dev/get-started/install/windows).

### Запуск приложения

```powershell
# 1. Перейти в папку фронта
cd frontend

# 2. Установить зависимости
flutter pub get

# 3. Список подключённых устройств / эмуляторов
flutter devices

# 4. Запустить на подключённом устройстве/эмуляторе
flutter run

# 5. Запустить widget-тесты
flutter test

# 6. Запустить integration-тест (нужен запущенный эмулятор)
flutter test integration_test/full_flow_test.dart
```

### Настройка URL бэкенда

Если бэкенд запущен не на `localhost:8000`, измените значение в **одном месте**:

```dart
// frontend/lib/core/api/api_client.dart
const String kApiBaseUrl = 'http://localhost:8000/api/v1';
```

**Важные адреса для разных сценариев на Windows:**

| Сценарий | Что писать вместо `localhost` |
|---|---|
| Android-эмулятор (AVD) → бэкенд на той же машине | `10.0.2.2` (специальный alias эмулятора для хоста) |
| Реальный Android-телефон по Wi-Fi | IP компьютера в локалке — узнать через `ipconfig` (поле «IPv4-адрес», обычно `192.168.x.x`) |
| Windows-десктоп / Chrome на хосте | `localhost` оставить как есть |

Узнать IP компьютера:

```powershell
ipconfig
# Найти секцию активного адаптера (Ethernet или Wi-Fi),
# взять значение "IPv4-адрес. . . . . . . . . . . : 192.168.x.x"
```

Если используется реальный телефон — открыть на компьютере порт 8000 в Брандмауэре Windows (см. ниже «Частые проблемы на Windows»).

---

## Частые проблемы на Windows

**1. PowerShell блокирует активацию venv: «выполнение сценариев отключено в этой системе».**
Один раз для текущего пользователя:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```
Перезапустить PowerShell.

**2. `python` не найден / открывается Microsoft Store.**
Windows подсовывает заглушку из Store. Решения:
- Переустановить Python с [python.org](https://www.python.org/downloads/windows/), отметив «Add python.exe to PATH».
- Отключить заглушку: `Параметры → Приложения → Дополнительные параметры приложений → Псевдонимы выполнения приложений → выключить App Installer для python.exe и python3.exe`.

**3. Длинные пути ломают `pip install` или `flutter pub get`.**
Включить поддержку длинных путей (PowerShell от админа):
```powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```
Перезагрузить компьютер.

**4. Android-эмулятор не видит бэкенд по `localhost`.**
Это нормально — внутри эмулятора `localhost` указывает на сам эмулятор, а не на хост. Использовать `10.0.2.2` (см. таблицу выше).

**5. Реальный телефон не может подключиться к компьютеру по локальной сети.**
- Узнать IP компьютера через `ipconfig`, прописать его в `kApiBaseUrl`.
- Открыть порт 8000 в Брандмауэре Windows (PowerShell от админа):
  ```powershell
  New-NetFirewallRule -DisplayName "Likray backend (8000)" `
      -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
  ```
- Запускать сервер с `--host 0.0.0.0`:
  ```powershell
  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
  ```

**6. `flutter doctor` ругается на Android licenses.**
```powershell
flutter doctor --android-licenses
# Принять все лицензии (нажимать y).
```

**7. После `choco install flutter` команда `flutter` не найдена.**
Закрыть и заново открыть PowerShell — Chocolatey добавляет PATH только для новых сессий. Если не помогло — проверить, что `C:\tools\flutter\bin` есть в `$env:Path`.

**8. Перенос строк: `\` не работает в PowerShell.**
В PowerShell для переноса длинной команды используется обратная кавычка `` ` `` в конце строки (не `\` как в bash).

---

## Шпаргалка к защите

Читай [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — там простым языком объяснено:

- Что такое «верифицированная анонимность» и почему это не противоречие
- Почему между `access_codes` и `votes` нет FK
- Зачем redeem двухэтапный (два SQL-коммита)
- Как устроены JWT: admin-токен vs student-токен
- Что такое `StaticPool` и почему тесты не работали бы без него
- Как работает защита n<5 в агрегаторе
- Архитектура Flutter-клиента (Riverpod, GoRouter, secure_storage)

---

## Известные ограничения

1. **Flutter-клиент не прогонялся на реальном эмуляторе** — Flutter SDK не был установлен на машине разработки. Код написан и покрыт тестами, но финальный end-to-end прогон нужно сделать самостоятельно после `flutter pub get`.

2. **Admin API проверен только через pytest** — ручное тестирование через Flutter-экраны администратора не проводилось.

3. **Экспорт файлов (PDF/CSV) в Flutter** — бэкенд генерирует файлы, Flutter их скачивает через Dio, но сохранение на устройство (в Downloads) не реализовано — TODO в `frontend/lib/features/admin/presentation/screens/results_screen.dart`.

4. **Docker не настроен** — для запуска используется `uvicorn` напрямую. Если нужен Docker, потребуется написать `Dockerfile` и `docker-compose.yml`.

5. **SQLite** подходит для прototipa (сотни учеников), для production потребуется PostgreSQL.

---

## Что делать дальше (DoD)

Полный чек-лист с пометками что готово и что осталось: [`docs/DOD.md`](docs/DOD.md).

**Ключевые следующие шаги:**

1. Установить Flutter SDK, прогнать `flutter test` и `flutter run`
2. Провести полный end-to-end сценарий: создать класс → сгенерировать коды → открыть голосование → проголосовать 5 раз → посмотреть результаты в дашборде
3. Допилить сохранение PDF/CSV на устройство в `results_screen.dart`
4. (Опционально) Написать `Dockerfile` для бэка

---

## Лицензия

MIT — см. `LICENSE` (добавить при необходимости).
