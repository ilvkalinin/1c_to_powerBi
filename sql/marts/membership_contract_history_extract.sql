-- Compact predecessor input for the membership marts.
-- The source remains read-only.  The target uses this set only inside the
-- refresh transaction to reproduce the current DAX predecessor rule.
WITH scoped_clients AS (
    SELECT DISTINCT c._fld681rref AS client_ref
    FROM public._accumrg7370 a
    JOIN public._reference59 c ON c._idrref=a._fld7371rref
    WHERE a._period >= $1::date AND a._period < $2::date
      AND a._recordertref=ANY(ARRAY[
        decode('0000013d','hex'),decode('0000013c','hex'),decode('0000011d','hex'),
        decode('00000130','hex'),decode('0000015a','hex'),decode('00000147','hex'),
        decode('0000013b','hex'),decode('0000014b','hex'),decode('00000131','hex'),
        decode('0000014d','hex'),decode('00000153','hex'),decode('00000154','hex'),
        decode('00000128','hex')
      ])
      AND c._fld681rref <> decode(repeat('00',16),'hex')
)
SELECT encode(c._idrref,'hex') AS contract_id,
       encode(c._fld681rref,'hex') AS client_key,
       c._fld670::date AS activation_date,
       c._fld671::date AS start_date,
       c._fld672::date AS end_date,
       CASE WHEN c._fld699rref=decode('9bd3ea4748457ee94b2011de6d9687d7','hex')
            THEN 'Рекарринг' ELSE 'Предоплата' END AS payment_type
FROM public._reference59 c
JOIN scoped_clients s ON s.client_ref=c._fld681rref;
