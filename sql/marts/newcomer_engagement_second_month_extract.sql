-- $1/$2 are inclusive/exclusive boundaries of month_of_engagement.
-- This reproduces the supplied current PBIT M/SQL rules; no status, posting,
-- deletion, return or deduplication predicate is added.
WITH main_pairs AS MATERIALIZED (
    SELECT
        ('main:' || encode(ab._idrref, 'hex') || ':' || encode(cl._idrref, 'hex'))::text AS source_row_id,
        encode(ab._idrref, 'hex')::text AS contract_id,
        ab._code::text AS contract_code,
        encode(cl._idrref, 'hex')::text AS client_id,
        cl._code::text AS client_code,
        cl._description::text AS client_name,
        encode(ab._fld687rref, 'hex')::text AS access_club_id,
        club._description::text AS access_club_name,
        ab._fld671::date AS membership_start_date,
        (date_trunc('month', ab._fld671::date) + INTERVAL '1 month')::date AS month_of_engagement,
        age._description::text AS age_category,
        CASE ab._fld694rref
            WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
            WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
            WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
            ELSE NULL
        END::text AS tenure
    FROM public._reference59 ab
    LEFT JOIN public._reference141x1 cl ON cl._idrref = ab._fld681rref
    LEFT JOIN public._reference132 club ON club._idrref = ab._fld687rref
    LEFT JOIN public._reference163 nom ON nom._idrref = ab._fld685rref
    LEFT JOIN public._reference87 age ON age._idrref = nom._fld1741rref
    WHERE ab._fld671 >= ($1::date - INTERVAL '1 month')
      AND ab._fld671 < ($2::date - INTERVAL '1 month')
      AND ab._fld672 > ab._fld671
      AND (ab._fld672 - ab._fld671) > INTERVAL '30 days'
      AND cl._idrref IS NOT NULL
      AND ab._fld696rref = decode('bf4b50662e88eb7b44046ebf4849976f', 'hex')
      AND nom._parentidrref <> decode('b5ad0e5b4356c20d11e7145dde9ec41c', 'hex')
      AND ab._fld693 > 30
), child_raw AS MATERIALIZED (
    SELECT
        v._document346_idrref AS receipt_ref,
        v._lineno4914 AS line_no,
        r._idrref AS contract_ref,
        r._code::text AS contract_code,
        child._idrref AS client_ref,
        child._code::text AS client_code,
        child._description::text AS client_name,
        r._fld687rref AS access_club_ref,
        club._description::text AS access_club_name,
        adult._idrref AS adult_ref,
        stock._fld4932rref AS product_ref,
        greatest(r._fld671::date, d._date_time::date) AS candidate_start_date,
        r._fld674 AS legacy_rank_order
    FROM public._document346_vt4913 v
    LEFT JOIN public._document346 d ON d._idrref = v._document346_idrref
    LEFT JOIN public._reference59 r ON r._idrref = v._fld4915rref
    LEFT JOIN public._reference132 club ON club._idrref = r._fld687rref
    LEFT JOIN public._reference141x1 child ON child._idrref = v._fld4916rref
    LEFT JOIN public._reference141x1 adult ON adult._idrref = r._fld681rref
    LEFT JOIN public._document346_vt4924 stock
      ON stock._document346_idrref = d._idrref AND stock._fld4929 = v._fld4917
    WHERE d._date_time::date >= DATE '2023-01-01'
      AND d._fld4910rref = decode('859cb45b51f9e02c4fb16764c804af3d', 'hex')
      AND r._fld672 > r._fld671
      AND (r._fld670 IS NOT NULL OR r._fld670 <> TIMESTAMP '0001-01-01 00:00:00')
      AND r._fld681rref IS NOT NULL
      AND child._code IS NOT NULL
      AND club._description IS NOT NULL
), child_sales AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref, a._fld7648rref AS adult_ref,
           a._fld7649rref AS product_ref, sum(a._fld7657)::numeric AS net_quantity,
           sum(a._fld7659)::numeric AS net_amount
    FROM public._accumrg7646 a
    JOIN (
        SELECT DISTINCT receipt_ref, adult_ref, product_ref
        FROM child_raw
        WHERE product_ref IS NOT NULL
    ) k ON k.receipt_ref = a._fld7647_rrref
       AND k.adult_ref = a._fld7648rref
       AND k.product_ref = a._fld7649rref
    GROUP BY 1, 2, 3
), child_valid_sales AS MATERIALIZED (
    SELECT cr.*
    FROM child_raw cr
    LEFT JOIN child_sales s USING (receipt_ref, adult_ref, product_ref)
    WHERE s.net_quantity IS NULL OR (s.net_quantity > 0 AND s.net_amount > 0)
), child_with_latest_start AS MATERIALIZED (
    SELECT cvs.*, max(candidate_start_date) OVER (
        PARTITION BY contract_ref, client_ref
    ) AS membership_start_date
    FROM child_valid_sales cvs
), child_ranked AS MATERIALIZED (
    SELECT *, rank() OVER (
        PARTITION BY adult_ref, client_ref, contract_ref
        ORDER BY legacy_rank_order DESC
    ) AS legacy_rank
    FROM child_with_latest_start
    WHERE candidate_start_date = membership_start_date
), child_filtered AS MATERIALIZED (
    SELECT *
    FROM child_ranked
    WHERE legacy_rank = 1
      AND (date_trunc('month', membership_start_date) + INTERVAL '1 month')::date >= $1::date
      AND (date_trunc('month', membership_start_date) + INTERVAL '1 month')::date < $2::date
), tenure_history AS MATERIALIZED (
    SELECT
        cl._code::text AS client_code,
        h._period AS changed_at,
        CASE h._fld5656rref
            WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
            WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
            WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
            ELSE NULL
        END::text AS tenure
    FROM public._inforg5654 h
    LEFT JOIN public._reference141x1 cl ON cl._idrref = h._fld5655rref
    WHERE h._fld5656rref IN (
        decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
        decode('9e369ac955bf602149e17b549b0f1498', 'hex'),
        decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex')
    )
), child_with_tenure AS MATERIALIZED (
    SELECT
        ('child:' || encode(cf.receipt_ref, 'hex') || ':' || cf.line_no::text)::text AS source_row_id,
        encode(cf.contract_ref, 'hex')::text AS contract_id,
        cf.contract_code,
        encode(cf.client_ref, 'hex')::text AS client_id,
        cf.client_code,
        cf.client_name,
        encode(cf.access_club_ref, 'hex')::text AS access_club_id,
        cf.access_club_name,
        cf.membership_start_date,
        (date_trunc('month', cf.membership_start_date) + INTERVAL '1 month')::date AS month_of_engagement,
        'Дети'::text AS age_category,
        coalesce(th.tenure, 'New')::text AS tenure,
        row_number() OVER (
            PARTITION BY cf.client_ref, cf.membership_start_date
            ORDER BY th.changed_at DESC
        ) AS legacy_tenure_row_number
    FROM child_filtered cf
    LEFT JOIN tenure_history th
      ON th.client_code = cf.client_code
     AND th.changed_at < cf.membership_start_date
), base_pairs AS MATERIALIZED (
    SELECT source_row_id, contract_id, contract_code, client_id, client_code,
           client_name, access_club_id, access_club_name, membership_start_date,
           month_of_engagement, age_category, tenure
    FROM main_pairs
    WHERE month_of_engagement >= $1::date AND month_of_engagement < $2::date
    UNION ALL
    SELECT source_row_id, contract_id, contract_code, client_id, client_code,
           client_name, access_club_id, access_club_name, membership_start_date,
           month_of_engagement, age_category, tenure
    FROM child_with_tenure
    WHERE legacy_tenure_row_number = 1 OR legacy_tenure_row_number IS NULL
), qualified_visits AS MATERIALIZED (
    SELECT encode(a._fld7578_rrref, 'hex')::text AS contract_id,
           encode(a._fld7576rref, 'hex')::text AS client_id,
           a._period::date AS visit_date
    FROM public._accumrg7575 a
    JOIN public._reference163 n ON n._idrref = a._fld7579rref
    WHERE a._period >= $1::date AND a._period < $2::date
      AND n._description = 'посещение клуба'
      AND n._description NOT LIKE '%ИП%'
      AND n._description NOT LIKE '%Контракт сотрудника%'
), visit_aggregate AS MATERIALIZED (
    SELECT b.source_row_id, count(v.visit_date)::bigint AS second_month_visit_count,
           max(v.visit_date)::date AS last_visit_date
    FROM base_pairs b
    LEFT JOIN qualified_visits v
      ON v.contract_id = b.contract_id AND v.client_id = b.client_id
     AND v.visit_date >= b.month_of_engagement
     AND v.visit_date < b.month_of_engagement + INTERVAL '1 month'
    GROUP BY b.source_row_id
), constants AS MATERIALIZED (
    SELECT decode('4296a4bf013441d111e7cae05001072c', 'hex') AS coupons_parent_ref,
           decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex') AS visit_operation_ref,
           decode('bf4b50662e88eb7b44046ebf4849976f', 'hex') AS club_card_type_ref
), spt_pairs AS MATERIALIZED (
    -- The supplied PBIT calculates all card/client SPT pairs and later joins
    -- them to the fact. Restricting cards to fact pairs is relationally
    -- equivalent to that final inner match and avoids an all-history join.
    SELECT DISTINCT b.contract_id, b.client_id
    FROM (SELECT DISTINCT contract_id, client_id FROM base_pairs) b
    JOIN public._reference59 card
      ON encode(card._idrref, 'hex')::text = b.contract_id
     AND encode(card._fld681rref, 'hex')::text = b.client_id
    JOIN public._inforg7006 rg ON rg._fld7008rref = card._fld681rref
    JOIN public._document329 lesson ON lesson._idrref = rg._fld7007_rrref
    JOIN public._enum448 e ON e._idrref = rg._fld7013rref
    JOIN public._reference163 service ON service._idrref = rg._fld7010rref
    JOIN constants c ON true
    JOIN public._document325 visit_doc
      ON visit_doc._fld4171rref = rg._fld7008rref
     AND visit_doc._date_time::date = lesson._fld4306::date
     AND visit_doc._date_time::date >= DATE '2024-01-01'
     AND visit_doc._fld4164rref = c.visit_operation_ref
    WHERE rg._period::date >= DATE '2024-01-01'
      AND e._enumorder = 4
      AND service._parentidrref = c.coupons_parent_ref
      AND card._fld696rref = c.club_card_type_ref
      AND lesson._fld4306::date BETWEEN card._fld671 AND card._fld672
)
SELECT b.source_row_id, b.contract_id, b.contract_code, b.client_id, b.client_code,
       b.client_name, b.access_club_id, b.access_club_name, b.membership_start_date,
       b.month_of_engagement, b.age_category, b.tenure,
       v.second_month_visit_count, v.last_visit_date,
       CASE WHEN v.second_month_visit_count >= 4 THEN '4+' ELSE v.second_month_visit_count::text END::text AS visit_bucket,
       CASE WHEN s.contract_id IS NULL THEN 'Не прошел' ELSE 'Прошел СПТ' END::text AS intro_training_status
FROM base_pairs b
JOIN visit_aggregate v USING (source_row_id)
LEFT JOIN spt_pairs s ON s.contract_id = b.contract_id AND s.client_id = b.client_id
ORDER BY b.source_row_id;
