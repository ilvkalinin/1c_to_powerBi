-- REVIEW ONLY — do not execute without explicit user approval.
-- Creates the compact Gymmy daily aggregate only. It does not read 1C,
-- load the external administrator journal or change existing marts.
-- Rollback before COMMIT: ROLLBACK;
-- Rollback after COMMIT: DROP TABLE mart.administrator_card_gymmy_daily;

BEGIN;

CREATE TABLE mart.administrator_card_gymmy_daily (
    event_date  date   NOT NULL,
    club_id     text   NOT NULL,
    direction   text   NOT NULL,
    usage_count bigint NOT NULL,
    CONSTRAINT administrator_card_gymmy_daily_pk
        PRIMARY KEY (event_date, club_id, direction),
    CONSTRAINT administrator_card_gymmy_daily_direction_ck
        CHECK (direction IN ('Вход', 'Выход')),
    CONSTRAINT administrator_card_gymmy_daily_usage_count_ck
        CHECK (usage_count > 0)
);

COMMIT;
