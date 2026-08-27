-- Stage 2 source controls for mart.employee_activity_interval.
-- $1/$2 are the inclusive/exclusive BR-003 horizon.  Each statement is
-- read-only and returns observed evidence; no result authorizes deduplication.

-- EW-V01. Expected: the InfoRg7006 technical key is unique, each candidate
-- belongs to at most one PZ/GZ document branch.  VT4352 multiplicity is
-- measured separately because current Power BI may preserve it under BR-018.
WITH activity_state AS MATERIALIZED (
    SELECT rg._period, rg._recordertref, rg._recorderrref, rg._lineno,
           rg._active, rg._fld7013rref
    FROM public._inforg7006 AS rg
    WHERE rg._period >= $1::date AND rg._period < $2::date
), keyed AS MATERIALIZED (
    SELECT *, count(*) OVER (
        PARTITION BY _period, _recordertref, _recorderrref, _lineno
    ) AS technical_key_rows
    FROM activity_state
), branched AS MATERIALIZED (
    SELECT k.*, pz._idrref AS pz_id, gz._idrref AS gz_id,
           vt._lineno4353 AS pz_service_line
    FROM keyed AS k
    LEFT JOIN public._document329 AS pz ON pz._idrref = k._recorderrref
    LEFT JOIN public._document279 AS gz ON gz._idrref = k._recorderrref
    LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = pz._idrref
)
SELECT 'EW-V01'::text AS control_id,
       count(*)::bigint AS source_rows,
       count(*) FILTER (WHERE technical_key_rows > 1)::bigint AS duplicate_technical_key_rows,
       count(*) FILTER (WHERE pz_id IS NULL AND gz_id IS NULL)::bigint AS unsupported_recorder_rows,
       count(*) FILTER (WHERE pz_id IS NOT NULL AND gz_id IS NOT NULL)::bigint AS ambiguous_branch_rows,
       count(*) FILTER (WHERE pz_id IS NOT NULL)::bigint AS pz_rows_before_vt,
       count(pz_service_line)::bigint AS pz_rows_after_vt,
       (count(pz_service_line) - count(DISTINCT (
           _period, _recordertref, _recorderrref, _lineno
       )) FILTER (WHERE pz_id IS NOT NULL))::bigint AS observed_vt_excess
FROM branched;

-- EW-V02. Expected: current M's state fields are observable.  Counts by state
-- are evidence only; semantic filtering stays exact current M until a mapped
-- business rule confirms a different one.
WITH activity_state AS MATERIALIZED (
    SELECT rg._active, rg._recorderrref, rg._fld7013rref
    FROM public._inforg7006 AS rg
    WHERE rg._period >= $1::date AND rg._period < $2::date
), states AS MATERIALIZED (
    SELECT a.*, e._enumorder, pz._posted AS pz_posted, pz._marked AS pz_marked,
           gz._posted AS gz_posted, gz._marked AS gz_marked
    FROM activity_state AS a
    LEFT JOIN public._enum448 AS e ON e._idrref = a._fld7013rref
    LEFT JOIN public._document329 AS pz ON pz._idrref = a._recorderrref
    LEFT JOIN public._document279 AS gz ON gz._idrref = a._recorderrref
)
SELECT 'EW-V02'::text AS control_id,
       count(*)::bigint AS source_rows,
       count(*) FILTER (WHERE _active)::bigint AS active_rows,
       count(*) FILTER (WHERE NOT _active)::bigint AS inactive_rows,
       count(*) FILTER (WHERE _enumorder IS NULL)::bigint AS missing_status_rows,
       count(*) FILTER (WHERE _enumorder = 4)::bigint AS current_m_completed_rows,
       count(*) FILTER (WHERE pz_posted IS FALSE OR pz_marked IS TRUE)::bigint AS pz_unposted_or_marked_rows,
       count(*) FILTER (WHERE gz_posted IS FALSE OR gz_marked IS TRUE)::bigint AS gz_unposted_or_marked_rows
FROM states;

