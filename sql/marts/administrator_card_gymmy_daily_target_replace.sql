-- Target replacement for mart.administrator_card_gymmy_daily.
-- Run only from scripts/load_administrator_card_gymmy_daily.py with --apply,
-- after the source controls succeeded in the same source snapshot.
-- The runner creates and fills _administrator_card_gymmy_daily_stage first.

CREATE TEMP TABLE _administrator_card_gymmy_daily_stage (
    event_date  date   NOT NULL,
    club_id     text   NOT NULL,
    direction   text   NOT NULL,
    usage_count bigint NOT NULL,
    PRIMARY KEY (event_date, club_id, direction),
    CHECK (direction IN ('Вход', 'Выход')),
    CHECK (usage_count > 0)
) ON COMMIT DROP;

-- The runner refuses any stage row outside the calculated BR-003 horizon,
-- then removes expired rows before replacing the current horizon in the same
-- target transaction.
DELETE FROM mart.administrator_card_gymmy_daily
WHERE event_date < $1::date
   OR event_date >= $2::date;

DELETE FROM mart.administrator_card_gymmy_daily
WHERE event_date >= $1::date
  AND event_date < $2::date;

INSERT INTO mart.administrator_card_gymmy_daily (
    event_date, club_id, direction, usage_count
)
SELECT event_date, club_id, direction, usage_count
FROM _administrator_card_gymmy_daily_stage;
