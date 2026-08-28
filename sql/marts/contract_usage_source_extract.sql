-- First-release source extract for mart.contract_usage.
-- $1: inclusive legacy-window start; $2: exclusive legacy-window end.
--
-- This preserves the current `%Renew` Power Query domain and COUNT(*) unit.
-- It deliberately does not add Active/Posted/Marked filters or a polymorphic
-- type predicate. CU-S01 and CU-S03 must pass before physical delivery.
WITH current_m_rows AS MATERIALIZED (
    SELECT a._recordertref,
           a._recorderrref,
           a._lineno,
           a._fld7578_type,
           a._fld7578_rtref,
           c._idrref AS contract_id,
           c._code::text AS contract_code,
           c._fld671::date AS membership_start_date,
           c._fld672::date AS membership_end_date,
           c._fld693::numeric AS membership_term_days
    FROM public._accumrg7575 AS a
    JOIN public._document325 AS d
      ON d._idrref = a._recorderrref
    JOIN public._reference132 AS club
      ON club._idrref = a._fld7577rref
    JOIN public._reference141x1 AS client
      ON client._idrref = d._fld4171rref
    JOIN public._reference59 AS c
      ON c._idrref = a._fld7578_rrref
    WHERE d._fld4164rref = decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
      AND club._description NOT IN ('Детский развивающий центр', 'Управляющая компания')
      AND a._period >= $1::date
      AND a._period < $2::date
      AND client._fld1532rref = decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
      AND c._code IS NOT NULL
), contract_counts AS MATERIALIZED (
    SELECT contract_id,
           contract_code,
           membership_start_date,
           membership_end_date,
           membership_term_days,
           count(*)::bigint AS visit_count
    FROM current_m_rows
    GROUP BY contract_id,
             contract_code,
             membership_start_date,
             membership_end_date,
             membership_term_days
), prepared AS MATERIALIZED (
    SELECT encode(contract_id, 'hex')::text AS contract_id,
           contract_code,
           membership_start_date,
           membership_end_date,
           date_trunc('month', membership_end_date)::date AS contract_end_month,
           membership_term_days,
           (12 * (extract(year FROM membership_end_date)::integer
                  - extract(year FROM membership_start_date)::integer)
             + extract(month FROM membership_end_date)::integer
             - extract(month FROM membership_start_date)::integer
             + 1)::integer AS active_calendar_months,
           visit_count
    FROM contract_counts
)
SELECT contract_id,
       contract_code,
       membership_start_date,
       membership_end_date,
       contract_end_month,
       membership_term_days,
       active_calendar_months,
       visit_count,
       visit_count::numeric / NULLIF(membership_term_days, 0) AS usage_rate,
       visit_count::numeric / NULLIF(active_calendar_months, 0) AS average_monthly_visits
FROM prepared
ORDER BY contract_id;
