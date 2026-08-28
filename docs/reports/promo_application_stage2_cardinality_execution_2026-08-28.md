# `mart.promo_application`: Stage 2 cardinality execution

Статус: `VALIDATION_FAILED / DECISION_REQUIRED`.

## Граница выполнения

Выполнен ровно согласованный пакет
[`promo_application_stage2_cardinality_authorization_2026-08-28.md`](promo_application_stage2_cardinality_authorization_2026-08-28.md):
`PC-V02` и `PC-V04` из
[`promo_codes_2026-08-13.sql`](../source_metadata/validation_sql/promo_codes_2026-08-13.sql).
DDL, DML, `COPY`, extract, изменение SQL/M/DAX и Power BI не выполнялись.

Каждый control запущен в отдельной короткой `BEGIN READ ONLY` сессии через
`scripts.mart_connection.connect_with_retry`, с `statement_timeout = 30000`.
Источник: `gymdb`, роль `gymdb_readonly`, `transaction_read_only = on`.
Результаты — только агрегаты, без PII и raw identifiers.

| Check | Executed at (UTC) | Duration | Expected before run | Actual | Status |
|---|---:|---:|---|---|---|
| PC-V02 | 2026-08-28T07:43:23.802007+00:00 | 0.944 s | Historical SV-091 observed 7,535 → 7,568 and excess 33; positive excess must remain a risk, not an automatic dedupe | base technical rows 7,535; joined rows 7,568; distinct technical keys 7,535; excess 33; Document332/VT4996/VT4924 matches 5,824/310/309 | `VALIDATION_FAILED` for one-to-many preservation; exact historical observation repeated |
| PC-V04 | 2026-08-28T07:43:24.745760+00:00 | 0.526 s | action parent orphan = 0; other cardinalities are observations and positive gift excess remains a risk | action rows 7,904; parent/null-discount 0/0; duplicate-discount groups 905; gift technical rows 11,698; joined rows 4,509; gift excess 406 | parent integrity `VALIDATED`; overall `VALIDATION_FAILED` for one-to-many gift join; historical risk repeated |

## Вывод

Результаты SV-091 не были transient-артефактом: bounded June-2026 current-M
joins по-прежнему размножают technical movements. Поэтому текущий результат
можно только сохранить по BR-018; source-side deduplication, выбор одной
document/gift line или изменение агрегирования будут методическим изменением.

`mart.promo_application` не допускается к Stage 3 planning, пока пользователь
отдельно не выберет воспроизводимую методику для этой кратности. Нулевые
action parent-orphans не снимают данную развилку.
