# RM-ASOF-S2-001: authorization and expected controls

Дата: 2026-08-29.

## User authorization

Пользователь явно подтвердил Stage 2 пакет ASOF-V01—V07 после Stage 1 design.

## Scope

Только короткие `REPEATABLE READ, READ ONLY` source/target sessions с
фиксированным SQL evidence. Запрещены DDL/DML/COPY, schedule, Power BI change,
new objects and any source mutation.

| ID | Expected before execution | Purpose |
|---|---|---|
| ASOF-V01 | current fact has one row per non-null contract ID and analytic snapshot columns remain nullable only as contract allows | eligibility of upstream reuse |
| ASOF-V02 | one current contract can produce at most one observation per run; current/previous state comparison has no ambiguous key | delta/tombstone feasibility |
| ASOF-V03 | current parent mart is committed atomically before any observation read | sequencing evidence from existing runner/target state |
| ASOF-V04 | a latest-observation selector can be unique by `(contract, observed_at)` | as-of query key design; no target observation relation exists yet |
| ASOF-V05 | each client/date has at most one deterministic effective rating and tenure source row, or ties are counted as a blocker | retrospective attributes |
| ASOF-V06 | interaction created/start dates and task-side state history establish whether selected interaction/funnel/fail can be known at a past date | CRM retrospective semantics |
| ASOF-V07 | contract dates/activation and source history establish whether earliest eligible next contract was known on a past date | next-contract/backdating semantics |

## Closure criterion

Для каждого ID сохранены exact SQL, source snapshot/connection result, actual
control value and status. Результат либо даёт proof forward observation и
retrospective field semantics, либо фиксирует конкретный `BLOCKER` / required
business decision. Не создаётся physical mart.
