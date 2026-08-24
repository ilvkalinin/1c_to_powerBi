# Авторизация runnable admission: «Маркетинговая воронка»

Статус: `CONFIRMED`.

## Решение пользователя

24.08.2026 пользователь явно подтвердил `STAGE_3_PRODUCT_ADMISSION` для
неизменяемого плана
[marketing_funnel_stage_3_admission_plan.md](marketing_funnel_stage_3_admission_plan.md):
source read-only snapshot, создание двух целевых таблиц, атомарная
full-rebuild загрузка, `MF-R01`—`MF-R06` и один rerun. Критерий закрытия —
нулевые отклонения по утверждённым control values и rerun.

## Разрешённый scope

| Граница | Разрешено |
|---|---|
| Новые объекты | `mart.marketing_funnel_task`, `mart.marketing_funnel_task_contract` |
| DDL | Только `CREATE TABLE` и `REVOKE ALL ... FROM PUBLIC` из reviewed DDL |
| Source | Один `REPEATABLE READ READ ONLY` snapshot 1С и binary `COPY` двух reviewed extracts |
| Target | Одна транзакция: initial `COPY`; при rerun — child-first `DELETE + COPY` |
| Контроли | `MF-R01`—`MF-R06`, включая BR-003, BR-020 и фиксированный PBIT control `23 864` за 2025-07-01 |
| Повтор | Один полный rerun в новом source snapshot |

Не входят в scope: любые изменения 1С, Power BI/M/DAX, Excel, планов,
расписаний, прав для BI-ролей и incremental refresh.

## Неизменяемые артефакты

- [План](marketing_funnel_stage_3_admission_plan.md)
- [DDL](../../sql/marts/marketing_funnel_reviewed_plan.sql)
- [Source extracts](../../sql/marts/marketing_funnel_source_extract.sql)
- [Reconciliation](../../sql/tests/marketing_funnel_reconciliation.sql)
- [Rollback](../../sql/marts/marketing_funnel_rollback.sql)
- [Runner](../../scripts/load_marketing_funnel.py)

Rollback не является автоматическим: допускается только отдельный запуск
reviewed `DROP TABLE` для двух объектов, созданных этим пакетом, пока
Power BI-потребитель не переключён.
