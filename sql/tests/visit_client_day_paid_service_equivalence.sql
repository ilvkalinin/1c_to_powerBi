-- DQ-VC-001 | Expected: old_only_rows = 0 and new_only_rows = 0.
-- Independent control: the old_paid CTE is the confirmed current-M LATERAL
-- card lookup; new_paid is the set-based implementation in the mart extract.
-- $1 = inclusive date, $2 = exclusive date. Read-only source test.
WITH constants AS (
  SELECT decode('bf4b50662e88eb7b44046ebf4849976f','hex') AS club_card_type,
         decode('9f007d77d46892dc47058346701d3bb6','hex') AS service_operation
), training_dates AS (
  SELECT _idrref AS training_ref, _fld3218::date AS training_date
  FROM public._document279
  WHERE _posted AND _fld3218 >= $1::date AND _fld3218 < $2::date
  UNION ALL
  SELECT _idrref, _fld4306::date
  FROM public._document329
  WHERE _posted AND _fld4306 >= $1::date AND _fld4306 < $2::date
), paid_seed AS (
  SELECT td.training_date, a._fld7577rref AS club_ref, a._fld7576rref AS client_ref
  FROM public._accumrg7575 a
  JOIN training_dates td ON td.training_ref=a._fld7581_rrref
  JOIN public._reference141x1 cl ON cl._idrref=a._fld7576rref
  JOIN public._reference163 svc ON svc._idrref=a._fld7579rref
  JOIN public._reference70 direction ON direction._idrref=svc._fld1733rref
  LEFT JOIN public._reference59 contract ON contract._idrref=a._fld7578_rrref
  CROSS JOIN constants k
  WHERE svc._fld1795rref=k.service_operation
    AND coalesce(direction._fld843rref,decode('00','hex')) NOT IN
        (decode('9e10e872e49a551b4968a66b95c28905','hex'),decode('ac626c95655c992a471b27ca8f8812cd','hex'))
    AND coalesce(svc._description::text,'')<>'посещение клуба'
    AND direction._description::text IN ('Игровой зал','Восстановительный фитнес','Боевые искусства','Детский клуб','Водные программы','Групповые программы','Тренажёрный зал','Тренажерный зал')
    AND contract._fld696rref IS DISTINCT FROM k.club_card_type
    AND cl._fld1532rref IS DISTINCT FROM decode('8e3e8dea66a1d5454387ceb554c10615','hex')
), old_paid AS (
  SELECT p.training_date AS visit_date, p.club_ref, p.client_ref
  FROM paid_seed p
  JOIN public._reference132 actual ON actual._idrref=p.club_ref
  CROSS JOIN constants k
  LEFT JOIN LATERAL (
    SELECT max(home._description::text) AS home_club
    FROM public._reference59 card
    JOIN public._reference132 home ON home._idrref=card._fld687rref
    WHERE card._fld681rref=p.client_ref AND card._fld696rref=k.club_card_type
      AND card._fld671<=p.training_date AND card._fld672>=p.training_date
  ) hc ON true
  WHERE (actual._description::text IN ('Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера','Парковая','Родионова','Советская','Спорт','Старт','Южное')
         AND hc.home_club IS NOT NULL AND hc.home_club NOT IN ('Детский развивающий центр','Пушкинский','Пушкинский VIP'))
     OR (actual._description::text='Пушкинский' AND hc.home_club='Пушкинский')
), new_card_homes AS (
  SELECT p.training_date, p.club_ref, p.client_ref,
         max(home._description::text) AS home_club
  FROM paid_seed p
  CROSS JOIN constants k
  LEFT JOIN public._reference59 card
    ON card._fld681rref=p.client_ref AND card._fld696rref=k.club_card_type
   AND card._fld671<=p.training_date AND card._fld672>=p.training_date
  LEFT JOIN public._reference132 home ON home._idrref=card._fld687rref
  GROUP BY p.training_date, p.club_ref, p.client_ref
), new_paid AS (
  SELECT p.training_date AS visit_date, p.club_ref, p.client_ref
  FROM new_card_homes p
  JOIN public._reference132 actual ON actual._idrref=p.club_ref
  WHERE (actual._description::text IN ('Автозаводский','Бурнаковский','Деловая','Корабли','Кстово','Мещера','Парковая','Родионова','Советская','Спорт','Старт','Южное')
         AND p.home_club IS NOT NULL AND p.home_club NOT IN ('Детский развивающий центр','Пушкинский','Пушкинский VIP'))
     OR (actual._description::text='Пушкинский' AND p.home_club='Пушкинский')
), old_set AS (
  SELECT DISTINCT visit_date, club_ref, client_ref FROM old_paid
), new_set AS (
  SELECT DISTINCT visit_date, club_ref, client_ref FROM new_paid
), old_only AS (
  SELECT * FROM old_set EXCEPT SELECT * FROM new_set
), new_only AS (
  SELECT * FROM new_set EXCEPT SELECT * FROM old_set
)
SELECT (SELECT count(*) FROM old_set)::bigint AS old_rows,
       (SELECT count(*) FROM new_set)::bigint AS new_rows,
       (SELECT count(*) FROM old_only)::bigint AS old_only_rows,
       (SELECT count(*) FROM new_only)::bigint AS new_only_rows;
