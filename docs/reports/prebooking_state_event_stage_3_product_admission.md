# Stage 3 PRODUCT ADMISSION: `mart.prebooking_state_event`

Статус: `IMPLEMENTED / initial BR-003 load VALIDATED — S3-PB-001—004`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.prebooking_state_event` 2026-08-14.
Граница пакета — один state-event fact; `mart.group_lesson`, views и внешние
источники в него не входят. DDL и DML требуют отдельных явных разрешений.

## Confirmed current-rule base

- state technical key is unique; PZ/GZ document branches are mutually
  exclusive (SV-072 PC-V02/V03);
- current M removes orphan enum through `INNER JOIN`; it does not introduce
  new `Active`, `Posted` or `Marked` filters;
- registry club/service are preserved despite document mismatches;
- PZ retains qualifying `VT4352` rows and GZ remains one event per technical
  key. This is a BR-018 safeguard, not an accidental new aggregation;
- BR-003 replaces static legacy dates but retains current filter field:
  `lesson_start_at`.

VM-2 precheck: PostgreSQL 18, schema `mart` is createable and
`mart.prebooking_state_event` is absent. Source extract typecheck confirmed
all 21 mapped columns without reading data.

## DDL review completed

For separate DDL approval prepared [DDL](prebooking_state_event_ddl_review.sql),
[source extract](../../sql/marts/prebooking_state_event_extract.sql),
[atomic target replace](../../sql/marts/prebooking_state_event_target_replace.sql)
and [loader](../../scripts/load_prebooking_state_event.py). The loader refuses
DML without `--apply` and reconciles source rows, PZ/GZ rows, arrivals, net
delta, the nullable legacy key and contract violations.

After separate explicit DDL approval 2026-08-14, created
`mart.prebooking_state_event`. Post-check: 21 columns, table rows = 0 and
`UNIQUE NULLS NOT DISTINCT` legacy key — passed.

## Initial DML load and reconciliation completed

After separate explicit DML approval 2026-08-14, the loader completed one
atomic BR-003 rebuild. The source snapshot before target `COPY` contained
2,389,981 rows: PZ 575,206; GZ 1,814,775; arrived 133,284; net
`booking_delta` 1,686,747. Persisted mart controls matched exactly.

`S3-PB-001` source-to-target controls — `PASS`; `S3-PB-002` nullable legacy
key duplicates = 0 — `PASS`; `S3-PB-003` BR-003 out-of-horizon rows,
required contract nulls and invalid state delta = 0 — `PASS`; `S3-PB-004`
branch/status totals retained — `PASS`. Reproducible read-only SQL:
[`prebooking_state_event_reconciliation.sql`](../../sql/tests/prebooking_state_event_reconciliation.sql).
ПЗ сохраняет 16,749 строк legacy-кратности `VT4352`: 558,457 state-events →
575,206 физических строк; это подтверждает BR-018 для initial load.

Performance review: all 21 fields remain contract-required. A narrow
source-control query was independently proven equivalent to the full extract
in one repeatable-read snapshot (2,389,967 rows / delta 1,686,736), while
running in 30.2 s versus 34.9 s. The load performs binary `COPY` directly to
the protected mart after that source control, avoiding the former second
staging-to-table write; any error rolls back the whole rebuild.
