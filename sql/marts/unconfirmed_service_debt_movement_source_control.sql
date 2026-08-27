-- Independent control path: EXISTS branches, not the extract UNION ALL joins.
WITH base AS MATERIALIZED (
    SELECT r._period AS debt_event_at, r._recordertref AS recorder_type,
           r._recorderrref AS recorder_id, r._lineno::integer AS recorder_line_no,
           r._recordkind::smallint AS record_kind, r._fld7512_rrref AS prebooking_id,
           r._fld7516 AS quantity_delta,
           CASE WHEN r._recordkind = 1 THEN -r._fld7517 ELSE r._fld7517 END AS amount_delta
    FROM public._accumrg7509 r
    JOIN public._reference163 service ON service._idrref = r._fld7513rref
    WHERE r._period >= $1::timestamp AND r._period < $2::timestamp
      AND service._description::text NOT ILIKE 'Купон%'
), base_prebookings AS MATERIALIZED (
    SELECT DISTINCT prebooking_id FROM base
), branch_paths AS MATERIALIZED (
    SELECT branch.prebooking_id, count(*)::integer AS branch_paths
    FROM (
        SELECT ids.prebooking_id
        FROM base_prebookings ids
        JOIN public._document329 d ON d._idrref = ids.prebooking_id
        JOIN public._reference225 e ON e._idrref = d._fld4322rref
        UNION ALL
        SELECT ids.prebooking_id
        FROM base_prebookings ids
        JOIN public._document279 d ON d._idrref = ids.prebooking_id
        JOIN public._reference225 e ON e._idrref = d._fld3223rref
    ) branch
    GROUP BY branch.prebooking_id
), qualified AS (
    SELECT b.*, coalesce(paths.branch_paths, 0) AS branch_paths
    FROM base b
    LEFT JOIN branch_paths paths ON paths.prebooking_id = b.prebooking_id
)
SELECT count(*) FILTER (WHERE branch_paths = 1)::bigint AS expected_rows,
       count(DISTINCT (debt_event_at, recorder_type, recorder_id, recorder_line_no)) FILTER (WHERE branch_paths = 1)::bigint AS expected_keys,
       count(*) FILTER (WHERE branch_paths <> 1)::bigint AS invalid_branch_paths,
       coalesce(sum(amount_delta) FILTER (WHERE branch_paths = 1), 0)::numeric(20,2) AS amount_sum,
       min(debt_event_at) FILTER (WHERE branch_paths = 1) AS min_event_at,
       max(debt_event_at) FILTER (WHERE branch_paths = 1) AS max_event_at
FROM qualified;
