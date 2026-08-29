# RM-S3-TECH-001: immutable extract scope

Status: `VALIDATED`; admission package is ready, but no target operation has yet run.

One target row is one retained source contract. The reviewed column set is:

`expiring_contract_id`, `expiring_contract_code`, `client_id`, `client_code`,
`client_name`, `client_phone`, `birth_date`, `membership_start_date`,
`membership_end_date`, `contract_end_month`, `membership_term_days`,
`access_club_id`, `purchase_price`, `visit_count`, `usage_rate`,
`average_monthly_visits`, `renewed_by_month_close_flag`,
`renewed_current_flag`, `next_contract_id`, `next_contract_code`,
`renewal_activation_date`, `next_contract_start_date`,
`next_contract_term_days`, `renewal_type`, `renewal_lead_lag_days`,
`return_days`, `return_bucket`, `current_rating`, `current_tenure`,
`last_interaction_at`, `last_interaction_type`, `current_funnel_stage`, and
`current_fail_reason`.

Technical IDs are `encode(bytea, 'hex')::text`. BR-050 orders next-contract
ties as paid first then minimum technical ID and interaction ties as minimum
technical ID. The extract preserves current M's cohort, price `RecordKind=0`,
and visit `COUNT(*)` predicates without a new state filter.

## Source-plan evidence

All runs used one `REPEATABLE READ, READ ONLY` source session and no parallel
heavy query or transport.

| Run | Horizon | Rows | Execution | Key evidence |
|---|---|---:|---:|---|
| representative sample | 2025-01-15 | 161 | 3.715 s | exact extract; 3,397,796 legacy visit rows scanned |
| scaling sample | 2025-01 | 6,534 | 15.402 s | interaction 9.935 s; exact extract |
| full baseline | 2024-01-02..2027-02-01 | 240,969 | 89.433 s | interaction 45.230 s; visits 24.054 s; no timeout |
| independent controls | 2024-01-02..2027-02-01 | 240,968 | 31.479 s | price 5,147,421,379.41; visits 1,898,933 |

The full extract and controls use different live snapshots, so their one-row
difference is not a reconciliation result. The loader repeats the controls and
exact `COPY` in one source snapshot and refuses to open the target transaction
when their row counts differ.

`enable_nestloop=off` was tested only session-locally on the same one-day
sample and worsened time from 10.076 s to 23.289 s while triggering full scans;
it is explicitly not used. The final source extract uses hash full joins only
because every auxiliary CTE is a demonstrated subset of the cohort, preserving
row semantics while preventing CTE-estimation-driven quadratic joins.
