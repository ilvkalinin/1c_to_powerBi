# Source-to-target mapping: групповые занятия

Статус: `IMPLEMENTED / initial BR-003 load VALIDATED — S3-GL-001—003`.

## Гранулярность и граница

Одна строка — одно непомеченное групповое занятие `Document279` в горизонте
BR-003 по `lesson_start_at`. Логический и физический key —
`group_lesson_id` (`Document279._IDRRef`); SV-072 PC-V11 подтвердил
уникальность ID. Помещение, представление документа, возрастная категория и
описания не входят: они не нужны согласованному контракту этой витрины.

`active_booking_count` и платные прибытия не пересчитывают `InfoRg7006`:
они агрегируют уже validated `mart.prebooking_state_event` только по ветви
`GZ`. Это сохраняет current M inner-join qualification статусов, включая
исключение special-service и orphan enum. `InfoRg8675` остаётся отдельным
источником бесплатных прибытий; SV-072 PC-V12 подтвердил максимум одну строку
на затронутое занятие.

## Поля

| Колонка | Источник / преобразование | Тип | NULL | Статус / evidence |
|---|---|---|---|---|
| `group_lesson_id` | `encode(Document279._IDRRef, 'hex')` | text | нет | CONFIRMED — PC-V11 unique ID |
| `lesson_created_at` | `Document279._Date_Time` | timestamp | нет | CONFIRMED current M output / metadata |
| `lesson_start_at`, `lesson_end_at` | `Fld3218`, `Fld3219` | timestamp | нет | CONFIRMED current M / PC-V11 |
| `club_id`, `employee_id`, `service_id` | encoded document `Fld3224/3223/3226` | text | нет | CONFIRMED current M document grain; employee inner join retains `Description IS NOT NULL` qualification |
| `activity_id` | document service `Reference163.Fld1733` through current left joins | text | да | CONFIRMED current M / physical metadata |
| `capacity` | `Fld3222::integer` | integer | да | CONFIRMED — PC-V11; 2026-08-14 no fractional source values |
| `is_free_program` | `Reference163.Fld1778 IS TRUE` | boolean | нет | CONFIRMED current M `Платное`: true produces “Бесплатное”; nullable source becomes false |
| `free_program_arrived_count` | `coalesce(InfoRg8675.Fld8677, 0)::integer` | integer | нет | CONFIRMED current M left join / PC-V12 single row |
| `active_booking_count` | `coalesce(sum(mart.prebooking_state_event.booking_delta), 0)` for `booking_kind='GZ'` | bigint | нет | CONFIRMED current M states 1/2/3 → `+1/-1`; shared fact preserves qualification |
| `arrived_count` | if a paid state-4 aggregate exists, its row count; otherwise free-program count | bigint | нет | CONFIRMED current M left-join precedence: paid arrivals first, then `InfoRg8675`, then 0 |

## Current-rule qualification

- BR-003 replaces static legacy dates with `lesson_start_at >= dynamic_from`
  and `< dynamic_to`; no other filter is widened;
- base lessons retain current M `Document279._Marked = false`, non-IP document
  service and employee presence; `Posted`, cancellation reason and other state
  flags are not added as filters;
- `mart.prebooking_state_event` is filtered only to `booking_kind='GZ'`; its
  documented status rules and inner-join exclusions remain unchanged;
- free attendance is not joined to raw state rows, preventing a hidden
  many-to-many multiplication.

## Reuse review

`mart.prebooking_state_event` is `REUSE` for paid group state aggregates;
`mart.dpfu_plan_assignment` has incompatible plan grain; no existing fact can
extend to lesson capacity without mixing grains. Decision: `NEW`
`mart.group_lesson` with one source-base stage and one shared state-fact join.

## Risks and safeguards

- Source document and registry club/service differ in some state rows
  (SV-072 PC-V05). Lesson dimensions remain document fields because current
  `Все уроки` uses the document; status count is joined only by lesson ID.
- Free attendance has no active flag. No invented source-state filter.
- A refresh of this fact requires a successful refresh of
  `mart.prebooking_state_event` first; otherwise it is a `BLOCKER`.
