BEGIN;

CREATE TABLE IF NOT EXISTS mart.visit_client_day (
    visit_date              date    NOT NULL,
    club_id                 text    NOT NULL,
    client_key              text    NOT NULL,
    has_visit               boolean NOT NULL,
    has_member_visit        boolean NOT NULL,
    has_guest_visit         boolean NOT NULL,
    has_vip_visit           boolean NOT NULL,
    has_drc_visit           boolean NOT NULL,
    has_after_school_visit  boolean NOT NULL,
    has_umnyashki_visit     boolean NOT NULL,
    CONSTRAINT visit_client_day_pkey PRIMARY KEY (visit_date, club_id, client_key)
);

ALTER TABLE mart.visit_client_day
    DROP COLUMN IF EXISTS has_coupon,
    DROP COLUMN IF EXISTS has_paid_service;

COMMIT;
