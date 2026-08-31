# Авторизация planning-пакета: единый orchestrator refresh для физических витрин

- Пакет: `project_wide_refresh_orchestration_planning_2026-08-31`
- Статус: `CONFIRMED USER DECISION`
- Основание: пользователь 2026-08-31 подтвердил подготовку общего
  dependency-aware планировщика для всех физических витрин, с измерениями на
  текущей рабочей машине и исполнением только на VM-2.

## Scope

1. Локально инвентаризировать catalog физического `mart`-слоя, versioned
   loader'ы, объединённые atomic chains, существующие config/SQL и evidence
   runtime; исключить `view` как отдельные refresh jobs.
2. Сформировать versioned manifest: один on-demand job на фактическую atomic
   единицу обновления, exact runner entry point, physical targets, dependency
   edges, evidence/status runtime, concurrency class и fail-closed policy.
3. Сформировать и статически проверить DAG, критический путь к BR-014 08:30
   МСК, правила mutual exclusion и форму журналов без credentials.
4. Подготовить PowerShell orchestrator и operator handoff для VM-2 root
   `C:\Users\a.tolstikov\Desktop\Fitness\_dwh`; задача запускается только
   от VM-2 и не содержит собственного per-mart daily trigger.

## Explicit exclusions

- Нет DDL, DML, `COPY`, запуска loader'ов, source query, изменения 1С или
  Power BI.
- Нет регистрации, изменения или запуска Windows Task Scheduler на VM-2 до
  отдельного принятия reviewed manifest/DAG/schedule.
- Нельзя объявлять runtime/SLA для jobs без pre-existing measured evidence;
  `UNKNOWN` остаётся fail-closed и исключает job из автоматического графика.

## Closure

Пакет закрывается только когда committed manifest/DAG и orchestrator проходят
static checks, все 40 физических объектов классифицированы как `RUNNABLE`,
`COMPOSITE`, `VIEW_NOT_JOB` или `BLOCKED`, а операторский handoff содержит
только безопасные VM-2 команды. После этого отдельный runnable
installation-пакет с точным schedule, task definitions, правами и rollback
показывается пользователю для approval.
