-- REVIEWED Stage-3 DDL: mart.administrator_bookings_daily.
-- Apply only through scripts/load_administrator_bookings_daily.py after
-- physical admission. Grain: one accepted document per branch.

BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.administrator_bookings_daily (
    booking_source        text          NOT NULL,
    booking_id            text          NOT NULL,
    booking_created_date  date          NOT NULL,
    lesson_date           date          NOT NULL,
    lesson_end_date       date          NOT NULL,
    club_id               text          NOT NULL,
    booking_author_id     text          NOT NULL,
    author_position_id    text          NOT NULL,
    service_id            text          NOT NULL,
    training_format_id    text,
    booking_count         bigint        NOT NULL,
    revenue_amount        numeric(18,2) NOT NULL,
    CONSTRAINT administrator_bookings_daily_pk PRIMARY KEY (booking_source, booking_id),
    CONSTRAINT administrator_bookings_daily_source_ck CHECK (booking_source IN ('group', 'prebooking')),
    CONSTRAINT administrator_bookings_daily_count_ck CHECK (booking_count = 1),
    CONSTRAINT administrator_bookings_daily_revenue_ck CHECK (revenue_amount > 0),
    CONSTRAINT administrator_bookings_daily_lesson_interval_ck CHECK (lesson_end_date >= lesson_date)
);

COMMENT ON TABLE mart.administrator_bookings_daily IS
    'PBIT-compatible current source selection: one group/prebooking booking document per row; no PII or raw 1C movements.';

REVOKE ALL ON mart.administrator_bookings_daily FROM PUBLIC;

COMMIT;

-- Before COMMIT rollback: ROLLBACK. Post-commit DROP is deliberately not automated.
