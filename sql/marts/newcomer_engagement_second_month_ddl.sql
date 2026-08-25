BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.newcomer_engagement_second_month (
    source_row_id text NOT NULL,
    contract_id text NOT NULL,
    contract_code text NOT NULL,
    client_id text NOT NULL,
    client_code text NOT NULL,
    client_name text NOT NULL,
    access_club_id text,
    access_club_name text,
    membership_start_date date NOT NULL,
    month_of_engagement date NOT NULL,
    age_category text,
    tenure text,
    second_month_visit_count bigint NOT NULL,
    last_visit_date date,
    visit_bucket text NOT NULL,
    intro_training_status text NOT NULL,
    CONSTRAINT newcomer_engagement_second_month_pk PRIMARY KEY (source_row_id),
    CONSTRAINT newcomer_engagement_second_month_month_ck
        CHECK (month_of_engagement = date_trunc('month', membership_start_date + INTERVAL '1 month')::date),
    CONSTRAINT newcomer_engagement_second_month_visits_ck
        CHECK (second_month_visit_count >= 0),
    CONSTRAINT newcomer_engagement_second_month_bucket_ck
        CHECK (visit_bucket IN ('0', '1', '2', '3', '4+')),
    CONSTRAINT newcomer_engagement_second_month_bucket_count_ck
        CHECK (visit_bucket = CASE WHEN second_month_visit_count >= 4 THEN '4+' ELSE second_month_visit_count::text END),
    CONSTRAINT newcomer_engagement_second_month_last_visit_ck
        CHECK (last_visit_date IS NULL OR (last_visit_date >= month_of_engagement AND last_visit_date < month_of_engagement + INTERVAL '1 month')),
    CONSTRAINT newcomer_engagement_second_month_spt_ck
        CHECK (intro_training_status IN ('Прошел СПТ', 'Не прошел'))
);

COMMENT ON TABLE mart.newcomer_engagement_second_month IS
    'Current-Power-BI compatible second-month newcomer engagement; full atomic BR-003 rebuild, with source-row identity preserving legacy child RANK ties.';

COMMIT;
