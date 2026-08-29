-- PII-free RM-S2-02 examples via the accepted client-indexed LATERAL path.
WITH cohort AS MATERIALIZED (
    SELECT a._idrref AS contract_id,a._fld681rref AS client_id,a._fld671 AS membership_start,a._fld672::date AS membership_end_date
    FROM public._reference59 a JOIN public._reference141x1 cl ON cl._idrref=a._fld681rref
    LEFT JOIN public._document332 d332 ON d332._fld4422rref=a._idrref AND d332._posted LEFT JOIN public._document287 d287 ON d287._fld3379rref=a._idrref
    WHERE a._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex') AND a._fld699rref NOT IN (decode('96976725cebf51f7461429d74d3f6cbe','hex'),decode('9bd3ea4748457ee94b2011de6d9687d7','hex'))
      AND a._fld672>DATE '2024-01-01' AND a._fld672<=date_trunc('month',current_date)+interval '6 month'-interval '1 day' AND a._fld693>=30
      AND a._description NOT LIKE '%ИП%' AND a._description NOT LIKE '%сотрудн%' AND extract(day FROM (a._fld672-a._fld671))>=30 AND cl._code IS NOT NULL
      AND a._fld690=TIMESTAMP '0001-01-01 00:00:00' AND d332._idrref IS NULL AND d287._idrref IS NULL
), first_start AS MATERIALIZED (
    SELECT c.*,candidate.next_start_date
    FROM cohort c LEFT JOIN LATERAL (
        SELECT n._fld671::date AS next_start_date FROM public._reference59 n
        WHERE n._fld681rref=c.client_id AND n._fld671>c.membership_start AND n._fld672>c.membership_end_date AND n._fld672>n._fld671
          AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex') AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
          AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex')))
          AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%' ORDER BY n._fld671 LIMIT 1
    ) candidate ON TRUE
), tied_groups AS (
    SELECT f.contract_id,f.client_id,f.membership_start,f.membership_end_date,f.next_start_date,row_number() OVER (ORDER BY encode(f.contract_id,'hex'))::integer AS example_no
    FROM first_start f CROSS JOIN LATERAL (
        SELECT count(*)::integer AS tie_size FROM public._reference59 n
        WHERE f.next_start_date IS NOT NULL AND n._fld681rref=f.client_id AND n._fld671::date=f.next_start_date
          AND n._fld671>f.membership_start AND n._fld672>f.membership_end_date AND n._fld672>n._fld671 AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
          AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex') AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex')))
          AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
    ) count_group WHERE count_group.tie_size>1 ORDER BY encode(f.contract_id,'hex') LIMIT 3
), examples AS (
    SELECT g.example_no,row_number() OVER (PARTITION BY g.contract_id ORDER BY encode(n._idrref,'hex'))::integer AS candidate_no,
           count(*) OVER (PARTITION BY g.contract_id)::integer AS tie_size,g.membership_end_date AS source_end_date,n._fld671::date AS next_start_date,
           n._fld670::date AS activation_date,n._fld672::date AS next_end_date,n._fld693::numeric AS term_days,
           CASE WHEN n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex') THEN 'Бесплатный' ELSE 'Платный' END AS payment_category,n._marked AS marked
    FROM tied_groups g JOIN public._reference59 n ON n._fld681rref=g.client_id AND n._fld671::date=g.next_start_date
    WHERE n._fld671>g.membership_start AND n._fld672>g.membership_end_date AND n._fld672>n._fld671 AND n._fld696rref<>decode('9b656ee141a764e44de79e83cd30c1b2','hex')
      AND n._fld699rref<>decode('9bd3ea4748457ee94b2011de6d9687d7','hex') AND ((n._fld693>=30 AND n._fld699rref<>decode('96976725cebf51f7461429d74d3f6cbe','hex')) OR (n._fld693>=1 AND n._fld699rref=decode('96976725cebf51f7461429d74d3f6cbe','hex')))
      AND n._description NOT LIKE '%ИП%' AND n._description NOT LIKE '%сотрудн%'
)
SELECT * FROM examples ORDER BY example_no,candidate_no;
