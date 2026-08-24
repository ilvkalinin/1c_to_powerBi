# Compatibility decision: услуга в «Воронке лиды фитнес»

Статус: `CONFIRMED user decision`.

## Решение

Воспроизводится current Power BI result, а не вводится новая дедупликация:

- если source `Задания[Услуга]` не пуст, все его строки сохраняются; две
  услуги одной задачи остаются двумя service-attributions;
- если прямой услуги нет, current DAX находит earliest booking date внутри
  current window и берёт лексикографический `MIN(НаименованиеУслуги)` на этой
  дате;
- raw early technical close dates не нормализуются.

## Физическая граница будущего продукта

`mart.fitness_leads_funnel_task` сохраняет grain one `task_id` and does not
contain a fabricated singular `service_name`. A future service consumer is a
separate bridge at task × current-service attribution grain. It is allowed to
contain multiple rows per task and must not be used to change task-count,
booking or training-count denominators.

## Evidence and impact

The decision preserves the current PBIT and the observed source cases: two
multivalued direct-service tasks, 1,432 earliest-day service ties, 951
multi-VT booking documents and 142,255 technical early end dates. Evidence:
`docs/source_metadata/fitness_leads_funnel_stage2_validation_2026-08-24.md`.

This package creates no SQL, object or source query. A later runnable-admission
package must contain immutable source extract, separate bridge key/cardinality
controls and source-to-target reconciliation for task fact and bridge.
