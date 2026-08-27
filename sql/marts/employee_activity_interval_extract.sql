-- Exact source extract for mart.employee_activity_interval.
-- $1/$2 are the inclusive/exclusive BR-003 date horizon.  The result contains
-- no raw source columns or client detail and is suitable for binary COPY only.
WITH constants AS (
    SELECT decode('a0d533e2ede766b3408ad9ef5403fadd', 'hex') AS pz_completed_ref,
           decode('00000000000000000000000000000000', 'hex') AS empty_ref,
           decode('4296a4bf013441d111e7cae05001072c', 'hex') AS coupons_parent_ref,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation_ref,
           decode('bf4b50662e88eb7b44046ebf4849976f', 'hex') AS club_card_type_ref,
           decode('bd57e817bb8afd31455f678cd21a2f8e', 'hex') AS duty_type_ref
),
coupon_services AS MATERIALIZED (
    SELECT s._idrref
    FROM public._reference163 AS s
    CROSS JOIN constants AS c
    WHERE s._parentidrref = c.coupons_parent_ref
),
training_pz AS MATERIALIZED (
    SELECT
        'PZ:' || encode(p._idrref, 'hex') || ':' || coalesce(vt._lineno4353::text, 'NO_VT')
            AS activity_event_key,
        p._fld4306::date AS activity_date,
        encode(p._fld4310rref, 'hex') AS club_id,
        encode(p._fld4322rref, 'hex') AS employee_id,
        encode(s._fld1733rref, 'hex') AS activity_id,
        encode(p._fld4316rref, 'hex') AS service_id,
        encode(p._fld4320rref, 'hex') AS room_id,
        'TRAINING'::text AS activity_kind,
        p._fld4306 AS start_at,
        p._fld4307 AS end_at,
        extract(epoch FROM p._fld4307 - p._fld4306) / 60.0 AS duration_minutes,
        CASE WHEN s._fld1778 IS TRUE THEN 'Бесплатно' ELSE 'Платно' END AS payment_kind
    FROM public._document329 AS p
    JOIN public._reference163 AS s ON s._idrref = p._fld4316rref
    JOIN public._reference70 AS a ON a._idrref = s._fld1733rref
    LEFT JOIN public._document329_vt4352 AS vt ON vt._document329_idrref = p._idrref
    CROSS JOIN constants AS c
    WHERE p._fld4306 >= $1::date AND p._fld4306 < $2::date
      AND p._fld4323rref = c.pz_completed_ref
      AND p._posted
      AND NOT EXISTS (
          SELECT 1 FROM public._document313 AS cancel
          WHERE cancel._fld3810_rrref = p._idrref
      )
      AND p._fld4306 IS NOT NULL AND p._fld4307 > p._fld4306
      AND p._fld4310rref IS NOT NULL AND p._fld4322rref IS NOT NULL
      AND p._fld4316rref IS NOT NULL
),
training_gz AS MATERIALIZED (
    SELECT
        'GZ:' || encode(g._idrref, 'hex') AS activity_event_key,
        g._fld3218::date AS activity_date,
        encode(g._fld3224rref, 'hex') AS club_id,
        encode(g._fld3223rref, 'hex') AS employee_id,
        encode(s._fld1733rref, 'hex') AS activity_id,
        encode(g._fld3226rref, 'hex') AS service_id,
        encode(g._fld3227rref, 'hex') AS room_id,
        'TRAINING'::text AS activity_kind,
        g._fld3218 AS start_at,
        g._fld3219 AS end_at,
        extract(epoch FROM g._fld3219 - g._fld3218) / 60.0 AS duration_minutes,
        CASE WHEN s._fld1778 IS TRUE THEN 'Бесплатно' ELSE 'Платно' END AS payment_kind
    FROM public._document279 AS g
    JOIN public._reference163 AS s ON s._idrref = g._fld3226rref
    JOIN public._reference70 AS a ON a._idrref = s._fld1733rref
    CROSS JOIN constants AS c
    WHERE g._fld3218 >= $1::date AND g._fld3218 < $2::date
      AND g._fld3231rref = c.empty_ref
      AND NOT g._marked
      AND g._fld3218 IS NOT NULL AND g._fld3219 > g._fld3218
      AND g._fld3224rref IS NOT NULL AND g._fld3223rref IS NOT NULL
      AND g._fld3226rref IS NOT NULL
),
coupon_ranked AS MATERIALIZED (
    SELECT
        rg._period,
        rg._fld7008rref AS client_ref,
        rg._fld7009rref AS club_ref,
        client._code::text AS client_code,
        doc._fld4322rref AS employee_ref,
        rg._fld7010rref AS service_ref,
        service._fld1733rref AS activity_ref,
        doc._fld4306 AS class_start,
        doc._fld4307 AS class_end,
        rg._fld7012::numeric AS quantity,
        service._fld1767::numeric AS service_minutes,
        service._description::text AS service_name,
        division._description::text AS division_name,
        row_number() over (
            partition by rg._fld7007_rrref, rg._fld7010rref
            order by rg._period desc
        ) AS rn
    FROM public._inforg7006 AS rg
    JOIN public._document329 AS doc ON doc._idrref = rg._fld7007_rrref
    JOIN public._reference141x1 AS client ON client._idrref = rg._fld7008rref
    JOIN public._reference225 AS employee ON employee._idrref = doc._fld4322rref
    JOIN public._enum448 AS state ON state._idrref = rg._fld7013rref
    JOIN coupon_services AS cs ON cs._idrref = rg._fld7010rref
    JOIN public._document329_vt4352 AS vt
      ON vt._document329_idrref = doc._idrref AND vt._fld4356rref = rg._fld7010rref
    JOIN public._reference163 AS service ON service._idrref = rg._fld7010rref
    JOIN public._reference70 AS division ON division._idrref = service._fld1733rref
    WHERE rg._period >= $1::date AND rg._period < $2::date
      AND state._enumorder = 4
      AND doc._fld4306 IS NOT NULL AND doc._fld4307 > doc._fld4306
),
coupon_latest AS MATERIALIZED (
    SELECT _period, client_ref, club_ref, client_code, employee_ref, service_ref,
           activity_ref, class_start, class_end, quantity, service_minutes,
           service_name, division_name
    FROM coupon_ranked
    WHERE rn = 1
),
coupon_visits AS MATERIALIZED (
    SELECT v._fld4171rref AS client_ref, v._fld4167rref AS club_ref,
           v._date_time AS visit_at, v._fld4172 AS visit_start
    FROM public._document325 AS v
    CROSS JOIN constants AS c
    JOIN (SELECT DISTINCT client_ref FROM coupon_latest) AS clients
      ON clients.client_ref = v._fld4171rref
    WHERE v._date_time >= $1::date AND v._date_time < $2::date
      AND v._fld4164rref = c.visit_operation_ref
),
coupon_contracts AS MATERIALIZED (
    SELECT client_ref, contract_start, contract_end
    FROM (
        SELECT contract._fld681rref AS client_ref,
               CASE WHEN contract._fld671 <> DATE '0001-01-01'
                    THEN contract._fld671 ELSE contract._fld674 END AS contract_start,
               contract._fld672 AS contract_end,
               row_number() over (
                   partition by contract._fld681rref order by contract._fld672 desc
               ) AS rn
        FROM public._reference59 AS contract
        CROSS JOIN constants AS c
        WHERE contract._fld696rref = c.club_card_type_ref
          AND contract._fld672 > $1::date
          AND contract._fld681rref IN (SELECT DISTINCT client_ref FROM coupon_latest)
    ) AS ranked
    WHERE rn = 1
),
coupon_candidate AS MATERIALIZED (
    SELECT p.*, v.visit_at
    FROM coupon_latest AS p
    JOIN coupon_visits AS v
      ON v.client_ref = p.client_ref
     AND v.club_ref = p.club_ref
     AND v.visit_at::date = p._period::date
     AND v.visit_start <= p.class_start
     AND v.visit_start <= p.class_end
    JOIN coupon_contracts AS c ON c.client_ref = p.client_ref
    WHERE c.contract_end > p.class_start
      AND ((p.division_name = 'Водные программы' AND p.class_start::date >= c.contract_start::date)
        OR (p.class_start::date >= c.contract_start::date
            AND p.class_start::date - c.contract_start::date < 31))
      AND p.quantity IS NOT NULL AND p.service_minutes IS NOT NULL
      AND p.quantity * p.service_minutes > 0
),
coupon_events AS MATERIALIZED (
    SELECT
        'CP:' || md5(concat_ws(E'\\x1f',
            coalesce(client_code, E'\\x00'), encode(club_ref, 'hex'),
            encode(activity_ref, 'hex'), encode(employee_ref, 'hex'),
            encode(service_ref, 'hex'), class_start::text
        )) AS activity_event_key,
        min(visit_at::date) AS activity_date,
        encode(club_ref, 'hex') AS club_id,
        encode(employee_ref, 'hex') AS employee_id,
        encode(activity_ref, 'hex') AS activity_id,
        encode(service_ref, 'hex') AS service_id,
        NULL::text AS room_id,
        CASE WHEN service_name IN ('Купон: Фитнес тест', 'Анализ состава тела ACCUNIQ')
             THEN 'COUPON_1' ELSE 'COUPON_2' END AS activity_kind,
        class_start AS start_at,
        class_end AS end_at,
        max(quantity * service_minutes) AS duration_minutes,
        'Бесплатно'::text AS payment_kind
    FROM coupon_candidate
    GROUP BY client_code, club_ref, activity_ref, employee_ref, service_ref,
             class_start, class_end, service_name
),
duty_coupon_pre AS MATERIALIZED (
    SELECT
        rg._period::date AS session_date,
        rg._fld7008rref AS client_ref,
        rg._fld7009rref AS club_ref,
        doc._fld4322rref AS employee_ref,
        doc._fld4306 AS session_start,
        doc._fld4307 AS session_end,
        service._fld1733rref AS activity_ref
    FROM public._inforg7006 AS rg
    JOIN public._document329 AS doc ON doc._idrref = rg._fld7007_rrref
    JOIN public._enum448 AS state ON state._idrref = rg._fld7013rref
    JOIN coupon_services AS cs ON cs._idrref = rg._fld7010rref
    JOIN public._reference163 AS service ON service._idrref = rg._fld7010rref
    WHERE rg._period >= $1::date AND rg._period < $2::date
      AND state._enumorder = 4
      AND doc._fld4306 IS NOT NULL AND doc._fld4307 > doc._fld4306
),
duty_coupon_visits AS MATERIALIZED (
    SELECT v._fld4171rref AS client_ref, v._fld4167rref AS club_ref,
           v._date_time::date AS visit_date, v._fld4172 AS visit_start
    FROM public._document325 AS v
    CROSS JOIN constants AS c
    JOIN (SELECT DISTINCT client_ref FROM duty_coupon_pre) AS clients
      ON clients.client_ref = v._fld4171rref
    WHERE v._date_time >= $1::date AND v._date_time < $2::date
      AND v._fld4164rref = c.visit_operation_ref
),
duty_coupon_contracts AS MATERIALIZED (
    SELECT contract._fld681rref AS client_ref,
           CASE WHEN contract._fld671 <> DATE '0001-01-01'
                THEN contract._fld671 ELSE contract._fld674 END AS contract_start,
           contract._fld672 AS contract_end
    FROM public._reference59 AS contract
    CROSS JOIN constants AS c
    WHERE contract._fld696rref = c.club_card_type_ref
      AND contract._fld672 > $1::date
      AND contract._fld681rref IN (SELECT DISTINCT client_ref FROM duty_coupon_pre)
),
duty_coupon_sessions AS MATERIALIZED (
    SELECT p.session_date, p.club_ref, p.employee_ref, p.session_start, p.session_end
    FROM duty_coupon_pre AS p
    JOIN duty_coupon_visits AS v
      ON v.client_ref = p.client_ref
     AND v.club_ref = p.club_ref
     AND v.visit_date = p.session_date
     AND v.visit_start <= p.session_end
    JOIN duty_coupon_contracts AS c ON c.client_ref = p.client_ref
    LEFT JOIN public._reference70 AS division ON division._idrref = p.activity_ref
    WHERE c.contract_end > p.session_start
      AND ((division._description::text = 'Водные программы'
            AND p.session_start::date >= c.contract_start::date)
        OR (p.session_start::date >= c.contract_start::date
            AND p.session_start::date - c.contract_start::date < 31))
),
duty_inputs AS MATERIALIZED (
    SELECT d._fld7108rref AS club_ref, d._fld7109rref AS employee_ref,
           d._fld7113rref AS room_ref, d._fld7110 AS start_at,
           d._fld7111 AS end_at, d._fld7115::numeric AS duty_minutes
    FROM public._inforg7107 AS d
    CROSS JOIN constants AS c
    WHERE d._fld7112rref = c.duty_type_ref
      AND d._fld7110 >= $1::date AND d._fld7110 < $2::date
      AND d._fld7111 > d._fld7110
),
duty_events AS MATERIALIZED (
    SELECT
        'DU:' || md5(concat_ws(E'\\x1f', encode(d.club_ref, 'hex'),
            encode(d.employee_ref, 'hex'), encode(d.room_ref, 'hex'),
            d.start_at::text, d.end_at::text, d.duty_minutes::text
        )) AS activity_event_key,
        d.start_at::date AS activity_date,
        encode(d.club_ref, 'hex') AS club_id,
        encode(d.employee_ref, 'hex') AS employee_id,
        NULL::text AS activity_id,
        NULL::text AS service_id,
        encode(d.room_ref, 'hex') AS room_id,
        'DUTY'::text AS activity_kind,
        d.start_at,
        d.end_at,
        greatest(0::numeric, d.duty_minutes - coalesce(sum(
            extract(epoch FROM least(d.end_at, s.session_end)
                - greatest(d.start_at, s.session_start)) / 60.0
        ), 0::numeric)) AS duration_minutes,
        'Дежурство'::text AS payment_kind
    FROM duty_inputs AS d
    LEFT JOIN duty_coupon_sessions AS s
      ON s.club_ref = d.club_ref
     AND s.employee_ref = d.employee_ref
     AND s.session_date = d.start_at::date
     AND s.session_start < d.end_at AND s.session_end > d.start_at
    GROUP BY d.club_ref, d.employee_ref, d.room_ref, d.start_at, d.end_at, d.duty_minutes
)
SELECT activity_event_key, activity_date, club_id, employee_id, activity_id,
       service_id, room_id, activity_kind, start_at, end_at, duration_minutes,
       payment_kind
FROM training_pz
UNION ALL
SELECT activity_event_key, activity_date, club_id, employee_id, activity_id,
       service_id, room_id, activity_kind, start_at, end_at, duration_minutes,
       payment_kind
FROM training_gz
UNION ALL
SELECT activity_event_key, activity_date, club_id, employee_id, activity_id,
       service_id, room_id, activity_kind, start_at, end_at, duration_minutes,
       payment_kind
FROM duty_events
UNION ALL
SELECT activity_event_key, activity_date, club_id, employee_id, activity_id,
       service_id, room_id, activity_kind, start_at, end_at, duration_minutes,
       payment_kind
FROM coupon_events;
