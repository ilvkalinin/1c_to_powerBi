# Readiness matrix: incremental refresh design

Пакет: `project_refresh_incremental_design_2026-08-31`. Статусы ниже относятся
только к возможности automatic incremental refresh; они не меняют acceptance
существующих физических витрин.

| DAG job | Physical targets | Status | Evidence / decision |
|---|---|---|---|
| `administrator_bookings_daily` | `mart.administrator_bookings_daily` | `BLOCKED` | Runner существует только как незакоммиченный файл и отсутствует в `HEAD`/GitHub release. Нельзя анализировать или автоматизировать unversioned implementation. |
| `administrator_card_gymmy_daily` | `mart.administrator_card_gymmy_daily` | `FULL_REBUILD_ONLY` | `public._inforg5836`: 54,730,751 rows; columns only `_period` plus event payload, no active/deletion marker, update/version timestamp or change feed. `_period` is event time. Late changes/deletions cannot be reconciled by a watermark; current atomic BR-003 rebuild remains the only evidence-based mode. |
| `children_package_sale` | `mart.children_package_sale` | `FULL_REBUILD_ONLY` | BR-039 output depends on `AccumRg7646`, `Document346`, `VT4913` and `VT4924`, including return report-groups. Only `Document346` exposes `_version`; movement and both tabular parts have no change field, and `AccumRg7646` has 4,923,880 rows with `_active=false` = 0. A document-only watermark misses late mutation/deletion of the remaining inputs, so no separate incremental runner is safe. |
