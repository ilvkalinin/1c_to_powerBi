-- Source extract for mart.ip_revenue_daily.
-- REVIEW ONLY. The runner binds $1 = BR-003 horizon_start and
-- $2 = BR-003 horizon_end, opens one REPEATABLE READ, READ ONLY source
-- snapshot, then streams these explicit target columns to a VM-2 temp stage.
-- The legacy LEFT JOIN rule is preserved: an unmatched movement club is NULL;
-- the contract club is never substituted.

WITH qualified AS (
    SELECT r._period::date AS revenue_date,
           CASE WHEN club._idrref IS NULL
                THEN NULL
                ELSE encode(r._fld7372rref, 'hex')
           END AS club_id,
           encode(contract._fld685rref, 'hex') AS service_id,
           CAST(service._description AS varchar(1000)) AS service_name,
           r._fld7377::numeric(18, 2) AS revenue_amount
    FROM public._accumrg7370 r
    JOIN public._reference59 contract ON contract._idrref = r._fld7371rref
    JOIN public._reference163 service ON service._idrref = contract._fld685rref
    LEFT JOIN public._reference132 club ON club._idrref = r._fld7372rref
    WHERE r._period >= $1::date
      AND r._period < $2::date
      AND r._recordkind = 0
      AND CAST(service._description AS varchar(1000)) ILIKE '%ИП%'
)
SELECT revenue_date, club_id, service_id,
       max(service_name) AS service_name,
       sum(revenue_amount)::numeric(18, 2) AS revenue_amount
FROM qualified
GROUP BY revenue_date, club_id, service_id;
