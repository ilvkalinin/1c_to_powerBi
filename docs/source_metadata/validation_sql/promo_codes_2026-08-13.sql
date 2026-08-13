-- Stage 2 controls for the current SQL/M/DAX of «Отчёта по промокодам».
-- Execute only against gymdb with gymdb_readonly in BEGIN READ ONLY.
-- All outputs are aggregates; no PII, business names, or raw IDs are returned.
-- Snapshot: live source at execution on 2026-08-13; statement_timeout 30000 ms.
--
-- Expected results are fixed before execution. A count observed by a current
-- legacy rule is not a licence to alter that rule (BR-018).

BEGIN READ ONLY;
SET LOCAL statement_timeout = '30000';

-- CHECK: PC-V00 source metadata
-- Expected: each physical field named by current M exists exactly once. Any
-- missing field is a validation failure and is recorded only in the missing
-- source-object registry if the relation itself is absent.
SELECT table_name,
       count(*)::bigint AS expected_field_count,
       count(*) FILTER (WHERE data_type = 'bytea')::bigint AS bytea_fields,
       count(*) FILTER (WHERE data_type IN ('timestamp without time zone', 'timestamp with time zone'))::bigint AS timestamp_fields
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (table_name, column_name) IN (
      ('_accumrg7606', '_period'), ('_accumrg7606', '_recordertref'),
      ('_accumrg7606', '_recorderrref'), ('_accumrg7606', '_lineno'),
      ('_accumrg7606', '_recordkind'), ('_accumrg7606', '_active'),
      ('_accumrg7606', '_fld7607rref'), ('_accumrg7606', '_fld7608rref'),
      ('_accumrg7606', '_fld7610rref'), ('_accumrg7606', '_fld7611rref'),
      ('_accumrg7606', '_fld7612rref'), ('_accumrg7606', '_fld7613'),
      ('_accumrg7615', '_period'), ('_accumrg7615', '_recordertref'),
      ('_accumrg7615', '_recorderrref'), ('_accumrg7615', '_lineno'),
      ('_accumrg7615', '_active'), ('_accumrg7615', '_fld7616rref'),
      ('_accumrg7615', '_fld7617_rrref'), ('_accumrg7615', '_fld7618rref'),
      ('_accumrg7615', '_fld7619rref'), ('_accumrg7615', '_fld7620rref'),
      ('_accumrg7615', '_fld7621rref'), ('_accumrg7615', '_fld7623rref'),
      ('_accumrg7615', '_fld7624rref'), ('_accumrg7615', '_fld7626'),
      ('_accumrg7553', '_period'), ('_accumrg7553', '_recordkind'),
      ('_accumrg7553', '_active'), ('_accumrg7553', '_fld7554rref'),
      ('_accumrg7553', '_fld7555rref'), ('_accumrg7553', '_fld7557rref'),
      ('_accumrg7553', '_fld7559_rrref'),
      ('_document298_vt3596', '_document298_idrref'),
      ('_document298_vt3596', '_fld3600rref')
  )
GROUP BY table_name
ORDER BY table_name;

-- CHECK: PC-V01 technical key
-- Expected: in each source register, (RecorderTRef, RecorderRRef, LineNo)
-- is non-NULL and has no duplicate group. This is a physical key check, not
-- proof of business grain.
WITH source_rows AS (
    SELECT 'promo_gift'::text AS source_kind,
           _recordertref, _recorderrref, _lineno
    FROM _accumrg7606
    WHERE _period >= timestamp '2025-01-01'
    UNION ALL
    SELECT 'discount'::text,
           _recordertref, _recorderrref, _lineno
    FROM _accumrg7615
    WHERE _period >= timestamp '2025-01-01'
), grouped AS (
    SELECT source_kind, _recordertref, _recorderrref, _lineno, count(*)::bigint AS n
    FROM source_rows
    GROUP BY source_kind, _recordertref, _recorderrref, _lineno
)
SELECT source_kind,
       sum(n)::bigint AS source_rows,
       count(*)::bigint AS distinct_technical_keys,
       count(*) FILTER (WHERE n > 1)::bigint AS duplicate_key_groups,
       coalesce(sum(n) FILTER (WHERE n > 1) - count(*) FILTER (WHERE n > 1), 0)::bigint AS excess_rows,
       count(*) FILTER (WHERE _recordertref IS NULL OR _recorderrref IS NULL OR _lineno IS NULL)::bigint AS null_key_groups
