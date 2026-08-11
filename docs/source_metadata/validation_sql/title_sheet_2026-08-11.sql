-- Title Sheet server validation, executed 2026-08-11 in a read-only
-- connection to gymdb. Results are live controls, not a frozen PBIT export.

-- SV-062: exact PBIT visit source, parameterised for one full month.
WITH pbit_visits AS (
    SELECT a._recorderrref AS visit_document_id,
           d._fld4172 AS entry_at, d._fld4174 AS exit_at,
           a._active, d._posted, d._marked
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
SELECT count(*) AS pbit_counted_rows,
       count(DISTINCT visit_document_id) AS distinct_visit_documents,
       count(*) - count(DISTINCT visit_document_id) AS source_join_excess,
       count(*) FILTER (WHERE exit_at IS NULL OR exit_at <= timestamp '0001-01-01') AS open_visit_rows,
       count(*) FILTER (WHERE NOT _active) AS inactive_movement_rows,
       count(*) FILTER (WHERE NOT _posted) AS unposted_documents,
       count(*) FILTER (WHERE _marked) AS marked_documents
FROM pbit_visits;

-- SV-062: exact DAX boundary condition for the card `МаксЧКвКлубе`.
-- `entry_hour < hour_slot` and `exit_hour >= hour_slot` are deliberately
-- asymmetric legacy semantics. The date below is the control 2026-07-15.
WITH pbit_visits AS (
    SELECT c._description AS club,
           extract(hour FROM d._fld4172)::integer AS entry_hour,
           extract(hour FROM d._fld4174)::integer AS exit_hour
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
), hourly AS (
    SELECT clubs.club, h AS hour_slot, count(p.*) AS visit_documents
    FROM (SELECT DISTINCT club FROM pbit_visits) clubs
    CROSS JOIN generate_series(0, 23) AS h
    LEFT JOIN pbit_visits p
      ON p.club = clubs.club
     AND p.entry_hour < h
     AND p.exit_hour >= h
    GROUP BY 1, 2
)
SELECT club, max(visit_documents) AS max_concurrent_visit_count
FROM hourly GROUP BY club ORDER BY club;

-- SV-063: after applying the exact PBIT DPFU and Reception category filters
-- (they are preserved verbatim in the PBIT and query review), compare their
-- movement keys. Result must be empty; it was empty for July 2026.
SELECT d.source_kind, d.recorder_tref, d.recorder_rref, d.line_no
FROM :title_dpfu_qualified_rows d
JOIN :title_reception_qualified_rows r
  USING (source_kind, recorder_tref, recorder_rref, line_no);

-- SV-064: after applying each exact Membership PBIT branch (contracts,
-- other services, goods), validate that polymorphic recorder joins retain
-- the source technical key. All three branches had zero excess in July 2026.
SELECT membership_branch,
       count(*) AS pbit_rows,
       count(DISTINCT (recorder_tref, recorder_rref, line_no)) AS technical_events,
       count(*) - count(DISTINCT (recorder_tref, recorder_rref, line_no)) AS join_excess,
       sum(signed_amount) AS signed_amount
FROM :title_membership_qualified_rows
GROUP BY membership_branch;

-- The two :title_* names above are one-time source-side CTEs consisting of
-- the literal SQL extracted from `Титульный лист.pbit`; they are not
-- production objects or PostgreSQL dependencies. This avoids silently
-- changing the report's long text/GUID category filters during validation.
