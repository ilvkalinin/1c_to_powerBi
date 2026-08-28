-- Read-only Stage 2 controls for candidate mart.employee_presence_day.
-- $1/$2 are the inclusive/exclusive BR-003 horizon.  The controls preserve
-- the current Power Query source path; they never select an employee for a
-- multi-link client and do not authorise target DDL/DML/COPY.

-- EPD-V01. Expected: the mapped physical tables and every required column
-- exist with one physical definition.  A missing/ambiguous field is BLOCKED.
WITH required_columns(table_name, column_name) AS (
    VALUES
      ('_accumrg7575', '_period'), ('_accumrg7575', '_recorderrref'),
      ('_accumrg7575', '_fld7576rref'), ('_accumrg7575', '_fld7577rref'),
      ('_accumrg7575', '_fld7578_rrref'),
      ('_document325', '_idrref'), ('_document325', '_date_time'),
      ('_document325', '_marked'), ('_document325', '_posted'),
      ('_document325', '_fld4164rref'), ('_document325', '_fld4167rref'),
      ('_document325', '_fld4171rref'), ('_document325', '_fld4172'),
      ('_document325', '_fld4174'),
      ('_reference225', '_idrref'), ('_reference225', '_fld2504rref'),
      ('_reference59', '_idrref'), ('_reference59', '_fld685rref'),
      ('_reference163', '_idrref'), ('_reference163', '_parentidrref'),
      ('_reference132', '_idrref'), ('_reference132', '_description')
), observed AS (
    SELECT c.table_name, c.column_name, cols.data_type, cols.udt_name
    FROM required_columns AS c
    LEFT JOIN information_schema.columns AS cols
      ON cols.table_schema = 'public'
     AND cols.table_name = c.table_name
     AND cols.column_name = c.column_name
)
SELECT 'EPD-V01'::text AS control_id,
       count(*)::bigint AS required_columns,
       count(*) FILTER (WHERE data_type IS NOT NULL)::bigint AS present_columns,
       count(*) FILTER (WHERE data_type IS NULL)::bigint AS missing_columns,
       jsonb_agg(jsonb_build_object('table', table_name, 'column', column_name,
                                    'data_type', data_type, 'udt_name', udt_name)
                 ORDER BY table_name, column_name) AS physical_columns
FROM observed;

-- EPD-V02. Expected: the exact current-M source path is measurable on BR-003.
-- It intentionally has no Marked/Posted predicate: current Power Query has none.
WITH service AS MATERIALIZED (
    SELECT child._idrref
    FROM public._reference163 AS child
    LEFT JOIN public._reference163 AS parent ON parent._idrref = child._parentidrref
    WHERE parent._description::text = 'Служебная'
), current_m AS MATERIALIZED (
    SELECT a._recorderrref AS visit_id, a._period::date AS presence_date,
           a._fld7577rref AS club_id, e._idrref AS employee_id,
           d._fld4172 AS start_at, d._fld4174 AS end_at,
           d._marked, d._posted
    FROM public._accumrg7575 AS a
    LEFT JOIN public._document325 AS d ON d._idrref = a._recorderrref
    LEFT JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    INNER JOIN public._reference225 AS e ON e._fld2504rref = a._fld7576rref
    LEFT JOIN public._reference59 AS contract ON contract._idrref = a._fld7578_rrref
    INNER JOIN service AS s ON s._idrref = contract._fld685rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
), clipped AS MATERIALIZED (
    SELECT *, CASE
      WHEN end_at = TIMESTAMP '0001-01-01 00:00:00'
        OR end_at > date_trunc('day', start_at) + interval '1 day' - interval '1 microsecond'
      THEN date_trunc('day', start_at) + interval '1 day' - interval '1 microsecond'
      ELSE end_at END AS effective_end_at
    FROM current_m
)
SELECT 'EPD-V02'::text AS control_id,
       count(*)::bigint AS current_m_rows,
       count(DISTINCT visit_id)::bigint AS distinct_visit_ids,
       min(presence_date) AS min_presence_date, max(presence_date) AS max_presence_date,
       count(*) FILTER (WHERE start_at IS NULL)::bigint AS null_start_rows,
       count(*) FILTER (WHERE end_at = TIMESTAMP '0001-01-01 00:00:00')::bigint AS open_end_rows,
       count(*) FILTER (WHERE end_at > date_trunc('day', start_at) + interval '1 day' - interval '1 microsecond')::bigint AS after_day_end_rows,
       count(*) FILTER (WHERE effective_end_at < start_at)::bigint AS negative_interval_rows,
       count(*) FILTER (WHERE _marked)::bigint AS marked_rows,
       count(*) FILTER (WHERE NOT _posted)::bigint AS unposted_rows,
       coalesce(sum(extract(epoch FROM effective_end_at - start_at) / 60.0), 0)::numeric AS current_m_minutes
FROM clipped;