FROM grouped
GROUP BY source_kind
ORDER BY source_kind;

-- CHECK: PC-V02 discount-line join preservation
-- Expected: the current M joins must preserve a technical discount movement
-- once in the bounded control month [2026-06-01; 2026-07-01). A positive
-- excess is a documented one-to-many risk, not a reason to deduplicate or
-- change current MAX/SUM aggregation. The bound is a safety limit after the
-- full historical join exceeded statement_timeout without a result.
WITH base AS (
    SELECT ar._recordertref, ar._recorderrref, ar._lineno,
           ar._fld7617_rrref, ar._fld7621rref, ar._fld7620rref,
           ar._fld7623rref, ar._fld7619rref
    FROM _accumrg7615 ar
    LEFT JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7621rref
      AND membership._fld672 > membership._fld671
      AND membership._fld672 IS NOT NULL
      AND membership._fld671 IS NOT NULL
      AND membership._fld671 <> timestamp '0001-01-01'
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND promo._description IS NOT NULL
      AND (membership._code IS NULL
           OR (membership._fld672 > membership._fld671
               AND membership._fld672 IS NOT NULL
               AND membership._fld671 IS NOT NULL
               AND membership._fld671 <> timestamp '0001-01-01'))
), joined AS (
    SELECT b._recordertref, b._recorderrref, b._lineno,
           d332._idrref AS document332_id,
           v4465._lineno4466 AS document332_line_no,
           d346._idrref AS document346_id,
           v4996._lineno4997 AS document346_discount_line_no,
           v4924._lineno4925 AS document346_sale_line_no
    FROM base b
    LEFT JOIN _document332 d332 ON d332._idrref = b._fld7617_rrref
    LEFT JOIN _document332_vt4465 v4465
      ON v4465._document332_idrref = d332._idrref
     AND v4465._fld4467rref = b._fld7621rref
    LEFT JOIN _document346 d346 ON d346._idrref = b._fld7617_rrref
    LEFT JOIN _document346_vt4996 v4996
      ON v4996._document346_idrref = d346._idrref
     AND v4996._fld5003rref = b._fld7620rref
     AND v4996._fld5001rref = b._fld7623rref
     AND v4996._fld5000rref = b._fld7619rref
     AND v4996._lineno4997 = b._lineno
    LEFT JOIN _document346_vt4924 v4924
      ON v4924._document346_idrref = d346._idrref
     AND v4924._fld4932rref = b._fld7619rref
     AND v4924._lineno4925 = b._lineno
)
SELECT (SELECT count(*)::bigint FROM base) AS base_technical_rows,
       count(*)::bigint AS rows_after_current_joins,
       count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint AS distinct_technical_keys_after_join,
       (count(*) - count(DISTINCT (_recordertref, _recorderrref, _lineno)))::bigint AS join_excess_rows,
       count(*) FILTER (WHERE document332_id IS NOT NULL AND document332_line_no IS NOT NULL)::bigint AS document332_line_matches,
       count(*) FILTER (WHERE document346_id IS NOT NULL AND document346_discount_line_no IS NOT NULL)::bigint AS document346_discount_line_matches,
       count(*) FILTER (WHERE document346_id IS NOT NULL AND document346_sale_line_no IS NOT NULL)::bigint AS document346_sale_line_matches
FROM joined;

