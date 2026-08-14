# Source-to-target mapping: события предзаписи

Статус: `STAGE_3 ADMISSION / current-rule source mapping CONFIRMED`.

## Гранулярность и граница

Физическая строка первого релиза:

> state-event × qualifying строка взаиморасчётов `Document329.VT4352` для ПЗ; одно state-event для ГЗ.

Это намеренная legacy-совместимость. Current M ПЗ соединяет `VT4352` только
по документу и оставляет каждую qualifying строку; SV-072 наблюдал 1 554 042
state-events → 1 613 623 legacy rows. Дедупликация изменила бы текущие
количества, поэтому запрещена BR-018.

Горизонт BR-003 применяется к `lesson_start_at`, потому что exact current M
фильтрует `Document329.Fld4306` / `Document279.Fld3218`, а не время изменения
состояния. Статическая дата legacy query заменяется только dynamic bounds.

## Целевые поля

| Колонка | Источник / преобразование | Тип | NULL | Статус / evidence |
|---|---|---|---|---|
| `state_event_at` | `InfoRg7006._Period` | timestamp | нет | CONFIRMED current M / physical metadata |
| `booking_kind` | `Document329` → `PZ`; `Document279` → `GZ` | text | нет | CONFIRMED — SV-072 PC-V03; branches disjoint |
| `recorder_tref`, `recorder_id`, `source_line_no` | encoded `RecorderTRef`, `RecorderRRef`, `_LineNo::integer` | text, text, integer | нет | CONFIRMED — technical key unique, SV-072 PC-V02 |
| `legacy_settlement_line_no` | `Document329.VT4352._LineNo4353`; `NULL` for GZ | integer | да | CONFIRMED — preserves current PZ row multiplication |
| `booking_document_id` | encoded `InfoRg7006._Fld7007_RRRef` | text | нет | CONFIRMED current M |
| `lesson_start_at`, `lesson_end_at` | PZ `Document329.Fld4306/07`; GZ `Document279.Fld3218/19` | timestamp | нет | CONFIRMED current M |
| `club_id`, `service_id` | encoded registry `InfoRg7006.Fld7009/Fld7010` | text | нет | CONFIRMED current M; registry values are not replaced by document values |
| `activity_id` | document service `Reference163.Fld1733` through current left join | text | да | CONFIRMED current M; do not replace with registry service |
| `employee_id` | PZ `Document329.Fld4322`; GZ `Document279.Fld3223` | text | нет | CONFIRMED current M; inner join preserves current exclusion of missing employee |
| `client_key` | encoded `InfoRg7006.Fld7008` | text | нет | CONFIRMED stable source reference; `_Code` not promoted to key |
| `client_code`, `client_name` | `Reference141X1._Code`, `_Description` | text | да | CONFIRMED PII detail BR-017; one source code is blank, therefore nullable |
| `state_order` | `Enum448._EnumOrder` | smallint | нет | CONFIRMED current inner join; 104 orphan-enum state rows stay excluded |
| `event_category` | current cutoff CASE by state/time | text | нет | CONFIRMED current M: legacy “До 9:00” means before midnight lesson date |
| `booking_delta` | order 1 → +1; 2/3 → −1; 4 → 0 | smallint | нет | CONFIRMED current DAX branch |
| `cancelled_before_lesson` | state 2/3 and `_Period < lesson_start_at` | boolean | да | CONFIRMED current M |
| `is_paid_booking` | PZ qualifying branch → true; GZ `Document279.Fld3228` | boolean | нет | CONFIRMED current branch-specific filters |

## Current-rule qualification

- both branches exclude registry service `bcd000505688c8b011ee0a8ba155d4a1`;
- PZ keeps only orders 1/2/3, excludes employee-settlement lines
  `a0f1524d502e0d5d4c1dfeb9d5bbb3fe` and coupon parent
  `4296a4bf013441d111e7cae05001072c`; null document-service parent remains
  non-coupon as in current Power Query CASE;
- GZ keeps orders 1/2/3/4 and exposes its prepayment flag. Consumer measures
  retain their current order-specific filters;
- no `_Active`, `Posted` or `Marked` filter is added. Their observed state is
  evidence, not a new business rule.

## Confirmed source evidence

SV-072 established technical key uniqueness, mutually exclusive document
branches, complete current inner-join client/club coverage, current
inner-join exclusion of 104 orphan-enum rows, and document-vs-registry
mismatches. The product deliberately takes club/service from `InfoRg7006` and
employee/time/activity from the document branch, precisely matching current M.

## Пул возможных методических доработок

| Идея | Наблюдаемый эффект | Статус |
|---|---|---|
| Схлопнуть ПЗ до одного state-event без строк `VT4352` | изменит текущие counts: в SV-072 1 554 042 events стали 1 613 623 rows | NOT FIRST RELEASE — отдельное явное решение |
| Подменять registry club/service документными | SV-072 нашёл service mismatch 1 871 ГЗ / 22 093 ПЗ и club mismatch 4 ПЗ | NOT FIRST RELEASE — отдельное решение атрибуции |
