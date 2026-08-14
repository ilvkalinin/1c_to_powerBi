-- S3-PLAN-001 — read-only source controls for mart.dpfu_plan_assignment.
-- Execute in REPEATABLE READ, READ ONLY. Dynamic BR-003 horizon.

WITH calendar_bounds AS (
    SELECT CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN 1 AND 3
                THEN (date_trunc('year', CURRENT_DATE) - INTERVAL '2 years')::date
                ELSE (date_trunc('year', CURRENT_DATE) - INTERVAL '1 year')::date
           END AS date_from,
           (date_trunc('year', CURRENT_DATE) + INTERVAL '1 year')::date AS date_to
), p AS (
    SELECT r._active, r._recordertref, r._recorderrref, r._lineno,
           r._fld6613::date AS plan_date, r._fld6614rref, r._fld6615rref,
           r._fld6616rref, r._fld6617rref, r._fld6619,
           r._fld6620::numeric(18,2) AS planned_revenue
    FROM public._inforg6612 r
    CROSS JOIN calendar_bounds b
    WHERE r._fld6613 >= b.date_from AND r._fld6613 < b.date_to
)
SELECT
    count(*)::bigint AS source_rows,
    coalesce(sum(planned_revenue), 0)::numeric(18,2) AS planned_revenue,
    count(*) FILTER (WHERE NOT _active)::bigint AS inactive_rows,
    count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)) AS duplicate_technical_keys,
    count(*) - count(DISTINCT (plan_date, _fld6615rref, _fld6614rref, _fld6616rref, _fld6617rref)) AS excess_without_discriminator,
    count(*) - count(DISTINCT (plan_date, _fld6615rref, _fld6614rref, _fld6616rref, _fld6617rref, _fld6619)) AS excess_with_discriminator,
    count(*) FILTER (WHERE plan_date IS NULL OR _fld6614rref IS NULL OR _fld6615rref IS NULL OR _fld6616rref IS NULL OR _fld6617rref IS NULL OR _fld6619 IS NULL OR planned_revenue IS NULL)::bigint AS null_required_components
FROM p;