-- CHECK: PC-V03 physical states
-- Expected: quantify, without interpreting, RecordKind/Active and document
-- Posted/Marked. No new state filter is allowed from this observation alone.
WITH discount_rows AS (
    SELECT ar._active, ar._fld7617_rrref
    FROM _accumrg7615 ar
    LEFT JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    WHERE ar._period >= timestamp '2025-01-01'
      AND promo._description IS NOT NULL
)
SELECT
    (SELECT count(*)::bigint FROM _accumrg7606 WHERE _period >= timestamp '2025-01-01') AS promo_gift_rows,
    (SELECT count(*)::bigint FROM _accumrg7606 WHERE _period >= timestamp '2025-01-01' AND NOT _active) AS promo_gift_inactive,
    (SELECT count(*)::bigint FROM _accumrg7606 WHERE _period >= timestamp '2025-01-01' AND _recordkind = 1) AS promo_gift_recordkind_1,
    (SELECT count(*)::bigint FROM _accumrg7606 WHERE _period >= timestamp '2025-01-01' AND _recordkind <> 1) AS promo_gift_other_recordkind,
    (SELECT count(*)::bigint FROM discount_rows) AS discount_rows,
    (SELECT count(*)::bigint FROM discount_rows WHERE NOT _active) AS discount_inactive,
    (SELECT count(*)::bigint FROM discount_rows r JOIN _document332 d ON d._idrref = r._fld7617_rrref WHERE NOT d._posted) AS document332_unposted,
    (SELECT count(*)::bigint FROM discount_rows r JOIN _document332 d ON d._idrref = r._fld7617_rrref WHERE d._marked) AS document332_marked,
    (SELECT count(*)::bigint FROM discount_rows r JOIN _document346 d ON d._idrref = r._fld7617_rrref WHERE NOT d._posted) AS document346_unposted,
    (SELECT count(*)::bigint FROM discount_rows r JOIN _document346 d ON d._idrref = r._fld7617_rrref WHERE d._marked) AS document346_marked;

-- CHECK: PC-V04 action and gift cardinality
-- Expected: every table-part row has a parent marketing-action document;
-- current M removes duplicate discount values, so any duplicate group is a
-- source observation and must not change the current filter result.
WITH action_rows AS (
    SELECT vt._document298_idrref, vt._fld3600rref, d._idrref AS parent_id
    FROM _document298_vt3596 vt
    LEFT JOIN _document298 d ON d._idrref = vt._document298_idrref
), duplicate_discounts AS (
    SELECT _fld3600rref
    FROM action_rows
    WHERE _fld3600rref IS NOT NULL
    GROUP BY _fld3600rref
    HAVING count(*) > 1
), gift_base AS (
    SELECT ar._recordertref, ar._recorderrref, ar._lineno,
           ar._fld7610rref, kd._fld1456rref AS discount_id
    FROM _accumrg7606 ar
    LEFT JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    LEFT JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1
      AND ar._fld7613 = 1
      AND promo._description IS NOT NULL
), gift_join AS (
    SELECT b._recordertref, b._recorderrref, b._lineno
    FROM gift_base b
    JOIN _accumrg7553 p
      ON p._fld7554rref = b._fld7610rref
     AND p._fld7555rref = b.discount_id
     AND p._recordkind = 1
     AND p._period::date >= date '2025-01-01'
    JOIN _reference187 g ON g._idrref = p._fld7557rref
)
SELECT
    (SELECT count(*)::bigint FROM action_rows) AS action_table_rows,
    (SELECT count(*)::bigint FROM action_rows WHERE parent_id IS NULL) AS action_rows_without_parent,
    (SELECT count(*)::bigint FROM action_rows WHERE _fld3600rref IS NULL) AS action_rows_without_discount,
    (SELECT count(*)::bigint FROM duplicate_discounts) AS duplicate_discount_groups,
    (SELECT count(*)::bigint FROM gift_base) AS promo_gift_technical_rows,
    (SELECT count(*)::bigint FROM gift_join) AS rows_after_current_gift_join,
    (SELECT count(*)::bigint FROM gift_join) -
      (SELECT count(DISTINCT (_recordertref, _recorderrref, _lineno))::bigint FROM gift_join) AS gift_join_excess_rows;