-- EW-V02A. Exact current-M eligibility for the two lesson branches.
-- The historical M filters PZ by its status and posting, excludes a linked
-- cancellation document, and left-joins VT4352; it filters GZ by the empty
-- cancellation-reason reference and deletion mark.  The VT join's observed
-- excess is evidence only: current M assigns an index after the join, so a
-- future physical event key must preserve it.
WITH constants AS (
    SELECT decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS pz_status_ref,
           decode('00000000000000000000000000000000', 'hex') AS empty_ref
), pz AS MATERIALIZED (
    SELECT p._idrref, p._fld4306 AS start_at, p._fld4307 AS end_at,
           p._posted, p._fld4323rref,
           EXISTS (
               SELECT 1 FROM public._document313 AS c
               WHERE c._fld3810_rrref = p._idrref
           ) AS has_cancellation
    FROM public._document329 AS p
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
), pz_joined AS MATERIALIZED (
    SELECT p.*, vt._lineno4353
    FROM pz AS p
    LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = p._idrref
), gz AS MATERIALIZED (
    SELECT g._idrref, g._fld3218 AS start_at, g._fld3219 AS end_at,
           g._marked, g._fld3231rref
    FROM public._document279 AS g
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
)
SELECT 'EW-V02A'::text AS control_id,
       (SELECT count(*)::bigint FROM pz) AS pz_rows,
       (SELECT count(*)::bigint FROM pz
         CROSS JOIN constants AS c
         WHERE _fld4323rref = c.pz_status_ref AND _posted AND NOT has_cancellation)
           AS pz_current_m_eligible_rows,
       (SELECT count(*)::bigint FROM pz
         CROSS JOIN constants AS c
         WHERE _fld4323rref = c.pz_status_ref AND _posted AND has_cancellation)
           AS pz_cancelled_after_current_status_rows,
       (SELECT count(*)::bigint FROM pz
         CROSS JOIN constants AS c
         WHERE _fld4323rref = c.pz_status_ref AND _posted AND NOT has_cancellation
           AND (start_at IS NULL OR end_at IS NULL OR end_at <= start_at))
           AS pz_nonpositive_current_m_rows,
       (SELECT count(*)::bigint - count(DISTINCT _idrref)::bigint FROM pz_joined
         CROSS JOIN constants AS c
         WHERE _fld4323rref = c.pz_status_ref AND _posted AND NOT has_cancellation)
           AS pz_vt_join_excess_rows,
       (SELECT count(*)::bigint - count(DISTINCT (_idrref, _lineno4353))::bigint
          FROM pz_joined
         CROSS JOIN constants AS c
         WHERE _fld4323rref = c.pz_status_ref AND _posted AND NOT has_cancellation
           AND _lineno4353 IS NOT NULL)
           AS pz_duplicate_vt_technical_key_rows,
       (SELECT count(*)::bigint FROM gz) AS gz_rows,
       (SELECT count(*)::bigint FROM gz
         CROSS JOIN constants AS c
         WHERE _fld3231rref = c.empty_ref AND NOT _marked)
           AS gz_current_m_eligible_rows,
       (SELECT count(*)::bigint FROM gz
         CROSS JOIN constants AS c
         WHERE _fld3231rref = c.empty_ref AND NOT _marked
           AND (start_at IS NULL OR end_at IS NULL OR end_at <= start_at))
           AS gz_nonpositive_current_m_rows;

-- EW-V03. Expected: duty bounds are positive and stored minutes agree with
-- timestamp duration.  Coupon-overlap attribution is not inferred here.
SELECT 'EW-V03'::text AS control_id,
       count(*)::bigint AS duty_rows,
       count(*)::bigint - count(DISTINCT (
           _fld7108rref, _fld7109rref, _fld7110, _fld7111, _fld7112rref, _fld7113rref, _fld7115
       ))::bigint AS duplicate_current_m_duty_input_rows,
       count(*) FILTER (WHERE _fld7111 <= _fld7110)::bigint AS nonpositive_interval_rows,
       count(*) FILTER (
           WHERE _fld7111 > _fld7110
             AND _fld7115 <> extract(epoch FROM _fld7111 - _fld7110) / 60
       )::bigint AS stored_minute_mismatch_rows
FROM public._inforg7107
WHERE _fld7110 >= $1::date AND _fld7110 < $2::date
  AND _fld7112rref = decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex');

