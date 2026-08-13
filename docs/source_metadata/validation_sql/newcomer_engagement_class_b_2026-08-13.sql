-- SV-092 / NE-V02: supplementary Stage-2 observation for «Вовлечение новичков».
-- Execute only against gymdb as gymdb_readonly in BEGIN READ ONLY.
-- Output is aggregate-only: no PII, business names or raw identifiers.
--
-- Expected: the technical visit key remains unique.  Row count, recorder count
-- and quantity are compared only to identify the legacy unit; the result must
-- not change the current M row-count rule (BR-018).

BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000ms';

WITH current_visit_scope AS (
    SELECT a._recordertref, a._recorderrref, a._lineno, a._active,
           a._fld7585, a._fld7576rref AS client_id,
           a._fld7578_rrref AS contract_id
    FROM public._accumrg7575 a
    JOIN public._reference163 service ON service._idrref = a._fld7579rref
    JOIN public._reference59 contract ON contract._idrref = a._fld7578_rrref
    WHERE a._period >= timestamp '2026-01-01'
      AND a._period < timestamp '2027-01-01'
      AND service._description::text = 'посещение клуба'
      AND service._description::text NOT LIKE '%ИП%'
      AND service._description::text NOT LIKE '%Контракт сотрудника%'
      AND contract._fld694rref = decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex')
), key_groups AS (
    SELECT _recordertref, _recorderrref, _lineno, count(*)::bigint AS n
    FROM current_visit_scope
    GROUP BY 1, 2, 3
)
SELECT (SELECT count(*)::bigint FROM current_visit_scope) AS visit_rows,
       (SELECT count(*)::bigint FROM key_groups) AS technical_keys,
       (SELECT count(*) FILTER (WHERE n > 1)::bigint FROM key_groups) AS duplicate_key_groups,
       (SELECT count(DISTINCT (_recordertref, _recorderrref))::bigint FROM current_visit_scope) AS recorder_pairs,
       (SELECT count(*) FILTER (WHERE NOT _active)::bigint FROM current_visit_scope) AS inactive_rows,
       (SELECT count(*) FILTER (WHERE _fld7585 IS NULL)::bigint FROM current_visit_scope) AS null_quantity_rows,
       (SELECT coalesce(sum(_fld7585), 0)::numeric FROM current_visit_scope) AS quantity_sum,
       (SELECT count(*) FILTER (WHERE client_id IS NULL OR contract_id IS NULL)::bigint
        FROM current_visit_scope) AS null_business_link_rows;

ROLLBACK;