-- CHECK: PC-V05 strict 45-day membership outcome boundary
-- Expected: only day offsets 1..44 are accepted by the confirmed current
-- rule. Day 0 and day 45 are measured separately and must not be treated as
-- accepted outcomes. This is a source-side boundary check, not an independent
-- Power BI-card reconciliation. Applications are bounded to June 2026 so that
-- the source-side join finishes within the approved statement timeout.
WITH applications AS (
    SELECT 'promo_gift'::text AS source_kind, ar._recordertref, ar._recorderrref,
           ar._lineno, ar._period::date AS application_date, ar._fld7607rref AS client_id,
           ar._fld7610rref AS source_membership_id
    FROM _accumrg7606 ar
    JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    JOIN _accumrg7553 gift ON gift._fld7554rref = ar._fld7610rref
      AND gift._fld7555rref = kd._fld1456rref
      AND gift._recordkind = 1
      AND gift._period::date >= date '2025-01-01'
    JOIN _reference187 gift_name ON gift_name._idrref = gift._fld7557rref
    JOIN _reference59 membership ON membership._idrref = ar._fld7610rref
      AND membership._fld670 IS NOT NULL
      AND membership._fld670 <> timestamp '0001-01-01'
      AND membership._fld672 > membership._fld671
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1 AND ar._fld7613 = 1
      AND promo._description IS NOT NULL
    UNION ALL
    SELECT 'discount', ar._recordertref, ar._recorderrref, ar._lineno,
           ar._period::date, ar._fld7618rref, ar._fld7621rref
    FROM _accumrg7615 ar
    JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7621rref
      AND membership._fld672 > membership._fld671
      AND membership._fld671 <> timestamp '0001-01-01'
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND promo._description IS NOT NULL
      AND (membership._code IS NULL OR membership._fld672 > membership._fld671)
), activations AS (
    SELECT _fld681rref AS client_id, _fld670::date AS activation_date, _idrref AS membership_id
    FROM _reference59
    WHERE _fld670 >= timestamp '2025-01-01'
      AND _fld670 < timestamp '2027-01-01'
      AND _fld670 <> timestamp '0001-01-01'
      AND _fld672 > _fld671
)
SELECT count(*) FILTER (WHERE a.activation_date - p.application_date = 0)::bigint AS day_0_pairs,
       count(*) FILTER (WHERE a.activation_date - p.application_date = 1)::bigint AS day_1_pairs,
       count(*) FILTER (WHERE a.activation_date - p.application_date = 44)::bigint AS day_44_pairs,
       count(*) FILTER (WHERE a.activation_date - p.application_date = 45)::bigint AS day_45_pairs,
       count(*) FILTER (WHERE a.activation_date > p.application_date
                          AND a.activation_date < p.application_date + 45
                          AND a.membership_id <> p.source_membership_id)::bigint AS current_rule_accepted_pairs
FROM applications p
JOIN activations a ON a.client_id = p.client_id
  AND a.activation_date >= p.application_date
  AND a.activation_date <= p.application_date + 45;

-- CHECK: PC-V05a strict 45-day DPFU outcome boundary
-- Expected: the current DPFU outcome accepts only day offsets 1..44. Day 0
-- and day 45 remain excluded. The same June-2026 application control window
-- is used; no client code or service name is returned.
WITH applications AS (
    SELECT ar._period::date AS application_date, ar._fld7607rref AS client_id
    FROM _accumrg7606 ar
    JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    JOIN _accumrg7553 gift ON gift._fld7554rref = ar._fld7610rref
      AND gift._fld7555rref = kd._fld1456rref
      AND gift._recordkind = 1 AND gift._period::date >= date '2025-01-01'
    JOIN _reference187 gift_name ON gift_name._idrref = gift._fld7557rref
    JOIN _reference59 membership ON membership._idrref = ar._fld7610rref
      AND membership._fld670 IS NOT NULL AND membership._fld670 <> timestamp '0001-01-01'
      AND membership._fld672 > membership._fld671
    WHERE ar._period >= timestamp '2026-06-01' AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1 AND ar._fld7613 = 1 AND promo._description IS NOT NULL
    UNION ALL
    SELECT ar._period::date, ar._fld7618rref
    FROM _accumrg7615 ar
    JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7621rref
      AND membership._fld672 > membership._fld671 AND membership._fld671 <> timestamp '0001-01-01'
    WHERE ar._period >= timestamp '2026-06-01' AND ar._period < timestamp '2026-07-01'
      AND promo._description IS NOT NULL
      AND (membership._code IS NULL OR membership._fld672 > membership._fld671)
), dpfu AS (
    SELECT a._period::date AS purchase_date, a._fld7576rref AS client_id
    FROM _accumrg7575 a
    JOIN _reference163 n ON n._idrref = a._fld7579rref
    JOIN _reference70 d ON d._idrref = n._fld1733rref
    WHERE a._period >= timestamp '2026-06-01' AND a._period < timestamp '2026-08-15'
      AND n._description::text IS DISTINCT FROM 'посещение клуба'
      AND d._description::text IN ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы', 'Тренажёрный зал', 'Тренажерный зал')
    UNION ALL
    SELECT a._period::date, a._fld7648rref
    FROM _accumrg7646 a
    JOIN _reference163 n ON n._idrref = a._fld7649rref
    JOIN _reference70 d ON d._idrref = n._fld1733rref
    WHERE a._period >= timestamp '2026-06-01' AND a._period < timestamp '2026-08-15'
      AND n._description::text IS DISTINCT FROM 'посещение клуба'
      AND d._description::text IN ('Игровой зал', 'Восстановительный фитнес', 'Боевые искусства',
          'Детский клуб', 'Водные программы', 'Групповые программы', 'Тренажёрный зал', 'Тренажерный зал')
)
SELECT count(*) FILTER (WHERE d.purchase_date - p.application_date = 0)::bigint AS day_0_pairs,
       count(*) FILTER (WHERE d.purchase_date - p.application_date = 1)::bigint AS day_1_pairs,
       count(*) FILTER (WHERE d.purchase_date - p.application_date = 44)::bigint AS day_44_pairs,
       count(*) FILTER (WHERE d.purchase_date - p.application_date = 45)::bigint AS day_45_pairs,
       count(*) FILTER (WHERE d.purchase_date > p.application_date
                          AND d.purchase_date < p.application_date + 45)::bigint AS current_rule_accepted_pairs
