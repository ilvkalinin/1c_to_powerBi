-- REVIEW ONLY — target DML is not approved by this file.
-- Product: mart.client_base_daily.
-- Scope: BR-003 full atomic rebuild over [2025-01-01, 2027-01-01) on 2026-08-19.
-- No raw memberships, client IDs or PII are transferred to VM-2.
--
-- Full source aggregate: sql/marts/client_base_daily_extract.sql.
-- Independent source totals: sql/marts/client_base_daily_source_controls.sql.
-- Runner: scripts/load_client_base_daily.py (refuses to write without --apply).
-- VM-1 runs READ ONLY with a hard 60-second statement cap: the independently
-- measured query completes in less time, but binary transfer of 1.66m rows
-- needs more than the former 30-second cap.

-- VM-1:
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '60000';
-- Capture independent source controls, then stream only the seven aggregate
-- fields through binary COPY. No source-side write is possible.
ROLLBACK;

-- VM-2:
BEGIN;

SELECT pg_advisory_xact_lock(hashtext('mart.client_base_daily:refresh'));

CREATE TEMP TABLE _client_base_daily_stage (
    LIKE mart.client_base_daily INCLUDING DEFAULTS
) ON COMMIT DROP;

CREATE TEMP TABLE _client_base_daily_expected (
    report_date date NOT NULL,
    scope_level text NOT NULL,
    client_count bigint NOT NULL,
    PRIMARY KEY (report_date, scope_level)
) ON COMMIT DROP;

-- Binary COPY streams the already aggregated seven fields from VM-1 into the
-- stage. Before any delete, the runner verifies the stage key, every schema
-- invariant, horizon and exact equality with independent source totals.
COPY _client_base_daily_stage (
    scope_level, report_date, club_id, age_years, age_group, gender, client_count
) FROM STDIN WITH (FORMAT BINARY);

DELETE FROM mart.client_base_daily
WHERE report_date >= DATE '2025-01-01'
  AND report_date < DATE '2027-01-01';

INSERT INTO mart.client_base_daily (
    scope_level, report_date, club_id, age_years, age_group, gender, client_count
)
SELECT scope_level, report_date, club_id, age_years, age_group, gender, client_count
FROM _client_base_daily_stage;

-- The runner verifies persisted daily scope totals against the same independent
-- source snapshot before COMMIT. Any failure rolls this transaction back.
COMMIT;

-- After COMMIT, rollback is a separate approved change. No Power BI source,
-- schedule, snapshot/retention table or source object changes here.
