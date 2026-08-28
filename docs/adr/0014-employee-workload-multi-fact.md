# ADR-0014: многомерная модель загрузки сотрудников

- Статус: `STAGE 2 VALIDATED / STAGE 3 SQL PLAN REQUIRED / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёт: №6 «Загрузка сотрудников»

## Контекст

Часы занятий/дежурств/купонов, присутствие СКУД, движения выручки и дневной
план имеют несовместимые ключи. Одна широкая таблица размножила бы часы,
выручку либо плановые назначения.

## Решение

Модель использует два новых компактных факта и повторно использует три общих:

- `mart.employee_activity_interval`: одно квалифицированное событие
  `занятие/дежурство/купон × сотрудник × клуб × интервал × тип`;
- `mart.employee_presence_day`: `сотрудник × дата × фактический клуб`, с
  суммарными минутами каждого visit, где client имеет хотя бы одну
  employee-карточку;
- REUSE `mart.ancillary_revenue_movement`,
  `mart.dpfu_plan_assignment` и `mart.ip_training_daily`.

Оба новых объекта — физические таблицы после source-side квалификации и
атомарной загрузки. Постоянный staging не нужен. View поверх сырых VM-1
отклонён; materialization поверх локальных таблиц рассматривается только при
измеренном нарушении SLA.

## Обновление и модель

Ежедневный bounded rebuild BR-003, без выдуманного watermark. Таблица порогов
отчислений остаётся внешним Power BI-фактом. Общие календарь, клуб,
деятельность и сотрудник фильтруют каждый факт однонаправленно; fact-to-fact
связей нет.

PostgreSQL воспроизводит current-M интервалы, длительность и raw-сумму
пересечений купон/дежурство, а затем применяет `GREATEST(0, …)` к чистому
дежурству по BR-040. В первом релизе он не заменяет raw-сумму union интервалов.
DAX считает сумму загрузки, долю,
процент от времени в клубе, эффективность и план-факт.

BR-044/BR-045 задают одну персональную СКУД-витрину: no-link visits исключены,
а multi-link visits получают `MIN(Reference225._idrref)` как произвольный
стабильный representative. Recommended storage is one physical table with
source-side aggregation; no persistent source replica, index or incremental
watermark is planned. Initial load and rebuild use derived monthly binary COPY
files prepared before a short target transaction, an advisory lock, temporary
target stages, `DELETE + INSERT` replacement and rollback on every failed
reconciliation. This is a full-rebuild baseline only.

## Риски

Ключи уроков, `VT4352`, source states, duty-grain и coupon grain проверены.
149 текущих `Table.Distinct` coupon keys имеют разный visit timestamp, но
одинаковые calendar day, duration, contract и dimension IDs, поэтому текущий
output grain воспроизводим. При
недоказанной однозначной связи СКУД строка не включается в
`employee_presence_day`. BR-044 исключает exact current-M no-link visits;
BR-045 выбирает произвольного, но стабильного employee representative для
multi-link visits. Это целевые правила, принятые после EPD Stage 2, а не
current-M атрибуция.
Historical employment attribution также отложена из-за 655 nonpositive и 187
overlapping intervals. См. Stage 2 evidence.

## Доказательства

- [Требования](../reports/employee_workload.md)
- [Mapping](../mappings/employee_workload.md)
- [Stage 2 evidence](../reports/employee_activity_interval_stage2_validation_2026-08-27.md)
- [Follow-up evidence](../reports/employee_activity_interval_followup_validation_2026-08-27.md)
- [EPD decision](../reports/employee_presence_day_attribution_decision_2026-08-28.md)
- [Any-link attribution decision](../reports/employee_presence_day_any_link_attribution_decision_2026-08-28.md)
