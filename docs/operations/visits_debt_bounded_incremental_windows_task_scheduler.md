# Windows Task Scheduler: bounded visits-debt refresh

Статус: `BLOCKED — external installation authority required`.

Execution boundary: задача запускается **только на VM-2**. Текущая рабочая
машина используется лишь для versioned deploy-артефактов и не является
scheduler host. Project checkout, Python environment, ACL-защищённый `.env` и
log directory должны находиться на VM-2; пути в XML относятся только к VM-2.

Подготовлены:

- `scripts/run_unconfirmed_service_debt_movement_incremental_scheduled.ps1`;
- `config/windows_task_scheduler_visits_debt_bounded_incremental.xml`.

## Установка оператором на VM-2

1. Выполнять все следующие действия в интерактивной/operator-сессии **на
   VM-2**. Проверить `Get-TimeZone`: локальная зона VM-2 должна соответствовать
   Moscow Standard Time, потому что общий orchestrator использует local time.
2. Выбрать отдельную service account с read/execute к project, Python и `.env`,
   write только к log directory и необходимыми PostgreSQL permissions. Пароль
   не записывать в XML, repository или command history.
3. Разместить reviewed project revision на VM-2. В копии XML заменить
   `__TASK_USER_SID__`, `__PROJECT_ROOT__`, `__PYTHON_EXE__`,
   `__LOG_DIRECTORY__` только на абсолютные VM-2 значения.
4. Импортировать XML через Task Scheduler UI с вводом пароля account в
   защищённом диалоге. Имя задачи:
   `NFG\VisitsDebtBoundedRefresh`.
5. Read-back проверить: собственный trigger отсутствует, `IgnoreNew`, `PT5M`,
   network required, action paths и LeastPrivilege. Эту задачу должен вызывать
   общий оркестратор после учёта dependencies и concurrency budget.
6. Не запускать задачу вручную сразу после импорта: bounded refresh уже
   выполнен 2026-08-31. После первого планового запуска проверить exit code 0,
   timestamped log и Application Event ID 100. ID 101/102 либо ненулевой
   `LastTaskResult` означает fail-closed failure; не запускать current full
   loader как автоматический fallback.

`.env` не копируется в XML и не выводится в лог. Wrapper передаёт наружу exit
code runner, а runner уже использует тот же transaction advisory lock, поэтому
параллельный DML одного объекта не принимается.

`IgnoreNew` не означает глобальную последовательность 40 витрин. Общий график
должен использовать измеренные runtimes, не запускать параллельно тяжёлые
source plans/transports и разрешать ограниченную параллельность только
независимым лёгким веткам. Этот project-wide orchestrator не входит в данный
handoff.