-- EW-V03C. Current M groups duties by club and room descriptions but retains
-- the employee ID.  A name collision across distinct IDs would prevent the
-- physical ID-based key from reproducing its output grain.
WITH duties AS MATERIALIZED (
    SELECT d._fld7108rref AS club_id, d._fld7109rref AS employee_id,
           d._fld7113rref AS room_id, d._fld7110 AS start_at,
           d._fld7111 AS end_at, d._fld7115 AS duty_minutes,
           club._description::text AS club_name, room._description::text AS room_name
    FROM public._inforg7107 AS d
    JOIN public._reference132 AS club ON club._idrref = d._fld7108rref
    JOIN public._reference191 AS room ON room._idrref = d._fld7113rref
    WHERE d._fld7110 >= $1::date AND d._fld7110 < $2::date
      AND d._fld7112rref = decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex')
), current_m_groups AS MATERIALIZED (
    SELECT club_name, employee_id, room_name, start_at, end_at, duty_minutes,
           count(DISTINCT (club_id, room_id))::bigint AS physical_id_combinations
    FROM duties
    GROUP BY club_name, employee_id, room_name, start_at, end_at, duty_minutes
)
SELECT 'EW-V03C'::text AS control_id,
       (SELECT count(*)::bigint FROM duties) AS duty_source_rows,
       count(*)::bigint AS current_m_output_groups,
       count(*) FILTER (WHERE physical_id_combinations > 1)::bigint AS current_m_groups_with_id_name_collision
FROM current_m_groups;

