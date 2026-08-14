-- Global read-only review: physical keys and recurring-payment candidates.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '60000';

-- Full BR-003 source states; technical movement key is guaranteed by the
-- unique indexes (_recordertref, _recorderrref, _lineno).
SELECT source_kind, active, recordkind, rows_total, null_key_rows,
       null_amount_rows, negative_amount_rows
FROM (
    SELECT '7370'::text AS source_kind, _active AS active,
           _recordkind AS recordkind, count(*) AS rows_total,
           count(*) FILTER (WHERE _recordertref IS NULL OR _recorderrref IS NULL
                             OR _lineno IS NULL) AS null_key_rows,
           count(*) FILTER (WHERE _fld7377 IS NULL) AS null_amount_rows,
           count(*) FILTER (WHERE _fld7377 < 0) AS negative_amount_rows
    FROM public._accumrg7370
    WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01'
    GROUP BY 1, 2, 3
    UNION ALL
    SELECT '7739', _active, _recordkind, count(*),
           count(*) FILTER (WHERE _recordertref IS NULL OR _recorderrref IS NULL
                             OR _lineno IS NULL),
           count(*) FILTER (WHERE _fld7749 IS NULL),
           count(*) FILTER (WHERE _fld7749 < 0)
    FROM public._accumrg7739
    WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01'
    GROUP BY 1, 2, 3
) AS source_states
ORDER BY 1, 2, 3;

-- Candidate 1: contract × analytics sequence.
WITH candidate AS (
    SELECT _fld7371rref AS contract_id, _fld7376rref AS analytics_id,
           count(*) AS movement_rows
    FROM public._accumrg7370
    WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01'
    GROUP BY 1, 2
)
SELECT count(*) AS candidate_keys,
       count(*) FILTER (WHERE analytics_id IS NULL) AS null_analytics_keys,
       count(*) FILTER (WHERE movement_rows > 1) AS duplicate_candidate_groups,
       coalesce(max(movement_rows), 0) AS max_rows_per_candidate
FROM candidate;

-- Candidate 2: contract × recorder document.
WITH candidate AS (
    SELECT _fld7371rref AS contract_id, _recordertref AS recorder_type,
           _recorderrref AS recorder_id, count(*) AS movement_rows
    FROM public._accumrg7370
    WHERE _period >= DATE '2025-01-01' AND _period < DATE '2027-01-01'
    GROUP BY 1, 2, 3
)
SELECT count(*) AS candidate_keys,
       count(*) FILTER (WHERE movement_rows > 1) AS duplicate_candidate_groups,
       coalesce(max(movement_rows), 0) AS max_rows_per_candidate
FROM candidate;

ROLLBACK;
