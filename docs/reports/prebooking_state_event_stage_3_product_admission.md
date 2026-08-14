# Stage 3 PRODUCT ADMISSION: `mart.prebooking_state_event`

Статус: `DML APPROVAL PENDING — empty target table created and verified`.

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
all 21 mapped columns without reading data. DDL/DML have not been performed.

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

Next constraint: first event load remains a separate DML approval. The loader
will perform a bounded rebuild and source-to-target reconciliation atomically.