FROM applications p
JOIN dpfu d ON d.client_id = p.client_id
  AND d.purchase_date >= p.application_date
  AND d.purchase_date <= p.application_date + 45;

-- CHECK: PC-V05b strict 45-day friend-membership outcome boundary
-- Expected: the friend outcome starts from friend_activation_date and accepts
-- only offsets 1..44, excluding the gifted membership itself. Day 0 and 45
-- are explicitly measured and excluded by the current rule.
WITH friend_gifts AS (
    SELECT ar._period::date AS application_date, present._fld7559_rrref AS friend_membership_id,
           friend_membership._fld681rref AS friend_id,
           friend_membership._fld670::date AS friend_activation_date
    FROM _accumrg7606 ar
    JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    JOIN _accumrg7553 present ON present._fld7554rref = ar._fld7610rref
      AND present._fld7555rref = kd._fld1456rref
      AND present._recordkind = 1 AND present._period::date >= date '2025-01-01'
    JOIN _reference187 gift_name ON gift_name._idrref = present._fld7557rref
    JOIN _reference59 friend_membership ON friend_membership._idrref = present._fld7559_rrref
    WHERE ar._period >= timestamp '2026-06-01' AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1 AND ar._fld7613 = 1 AND promo._description IS NOT NULL
      AND present._fld7559_rrref IS NOT NULL
), activations AS (
    SELECT _fld681rref AS client_id, _fld670::date AS activation_date, _idrref AS membership_id
    FROM _reference59
    WHERE _fld670 >= timestamp '2025-01-01' AND _fld670 < timestamp '2027-01-01'
      AND _fld670 <> timestamp '0001-01-01' AND _fld672 > _fld671
)
SELECT count(*) FILTER (WHERE a.activation_date - f.friend_activation_date = 0)::bigint AS day_0_pairs,
       count(*) FILTER (WHERE a.activation_date - f.friend_activation_date = 1)::bigint AS day_1_pairs,
       count(*) FILTER (WHERE a.activation_date - f.friend_activation_date = 44)::bigint AS day_44_pairs,
       count(*) FILTER (WHERE a.activation_date - f.friend_activation_date = 45)::bigint AS day_45_pairs,
       count(*) FILTER (WHERE a.activation_date > f.friend_activation_date
                          AND a.activation_date < f.friend_activation_date + 45
                          AND a.membership_id <> f.friend_membership_id)::bigint AS current_rule_accepted_pairs
FROM friend_gifts f
JOIN activations a ON a.client_id = f.friend_id
  AND a.activation_date >= f.friend_activation_date
  AND a.activation_date <= f.friend_activation_date + 45;

-- CHECK: PC-V06 gift-day parser risk
-- Expected: count values whose numeric gift days need three or more digits.
-- Zero means the legacy two-character DAX extraction is not truncated in the
-- current source; a positive count is VALIDATION_FAILED for that assumption,
-- while the legacy result remains unchanged under BR-018.
SELECT count(*)::bigint AS gift_names_with_day_pattern,
       count(*) FILTER (WHERE _description::text ~ '\\+\\s*[0-9]{3,}\\s*дн\\.')::bigint AS gift_names_with_100_plus_days
