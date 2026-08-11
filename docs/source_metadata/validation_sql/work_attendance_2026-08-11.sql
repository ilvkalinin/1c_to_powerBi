-- Work-attendance server validation, executed 2026-08-11 in a READ ONLY
-- transaction against the 1C source. This is a source control, not DDL/DML.

-- WA-V01, WA-V02, WA-V03: exact current source population for a full month.
-- Run once per stated [start_date, end_date) range. Expected source integrity:
-- source_join_excess = 0; inactive/unposted/marked = 0. Interval anomalies are
-- observed and reconciled to the legacy Power Query rule, not discarded.
WITH pbit_visits AS (
    SELECT a._recorderrref AS visit_document_id,
           d._fld4172 AS entry_at,
           d._fld4174 AS exit_at,
           a._active,
           d._posted,
           d._marked
    FROM public._accumrg7575 a
    JOIN public._document325 d ON a._recorderrref = d._idrref
    JOIN public._reference132 c ON a._fld7577rref = c._idrref
    JOIN public._reference141x1 client ON d._fld4171rref = client._idrref
    JOIN public._reference59 contract ON a._fld7578_rrref = contract._idrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND c._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= :start_date::date AND a._period < :end_date::date
      AND contract._description NOT LIKE '%ИП%'
      AND contract._description NOT LIKE '%сотрудн%'
      AND d._fld4172 <> d._fld4174
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
), measured AS (
    SELECT *,
           CASE
               WHEN exit_at IS NULL OR exit_at <= timestamp '0001-01-01'
                   THEN date_trunc('day', entry_at) + interval '23:59:59'
               ELSE exit_at
           END AS effective_exit_at
    FROM pbit_visits
)
SELECT count(*) AS pbit_counted_rows,
       count(DISTINCT visit_document_id) AS distinct_visit_documents,
       count(*) - count(DISTINCT visit_document_id) AS source_join_excess,
       count(*) FILTER (WHERE NOT _active) AS inactive_movement_rows,
       count(*) FILTER (WHERE NOT _posted) AS unposted_documents,
       count(*) FILTER (WHERE _marked) AS marked_documents,
       count(*) FILTER (WHERE exit_at IS NULL OR exit_at <= timestamp '0001-01-01') AS open_visit_rows,
       count(*) FILTER (WHERE effective_exit_at < entry_at) AS negative_interval_rows,
       count(*) FILTER (WHERE effective_exit_at - entry_at > interval '24 hours') AS over_24h_rows,
       round(sum(extract(epoch FROM (effective_exit_at - entry_at)) / 60.0)::numeric, 2) AS fallback_minutes_total
FROM measured;
