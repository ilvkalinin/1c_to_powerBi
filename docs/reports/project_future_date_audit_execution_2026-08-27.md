# Исполнение: полный аудит будущих дат в физических витринах

Статус: `VALIDATED`.

## Граница и inventory

По каталогу `mart` найдены 30 physical base tables и 66 колонок типов
`date`/`timestamp`. Для контроля выбрана одна каноническая business-date
колонка на каждый факт: дата отчёта/движения/посещения/события/слота, а не
описательный атрибут строки. `marketing_funnel_task_contract.activation_date`
исключена из cleanup: это дата атрибута contract bridge, а business date bridge
наследует от parent `marketing_funnel_task.task_date`. Три значения `2029-08-31`
при текущих parent tasks поэтому не являются future fact rows и не удалялись.

`visit_client_day__loading` включён как physical base table: future rows = 0.
Views отсутствуют из scope. Source 1С и Power BI не менялись.

## Измерения до масштабирования

Точный target read-control `client_base_daily.report_date >= CURRENT_DATE + 1`
выполнился Index Only Scan за 5.805 ms (11 shared hit, 9 read). Для наиболее
тяжёлого неиндексированного класса выполнен месячный sample
`lesson_room_slot_5m.slot_start_at` в `[tomorrow; tomorrow + 1 month)`:
Parallel Seq Scan, 224 984 shared reads, 3.386 s и 24 520 строк. Это подтвердило
необходимость последовательного, а не параллельного full audit.

Перед cleanup четыре точных rollback-only месячных `DELETE` probes завершились
с rollback: dpfu plan 387.708 ms (Index Scan, 2 828 rows), group lesson
414.158 ms (Seq Scan, 3 245 rows), IP training 10.355 ms (Bitmap scan, 41 rows),
room slots 4.106 s (Seq Scan, 24 520 rows). Foreign-key review для этих четырёх
facts: 0 constraints.

## Full audit, cleanup и reconciliation

Полный последовательный canonical audit до cleanup обнаружил future rows только
в четырёх facts. Повторный atomic precheck на одном московском
`REPEATABLE READ` snapshot зафиксировал точные удалённые объёмы:

| Fact | Canonical column | Deleted future rows | Future rows after cleanup |
|---|---|---:|---:|
| `mart.dpfu_plan_assignment` | `plan_date` | 2 889 | 0 |
| `mart.group_lesson` | `lesson_start_at` | 3 957 | 0 |
| `mart.ip_training_daily` | `training_date` | 67 | 0 |
| `mart.lesson_room_slot_5m` | `slot_start_at` | 31 033 | 0 |
| Other 26 applicable physical facts | canonical date | 0 | 0 |

Всего удалено 37 946 строк. Каждая future-row проверка после commit дала 0 для
всех 30 physical facts по их canonical/inherited business date; clean dry-run
независимого script подтвердил direct canonical controls отдельной transaction.
Рост числа future schedule rows между первоначальным
read audit и precheck не был проигнорирован: deletion ориентировался только на
последний repeatable-read precheck и его exact row counts.

После cleanup выполнен `ANALYZE` для четырёх затронутых facts. Target
post-cleanup controls: dpfu plan 0.577 ms, group lesson 90.682 ms, IP training
0.031 ms, room slots 740.409 ms. У двух schedule facts нет индекса канонической
даты, поэтому их zero-row control остаётся full scan; индекс не добавлялся без
отдельного workload/SLA решения.

## Предотвращение повторения

Проверены действующие runners: `dpfu_plan_assignment` и `ip_training_daily`
вычисляют exclusive BR-003 horizon как Moscow `today + 1`, а `group_lesson` и
`lesson_room_slot_5m` импортируют тот же dynamic helper. Это согласуется с
очисткой исторически загруженных future rows; активных target writer sessions
перед apply не было. Следующий regular rerun этих facts обязан использовать
этот dynamic horizon и проходит отдельную source sample-plan проверку по
постоянному правилу проекта.
