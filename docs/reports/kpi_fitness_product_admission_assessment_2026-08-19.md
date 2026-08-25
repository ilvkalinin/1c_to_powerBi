# S3-KF-ADMISSION-001: оценка допуска «KPI Фитнеса»

Дата: 2026-08-19. Статус: `BLOCKER CLOSED 2026-08-20 — composite implemented`.
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
| `mart.client_base_daily` | схема создана; строк нет по отдельному решению |

Последний факт является обязательным знаменателем подтверждённой метрики
вовлечённости. Убрать его из первого релиза означало бы изменить отчёт и
нарушить BR-018; создать новую KPI-таблицу означало бы смешать несовместимые
grain, что ADR-0012 прямо запрещает.

## Статус зависимости

Source formation, физический контракт и product admission
`mart.client_base_daily` подтверждены: S3-CBD-REFRESH-001 загрузил 1 657 353
агрегированные строки, а S3-KF-COMPOSITE-001 подтвердил полный contract пяти
фактов. Пустой dependency больше не существует.

## Вывод

`KPI Фитнеса` реализован как composite PostgreSQL contract без отдельного
DDL/DML-пакета и без новой KPI-таблицы. Power BI switch, внешние планы и
interactive DAX остаются отдельной границей реализации.

## Evidence

- [mapping KPI](../mappings/kpi_fitness.md);
- [contract KPI](../data_contracts/kpi_fitness.md);
- [ADR-0012](../adr/0012-kpi-fitness-composite-model.md);
- [catalog data products](../catalogs/data_products.md);
- [mapping client base](../mappings/client_base.md).
