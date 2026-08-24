# Stage-2 source validation: «Воронка лиды фитнес»

Статус: `VALIDATED WITH BLOCKER`.

Scope — V-01—V-09 and V-11 in [authorization](../reports/fitness_leads_funnel_stage_2_server_validation_authorization_2026-08-24.md). Every check used an isolated `REPEATABLE READ, READ ONLY` source snapshot with `statement_timeout = 30s`; neither 1С nor VM-2 was written.

| Check | Status | Snapshot / elapsed | Expected before execution | Actual result |
|---|---|---|---|---|
| FL-V01 | PASS | `12388792:12388792:` | all mapped relations/columns resolve | CRM, booking and DPFU relations resolve in `public`; IDs are `bytea`, dates `timestamp`, and `_marked`/`_active`/`_posted` exist |
| FL-V02 | PASS | `12389190:12389190:`, 1.4s | no duplicate task ID; code measured independently | 166,792 tasks = 166,792 distinct IDs = 166,792 distinct codes; 0 NULL/duplicate codes |
| FL-V03 | VALIDATED | `12389260:12389260:`, 0.891s | raw four-funnel counts reproducible | three names occur in 2025; «Запись на тренировку КЦ» first occurs in 2026; raw count 166,792, current two duplicate-reason filters leave 166,720 |
| FL-V04 | PASS | `12389260:12389260:`, 0.586s | dimensions preserve task grain | 166,792 task rows = joined rows = distinct task IDs; excess 0 |
| FL-V05 | FAIL | `12389489:12389489:`, 3.085s | no multivalued current service join | 166,792 tasks, 166,794 joined rows, excess 2; 2 multirow / multiservice tasks; 141,335 without current service match |
| FL-V06 | FAIL | `12389680:12389680:`, 1.906s | no unrecorded booking multiplication | 19,450 matched registry rows; dual document branch 0, orphan branch 0; 951 documents have multiple VT4352 lines (max 18) |
| FL-V07 | VALIDATED | `12389680:12389680:`, 1.671s | states are recorded, not inferred | active task rows: 166,792 `marked=false`; matched registry: 27,003 `active=true`; Document329: 11,309 `marked=false, posted=true`; Document279: 15,624 `marked=false, posted=true`, plus 70 `marked=true, posted=false` |
| FL-V08 | PASS with NULL case | `12389997:12389997:`, 2.811s | code unambiguous and representable | 112,460 task clients / 112,459 distinct codes; 12 raw tasks have NULL code; 0 rows with ambiguous code. After exact duplicate-reason filters blank-code branch is 0 (`12390633:12390633:`, 2.774s). |
| FL-V09 | FAIL for normalized window / VALIDATED current rule | `12389862:12389862:`, 0.469s; `12390304:12390304:`, 20.610s; `12390456:12390456:`, 10.102s | inclusive bounds and time anomalies recorded | `closed_before_created=92,789`, `forced_closed_before_created=141,697`; current `MINX` service end is before task start for 142,255 of 166,720 filtered tasks. 8,459 tasks have a booking in current window; 1,432 have an earliest-day multi-service tie. DPFU events: 4,694 at start and 1,842 at day 45. |
| FL-V11 | PARTIALLY VALIDATED | `12390148:12390148:`, 11.416s | current PBIT source controls | 166,720 tasks; 65,659 stage-based booking tasks; 12,157 positive-training tasks; `training_count` sum 63,142 |

## Evidence and reconciliation status

The physical task grain is confirmed: one `public._reference106._idrref` (`bytea`) per raw task. CRM task/dimension keys, BR-003 scope, client-code non-ambiguity, current DPFU filters and inclusive 45-day evidence are source-confirmed. Executed control text is retained in [validation SQL](validation_sql/fitness_leads_funnel_stage2_2026-08-24.sql) and in PBIT `DataModelSchema` (`ДПФУ факт`, `Записи`, `УслугаДляЗаписи`, `Сумма ДПФУ за 45 дней`, `КоличествоТренировок`).

Source-to-Power-BI reconciliation is `BLOCKED`: no independently confirmed Power BI display filters/control values were supplied, and no target mart exists. The source controls must not be represented as a screen match or target rerun.

## Runnable-admission blocker

Two current service rows for two tasks and 1,432 earliest-day DAX service ties have no approved source-side selector. Current DAX also accepts raw technical close dates earlier than task creation. A normalisation, arbitrary priority or `MIN` substitution would alter current result and requires a separate business decision. Raw VT4352 cannot join a one-task fact because 951 relevant documents have multiple lines. No DDL/DML, target load or Power BI change is authorized.
