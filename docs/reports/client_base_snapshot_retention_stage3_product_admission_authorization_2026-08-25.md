# Авторизация Stage 3 product admission: физические snapshot и retention

- Дата: 2026-08-25
- Пакет: `client_base_snapshot_retention_stage3_product_admission_2026-08-25`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёты: `client_base_snapshot`, `client_base_retention`
- Основание: пользователь подтвердил «завершение этих витрин» 2026-08-25 и
  затем отдельно подтвердил, что это разрешение означает доведение витрин до
  физического результата.

## Разрешённый scope

Создать и атомарно загрузить на VM-2 физические aggregate facts
`mart.client_base_snapshot` и `mart.client_base_retention` с подтверждёнными
BR-037/BR-038 package rules. В scope входят закрытие технического reviewed set,
source sample/full baseline, независимые source controls, target DDL, bounded
binary-COPY transport, reconciliation, atomic full rerun, target plans/sizes,
документация и commit. Power BI и source 1С не изменяются.

## Финальный immutable reviewed set

- `sql/marts/client_base_snapshot_extract.sql`
- `sql/marts/client_base_retention_extract.sql`
- `sql/marts/client_base_daily_source_controls.sql` (independent snapshot totals)
- `sql/marts/client_base_retention_source_control.sql` (independent retention cohorts)
- `sql/marts/client_base_snapshot_ddl.sql`
- `sql/marts/client_base_retention_ddl.sql`
- `sql/marts/client_base_snapshot_target_replace.sql`
- `sql/marts/client_base_retention_target_replace.sql`
- `scripts/load_client_base_snapshot_retention.py`
- `requirements-mart-runners.txt`
- `sql/tests/client_base_snapshot_retention_reconciliation.sql`

Runner создает ровно `mart.client_base_snapshot` и
`mart.client_base_retention`, затем временные target stages. В одном
`REPEATABLE READ, READ ONLY` source owner экспортирует один snapshot;
независимый дочерний reader для каждого `fact × month` присоединяется к этому
же snapshot и снимает independent control до COPY именно этого месяца. Каждая
агрегатная порция проходит через ровно один temporary binary COPY file; после
target COPY этот файл удаляется. Source reader имеет 180-second hard cap в
отдельном процессе и новое соединение при retry, поэтому зависший transport
не переиспользуется и не удерживает target COPY. Target DDL и полная замена
обеих facts происходят в одной target transaction под advisory lock. До commit
runner проверяет накопленные source→stage→target totals, key/contract/horizon;
ошибка откатывает всю target transaction. Автоматический `DROP` не выполняется.

`--initial-load` допускается, только если обе таблицы отсутствуют; `--rerun`
требует обе существующие и использует новый independent source snapshot. Grain,
источники, колонки, BR-037/BR-038 и Power BI boundary зафиксированы; их
изменение вне scope.

## Проверка preflight

- Retention contract-grain fix: previous extract grouped by hidden
  `birth_date`, which split a single visible age category and created up to
  1 386 666 monthly rows. It now groups by `current_age_years` and
  `current_age_group` — the mapped contract grain. `2026-07` output is
  52 514 rows, month controls = 20, deviations = 0, duplicate contract keys =
  0. No row is client-level.
- Exact retention month `2026-07-01..2026-08-01`: 52 514 rows, 27.646 s,
  2 578 666 shared-hit blocks and 167 669 temp-read blocks with default
  `work_mem=32MB`. The saved compare with session-local `work_mem=128MB`
  returned the same 52 514 rows in 26.240 s and 35 819 temp-read blocks.
  Only the retention COPY stage uses that measured transaction-local setting.
- Independent `2026-07` controls and extract aggregation совпали для всех
  20 `report_date × year_start/previous_year × club/network` values;
  deviations = 0.
- Exact one-shot retention horizon `[2025-01-01, 2027-01-01)` exceeded a
  20-minute statement timeout even after the contract-grain correction. It is
  therefore explicitly rejected as a delivery query. The reviewed delivery
  plan scales the measured monthly query inside one source snapshot; the
  runner's monthly control path was executed successfully for July (snapshot
  controls 10, retention controls 20).
- Target PostgreSQL 18.3 поддерживает `UNIQUE NULLS NOT DISTINCT`; обе facts
  физически отсутствуют перед initial DDL.
- Transport redesign does not change mapping, SQL or source snapshot semantics:
  `pg_export_snapshot()` → fresh per-month readers was validated on the source.
  It is a safe Stage-3 implementation control after observed TCP `ClientWrite`
  stalls, not a new business rule.

## Критерий закрытия

Обе таблицы созданы и загружены одной атомарной операцией, source/stage/target
controls имеют нулевые отклонения, contract/key/horizon tests и target plans
успешны, полный atomic rerun успешен со своим source snapshot, а Power BI
остается без изменений.
