# Авторизация: последовательное проектирование incremental refresh

- Пакет: `project_refresh_incremental_design_2026-08-31`
- Статус: `CONFIRMED USER DECISION`
- Scope: все 29 atomic job-единиц из
  `config/project_refresh_orchestration.json`, в order его проверенного DAG.

## Разрешённая автономная работа

Для каждой job последовательно:

1. Сверить existing mapping, data contract, runner, target grain/key и
   documented source states.
2. Выполнить только read-only source/target metadata и control checks для
   change timestamp/version/feed, deletion/correction/late-change behaviour.
3. Если кандидат поддержан фактами, спроектировать одну минимальную стратегию
   (watermark, mutable period, bounded sliding window либо append) и exact
   independent reconciliation/rollback requirements; иначе зафиксировать
   `BLOCKED` без придуманного watermark.
4. Выполнить progressive `EXPLAIN (ANALYZE, BUFFERS)` точного candidate
   source extract только после безопасного short-horizon control и не
   параллельно transport.
5. Добавить результат в versioned readiness matrix и dependency/concurrency
   plan. Measurements выполняет текущая рабочая машина; VM-2 не используется
   для source plan.

## Explicit exclusions

Нет DDL/DML, `COPY`, запуска full/incremental loader, изменения источника,
Power BI или Task Scheduler. Дизайн и measured read-only evidence не являются
approval на физическую загрузку. Каждая будущая implementation/installation
волна потребует immutable SQL/runner/reconciliation plan и отдельного
пользовательского approval.

## Closure

Для всех 29 jobs matrix фиксирует `INCREMENTAL_CANDIDATE`,
`FULL_REBUILD_ONLY` или `BLOCKED` с evidence. Для кандидата обязательны
watermark/state/deletion/late-change findings, plan ladder и reconciliation
design; отсутствие хотя бы одного делает job non-automatic. Затем user
получает один reviewed installation proposal только для jobs, признанных
автоматизируемыми.