FROM _reference187
WHERE _description::text LIKE '%+ %'
  AND _description::text ILIKE '%дн.%';

-- CHECK: PC-V07 current source-side eligibility
-- Expected: report current M input and required-dimension NULL counts in the
-- bounded control month [2026-06-01; 2026-07-01).
-- These values are source-side evidence for exact SQL/M/DAX reproduction;
-- they are not asserted to match an unavailable Power BI export.
WITH promo_gift AS (
    SELECT ar._period::date AS application_date, ar._fld7607rref AS client_id,
           ar._fld7612rref AS club_id, kd._fld1457rref AS promo_id
    FROM _accumrg7606 ar
    LEFT JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    LEFT JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    LEFT JOIN _accumrg7553 gift ON gift._fld7554rref = ar._fld7610rref
      AND gift._fld7555rref = kd._fld1456rref
      AND gift._recordkind = 1
      AND gift._period::date >= date '2025-01-01'
    LEFT JOIN _reference187 gift_name ON gift_name._idrref = gift._fld7557rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7610rref
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1 AND ar._fld7613 = 1
      AND promo._description IS NOT NULL AND gift_name._description IS NOT NULL
      AND membership._fld670 IS NOT NULL AND membership._fld670 <> timestamp '0001-01-01'
      AND membership._fld672 > membership._fld671
), discount AS (
    SELECT ar._period::date AS application_date, ar._fld7618rref AS client_id,
           ar._fld7616rref AS club_id, ar._fld7623rref AS promo_id
    FROM _accumrg7615 ar
    LEFT JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7621rref
    WHERE ar._period >= timestamp '2026-06-01'
      AND ar._period < timestamp '2026-07-01'
      AND promo._description IS NOT NULL
      AND (membership._code IS NULL
           OR (membership._fld672 > membership._fld671
               AND membership._fld672 IS NOT NULL
               AND membership._fld671 IS NOT NULL
               AND membership._fld671 <> timestamp '0001-01-01'))
), combined AS (
    SELECT 'promo_gift'::text AS source_kind, * FROM promo_gift
    UNION ALL
    SELECT 'discount', * FROM discount
)
SELECT source_kind,
       count(*)::bigint AS current_m_input_rows,
       min(application_date)::text AS min_application_date,
       max(application_date)::text AS max_application_date,
       count(*) FILTER (WHERE client_id IS NULL)::bigint AS null_client_rows,
       count(*) FILTER (WHERE club_id IS NULL)::bigint AS null_club_rows,
       count(*) FILTER (WHERE promo_id IS NULL)::bigint AS null_promo_rows
FROM combined
GROUP BY source_kind
ORDER BY source_kind;

