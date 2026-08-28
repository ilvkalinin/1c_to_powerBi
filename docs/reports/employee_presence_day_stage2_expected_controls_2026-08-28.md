# Expected controls before execution: `employee_presence_day`

- Package: `employee_presence_day_stage2_validation_2026-08-28`
- Environment: 1C PostgreSQL VM-1, fresh `REPEATABLE READ, READ ONLY` session
  for each statement via `connect_with_retry`.
- Horizon: BR-003 `[2025-01-01, 2026-08-28)`.
- SQL: [`employee_presence_day_source_controls.sql`](../../sql/marts/employee_presence_day_source_controls.sql).
- Target connection, DDL, DML, `COPY` and Power BI: not permitted.

| Check | Expected before execution | Independent evidence / status rule |
|---|---|---|
| EPD-V01 | Every mapped field of the current source path exists once in `public`; missing field is `BLOCKED`. | Inventory is independent of the business extract; physical names come from `Структура хранения базы данных.txt`. |
| EPD-V02 | The current M path is reproducible for BR-003 with its exact operation, service, club and end-of-day rules; all observed state and interval anomalies are retained as evidence. | Local query `Посещения сотрудников 2025-1 (4)` is separate from the new controls; it has no marked/posted predicate. |
| EPD-V03 | Every `AccumRg7575 → Document325 → employee` multiplication is reported. Any non-zero multiplication is evidence and cannot be silently deduplicated. | Independent per-visit cardinality aggregation over the same M path. |
| EPD-V04 | `visits_with_multiple_employee_links = 0`; any non-zero value is `BLOCKED` because one SКУД visit may not be assigned to an arbitrary employee. | Independent `Reference225` client-cardinality population, restricted only after measuring the exact current-M domain. |
| EPD-V05 | Candidate source contains only clients with exactly one employee; no negative clipped-minute aggregate is allowed. Its counts/minutes are an independent control value, not a target reconciliation. | Independent singular-domain aggregation; `min(employee_id)` is used solely where `count(employee_id)=1`, never as a tie-break. |

The final status is `VALIDATED` only if EPD-V01--V05 support a complete,
unambiguous source-to-target mapping. Otherwise the package closes with the
observed `BLOCKER` and does not create a mart.
