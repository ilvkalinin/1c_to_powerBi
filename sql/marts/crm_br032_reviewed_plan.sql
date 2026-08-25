-- REVIEW ONLY — BR-032/BR-033 replacement for the empty superseded CRM objects.
-- Do not execute until the exact plan, source extracts and acceptance controls
-- are approved as one Stage-3 package. All DROP targets were verified empty.

BEGIN;

DROP VIEW mart.v_sales_interaction;
DROP VIEW mart.v_feedback_interaction;
DROP VIEW mart.v_guest_tour;
DROP TABLE mart.crm_interaction_comment;
DROP TABLE mart.crm_interaction_phone;
DROP TABLE mart.crm_interaction;

CREATE TABLE mart.crm_interaction (
    interaction_id              text PRIMARY KEY,
    task_id                     text NOT NULL,
    task_code                   text NOT NULL,
    created_at                  timestamp without time zone NOT NULL,
    started_at                  timestamp without time zone NOT NULL,
    ended_at                    timestamp without time zone NOT NULL,
    planned_at                  timestamp without time zone NOT NULL,
    interaction_name            text,
    event_type_id               text NOT NULL,
    event_type_name             text,
    state_id                    text NOT NULL,
    state_name                  text,
    status_id                   text NOT NULL,
    status_name                 text,
    executor_id                 text NOT NULL,
    executor_name               text,
    cancellation_reason_name    text,
    client_id                   text,
    client_code                 text,
    client_name                 text,
    client_phone                text,
    club_id                     text,
    club_name                   text,
    network_name                text NOT NULL,
    funnel_id                   text,
    funnel_name                 text,
    campaign_id                 text,
    campaign_name               text,
    channel_id                  text,
    tenure_type_name            text,
    client_status_name          text,
    sales_scope                 boolean NOT NULL,
    guest_scope                 boolean NOT NULL,
    report_date                 date,
    tour_kind                   text,
    CHECK (sales_scope OR guest_scope),
    CHECK ((guest_scope AND report_date IS NOT NULL AND tour_kind IS NOT NULL)
           OR NOT guest_scope)
);

CREATE TABLE mart.crm_interaction_phone (
    interaction_id        text NOT NULL REFERENCES mart.crm_interaction(interaction_id),
    phone_reference_id    text NOT NULL,
    phone_event_id        text NOT NULL,
    phone_at              timestamp without time zone NOT NULL,
    answered_flag         boolean NOT NULL,
    PRIMARY KEY (interaction_id, phone_reference_id, phone_event_id)
);

-- This is the final PBIT business grouping. It deliberately has no
-- interaction_id because that key changes the calls-report output grain.
CREATE TABLE mart.feedback_interaction (
    task_code                     text NOT NULL,
    task_description              text NOT NULL,
    interaction_name              text,
    created_at                    timestamp without time zone NOT NULL,
    started_at                    timestamp without time zone NOT NULL,
    ended_at                      timestamp without time zone NOT NULL,
    planned_at                    timestamp without time zone NOT NULL,
    feedback_topic_name           text,
    feedback_theme                text,
    club_name                     text,
    funnel_name                   text,
    department_name               text,
    status_name                   text,
    state_name                    text,
    executor_name                 text,
    position_name                 text,
    client_code                   text,
    client_name                   text,
    client_phone                  text,
    tenure_type_name              text,
    campaign_name                 text,
    campaign_code                 text,
    channel_name                  text,
    regulated_interaction_name    text,
    cancellation_reason_name      text,
    comment_text                  text,
    comment_updated_at            timestamp without time zone,
    first_followup_at             timestamp without time zone,
    answered_flag                 boolean NOT NULL,
    worked_at                     timestamp without time zone,
    worked_flag                   boolean NOT NULL,
    response_minutes              numeric,
    resolution_days               integer
);

CREATE TABLE mart.club_day_metrics (
    event_date          date NOT NULL,
    club_id             text NOT NULL,
    club_name           text NOT NULL,
    visit_event_count   bigint NOT NULL CHECK (visit_event_count >= 0),
    PRIMARY KEY (event_date, club_id)
);

REVOKE ALL ON mart.crm_interaction,
              mart.crm_interaction_phone,
              mart.feedback_interaction,
              mart.club_day_metrics
FROM PUBLIC;

CREATE VIEW mart.v_sales_interaction AS
SELECT c.interaction_id,
       c.task_id,
       coalesce(p.phone_at, c.started_at)::date AS interaction_date,
       c.created_at,
       c.planned_at::date AS planned_date,
       CASE WHEN c.started_at = TIMESTAMP '0001-01-01'
                   OR c.ended_at = TIMESTAMP '0001-01-01'
                   OR c.ended_at < c.started_at THEN NULL
            ELSE extract(epoch FROM c.ended_at - c.started_at)::integer END AS duration_seconds,
       coalesce(p.answered_flag, false) AS answered_flag,
       c.event_type_id, c.event_type_name,
       c.state_id, c.state_name, c.status_id, c.status_name,
       c.executor_id AS manager_id, c.executor_name AS manager_name,
       c.club_id AS operator_club_id, c.network_name,
       c.client_id AS client_key, c.client_code, c.client_name, c.client_phone,
       c.tenure_type_name AS tenure_type, c.client_status_name AS client_status,
       c.funnel_id, c.funnel_name, c.campaign_id, c.campaign_name,
       c.channel_id, c.cancellation_reason_name,
       1::smallint AS interaction_count,
       coalesce(p.phone_reference_id, '') AS phone_reference_id,
       coalesce(p.phone_event_id, '') AS phone_event_id
FROM mart.crm_interaction c
LEFT JOIN mart.crm_interaction_phone p ON p.interaction_id = c.interaction_id
WHERE c.sales_scope;

CREATE VIEW mart.v_feedback_interaction AS
SELECT task_code, task_description, interaction_name, created_at,
       created_at::date AS created_date, started_at, ended_at, planned_at,
       resolution_days, feedback_topic_name, feedback_theme,
       club_name, funnel_name, department_name,
       status_name, state_name, executor_name,
       position_name, client_code, client_name, client_phone,
       tenure_type_name AS tenure_type, campaign_name, campaign_code,
       channel_name, regulated_interaction_name, cancellation_reason_name,
       comment_text, comment_updated_at, first_followup_at, answered_flag,
       worked_at, worked_flag, response_minutes
FROM mart.feedback_interaction;

CREATE VIEW mart.v_guest_tour AS
SELECT c.interaction_id,
       coalesce(p.phone_at, c.started_at)::date AS interaction_date,
       c.report_date, c.task_id, c.client_id, c.club_id, c.client_code,
       c.client_name, c.client_phone, c.state_name AS interaction_state,
       c.status_name AS interaction_status, c.executor_id AS performer_id,
       c.tour_kind, coalesce(p.phone_reference_id, '') AS phone_reference_id,
       coalesce(p.phone_event_id, '') AS phone_event_id
FROM mart.crm_interaction c
LEFT JOIN mart.crm_interaction_phone p ON p.interaction_id = c.interaction_id
WHERE c.guest_scope;

REVOKE ALL ON mart.v_sales_interaction,
              mart.v_feedback_interaction,
              mart.v_guest_tour
FROM PUBLIC;

COMMIT;