-- EW-V03A. Exact current-M coupon/duty qualification for the rolling month.
-- Expected for a safely additive clean-duty result: raw and unioned overlap
-- are equal and no clean duty is negative. A difference proves that the
-- current SUM-over-join formula double-subtracts an overlapping session; it
-- is evidence for a user decision, never an invitation to silently normalize.
WITH constants AS (
    SELECT decode('4296a4bf013441d111e7cae05001072c', 'hex') AS coupons_parent_ref,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation_ref,
           decode('bf4b50662e88eb7b44046ebf4849976f', 'hex') AS club_card_type_ref,
           decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex') AS duty_type_ref
), coupon_services AS MATERIALIZED (
    SELECT s._idrref
    FROM public._reference163 AS s
    CROSS JOIN constants AS c
    WHERE s._parentidrref = c.coupons_parent_ref
), visits_filtered AS MATERIALIZED (
    SELECT v._fld4171rref AS client_ref, v._fld4167rref AS club_ref,
           v._date_time::date AS visit_date, v._fld4172 AS visit_start
    FROM public._document325 AS v
    CROSS JOIN constants AS c
    WHERE v._date_time >= date_trunc('month', current_date) - interval '1 month'
      AND v._fld4164rref = c.visit_operation_ref
), pz_valid AS MATERIALIZED (
    SELECT rg._period::date AS session_date, rg._fld7008rref AS client_ref,
           rg._fld7009rref AS club_ref, doc._fld4322rref AS employee_ref,
           doc._fld4306 AS session_start, doc._fld4307 AS session_end,
           srv._fld1733rref AS division_ref
    FROM public._inforg7006 AS rg
    JOIN public._document329 AS doc ON doc._idrref = rg._fld7007_rrref
    JOIN public._enum448 AS e ON e._idrref = rg._fld7013rref
    JOIN coupon_services AS cs ON cs._idrref = rg._fld7010rref
    JOIN public._reference163 AS srv ON srv._idrref = rg._fld7010rref
    JOIN visits_filtered AS v
      ON v.client_ref = rg._fld7008rref
     AND v.club_ref = rg._fld7009rref
     AND v.visit_date = rg._period::date
     AND v.visit_start <= doc._fld4307
    WHERE rg._period >= date_trunc('month', current_date) - interval '1 month'
      AND e._enumorder = 4
      AND doc._fld4306 IS NOT NULL AND doc._fld4307 IS NOT NULL
), client_contracts AS MATERIALIZED (
    SELECT m._fld681rref AS client_ref,
           CASE WHEN m._fld671 <> DATE '0001-01-01' THEN m._fld671 ELSE m._fld674 END AS contract_start,
           m._fld672 AS contract_end
    FROM public._reference59 AS m
    CROSS JOIN constants AS c
    WHERE m._fld696rref = c.club_card_type_ref
      AND m._fld672 > current_date - interval '2 months'
      AND m._fld681rref IN (SELECT DISTINCT client_ref FROM pz_valid)
), valid_sessions AS MATERIALIZED (
    SELECT pv.club_ref, pv.employee_ref, pv.session_date, pv.session_start, pv.session_end
    FROM pz_valid AS pv
    JOIN client_contracts AS cc
      ON cc.client_ref = pv.client_ref AND cc.contract_end > pv.session_start
    LEFT JOIN public._reference70 AS d ON d._idrref = pv.division_ref
    WHERE (d._description::text = 'Водные программы' AND pv.session_start::date >= cc.contract_start::date)
       OR (pv.session_start::date >= cc.contract_start::date
           AND pv.session_start::date - cc.contract_start::date < 31)
), duties AS MATERIALIZED (
    SELECT row_number() OVER () AS duty_id, rg._fld7108rref AS club_ref,
           rg._fld7109rref AS employee_ref, rg._fld7110 AS duty_start,
           rg._fld7111 AS duty_end, rg._fld7115::numeric AS duty_minutes
    FROM public._inforg7107 AS rg
    CROSS JOIN constants AS c
    WHERE rg._fld7112rref = c.duty_type_ref
      AND rg._fld7110 >= date_trunc('month', current_date) - interval '1 month'
), intersection_rows AS MATERIALIZED (
    SELECT d.duty_id, d.duty_minutes,
           greatest(d.duty_start, s.session_start) AS overlap_start,
           least(d.duty_end, s.session_end) AS overlap_end
    FROM duties AS d
    JOIN valid_sessions AS s
      ON s.club_ref = d.club_ref AND s.employee_ref = d.employee_ref
     AND s.session_date = d.duty_start::date
     AND s.session_start < d.duty_end AND s.session_end > d.duty_start
), ordered AS MATERIALIZED (
    SELECT *, max(overlap_end) OVER (
        PARTITION BY duty_id ORDER BY overlap_start, overlap_end
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prior_end
    FROM intersection_rows
), islands AS MATERIALIZED (
    SELECT *, sum(CASE WHEN prior_end IS NULL OR overlap_start > prior_end THEN 1 ELSE 0 END)
        OVER (PARTITION BY duty_id ORDER BY overlap_start, overlap_end) AS island_id
    FROM ordered
), unioned AS MATERIALIZED (
    SELECT duty_id, sum(extract(epoch FROM island_end - island_start) / 60.0)::numeric AS union_minutes
    FROM (
        SELECT duty_id, island_id, min(overlap_start) AS island_start, max(overlap_end) AS island_end
        FROM islands GROUP BY duty_id, island_id
    ) AS x
    GROUP BY duty_id
), raw AS MATERIALIZED (
    SELECT duty_id, max(duty_minutes) AS duty_minutes,
           sum(extract(epoch FROM overlap_end - overlap_start) / 60.0)::numeric AS raw_overlap_minutes
    FROM intersection_rows GROUP BY duty_id
)
SELECT 'EW-V03A'::text AS control_id,
       (SELECT count(*)::bigint FROM duties) AS duty_rows,
       count(*)::bigint AS duties_with_coupon_overlap,
       count(*) FILTER (WHERE raw.raw_overlap_minutes <> unioned.union_minutes)::bigint
           AS double_subtraction_risk_duties,
       count(*) FILTER (WHERE raw.duty_minutes - raw.raw_overlap_minutes < 0)::bigint
           AS current_m_negative_clean_duties,
       count(*) FILTER (WHERE raw.duty_minutes - unioned.union_minutes < 0)::bigint
           AS union_negative_clean_duties,
       coalesce(sum(raw.raw_overlap_minutes - unioned.union_minutes), 0)::numeric
           AS duplicate_overlap_minutes
FROM raw
JOIN unioned USING (duty_id);

-- EW-V03B. Exact current-M coupon path within BR-003.  Power Query first
-- retains the latest InfoRg7006 record per PZ × service and later applies
-- Table.Distinct to a descriptive business key. The expanded metrics separate
-- a harmless visit-timestamp repeat from a divergence in a physical output
-- field; only the latter would require a business tie-break.
WITH constants AS (
    SELECT decode('4296a4bf013441d111e7cae05001072c', 'hex') AS coupons_parent_ref,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation_ref,
           decode('bf4b50662e88eb7b44046ebf4849976f', 'hex') AS club_card_type_ref
), coupon_services AS MATERIALIZED (
    SELECT s._idrref FROM public._reference163 AS s CROSS JOIN constants AS c
    WHERE s._parentidrref = c.coupons_parent_ref
), ranked AS MATERIALIZED (
    SELECT rg._period, rg._fld7008rref AS client_ref, rg._fld7009rref AS club_ref,
           rg._fld7007_rrref AS pz_id, rg._fld7010rref AS service_id,
           rg._fld7012 AS quantity, doc._fld4306 AS class_start,
           doc._fld4307 AS class_end, doc._fld4322rref AS employee_id,
           client._code::text AS client_code, club._description::text AS club_name,
           employee._description::text AS employee_name,
           service._description::text AS service_name,
           division._description::text AS division_name,
           service._fld1767 AS service_time,
           row_number() over (
               partition by rg._fld7007_rrref, rg._fld7010rref
               order by rg._period desc
           ) AS rn
    FROM public._inforg7006 AS rg
    JOIN public._document329 AS doc ON doc._idrref = rg._fld7007_rrref
    JOIN public._reference141x1 AS client ON client._idrref = rg._fld7008rref
    JOIN public._reference132 AS club ON club._idrref = rg._fld7009rref
    JOIN public._reference225 AS employee ON employee._idrref = doc._fld4322rref
    JOIN public._enum448 AS e ON e._idrref = rg._fld7013rref
    JOIN coupon_services AS cs ON cs._idrref = rg._fld7010rref
    JOIN public._document329_vt4352 AS vt
      ON vt._document329_idrref = doc._idrref AND vt._fld4356rref = rg._fld7010rref
    JOIN public._reference163 AS service ON service._idrref = rg._fld7010rref
    LEFT JOIN public._reference70 AS division ON division._idrref = service._fld1733rref
    WHERE rg._period >= $1::date AND rg._period < $2::date
      AND e._enumorder = 4
), pz AS MATERIALIZED (
    SELECT * FROM ranked WHERE rn = 1
), pz_clients AS MATERIALIZED (
    SELECT DISTINCT client_ref FROM pz
), visits AS MATERIALIZED (
    SELECT v._fld4171rref AS client_ref, v._fld4167rref AS club_ref,
           v._date_time AS visit_at, v._fld4172 AS visit_start
    FROM public._document325 AS v
    CROSS JOIN constants AS c
    JOIN pz_clients AS pc ON pc.client_ref = v._fld4171rref
    WHERE v._date_time >= $1::date AND v._date_time < $2::date
      AND v._fld4164rref = c.visit_operation_ref
), contracts_ranked AS MATERIALIZED (
    SELECT contract._fld681rref AS client_ref,
           CASE WHEN contract._fld671 <> DATE '0001-01-01' THEN contract._fld671 ELSE contract._fld674 END AS contract_start,
           contract._fld672 AS contract_end,
           row_number() over (partition by contract._fld681rref order by contract._fld672 desc) AS rn
    FROM public._reference59 AS contract
    CROSS JOIN constants AS c
    WHERE contract._fld696rref = c.club_card_type_ref
      AND contract._fld672 > $1::date
      AND contract._fld681rref IN (SELECT client_ref FROM pz_clients)
), candidate AS MATERIALIZED (
    SELECT pz.*, visit_at, contract_start, contract_end
    FROM pz
    JOIN visits AS v ON v.client_ref = pz.client_ref
                    AND v.club_ref = pz.club_ref
                    AND v.visit_at::date = pz._period::date
                    AND v.visit_start <= pz.class_start
                    AND v.visit_start <= pz.class_end
    LEFT JOIN contracts_ranked AS contract ON contract.client_ref = pz.client_ref AND contract.rn = 1
    WHERE contract.contract_end > pz.class_start OR contract.contract_end IS NULL
), salary_candidate AS MATERIALIZED (
    SELECT * FROM candidate
    WHERE (division_name = 'Водные программы' AND class_start::date >= contract_start::date)
       OR (class_start::date >= contract_start::date AND class_start::date - contract_start::date < 31)
), key_groups AS MATERIALIZED (
    SELECT client_code, club_name, division_name, employee_name, service_name, class_start,
           count(*)::bigint AS current_m_key_rows,
           count(DISTINCT (quantity, service_time, visit_at, contract_start, contract_end))::bigint
               AS current_m_key_payloads,
           count(DISTINCT (quantity, service_time))::bigint AS minute_payloads,
           count(DISTINCT visit_at)::bigint AS visit_payloads,
           count(DISTINCT visit_at::date)::bigint AS visit_day_payloads,
           count(DISTINCT (contract_start, contract_end))::bigint AS contract_payloads,
           count(DISTINCT (client_ref, club_ref, employee_id, service_id))::bigint AS dimension_payloads,
           max((quantity * service_time)::numeric) AS coupon_minutes
    FROM salary_candidate
    GROUP BY client_code, club_name, division_name, employee_name, service_name, class_start
)
SELECT 'EW-V03B'::text AS control_id,
       (SELECT count(*)::bigint FROM ranked) AS ranked_source_rows,
       (SELECT count(*)::bigint FROM pz) AS latest_pz_service_rows,
       (SELECT count(*)::bigint FROM salary_candidate) AS rows_before_current_m_distinct,
       count(*)::bigint AS current_m_distinct_rows,
       coalesce(sum(current_m_key_rows) FILTER (WHERE current_m_key_rows > 1), 0)::bigint
           AS rows_collapsed_by_current_m_distinct,
       count(*) FILTER (WHERE current_m_key_payloads > 1)::bigint AS collapsed_keys_with_divergent_payload,
       count(*) FILTER (WHERE minute_payloads > 1)::bigint AS collapsed_keys_with_divergent_coupon_minutes,
       count(*) FILTER (WHERE visit_payloads > 1)::bigint AS collapsed_keys_with_divergent_visit_payload,
       count(*) FILTER (WHERE visit_day_payloads > 1)::bigint AS collapsed_keys_with_divergent_visit_day,
       count(*) FILTER (WHERE contract_payloads > 1)::bigint AS collapsed_keys_with_divergent_contract_payload,
       count(*) FILTER (WHERE dimension_payloads > 1)::bigint AS collapsed_keys_with_divergent_dimension_ids,
       coalesce(sum(coupon_minutes), 0)::numeric AS current_m_distinct_coupon_minutes,
       (SELECT count(*)::bigint FROM salary_candidate
         WHERE quantity IS NULL OR service_time IS NULL OR quantity * service_time <= 0)
           AS nonpositive_or_null_coupon_minutes_rows
FROM key_groups;

-- EW-S3-LESSON. Independent aggregate for the two direct lesson branches of
-- the physical target. It intentionally does not reuse the COPY extract.
WITH constants AS (
    SELECT decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS pz_status_ref,
           decode('00000000000000000000000000000000', 'hex') AS empty_ref
), pz AS MATERIALIZED (
    SELECT p._fld4306 AS start_at, p._fld4307 AS end_at
    FROM public._document329 AS p
    JOIN public._reference163 AS service ON service._idrref = p._fld4316rref
    JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
    LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = p._idrref
    CROSS JOIN constants AS c
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND p._fld4323rref = c.pz_status_ref AND p._posted
      AND p._fld4306 IS NOT NULL AND p._fld4307 > p._fld4306
      AND p._fld4310rref IS NOT NULL AND p._fld4322rref IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM public._document313 AS cancel
          WHERE cancel._fld3810_rrref = p._idrref
      )
), gz AS MATERIALIZED (
    SELECT g._fld3218 AS start_at, g._fld3219 AS end_at
    FROM public._document279 AS g
    JOIN public._reference163 AS service ON service._idrref = g._fld3226rref
    JOIN public._reference70 AS activity ON activity._idrref = service._fld1733rref
    CROSS JOIN constants AS c
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND g._fld3231rref = c.empty_ref AND NOT g._marked
      AND g._fld3218 IS NOT NULL AND g._fld3219 > g._fld3218
      AND g._fld3224rref IS NOT NULL AND g._fld3223rref IS NOT NULL
)
SELECT 'EW-S3-LESSON'::text AS control_id,
       (SELECT count(*)::bigint FROM pz) AS pz_target_rows,
       (SELECT coalesce(sum(extract(epoch FROM end_at - start_at) / 60.0), 0)::numeric FROM pz)
           AS pz_target_minutes,
       (SELECT count(*)::bigint FROM gz) AS gz_target_rows,
       (SELECT coalesce(sum(extract(epoch FROM end_at - start_at) / 60.0), 0)::numeric FROM gz)
           AS gz_target_minutes,
       least((SELECT min(start_at::date) FROM pz), (SELECT min(start_at::date) FROM gz))
           AS lesson_min_date,
       greatest((SELECT max(start_at::date) FROM pz), (SELECT max(start_at::date) FROM gz))
           AS lesson_max_date;

