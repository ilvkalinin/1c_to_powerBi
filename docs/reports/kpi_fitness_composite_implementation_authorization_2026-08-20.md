# S3-KF-COMPOSITE-001: реализация composite-слоя «KPI Фитнеса»

Дата согласования: 2026-08-20. Статус: `COMPLETED`.

Пользователь подтвердил фактическую Stage 3 реализацию и приёмку KPI после
загрузки `mart.client_base_daily`. ADR-0012 запрещает отдельную KPI-таблицу:
реализация состоит в приёмке и фиксации composite contract над существующими
фактами.

## Scope

1. Read-only проверить наличие, contract, grain и текущую целостность пяти
   фактов: `mart.ancillary_revenue_movement`, `mart.ip_training_daily`,
   `mart.ip_revenue_daily`, `mart.dpfu_plan_assignment`,
   `mart.client_base_daily`.
2. Подтвердить, что `client_base_daily` теперь закрывает знаменатель
   вовлечённости, а KPI не создаёт physical fact и не дублирует existing data.
   Зафиксировать composite Power BI contract и known first-release limits
   BR-018.
3. Нет DDL/DML, новых views, Power BI/Excel/scheduler-изменений, source write
   или ежедневного incremental refresh. Внешние бюджет, мероприятия и
   классификатор услуг остаются в Power BI.

## Критерий закрытия

Пять подтверждённых фактов физически доступны, имеют допустимый contract и
покрывают все зафиксированные KPI-компоненты без fact-to-fact join или новой
копии. Документированная composite implementation снимает blocker
S3-KF-ADMISSION-001; все внешние и методические limits сохранены явно.

## Результат read-only acceptance

| Факт | Строк | Результат |
|---|---:|---|
| `mart.ancillary_revenue_movement` | 659 403 | PK и scope contract; `dpfu` 508 639, `reception` 150 764; required quantity/revenue non-NULL |
| `mart.ip_training_daily` | 141 327 | PK, required training count valid |
| `mart.ip_revenue_daily` | 1 253 | unique key, revenue non-NULL |
| `mart.dpfu_plan_assignment` | 528 482 | PK, planned revenue non-NULL |
| `mart.client_base_daily` | 1 657 353 | unique key и daily denominator contract valid |

Во всех пяти объектах присутствуют все обязательные поля data contract.
`client_base_daily` теперь заполняет ранее отсутствующий знаменатель
вовлечённости. Отдельный KPI-факт, fact-to-fact joins и новые raw copies не
создавались. PostgreSQL composite contract готов; внешний бюджет, мероприятия,
классификатор услуг и сам Power BI switch остаются вне пакета.