-- CHECK: PC-V07a DAX category completeness and precedence
-- Expected: each June-2026 current-M input row is assigned exactly one branch
-- by the published SWITCH(TRUE()) order, including «Прочее». The check does
-- not replace the DAX column: it only measures its source predicates.
WITH promo_gift AS (
    SELECT ar._period::date AS application_date, ar._fld7607rref AS client_id,
           ar._fld7612rref AS club_id, kd._fld1457rref AS promo_id,
           NULL::numeric AS discount_amount, NULL::numeric AS price_before_discount,
           NULL::text AS business_direction, NULL::text AS service_name,
           gift_name._description::text AS gift_name, present._fld7559_rrref AS gift_membership_id
    FROM _accumrg7606 ar
    LEFT JOIN _reference135 kd ON kd._idrref = ar._fld7608rref
    LEFT JOIN _reference163 promo ON promo._idrref = kd._fld1457rref
    LEFT JOIN _accumrg7553 present ON present._fld7554rref = ar._fld7610rref
      AND present._fld7555rref = kd._fld1456rref AND present._recordkind = 1
      AND present._period::date >= date '2025-01-01'
    LEFT JOIN _reference187 gift_name ON gift_name._idrref = present._fld7557rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7610rref
    WHERE ar._period >= timestamp '2026-06-01' AND ar._period < timestamp '2026-07-01'
      AND ar._recordkind = 1 AND ar._fld7613 = 1 AND promo._description IS NOT NULL
      AND gift_name._description IS NOT NULL AND membership._fld670 IS NOT NULL
      AND membership._fld670 <> timestamp '0001-01-01' AND membership._fld672 > membership._fld671
), discount AS (
    SELECT ar._period::date, ar._fld7618rref, ar._fld7616rref, ar._fld7623rref,
           ar._fld7626 AS discount_amount,
           COALESCE(v4465._fld4493 * v4465._fld4475, v4924._fld4945 * v4924._fld4930) AS price_before_discount,
           d._description::text AS business_direction, n._description::text AS service_name,
           NULL::text AS gift_name, NULL::bytea AS gift_membership_id
    FROM _accumrg7615 ar
    LEFT JOIN _reference163 promo ON promo._idrref = ar._fld7623rref
    LEFT JOIN _reference59 membership ON membership._idrref = ar._fld7621rref
    LEFT JOIN _reference163 n ON n._idrref = ar._fld7619rref
    LEFT JOIN _reference70 d ON d._idrref = n._fld1733rref
    LEFT JOIN _document332 d332 ON d332._idrref = ar._fld7617_rrref
    LEFT JOIN _document332_vt4465 v4465 ON v4465._document332_idrref = d332._idrref
      AND v4465._fld4467rref = ar._fld7621rref
    LEFT JOIN _document346 d346 ON d346._idrref = ar._fld7617_rrref
    LEFT JOIN _document346_vt4924 v4924 ON v4924._document346_idrref = d346._idrref
      AND v4924._fld4932rref = ar._fld7619rref AND v4924._lineno4925 = ar._lineno
    WHERE ar._period >= timestamp '2026-06-01' AND ar._period < timestamp '2026-07-01'
      AND promo._description IS NOT NULL
      AND (membership._code IS NULL
           OR (membership._fld672 > membership._fld671 AND membership._fld672 IS NOT NULL
               AND membership._fld671 IS NOT NULL AND membership._fld671 <> timestamp '0001-01-01'))
), combined AS (
    SELECT * FROM promo_gift UNION ALL SELECT * FROM discount
), classified AS (
    SELECT *,
      CASE
        WHEN gift_membership_id IS NOT NULL THEN 'gift_friend_membership'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'Членство' THEN 'discount_membership_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'ДСУ' THEN 'discount_fitness_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'Прочие услуги' THEN 'discount_other_service_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'Прочие членство' AND service_name ILIKE '%гостев%' THEN 'discount_guest_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount <> 0 AND business_direction = 'Прочие членство' AND service_name ILIKE '%гостев%' THEN 'discount_guest_partial'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'Прочие членство' AND service_name ILIKE '%замороз%' THEN 'discount_freeze_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount <> 0 AND business_direction = 'Прочие членство' AND service_name ILIKE '%замороз%' THEN 'discount_freeze_partial'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount = 0 AND business_direction = 'Прочие членство' THEN 'discount_membership_service_100'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount <> 0 AND business_direction = 'Членство' THEN 'discount_membership_partial'
        WHEN discount_amount IS NOT NULL AND price_before_discount - discount_amount <> 0 AND business_direction = 'ДСУ' THEN 'discount_fitness_partial'
        WHEN discount_amount IS NULL AND gift_name ILIKE '%членства%' THEN 'gift_membership'
        WHEN discount_amount IS NULL AND gift_name ILIKE '%заморозки%' THEN 'gift_freeze'
        WHEN discount_amount IS NULL AND gift_name ILIKE '%балл%' THEN 'gift_points'
        WHEN discount_amount IS NULL AND gift_name ILIKE '%100%' THEN 'gift_discount_membership_100'
        WHEN discount_amount IS NULL AND gift_name ILIKE '%со-доступ%' THEN 'gift_shared_access'
        WHEN discount_amount IS NULL AND gift_name LIKE '%Скидка%' THEN 'gift_discount_membership'
        ELSE 'other'
      END AS dax_switch_branch
    FROM combined
)
SELECT dax_switch_branch, count(*)::bigint AS source_rows
FROM classified
GROUP BY dax_switch_branch
ORDER BY dax_switch_branch;

COMMIT;