-- EW-S3-DUTY. Independent BR-040 aggregate.  The raw join multiplicity is
-- preserved; only its final residual is clamped to zero.
WITH constants AS (
    SELECT decode('4296a4bf013441d111e7cae05001072c', 'hex') AS coupons_parent_ref,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation_ref,
           decode('bf4b50662e88eb7b44046ebf4849976f', 'hex') AS club_card_type_ref,
           decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex') AS duty_type_ref
), coupon_services AS MATERIALIZED (
    SELECT s._idrref FROM public._reference163 AS s CROSS JOIN constants AS c
    WHERE s._parentidrref = c.coupons_parent_ref
), sessions_pre AS MATERIALIZED (
    SELECT rg._period::date AS session_date, rg._fld7008rref AS client_ref,
           rg._fld7009rref AS club_ref, doc._fld4322rref AS employee_ref,
           doc._fld4306 AS session_start, doc._fld4307 AS session_end,
           service._fld1733rref AS activity_ref
    FROM public._inforg7006 AS rg
    JOIN public._document329 AS doc ON doc._idrref = rg._fld7007_rrref
    JOIN public._enum448 AS state ON state._idrref = rg._fld7013rref
    JOIN coupon_services AS cs ON cs._idrref = rg._fld7010rref
    JOIN public._reference163 AS service ON service._idrref = rg._fld7010rref
    WHERE rg._period >= $1::date AND rg._period < $2::date
      AND state._enumorder = 4 AND doc._fld4306 IS NOT NULL AND doc._fld4307 > doc._fld4306
), visits AS MATERIALIZED (
    SELECT v._fld4171rref AS client_ref, v._fld4167rref AS club_ref,
           v._date_time::date AS visit_date, v._fld4172 AS visit_start
    FROM public._document325 AS v CROSS JOIN constants AS c
    JOIN (SELECT DISTINCT client_ref FROM sessions_pre) AS clients ON clients.client_ref = v._fld4171rref
    WHERE v._date_time >= $1::date AND v._date_time < $2::date
      AND v._fld4164rref = c.visit_operation_ref
), contracts AS MATERIALIZED (
    SELECT r._fld681rref AS client_ref,
           CASE WHEN r._fld671 <> DATE '0001-01-01' THEN r._fld671 ELSE r._fld674 END AS contract_start,
           r._fld672 AS contract_end
    FROM public._reference59 AS r CROSS JOIN constants AS c
    WHERE r._fld696rref = c.club_card_type_ref AND r._fld672 > $1::date
      AND r._fld681rref IN (SELECT DISTINCT client_ref FROM sessions_pre)
), sessions AS MATERIALIZED (
    SELECT p.session_date, p.club_ref, p.employee_ref, p.session_start, p.session_end
    FROM sessions_pre AS p
    JOIN visits AS v ON v.client_ref = p.client_ref AND v.club_ref = p.club_ref
                    AND v.visit_date = p.session_date AND v.visit_start <= p.session_end
    JOIN contracts AS c ON c.client_ref = p.client_ref
    LEFT JOIN public._reference70 AS division ON division._idrref = p.activity_ref
    WHERE c.contract_end > p.session_start
      AND ((division._description::text = 'Водные программы' AND p.session_start::date >= c.contract_start::date)
        OR (p.session_start::date >= c.contract_start::date
            AND p.session_start::date - c.contract_start::date < 31))
), duties AS MATERIALIZED (
    SELECT d._fld7108rref AS club_ref, d._fld7109rref AS employee_ref,
           d._fld7113rref AS room_ref, d._fld7110 AS start_at, d._fld7111 AS end_at,
           d._fld7115::numeric AS duty_minutes
    FROM public._inforg7107 AS d CROSS JOIN constants AS c
    WHERE d._fld7112rref = c.duty_type_ref AND d._fld7110 >= $1::date AND d._fld7110 < $2::date
      AND d._fld7111 > d._fld7110
), clean AS MATERIALIZED (
    SELECT d.start_at, greatest(0::numeric, d.duty_minutes - coalesce(sum(
               extract(epoch FROM least(d.end_at, s.session_end) - greatest(d.start_at, s.session_start)) / 60.0
           ), 0::numeric)) AS clean_minutes
    FROM duties AS d LEFT JOIN sessions AS s
      ON s.club_ref = d.club_ref AND s.employee_ref = d.employee_ref
     AND s.session_date = d.start_at::date AND s.session_start < d.end_at AND s.session_end > d.start_at
    GROUP BY d.club_ref, d.employee_ref, d.room_ref, d.start_at, d.end_at, d.duty_minutes
)
SELECT 'EW-S3-DUTY'::text AS control_id, count(*)::bigint AS duty_target_rows,
       coalesce(sum(clean_minutes), 0)::numeric AS clean_duty_minutes,
       min(start_at::date) AS duty_min_date, max(start_at::date) AS duty_max_date,
       count(*) FILTER (WHERE clean_minutes = 0)::bigint AS zero_clean_duty_rows