-- EPD-V03. Expected: every multiplication path is visible.  A non-zero value
-- is evidence, not permission to de-duplicate the current-M result.
WITH service AS MATERIALIZED (
    SELECT child._idrref
    FROM public._reference163 AS child
    LEFT JOIN public._reference163 AS parent ON parent._idrref = child._parentidrref
    WHERE parent._description::text = 'Служебная'
), current_m AS MATERIALIZED (
    SELECT a._recorderrref AS visit_id, e._idrref AS employee_id
    FROM public._accumrg7575 AS a
    LEFT JOIN public._document325 AS d ON d._idrref = a._recorderrref
    LEFT JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    INNER JOIN public._reference225 AS e ON e._fld2504rref = a._fld7576rref
    LEFT JOIN public._reference59 AS contract ON contract._idrref = a._fld7578_rrref
    INNER JOIN service AS s ON s._idrref = contract._fld685rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
), per_visit AS MATERIALIZED (
    SELECT visit_id, count(*)::bigint AS joined_rows,
           count(DISTINCT employee_id)::bigint AS employees
    FROM current_m
    GROUP BY visit_id
)
SELECT 'EPD-V03'::text AS control_id,
       count(*)::bigint AS distinct_visit_ids,
       coalesce(sum(joined_rows), 0)::bigint AS current_m_rows,
       count(*) FILTER (WHERE joined_rows > 1)::bigint AS visit_ids_with_multiple_current_m_rows,
       count(*) FILTER (WHERE employees > 1)::bigint AS visit_ids_with_multiple_current_m_employees,
       coalesce(max(joined_rows), 0)::bigint AS maximum_rows_per_visit_id,
       coalesce(max(employees), 0)::bigint AS maximum_current_m_employees_per_visit_id
FROM per_visit;

-- EPD-V04. Expected for a one-person fact: zero qualified SCUD visits with
-- more than one employee.  A non-zero result is a BLOCKER, never a tie-break.
WITH service AS MATERIALIZED (
    SELECT child._idrref
    FROM public._reference163 AS child
    LEFT JOIN public._reference163 AS parent ON parent._idrref = child._parentidrref
    WHERE parent._description::text = 'Служебная'
), employee_client AS MATERIALIZED (
    SELECT _fld2504rref AS client_id, count(*)::bigint AS employees
    FROM public._reference225
    WHERE _fld2504rref IS NOT NULL
    GROUP BY _fld2504rref
), qualified_visits AS MATERIALIZED (
    SELECT DISTINCT a._recorderrref AS visit_id, a._fld7576rref AS client_id
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    JOIN public._reference59 AS contract ON contract._idrref = a._fld7578_rrref
    JOIN service AS s ON s._idrref = contract._fld685rref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
)
SELECT 'EPD-V04'::text AS control_id,
       count(*)::bigint AS qualified_visit_ids,
       count(*) FILTER (WHERE e.client_id IS NULL)::bigint AS visits_without_employee_link,
       count(*) FILTER (WHERE e.employees = 1)::bigint AS visits_with_one_employee_link,
       count(*) FILTER (WHERE e.employees > 1)::bigint AS visits_with_multiple_employee_links,
       coalesce(max(e.employees), 0)::bigint AS maximum_employees_per_client
FROM qualified_visits AS v
LEFT JOIN employee_client AS e ON e.client_id = v.client_id;

-- EPD-V05. Expected: only one-employee source events can enter the candidate
-- employee × date × club aggregation.  It reports the independent population
-- and minutes; it does not materialize a target object.
WITH service AS MATERIALIZED (
    SELECT child._idrref
    FROM public._reference163 AS child
    LEFT JOIN public._reference163 AS parent ON parent._idrref = child._parentidrref
    WHERE parent._description::text = 'Служебная'
), employee_client AS MATERIALIZED (
    SELECT _fld2504rref AS client_id, min(_idrref) AS employee_id, count(*)::bigint AS employees
    FROM public._reference225
    WHERE _fld2504rref IS NOT NULL
    GROUP BY _fld2504rref
), singular_events AS MATERIALIZED (
    SELECT a._recorderrref AS visit_id, a._period::date AS presence_date,
           a._fld7577rref AS club_id, e.employee_id, d._fld4172 AS start_at,
           CASE WHEN d._fld4174 = TIMESTAMP '0001-01-01 00:00:00'
                     OR d._fld4174 > date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
                THEN date_trunc('day', d._fld4172) + interval '1 day' - interval '1 microsecond'
                ELSE d._fld4174 END AS effective_end_at
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club ON club._idrref = a._fld7577rref
    JOIN public._reference59 AS contract ON contract._idrref = a._fld7578_rrref
    JOIN service AS s ON s._idrref = contract._fld685rref
    JOIN employee_client AS e ON e.client_id = a._fld7576rref AND e.employees = 1
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description::text NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date AND a._period < $2::date
), candidate AS MATERIALIZED (
    SELECT employee_id, presence_date, club_id,
           count(*)::bigint AS source_rows,
           count(DISTINCT visit_id)::bigint AS distinct_visit_ids,
           coalesce(sum(extract(epoch FROM effective_end_at - start_at) / 60.0), 0)::numeric AS presence_minutes
    FROM singular_events
    GROUP BY employee_id, presence_date, club_id
)
SELECT 'EPD-V05'::text AS control_id,
       count(*)::bigint AS candidate_grain_rows,
       coalesce(sum(source_rows), 0)::bigint AS singular_source_rows,
       coalesce(sum(distinct_visit_ids), 0)::bigint AS singular_distinct_visit_ids,
       coalesce(sum(presence_minutes), 0)::numeric AS singular_presence_minutes,
       count(*) FILTER (WHERE presence_minutes < 0)::bigint AS negative_candidate_rows,
       min(presence_date) AS min_presence_date, max(presence_date) AS max_presence_date
FROM candidate;
