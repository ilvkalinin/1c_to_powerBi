# Source-to-target mapping: план ДПФУ

Статус: `STAGE_3 DML APPROVAL PENDING / empty target table CONFIRMED`.

## Гранулярность и граница

Одна строка целевого факта — одно назначение текущего плана:

> дата плана × клуб × подразделение × тренер × плановый клиент × технический различитель строки.

Источник — `InfoRg6612`. `Fld6617` — ссылка на планового клиента;
`Fld6619` не является клиентом и хранится только как hidden discriminator.
Детальный факт не агрегируется до `день × клуб`: такое свёртывание нужно
только отдельным потребителям и уничтожит подтверждённые разрезы KPI.

## Целевые поля

| Колонка | Источник / преобразование | Тип | NULL | Статус / evidence |
|---|---|---|---|---|
| `plan_date` | `InfoRg6612._Fld6613::date` | `date` | нет | CONFIRMED — current M; S3-PLAN-001 timestamp source |
| `club_id` | `encode(InfoRg6612._Fld6615RRef, 'hex')` | `text` | нет | CONFIRMED — S3-PLAN-001, orphan 0 |
| `activity_id` | `encode(InfoRg6612._Fld6614RRef, 'hex')` | `text` | нет | CONFIRMED — S3-PLAN-001, orphan 0 |
| `employee_id` | `encode(InfoRg6612._Fld6616RRef, 'hex')` | `text` | нет | CONFIRMED — S3-PLAN-001, orphan 0 |
| `planned_client_key` | `encode(InfoRg6612._Fld6617RRef, 'hex')` | `text` | нет | CONFIRMED — клиентская ссылка, S3-PLAN-001; не заменять `_Code` без отдельного решения |
| `planned_client_code` | `Reference141X1._Code::text` по `Fld6617` | `text` | нет | CONFIRMED detail consumer; 14 132 scoped codes, blank/duplicate 0 |
| `plan_line_discriminator` | `encode(InfoRg6612._Fld6619, 'hex')` | `text` | нет | CONFIRMED — 0 matches `Reference141X1`; required for unique logical key |
| `planned_revenue` | `InfoRg6612._Fld6620::numeric(18,2)` | `numeric(18,2)` | нет | CONFIRMED — source scale ≤ 2; sign is preserved |

## Current-rule qualification

- BR-003 sets the dynamic horizon; in August 2026 it is
  `2025-01-01`—`2027-01-01`;
- `_Active` is not a new filter: current M does not filter it and the current
  scope has zero inactive rows;
- the shared fact keeps all clubs and activities. Any report-specific club
  exclusion is a consumer filter and must not remove source plan assignments;
- 30 negative plan rows remain; source has no zero amounts. Excluding or
  normalising them would change the current result and is forbidden by BR-018.

## S3-PLAN-001 — source snapshot 2026-08-14

One `REPEATABLE READ, READ ONLY` snapshot for BR-003:

| Контроль | Результат |
|---|---:|
| source rows / planned revenue | 528 482 / 722 999 695,41 |
| date range | 2025-01-01 — 2026-09-30 |
| inactive / duplicate technical keys | 0 / 0 |
| excess without / with discriminator | 95 357 / 0 |
| null required components / club, activity, employee, client orphans | 0 / 0, 0, 0, 0 |
| `Fld6619` values matching a client | 0 |
| blank / duplicate scoped client codes | 0 / 0 |
| negative / zero plan amounts | 30 / 0 |

## Риски и возможные доработки

| Элемент | Статус | Следующее действие |
|---|---|---|
| Исторический отчёт «Выручка ДПФУ» агрегирует план до дня × клуба и местами исключает клубы в Power Query | NOT FIRST RELEASE | сохранять детальный общий факт; report-level aggregation/filter не переносить в source qualification |
| `Fld6619` в одном legacy query визуально назван клиентом | CONFIRMED technical mismatch | не менять его роль: source control доказал, что он не связан с `Reference141X1` |
