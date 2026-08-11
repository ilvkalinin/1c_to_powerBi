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

-- WA-V04: inspect every source birth-date value that produces an implausible
-- age in the exact July population. Expected: no undocumented sentinel values.
WITH pbit_visits AS (
    SELECT a._period::date AS visit_date,
           client._fld1507 AS birth_date,
           extract(year FROM age(a._period::date, client._fld1507::date))::int
               AS legacy_age_years,
           CASE WHEN client._fld1507::date = DATE '0001-01-01' THEN NULL
                ELSE extract(year FROM age(a._period::date, client._fld1507::date))::int
           END AS target_age_years
    FROM public._accumrg7575 a
    JOIN public._document325 d ON a._recorderrref = d._idrref
    JOIN public._reference132 c ON a._fld7577rref = c._idrref
    JOIN public._reference141x1 client ON d._fld4171rref = client._idrref
    JOIN public._reference59 contract ON a._fld7578_rrref = contract._idrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND c._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= DATE '2026-07-01' AND a._period < DATE '2026-08-01'
      AND contract._description NOT LIKE '%ИП%'
      AND contract._description NOT LIKE '%сотрудн%'
      AND d._fld4172 <> d._fld4174
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
)
SELECT birth_date::text AS stored_birth_date,
       pg_typeof(birth_date)::text AS source_type,
       legacy_age_years,
       target_age_years,
       count(*) AS visit_rows
FROM pbit_visits
WHERE legacy_age_years > 100
GROUP BY 1, 2, 3, 4
ORDER BY 1;

-- WA-V07: aggregation to the candidate hourly grain on the independent
-- control date 2026-07-15. Expected: aggregate visit/minute totals equal the
-- source totals and no required grain component is NULL.
WITH pbit_visits AS (
    SELECT a._period::date AS visit_date,
           a._fld7577rref AS club_id,
           extract(hour FROM d._fld4172)::smallint AS start_hour,
           extract(hour FROM d._fld4174)::smallint AS end_hour,
           client._fld1527rref AS sex_code,
           CASE WHEN client._fld1507::date = DATE '0001-01-01' THEN NULL
                ELSE extract(year FROM age(a._period::date, client._fld1507::date))::smallint
           END AS age_years,
           extract(epoch FROM (
               CASE WHEN d._fld4174 IS NULL OR d._fld4174 <= timestamp '0001-01-01'
                    THEN date_trunc('day', d._fld4172) + interval '23:59:59'
                    ELSE d._fld4174 END - d._fld4172
           )) / 60.0 AS minutes
    FROM public._accumrg7575 a
    JOIN public._document325 d ON a._recorderrref = d._idrref
    JOIN public._reference132 c ON a._fld7577rref = c._idrref
    JOIN public._reference141x1 client ON d._fld4171rref = client._idrref
    JOIN public._reference59 contract ON a._fld7578_rrref = contract._idrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND c._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= DATE '2026-07-15' AND a._period < DATE '2026-07-16'
      AND contract._description NOT LIKE '%ИП%'
      AND contract._description NOT LIKE '%сотрудн%'
      AND d._fld4172 <> d._fld4174
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
), aggregate_hourly AS (
    SELECT visit_date, club_id, start_hour, end_hour, sex_code, age_years,
           count(*) AS visit_count, sum(minutes) AS club_minutes_total
    FROM pbit_visits
    GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT (SELECT count(*) FROM pbit_visits) AS source_rows,
       (SELECT count(*) FROM aggregate_hourly) AS aggregate_rows,
       (SELECT sum(visit_count) FROM aggregate_hourly) AS aggregated_visit_count,
       round((SELECT sum(minutes) FROM pbit_visits)::numeric, 2) AS source_minutes,
       round((SELECT sum(club_minutes_total) FROM aggregate_hourly)::numeric, 2) AS aggregated_minutes,
       (SELECT count(*) FROM pbit_visits WHERE club_id IS NULL OR start_hour IS NULL)
           AS null_required_grain_rows,
       (SELECT count(*) FROM pbit_visits WHERE age_years > 100) AS invalid_age_rows;

-- WA-V08: run this exact source population with EXPLAIN (ANALYZE, BUFFERS,
-- FORMAT JSON) for the same control date. It is a source baseline, not an
-- implementation SLA or an index recommendation.
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT count(*)
FROM public._accumrg7575 a
JOIN public._document325 d ON a._recorderrref = d._idrref
JOIN public._reference132 c ON a._fld7577rref = c._idrref
JOIN public._reference141x1 client ON d._fld4171rref = client._idrref
JOIN public._reference59 contract ON a._fld7578_rrref = contract._idrref
WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
  AND c._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
  AND a._period >= DATE '2026-07-15' AND a._period < DATE '2026-07-16'
  AND contract._description NOT LIKE '%ИП%'
  AND contract._description NOT LIKE '%сотрудн%'
  AND d._fld4172 <> d._fld4174
  AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex');
