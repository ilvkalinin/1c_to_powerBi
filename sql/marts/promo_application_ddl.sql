-- REVIEWED DDL — execute only through the approved mart.promo_application delivery runner.
CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.promo_application (
    report_row_id bigint PRIMARY KEY,
    source_kind text NOT NULL CHECK (source_kind IN ('promo_gift', 'discount')),
    application_date date NOT NULL,
    client_key text NOT NULL,
    club_name text,
    membership_code text,
    promo_name text NOT NULL,
    serial_name text NOT NULL,
    discount_name text,
    discount_id text,
    discount_method text NOT NULL,
    service_name text,
    business_direction text,
    gift_name text,
    gift_recipient_membership_code text,
    client_stage text NOT NULL,
    discount_amount numeric,
    price_before_discount numeric,
    bought_membership_45d_flag boolean NOT NULL,
    bought_dpfu_45d_flag boolean NOT NULL,
    friend_bought_membership_45d_flag boolean,
    CONSTRAINT promo_application_kind_shape CHECK (
      (source_kind = 'promo_gift') = (gift_name IS NOT NULL)
    )
);

CREATE INDEX promo_application_application_date_ix
    ON mart.promo_application (application_date);
CREATE INDEX promo_application_promo_name_ix
    ON mart.promo_application (promo_name);
CREATE INDEX promo_application_club_name_ix
    ON mart.promo_application (club_name);
REVOKE ALL ON mart.promo_application FROM PUBLIC;
