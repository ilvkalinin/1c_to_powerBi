# Operations execution: расписание bounded visits-debt refresh

- Пакет: `visits_debt_bounded_incremental_scheduling_2026-08-31`
- Локальные артефакты: `PREPARED`
- Внешняя Windows task: `BLOCKED / NOT INSTALLED`

## Выполнено

Созданы credential-free PowerShell wrapper, on-demand Task Scheduler XML и
operator handoff. Собственного trigger нет; no overlap (`IgnoreNew`) действует
только для этой витрины, network required, timeout 5 minutes. Wrapper пишет
timestamped log, возвращает exit runner без преобразования success и создаёт
Windows Application Event 100/101/102 без credentials.

XML прошёл parser/static assertions для отсутствия trigger, timeout, concurrency и
placeholders. Wrapper проверен статически на обязательные параметры,
`--run`, capture `$LASTEXITCODE`, error events и ненулевой catch exit.

## External blocker

С текущего хоста VM-2 отвечает на WinRM HTTP, но отсутствуют Windows operator
credentials, WinRM client authority и TLS channel; SSH недоступен. Поэтому
Task Scheduler не изменялся. Это не выдаётся за установленное расписание.
Точная процедура: [operator handoff](../operations/visits_debt_bounded_incremental_windows_task_scheduler.md).

По уточнению пользователя execution boundary зафиксирована однозначно:
автоматический refresh запускается только Windows Task Scheduler/orchestrator
на VM-2. Текущая машина не является scheduler host; на ней задача не создавалась
и запуск по расписанию отсутствует.

Текущий full loader, bounded SQL/config, target data, Power BI и source 1С этим
пакетом не изменялись.

Фиксированный daily 07:30 trigger и 15-minute timeout были отклонены после
замечания пользователя о 40 витринах. Массовое расписание требует отдельного
dependency-aware orchestration package; 40 задач нельзя ни сериализовать по
15 минут, ни одновременно направить в VM-1/VPN.