FROM clean;

-- EW-V04. Expected: each active plan registry technical key occurs once.
SELECT 'EW-V04'::text AS control_id,
       count(*)::bigint AS plan_rows,
       count(*) FILTER (WHERE _active)::bigint AS active_rows,
       count(*) FILTER (WHERE NOT _active)::bigint AS inactive_rows,
       count(*)::bigint - count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint
           AS duplicate_technical_key_rows,
       coalesce(sum(_fld6620) FILTER (WHERE _active), 0)::numeric AS active_amount_total
FROM public._inforg6612
WHERE _fld6613 >= $1::date AND _fld6613 < $2::date;

-- EW-V05. Expected for a one-person SCUD fact: no client maps to more than
-- one employee.  Any multi-link is a BLOCKER for employee_presence_day and is
-- not resolved by choosing an employee.
WITH employee_client AS MATERIALIZED (
    SELECT _fld2504rref AS client_id, count(*)::bigint AS employees
    FROM public._reference225
    WHERE _fld2504rref IS NOT NULL
    GROUP BY _fld2504rref
), visits AS MATERIALIZED (
    SELECT _idrref AS visit_id, _fld4171rref AS client_id
    FROM public._document325
    WHERE _date_time >= $1::date AND _date_time < $2::date
)
SELECT 'EW-V05'::text AS control_id,
       count(*)::bigint AS visits,
       count(*) FILTER (WHERE e.client_id IS NULL)::bigint AS visits_without_employee_link,
       count(*) FILTER (WHERE e.employees > 1)::bigint AS visits_with_multiple_employee_links,
       coalesce(max(e.employees), 0)::bigint AS maximum_employees_per_client
