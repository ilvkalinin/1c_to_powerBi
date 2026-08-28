-- First-release source extract for mart.fitness_funnel_client_start.
-- $1: inclusive start-date boundary; $2: exclusive start-date boundary.
--
-- The physical grain is one client key × membership start date.  The current
-- PBI query's Table.Distinct does not choose a contract deterministically;
-- this query therefore keeps every distinct club/tenure combination.  FF-S02
-- must prove that the combination is unique before any target COPY, otherwise
-- the target primary key rejects the load rather than silently choosing one.
WITH eligible_contracts AS MATERIALIZED (
    SELECT r._fld681rref AS client_ref,
           r._fld671::date AS membership_start_date,
           r._fld687rref AS access_club_ref,
           CASE r._fld694rref
               WHEN decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex') THEN 'New'
               WHEN decode('9e369ac955bf602149e17b549b0f1498', 'hex') THEN 'Ex'
               WHEN decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex') THEN 'Renew'
           END::text AS tenure_type
    FROM public._reference59 AS r
    JOIN public._reference141x1 AS client
      ON client._idrref = r._fld681rref
    WHERE r._fld671 >= greatest($1::date, DATE '2024-01-01')
      AND r._fld671 < $2::date
      AND r._fld671 < r._fld672
      AND r._fld671 < CURRENT_DATE
      AND r._description::text NOT LIKE '%ИП%'
      AND r._description::text NOT LIKE '%сотруд%'
      AND client._code IS NOT NULL
      AND client._description IS NOT NULL
      AND r._fld681rref <> decode('00000000000000000000000000000000', 'hex')
      AND r._fld696rref <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
      AND r._fld693 > 6
      AND r._fld694rref = ANY (ARRAY[
          decode('bc06e4b21430ebfb44a67a65c46d41f9', 'hex'),
          decode('9e369ac955bf602149e17b549b0f1498', 'hex'),
          decode('91e4594e35ce15d847c4a3f32e1e18f2', 'hex')
      ])
      AND r._fld670 IS NOT NULL
      AND client._fld1507 IS NOT NULL
      AND extract(epoch FROM (r._fld670 - client._fld1507)) / 86400.0 / 365.0 >= 14
)
SELECT encode(client_ref, 'hex')::text AS client_key,
       membership_start_date,
       encode(access_club_ref, 'hex')::text AS access_club_id,
       tenure_type,
       1::smallint AS client_count
FROM eligible_contracts
GROUP BY client_ref, membership_start_date, access_club_ref, tenure_type
ORDER BY client_key, membership_start_date, access_club_id, tenure_type;
