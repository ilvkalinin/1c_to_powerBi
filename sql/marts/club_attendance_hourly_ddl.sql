-- REVIEWED Stage-3 DDL: mart.club_attendance_hourly.
-- Apply only through scripts/load_club_attendance_hourly.py.
-- Grain: visit_date × club_id × start_hour × end_hour/NULL × sex_code/NULL × age_years/NULL.

BEGIN;

CREATE TABLE mart.club_attendance_hourly (
    visit_date           date           NOT NULL,
    club_id              text           NOT NULL,
    start_hour           smallint       NOT NULL,
    end_hour             smallint,
    sex_code             text,
    age_years            smallint,
    visit_count          bigint         NOT NULL,
    club_minutes_total   numeric        NOT NULL,
    CONSTRAINT club_attendance_hourly_grain_uq
        UNIQUE NULLS NOT DISTINCT (visit_date, club_id, start_hour, end_hour, sex_code, age_years),
    CONSTRAINT club_attendance_hourly_start_hour_ck CHECK (start_hour BETWEEN 0 AND 23),
    CONSTRAINT club_attendance_hourly_end_hour_ck CHECK (end_hour IS NULL OR end_hour BETWEEN 0 AND 23),
    CONSTRAINT club_attendance_hourly_visit_count_ck CHECK (visit_count > 0)
);

COMMENT ON TABLE mart.club_attendance_hourly IS
    'Почасовая агрегированная посещаемость: дата × фактический клуб × часы × пол × возраст; BR-019 сохраняет sentinel birth date как NULL возраста.';

REVOKE ALL ON mart.club_attendance_hourly FROM PUBLIC;

COMMIT;

-- Before COMMIT rollback: ROLLBACK. After COMMIT an object DROP is deliberately
-- not automated and requires a separate explicit decision.
