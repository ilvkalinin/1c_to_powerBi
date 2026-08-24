-- $1/$2 are inclusive/exclusive checkpoint-date batch boundaries.
WITH main_pairs AS MATERIALIZED (
    SELECT r._idrref AS contract_ref, r._code::text AS contract_code,
           r._fld681rref AS client_ref, cl._code::text AS client_code,
           r._fld687rref AS club_ref, club._description::text AS club_name,
           r._fld671::date AS membership_start_date, r._fld670::date AS activation_date,
           cl._fld1507::date AS birth_date
    FROM public._reference59 r
    JOIN public._reference141x1 cl ON cl._idrref=r._fld681rref
    JOIN public._reference132 club ON club._idrref=r._fld687rref
    JOIN public._reference163 service ON service._idrref=r._fld685rref
    WHERE r._fld694rref=decode('bc06e4b21430ebfb44a67a65c46d41f9','hex')
      AND r._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex')
      AND r._fld672::date-r._fld671::date>=30
      AND r._fld681rref<>decode('00000000000000000000000000000000','hex')
      AND service._description::text <> 'Контракт ИП' AND service._description::text NOT LIKE '%Контракт сотрудника%'
      AND r._description::text NOT LIKE '%сотруд%' AND r._description::text NOT LIKE '%ИП%'
), child_raw AS MATERIALIZED (
    SELECT v._fld4915rref AS contract_ref,v._fld4916rref AS client_ref,
           r._fld681rref AS adult_ref,d._idrref AS receipt_ref,
           stock._fld4932rref AS product_ref,
           greatest(r._fld671::date,d._date_time::date) AS candidate_start_date
    FROM public._document346_vt4913 v JOIN public._document346 d ON d._idrref=v._document346_idrref
    JOIN public._reference59 r ON r._idrref=v._fld4915rref JOIN public._reference163 s ON s._idrref=r._fld685rref
    LEFT JOIN public._document346_vt4924 stock ON stock._document346_idrref=d._idrref AND stock._fld4929=v._fld4917
    WHERE d._fld4910rref=decode('859cb45b51f9e02c4fb16764c804af3d','hex')
      AND r._fld672::date>r._fld671::date AND r._fld670<>TIMESTAMP '0001-01-01 00:00:00'
      AND r._fld681rref<>decode('00000000000000000000000000000000','hex')
      AND r._fld696rref=decode('bf4b50662e88eb7b44046ebf4849976f','hex')
      AND s._description::text <> 'Контракт ИП' AND s._description::text NOT LIKE '%Контракт сотрудника%'
), child_sales AS MATERIALIZED (
    SELECT a._fld7647_rrref AS receipt_ref,a._fld7648rref AS adult_ref,a._fld7649rref AS product_ref,
           sum(a._fld7657)::numeric AS net_quantity,sum(a._fld7659)::numeric AS net_amount
    FROM public._accumrg7646 a JOIN (SELECT DISTINCT receipt_ref,adult_ref,product_ref FROM child_raw WHERE product_ref IS NOT NULL) k
      ON k.receipt_ref=a._fld7647_rrref AND k.adult_ref=a._fld7648rref AND k.product_ref=a._fld7649rref
    GROUP BY 1,2,3
), child_pairs AS MATERIALIZED (
    SELECT c.contract_ref,c.client_ref,max(c.candidate_start_date) AS membership_start_date
    FROM child_raw c LEFT JOIN child_sales s USING(receipt_ref,adult_ref,product_ref)
    WHERE s.net_quantity IS NULL OR (s.net_quantity>0 AND s.net_amount>0)
    GROUP BY 1,2
), pairs AS MATERIALIZED (
    SELECT * FROM main_pairs
    UNION ALL
    SELECT r._idrref,r._code::text,c.client_ref,ch._code::text,r._fld687rref,club._description::text,
           c.membership_start_date,r._fld670::date,ch._fld1507::date
    FROM child_pairs c JOIN public._reference59 r ON r._idrref=c.contract_ref JOIN public._reference141x1 ch ON ch._idrref=c.client_ref
    JOIN public._reference132 club ON club._idrref=r._fld687rref
    GROUP BY r._idrref,r._code,c.client_ref,ch._code,r._fld687rref,club._description,c.membership_start_date,r._fld670,ch._fld1507
), checkpoints AS MATERIALIZED (
    SELECT p.*,x.day::smallint AS checkpoint_day,(p.membership_start_date+x.day-1)::date AS checkpoint_date,
           CASE x.day WHEN 7 THEN 1 WHEN 14 THEN 2 WHEN 21 THEN 3 WHEN 28 THEN 4 WHEN 30 THEN 4 END::smallint AS target_visit_count
    FROM pairs p CROSS JOIN (VALUES(7),(14),(21),(28),(30)) x(day)
    WHERE p.membership_start_date+x.day-1 >= $1::date AND p.membership_start_date+x.day-1 < $2::date
), visit_counts AS MATERIALIZED (
    SELECT c.contract_ref,c.client_ref,c.checkpoint_day,count(a._period)::integer AS visits
    FROM checkpoints c LEFT JOIN public._accumrg7575 a ON a._fld7578_rrref=c.contract_ref AND a._fld7576rref=c.client_ref
      AND a._period>=c.membership_start_date AND a._period<c.membership_start_date+c.checkpoint_day*INTERVAL '1 day'
    LEFT JOIN public._reference163 s ON s._idrref=a._fld7579rref
    WHERE a._period IS NULL OR (s._description::text='посещение клуба' AND s._description::text NOT LIKE '%ИП%' AND s._description::text NOT LIKE '%Контракт сотрудника%')
    GROUP BY 1,2,3
), raw_freezes AS MATERIALIZED (
    SELECT f._fld7479rref AS contract_ref,r._code::text AS contract_code,i._fld5862::date AS start_date,i._fld5863::date AS end_date,f._period
    FROM public._accumrg7478 f JOIN public._reference59 r ON r._idrref=f._fld7479rref JOIN public._inforg5859 i ON i._recorderrref=f._recorderrref AND i._fld5860rref=f._fld7479rref
    WHERE f._recordkind=1 AND i._fld5863::date<>i._fld5862::date
), legacy_freezes AS MATERIALIZED (
    SELECT DISTINCT ON (contract_code,start_date) contract_ref,start_date,end_date
    FROM raw_freezes ORDER BY contract_code,start_date,_period DESC
), freeze_flags AS MATERIALIZED (
    SELECT DISTINCT c.contract_ref,c.checkpoint_day
    FROM checkpoints c JOIN legacy_freezes f ON f.contract_ref=c.contract_ref
    WHERE f.start_date<=c.checkpoint_date AND f.end_date>=c.checkpoint_date
), employee_flags AS MATERIALIZED (
    SELECT DISTINCT c.contract_ref,c.client_ref FROM checkpoints c JOIN public._reference225 e ON e._fld2502::text=c.client_code
    JOIN public._inforg6291 h ON h._fld6292rref=e._idrref
    WHERE h._fld6298::date<=c.membership_start_date AND (h._fld6299=TIMESTAMP '0001-01-01 00:00:00' OR h._fld6299::date>=c.membership_start_date)
)
SELECT encode(c.contract_ref,'hex'),c.contract_code,encode(c.client_ref,'hex'),c.client_code,encode(c.club_ref,'hex'),c.club_name,
       c.membership_start_date,c.checkpoint_day,c.checkpoint_date,coalesce(v.visits,0),
       CASE WHEN coalesce(v.visits,0)>=4 THEN '4+' ELSE coalesce(v.visits,0)::text END,c.target_visit_count,
       coalesce(v.visits,0)<c.target_visit_count,(f.contract_ref IS NOT NULL),(f.contract_ref IS NULL AND e.contract_ref IS NULL),
       CASE WHEN c.birth_date IS NULL OR c.birth_date=DATE '0001-01-01' THEN NULL WHEN extract(year FROM age(c.activation_date,c.birth_date))<14 THEN 'Дети' WHEN extract(year FROM age(c.activation_date,c.birth_date))<18 THEN 'Юниоры' ELSE 'Взрослые' END
FROM checkpoints c JOIN visit_counts v USING(contract_ref,client_ref,checkpoint_day) LEFT JOIN freeze_flags f USING(contract_ref,checkpoint_day) LEFT JOIN employee_flags e USING(contract_ref,client_ref);