FROM visits AS v
LEFT JOIN employee_client AS e ON e.client_id = v.client_id;

-- EW-V07. Expected for deterministic as-of employment: no nonpositive
-- interval and no overlap within employee × club × position.  The 1C sentinel
-- end is mapped only for measuring the existing interval, never as a target
-- business date.
WITH intervals AS MATERIALIZED (
    SELECT _fld6292rref AS employee_id, _fld6293rref AS club_id,
           _fld6296rref AS position_id, _fld6298 AS start_at,
           CASE WHEN _fld6299 = TIMESTAMP '0001-01-01 00:00:00'
                THEN TIMESTAMP '2099-12-31 00:00:00' ELSE _fld6299 END AS end_at
    FROM public._inforg6291
), overlap_pairs AS MATERIALIZED (
    SELECT 1
    FROM intervals AS a
    JOIN intervals AS b
      ON b.employee_id = a.employee_id
     AND b.club_id = a.club_id
     AND b.position_id = a.position_id
     AND (b.start_at, b.end_at) > (a.start_at, a.end_at)
     AND b.start_at < a.end_at
     AND a.start_at < b.end_at
)
SELECT 'EW-V07'::text AS control_id,
       (SELECT count(*)::bigint FROM intervals) AS employment_rows,
       (SELECT count(*)::bigint FROM intervals WHERE end_at <= start_at) AS nonpositive_interval_rows,
       (SELECT count(*)::bigint FROM overlap_pairs) AS overlapping_interval_pairs;
