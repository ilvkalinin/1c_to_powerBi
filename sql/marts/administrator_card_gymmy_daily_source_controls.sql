-- Independent source controls for mart.administrator_card_gymmy_daily.
-- The runner binds $1/$2 to the same BR-003 horizon and executes this query
-- before copying the detailed aggregate. It deliberately does not derive the
-- club mapping, so a missing/duplicated card-to-club join cannot self-confirm.

WITH requested_cards(card_code) AS (
    VALUES ('И00134834'), ('001365180'), ('001365168'), ('001365170'),
           ('001365171'), ('001365172'), ('001365174'), ('001365175'),
           ('001365177'), ('001365178'), ('001365167'), ('001365166')
)
SELECT CASE encode(g._fld5840rref, 'hex')
           WHEN 'b414fbc9cd1b4ef1401cbe6978d40f7e' THEN 'Вход'
           WHEN 'b2fad15d56e30d954d09c05642fff512' THEN 'Выход'
       END AS direction,
       count(*)::bigint AS source_events
FROM public._inforg5836 g
JOIN public._reference141x1 r ON r._idrref = g._fld5838rref
JOIN requested_cards q ON q.card_code = r._code::text
WHERE g._period >= $1::date
  AND g._period < $2::date
  AND g._fld5840rref IN (
      decode('b2fad15d56e30d954d09c05642fff512', 'hex'),
      decode('b414fbc9cd1b4ef1401cbe6978d40f7e', 'hex')
  )
  AND g._fld5841 IS NOT FALSE
GROUP BY 1
ORDER BY 1;
