# S3-KF-ADMISSION-001: оценка допуска «KPI Фитнеса»

Дата: 2026-08-19. Статус: `BLOCKER — required dependency unavailable`.
Проверка проведена по утверждённым mapping, data contract, ADR и каталогу
созданных объектов; SQL, DDL, DML и источники не изменялись.

## Проверенный контракт

ADR-0012 намеренно не создаёт отдельную таблицу KPI. Полный отчёт является
составной Power BI-моделью над пятью фактами с разными grain:

| Факт | Состояние |
|---|---|
| `mart.ancillary_revenue_movement` | создан и прошёл аудит |
| `mart.ip_training_daily` | создан и прошёл аудит |
| `mart.ip_revenue_daily` | создан и прошёл аудит |
| `mart.dpfu_plan_assignment` | создан и прошёл аудит |
| `mart.client_base_daily` | отсутствует |

Последний факт является обязательным знаменателем подтверждённой метрики
вовлечённости. Убрать его из первого релиза означало бы изменить отчёт и
нарушить BR-018; создать новую KPI-таблицу означало бы смешать несовместимые
grain, что ADR-0012 прямо запрещает.

## Почему зависимость нельзя создать автоматически

Контракт и mapping `mart.client_base_daily` помечают как implementation
blockers неподтверждённые статусы исходных объектов, физические типы/ключи и
контрольные значения. SV-111 подтверждает нужную cohort как source-side
evidence, но не заменяет отдельный product admission физического объекта.

## Вывод

`KPI Фитнеса` не имеет безопасного самостоятельного DDL/DML-пакета до
появления принятой `mart.client_base_daily`. Блокер не меняет готовые четыре
факта и не требует их повторной загрузки. Для продолжения выбрана следующая
независимая витрина с закрытыми source controls —
`mart.administrator_card_gymmy_daily`.

## Evidence

- [mapping KPI](../mappings/kpi_fitness.md);
- [contract KPI](../data_contracts/kpi_fitness.md);
- [ADR-0012](../adr/0012-kpi-fitness-composite-model.md);
- [catalog data products](../catalogs/data_products.md);
- [mapping client base](../mappings/client_base.md).
