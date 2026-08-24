BEGIN;

CREATE SCHEMA IF NOT EXISTS mart;

CREATE TABLE mart.newcomer_engagement_milestone (
    contract_id text NOT NULL,
    contract_code text NOT NULL,
    client_id text NOT NULL,
    client_code text NOT NULL,
    access_club_id text NOT NULL,
    access_club_name text NOT NULL,
    membership_start_date date NOT NULL,
    checkpoint_day smallint NOT NULL,
    checkpoint_date date NOT NULL,
    visit_count_to_checkpoint integer NOT NULL,
    visit_bucket text NOT NULL,
    target_visit_count smallint NOT NULL,
    below_target_flag boolean NOT NULL,
    frozen_at_checkpoint_flag boolean NOT NULL,
    eligible_flag boolean NOT NULL,
    age_group text,
    CONSTRAINT newcomer_engagement_milestone_pk PRIMARY KEY (contract_id, client_id, checkpoint_day),
    CONSTRAINT newcomer_engagement_milestone_checkpoint_ck CHECK (checkpoint_day IN (7,14,21,28,30)),
    CONSTRAINT newcomer_engagement_milestone_bucket_ck CHECK (visit_bucket IN ('0','1','2','3','4+')),
    CONSTRAINT newcomer_engagement_milestone_age_ck CHECK (age_group IS NULL OR age_group IN ('Дети','Юниоры','Взрослые')),
    CONSTRAINT newcomer_engagement_milestone_date_ck CHECK (checkpoint_date = membership_start_date + checkpoint_day - 1),
    CONSTRAINT newcomer_engagement_milestone_visits_ck CHECK (visit_count_to_checkpoint >= 0),
    CONSTRAINT newcomer_engagement_milestone_target_ck CHECK (target_visit_count = CASE checkpoint_day WHEN 7 THEN 1 WHEN 14 THEN 2 WHEN 21 THEN 3 WHEN 28 THEN 4 WHEN 30 THEN 4 END),
    CONSTRAINT newcomer_engagement_milestone_below_ck CHECK (below_target_flag = (visit_count_to_checkpoint < target_visit_count))
);

COMMENT ON TABLE mart.newcomer_engagement_milestone IS 'New engagement fact: one contract × client × 7/14/21/28/30-day checkpoint; full atomic BR-003 rebuild.';

COMMIT;
