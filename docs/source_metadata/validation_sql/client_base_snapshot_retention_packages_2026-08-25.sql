-- Stage 2 technical controls for package-aware client-base snapshot/retention.
-- Run each statement in one REPEATABLE READ READ ONLY source transaction.

-- CB-SNAP-PKG-READY-002. Expected at 2026-07-01: direct registry client and
-- Document325 client have zero differences for qualified 30-day visit rows.
SELECT count(*) FILTER (WHERE a._fld7576rref = d._fld4171rref)::bigint AS equal_client_rows,
       count(*) FILTER (WHERE a._fld7576rref <> d._fld4171rref)::bigint AS different_client_rows,
       count(*)::bigint AS qualified_rows
FROM public._accumrg7575 AS a
JOIN public._document325 AS d ON d._idrref = a._recorderrref
JOIN public._reference163 AS s ON s._idrref = a._fld7579rref
WHERE a._period >= TIMESTAMP '2026-06-01 00:00:00'
  AND a._period < TIMESTAMP '2026-07-01 00:00:00'
  AND a._fld7585 <> 0
  AND s._description = 'посещение клуба';

-- CB-SNAP-PKG-READY-003. Expected: zero latest-period tie; client without a
-- prior tenure record maps to `Не указано`, not a dropped client.
WITH active_clients AS (
    SELECT DISTINCT ab._fld681rref AS client_id
    FROM public._reference59 AS ab
    WHERE ab._fld671 < DATE '2026-07-01'
      AND ab._fld672 >= DATE '2026-06-30'
), last_period AS (
    SELECT h._fld5655rref AS client_id, max(h._period) AS period
    FROM public._inforg5654 AS h
    JOIN active_clients AS c ON c.client_id = h._fld5655rref
    WHERE h._period < TIMESTAMP '2026-07-01 00:00:00'
    GROUP BY h._fld5655rref
), latest AS (
    SELECT h._fld5655rref AS client_id, h._period
    FROM public._inforg5654 AS h
    JOIN last_period AS p ON p.client_id = h._fld5655rref AND p.period = h._period
)
SELECT (SELECT count(*) FROM active_clients)::bigint AS active_clients,
       (SELECT count(*) FROM last_period)::bigint AS clients_with_tenure,
       ((SELECT count(*) FROM active_clients) - (SELECT count(*) FROM last_period))::bigint AS clients_without_tenure,
       (SELECT count(*) FROM (SELECT client_id FROM latest GROUP BY client_id HAVING count(*) > 1) AS ties)::bigint AS latest_tie_clients,
       (SELECT count(*) FROM latest)::bigint AS latest_rows;

-- CB-SNAP-PKG-READY-004. Expected: zero sentinel/null child rows in BR-003.
-- Otherwise retain current predicate and open a separate BR-018 decision.
SELECT count(*) FILTER (WHERE r._fld670 = TIMESTAMP '0001-01-01 00:00:00')::bigint AS sentinel_rows,
       count(*) FILTER (WHERE r._fld670 IS NULL)::bigint AS null_rows,
       count(*)::bigint AS all_current_child_rows
FROM public._document346_vt4913 AS v
JOIN public._document346 AS d ON d._idrref = v._document346_idrref
JOIN public._reference59 AS r ON r._idrref = v._fld4915rref
WHERE d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
  AND r._fld672 >= DATE '2024-12-31';
