-- Global read-only review: «Карта администратора», Gymmy part only.
-- Executed against gymdb as gymdb_readonly on 2026-08-17. The external administrator log is
-- outside scope: Excel and its Power Query are neither read nor changed.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';
SET LOCAL enable_seqscan = off;

-- AC-V01—V04. Bounded July-2026 control. Expected: candidate physical event
-- key is unique (also enforced by source unique index); the 12
-- confirmed cards and two confirmed directions are present; success is only
-- measured before the user-approved exclusion of false. One card must not
-- resolve to several text-derived clubs. This observes the current name rule,
-- not a new canonical card-to-club mapping.
WITH selected_events AS MATERIALIZED (
  SELECT g._period::date AS event_date, g._period, g._fld5837rref AS terminal_id,
         g._fld5838rref AS card_client_id, g._fld5839 AS event_id,
         g._fld5840rref AS direction_id, g._fld5841 AS success_value,
         r._description::text AS card_description
  FROM public._inforg5836 g
  JOIN public._reference141x1 r ON r._idrref = g._fld5838rref
  WHERE g._period >= DATE '2026-07-01' AND g._period < DATE '2026-08-01'
    AND r._code IN ('И00134834', '001365180', '001365168', '001365170',
                    '001365171', '001365172', '001365174', '001365175',
                    '001365177', '001365178', '001365167', '001365166')
    AND g._fld5840rref IN (
      decode('b2fad15d56e30d954d09c05642fff512', 'hex'),
      decode('b414fbc9cd1b4ef1401cbe6978d40f7e', 'hex')
    )
), card_clubs AS (
  SELECT card_client_id,
         count(DISTINCT nullif(regexp_replace(trim(card_description), '^.*\\s+', ''), ''))
           AS derived_clubs_per_card
  FROM selected_events
  GROUP BY 1
), daily AS (
  SELECT event_date, direction_id, count(*) AS usage_count
  FROM selected_events
  WHERE success_value IS NOT FALSE
  GROUP BY 1, 2
)
SELECT (SELECT count(*) FROM selected_events) AS selected_events,
       (SELECT count(DISTINCT (event_date, terminal_id, card_client_id, event_id)) FROM selected_events) AS technical_event_keys,
       (SELECT count(*) FROM selected_events) - (SELECT count(DISTINCT (event_date, terminal_id, card_client_id, event_id)) FROM selected_events) AS duplicate_event_keys,
       (SELECT count(DISTINCT card_client_id) FROM selected_events) AS present_cards,
       (SELECT count(DISTINCT direction_id) FROM selected_events) AS present_directions,
       (SELECT count(*) FROM selected_events WHERE success_value IS FALSE) AS false_success_events,
       (SELECT count(*) FROM selected_events WHERE success_value IS NULL) AS null_success_events,
       (SELECT count(*) FROM card_clubs WHERE derived_clubs_per_card <> 1) AS cards_with_nonunique_derived_club,
       (SELECT coalesce(sum(usage_count), 0) FROM daily) AS successful_events_after_current_rule;

-- AC-V05. Expected: each of the 12 current card codes resolves through the
-- existing last-word label to exactly one physical club. This validates the
-- current mapping to a canonical source ID; it does not change the card list
-- or rewrite the current Power Query rule.
WITH requested_cards(card_code) AS (
  VALUES ('И00134834'), ('001365180'), ('001365168'), ('001365170'),
         ('001365171'), ('001365172'), ('001365174'), ('001365175'),
         ('001365177'), ('001365178'), ('001365167'), ('001365166')
), card_labels AS (
  SELECT q.card_code,
         nullif(regexp_replace(trim(r._description::text), '^.*\\s+', ''), '')
           AS derived_club_label
  FROM requested_cards q
  LEFT JOIN public._reference141x1 r ON r._code::text = q.card_code
), label_matches AS (
  SELECT l.card_code, count(c._idrref) AS exact_club_matches
  FROM card_labels l
  LEFT JOIN public._reference132 c ON c._description::text = l.derived_club_label
  GROUP BY l.card_code
)
SELECT count(*) AS requested_cards,
       count(*) FILTER (WHERE exact_club_matches = 1) AS cards_with_one_exact_club,
       count(*) FILTER (WHERE exact_club_matches = 0) AS cards_without_exact_club,
       count(*) FILTER (WHERE exact_club_matches > 1) AS cards_with_multiple_exact_clubs
FROM label_matches;

ROLLBACK;
