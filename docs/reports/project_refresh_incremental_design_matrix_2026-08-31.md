# Readiness matrix: incremental refresh design

Пакет: `project_refresh_incremental_design_2026-08-31`. Статусы ниже относятся
только к возможности automatic incremental refresh; они не меняют acceptance
существующих физических витрин.

| DAG job | Physical targets | Status | Evidence / decision |
|---|---|---|---|
| `administrator_bookings_daily` | `mart.administrator_bookings_daily` | `BLOCKED` | Runner существует только как незакоммиченный файл и отсутствует в `HEAD`/GitHub release. Нельзя анализировать или автоматизировать unversioned implementation. |
| `administrator_card_gymmy_daily` | `mart.administrator_card_gymmy_daily` | `FULL_REBUILD_ONLY` | `public._inforg5836`: 54,730,751 rows; columns only `_period` plus event payload, no active/deletion marker, update/version timestamp or change feed. `_period` is event time. Late changes/deletions cannot be reconciled by a watermark; current atomic BR-003 rebuild remains the only evidence-based mode. |
