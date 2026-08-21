-- Fail-closed read-only guard for the created_at transport prefilter.
-- Bind the inclusive and exclusive horizon as the first two parameters.
-- It reproduces CORE-001 membership and its min effective transport anchor,
-- then measures how far created_at lies outside each anchor quarter.
WITH params AS (
    SELECT $1::timestamp without time zone AS source_start,
           $2::timestamp without time zone AS source_end
), sales_candidates AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           min(CASE WHEN interaction_phone._fld7150 IS NULL
                    THEN i._fld820 ELSE interaction_phone._fld7150 END) AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference225 manager ON manager._idrref = i._fld824rref
    LEFT JOIN public._inforg7146 interaction_phone
      ON interaction_phone._fld7151rref = i._idrref
    CROSS JOIN params p
    WHERE t._fld1191rref IN (
              decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex'),
              decode('99b0e03a7af94bc911ef0167b7844d74', 'hex'),
              decode('99b0e03a7af94bc911ef016b69a7124a', 'hex')
          )
      AND NOT (t._fld1191rref = decode('99b0e03a7af94bc911ef0167b7844d74', 'hex')
               AND t._fld1197rref IN (
                   decode('99e886b88886661011f0ae4e3da6296e', 'hex'),
                   decode('99cc8098b8acd0e411efe53f048393c3', 'hex')))
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) >= p.source_start
      AND (CASE WHEN interaction_phone._fld7150 IS NULL THEN i._fld820
                ELSE interaction_phone._fld7150 END) < p.source_end
      AND EXISTS (
          SELECT 1
          FROM public._inforg6291 h
          JOIN public._reference225 employment_employee
            ON employment_employee._idrref = h._fld6292rref
          JOIN public._reference101 employment_position
            ON employment_position._idrref = h._fld6296rref
          WHERE employment_employee._description = manager._description
            AND employment_position._description IN (
                'Менеджер ОП', 'Старший менеджер ОП', 'Ведущий менеджер'
            )
            AND h._fld6298 <= i._fld823
            AND coalesce(nullif(h._fld6299, TIMESTAMP '0001-01-01'),
                         TIMESTAMP '2099-12-31') >= i._fld823
      )
    GROUP BY i._idrref
), guest AS MATERIALIZED (
    SELECT i._idrref AS interaction_id,
           (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                 THEN i._fld822::date ELSE i._fld820::date END)::timestamp AS anchor_at
    FROM public._reference106 t
    JOIN public._reference67 i ON i._owneridrref = t._idrref
    LEFT JOIN public._reference224 state ON state._idrref = i._fld829rref
    CROSS JOIN params p
    WHERE i._fld831rref = decode('b538e5326d9fc9a943c11fd0e7a0e678', 'hex')
      AND t._fld1191rref = decode('99a9ebb169a4e2a611eecbf18a73ffa6', 'hex')
      AND ((state._description = 'Закрыто'
            AND i._fld830rref = decode('b78f16cfde0c1e1f4f7c0ae8d942393d', 'hex'))
        OR (state._description = 'Запланировано'
            AND i._fld830rref = decode('83b62b0bd3908a65448b72ca1ec17e94', 'hex')))
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                THEN i._fld822::date ELSE i._fld820::date END)
          >= p.source_start::date
      AND (CASE WHEN i._fld820 = TIMESTAMP '0001-01-01'
                THEN i._fld822::date ELSE i._fld820::date END)
          < p.source_end::date
), scoped AS MATERIALIZED (
    SELECT interaction_id, true AS sales_scope, false AS guest_scope, anchor_at
    FROM sales_candidates
    UNION ALL
    SELECT interaction_id, false, true, anchor_at
    FROM guest
), core_membership AS MATERIALIZED (
    SELECT interaction_id,
           bool_or(sales_scope) AS sales_scope,
           bool_or(guest_scope) AS guest_scope,
           min(anchor_at) AS anchor_at
    FROM scoped
    GROUP BY interaction_id
), measured AS (
    SELECT date_trunc('quarter', membership.anchor_at)::date AS anchor_quarter,
           membership.sales_scope,
           membership.guest_scope,
           membership.anchor_at,
           i._fld823 AS created_at
    FROM core_membership membership
    JOIN public._reference67 i ON i._idrref = membership.interaction_id
)
SELECT anchor_quarter,
       count(*)::bigint AS interaction_count,
       min(created_at) AS earliest_created_at,
       max(created_at) AS latest_created_at,
       min(anchor_at) AS earliest_anchor_at,
       max(anchor_at) AS latest_anchor_at,
       max(anchor_quarter::timestamp - created_at)
           FILTER (WHERE created_at < anchor_quarter::timestamp) AS required_lookback,
       max(created_at - (anchor_quarter::timestamp + INTERVAL '3 months'))
           FILTER (WHERE created_at >= anchor_quarter::timestamp + INTERVAL '3 months')
           AS required_lookahead,
       count(*) FILTER (
           WHERE created_at < anchor_quarter::timestamp - INTERVAL '1 month'
              OR created_at >= anchor_quarter::timestamp + INTERVAL '4 months'
       )::bigint AS outside_one_month_window_count,
       count(*) FILTER (
           WHERE created_at < anchor_quarter::timestamp
              OR created_at >= anchor_quarter::timestamp + INTERVAL '3 months'
       )::bigint AS outside_exact_quarter_count,
       count(*) FILTER (WHERE created_at IS NULL)::bigint AS null_created_at_count,
       count(*) FILTER (WHERE sales_scope)::bigint AS sales_interaction_count,
       count(*) FILTER (WHERE guest_scope)::bigint AS guest_interaction_count
FROM measured
GROUP BY anchor_quarter
ORDER BY anchor_quarter;
