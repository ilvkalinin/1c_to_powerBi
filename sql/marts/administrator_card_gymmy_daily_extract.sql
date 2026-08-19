-- Source extract for mart.administrator_card_gymmy_daily.
-- REVIEW ONLY. The runner binds $1 = BR-003 horizon_start and
-- $2 = horizon_end, opens one REPEATABLE READ, READ ONLY source snapshot and
-- streams only this daily aggregate to VM-2. The external administrator log
-- remains outside PostgreSQL.

WITH requested_cards(card_code) AS (
    VALUES ('И00134834'), ('001365180'), ('001365168'), ('001365170'),
           ('001365171'), ('001365172'), ('001365174'), ('001365175'),
           ('001365177'), ('001365178'), ('001365167'), ('001365166')
), card_club AS (
    SELECT r._idrref AS card_client_id,
           encode(c._idrref, 'hex') AS club_id
    FROM requested_cards q
    JOIN public._reference141x1 r ON r._code::text = q.card_code
    JOIN public._reference132 c
      ON c._description::text = nullif(
          regexp_replace(trim(r._description::text), '^.*\\s+', ''), ''
      )
), selected_events AS (
    SELECT g._period::date AS event_date,
           cc.club_id,
           CASE encode(g._fld5840rref, 'hex')
               WHEN 'b414fbc9cd1b4ef1401cbe6978d40f7e' THEN 'Вход'
               WHEN 'b2fad15d56e30d954d09c05642fff512' THEN 'Выход'
           END AS direction
    FROM public._inforg5836 g
    JOIN card_club cc ON cc.card_client_id = g._fld5838rref
    WHERE g._period >= $1::date
      AND g._period < $2::date
      AND g._fld5840rref IN (
          decode('b2fad15d56e30d954d09c05642fff512', 'hex'),
          decode('b414fbc9cd1b4ef1401cbe6978d40f7e', 'hex')
      )
      AND g._fld5841 IS NOT FALSE
)
SELECT event_date,
       club_id,
       direction,
       count(*)::bigint AS usage_count
FROM selected_events
GROUP BY event_date, club_id, direction
ORDER BY event_date, club_id, direction;
