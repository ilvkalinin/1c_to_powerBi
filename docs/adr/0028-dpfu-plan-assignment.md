# ADR-0028: общий детальный план ДПФУ

- Статус: `IMPLEMENTED / initial BR-003 load VALIDATED`
- Дата: 2026-08-14
- Потребители: KPI Фитнеса, «Выручка ДПФУ», контроль предзаписи, загрузка сотрудников

## Решение

Создать один физический факт `mart.dpfu_plan_assignment` с grain:

> дата плана × клуб × подразделение × тренер × плановый клиент × technical plan-line discriminator.

`InfoRg6612.Fld6617` является плановым клиентом. `Fld6619` — обязательный
технический различитель: без него в BR-003 есть 95 357 повторов, с ним — 0.
Он не переводится в client key, хотя один legacy query использует для него
неверную пользовательскую подпись; это зафиксированный артефакт для будущей
доработки, а не правило нового факта.

## Архитектура и refresh

`read-only source projection → temporary target stage → mart table → Power BI
Import`. Постоянный staging/core не создаётся. Ежедневный полный bounded
rebuild BR-003 выбран, поскольку watermark и правила поздних исправлений не
подтверждены. Сумма и знак плана рассчитываются в PostgreSQL; план-факт и
агрегации до day×club остаются в DAX/потребительской модели.

## Последствия и риски

- факт сохраняет все назначения, включая 30 отрицательных строк; `_Active`
  не становится фильтром без нового решения;
- `planned_client_key` — encoded source ID. `planned_client_code` — только
  отдельное detail-поле; BR-007 не расширяется на новый ключ без решения;
- DDL выполнен 2026-08-14: таблица пустая, восемь согласованных колонок и
  primary-key post-check пройдены. DML требует отдельного approval, а initial
  load — reconciliation.

## Evidence

- [mapping](../mappings/dpfu_plan.md)
- [admission](../reports/dpfu_plan_stage_3_product_admission.md)
- [KPI composite ADR](0012-kpi-fitness-composite-model.md)
