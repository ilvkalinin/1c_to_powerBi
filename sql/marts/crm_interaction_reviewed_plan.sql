-- REVIEW ONLY — no statement in this file has been executed on VM-2.
-- Approved technical plan for the future CRM implementation package. The
-- package must bind an approved BI role before adding GRANT statements.
-- Source IDs are explicitly encode(..., 'hex') text values.

BEGIN;

CREATE TABLE mart.crm_interaction (
    interaction_id              text PRIMARY KEY,
    task_id                     text NOT NULL,
    task_code                   text NOT NULL,
    task_description            text NOT NULL,
    created_at                  timestamp without time zone NOT NULL,
    started_at                  timestamp without time zone NOT NULL,
    ended_at                    timestamp without time zone NOT NULL,
    planned_at                  timestamp without time zone NOT NULL,
    interaction_name            text,
    event_type_id               text NOT NULL,
    state_id                    text NOT NULL,
    state_name                  text,
    status_id                   text NOT NULL,
    status_name                 text,
    executor_id                 text NOT NULL,
    executor_name               text,
    cancellation_reason_id      text NOT NULL,
    cancellation_reason_name    text,
    client_id                   text NOT NULL,
    client_code                 text,
    client_name                 text,
    client_phone                text,
    club_id                     text NOT NULL,
    club_name                   text,
    funnel_id                   text NOT NULL,
    funnel_name                 text,
    campaign_id                 text NOT NULL,
    campaign_name               text,
    campaign_code               text,
    channel_id                  text NOT NULL,
    channel_name                text,
    tenure_type_id              text NOT NULL,
    tenure_type_name            text,
    client_status_id            text NOT NULL,
    client_status_name          text,
    feedback_topic_id           text NOT NULL,
    feedback_topic_name         text,
    feedback_theme              text,
    department_id               text NOT NULL,
    department_name             text,
    position_id                 text NOT NULL,
    position_name               text,
    regulated_interaction_id    text NOT NULL,
    regulated_interaction_name  text,
    sales_employee_eligible     boolean NOT NULL,
    source_marked               boolean NOT NULL,
    source_archived             boolean NOT NULL
);

CREATE TABLE mart.crm_interaction_phone (
    interaction_id        text NOT NULL REFERENCES mart.crm_interaction(interaction_id),
    phone_reference_id    text NOT NULL,
    phone_event_id        text NOT NULL,
    phone_at              timestamp without time zone NOT NULL,
    answered_at           timestamp without time zone,
    PRIMARY KEY (interaction_id, phone_reference_id, phone_event_id)
);

CREATE TABLE mart.crm_interaction_comment (
    interaction_id        text NOT NULL REFERENCES mart.crm_interaction(interaction_id),
    comment_id            text NOT NULL,
    comment_updated_at    timestamp without time zone NOT NULL,
    comment_html          text NOT NULL,
    PRIMARY KEY (interaction_id, comment_id)
);

-- PII remains in protected tables. A future implementation package may grant
-- these views, but never the tables, to its specifically approved BI role.
REVOKE ALL ON mart.crm_interaction,
              mart.crm_interaction_phone,
              mart.crm_interaction_comment
FROM PUBLIC;

CREATE VIEW mart.v_sales_interaction AS
SELECT c.interaction_id,
       c.task_id,
       coalesce(p.phone_at, c.started_at)::date AS interaction_date,
       c.created_at,
       c.planned_at::date AS planned_date,
       CASE
         WHEN c.started_at = TIMESTAMP '0001-01-01'
           OR c.ended_at = TIMESTAMP '0001-01-01'
           OR c.ended_at < c.started_at THEN NULL
         ELSE extract(epoch FROM c.ended_at - c.started_at)::integer
       END AS duration_seconds,
       (p.answered_at IS NOT NULL) AS answered_flag,
       c.event_type_id, c.state_id, c.state_name, c.status_id, c.status_name,
       c.executor_id AS manager_id, c.executor_name AS manager_name,
       c.club_id AS operator_club_id, c.client_id AS client_key,
       c.client_code, c.client_name, c.client_phone,
       c.tenure_type_name AS tenure_type, c.client_status_name AS client_status,
       c.funnel_id, c.funnel_name, c.campaign_id, c.campaign_name,
       c.channel_id, c.cancellation_reason_name,
       1::smallint AS interaction_count,
       coalesce(p.phone_reference_id, '') AS phone_reference_id,
       coalesce(p.phone_event_id, '') AS phone_event_id
FROM mart.crm_interaction c
LEFT JOIN mart.crm_interaction_phone p ON p.interaction_id = c.interaction_id
WHERE c.sales_employee_eligible
  AND c.funnel_id IN ('99a9ebb169a4e2a611eecbf18a73ffa6',
                      '99b0e03a7af94bc911ef0167b7844d74',
                      '99b0e03a7af94bc911ef016b69a7124a')
  AND NOT (c.funnel_id = '99b0e03a7af94bc911ef0167b7844d74'
           AND c.campaign_id IN ('99e886b88886661011f0ae4e3da6296e',
                                 '99cc8098b8acd0e411efe53f048393c3'));

CREATE VIEW mart.v_feedback_interaction AS
WITH feedback_rows AS (
    SELECT f.*, p.answered_at, cm.comment_html, cm.comment_updated_at
    FROM mart.crm_interaction f
    LEFT JOIN mart.crm_interaction_phone p ON p.interaction_id = f.interaction_id
    LEFT JOIN mart.crm_interaction_comment cm ON cm.interaction_id = f.interaction_id
    WHERE f.event_type_id = '9db9fdbf6bd80f2044eb2835157b3bc8'
), normalized AS (
    SELECT *,
           CASE WHEN comment_html IS NULL THEN NULL
                ELSE coalesce(nullif(regexp_replace(regexp_replace(
                       substring(comment_html from '<body>(.*?)</body>'),
                       '</?p>', '', 'g'), '\\s+', ' ', 'g'), ''), comment_html)
           END AS comment_text
    FROM feedback_rows
), grouped AS (
    SELECT task_id, task_code, task_description, created_at, started_at,
           ended_at, planned_at, feedback_topic_id, feedback_topic_name,
           feedback_theme, club_id, club_name, funnel_id, funnel_name,
           department_id, department_name, status_id, status_name, state_id,
           state_name, executor_id, executor_name, position_id, position_name,
           client_id, client_code, client_name, client_phone,
           tenure_type_name, campaign_id, campaign_name, campaign_code,
           channel_name, regulated_interaction_name, cancellation_reason_name,
           string_agg(DISTINCT comment_text, ', ' ORDER BY comment_text) AS comment_text,
           min(comment_updated_at) FILTER (WHERE comment_updated_at > created_at)
             AS comment_updated_at,
           bool_or(answered_at IS NOT NULL
                   AND answered_at <> TIMESTAMP '0001-01-01') AS answered_flag
    FROM normalized
    GROUP BY task_id, task_code, task_description, created_at, started_at,
             ended_at, planned_at, feedback_topic_id, feedback_topic_name,
             feedback_theme, club_id, club_name, funnel_id, funnel_name,
             department_id, department_name, status_id, status_name, state_id,
             state_name, executor_id, executor_name, position_id, position_name,
             client_id, client_code, client_name, client_phone,
             tenure_type_name, campaign_id, campaign_name, campaign_code,
             channel_name, regulated_interaction_name, cancellation_reason_name
), enriched AS (
    SELECT f.*, fu.created_at AS first_followup_at
    FROM grouped f
    LEFT JOIN LATERAL (
        SELECT x.created_at
        FROM mart.crm_interaction x
        WHERE x.task_code = f.task_code
          AND x.client_code IS NOT DISTINCT FROM f.client_code
          AND x.created_at >= f.created_at
          AND x.event_type_id <> '9db9fdbf6bd80f2044eb2835157b3bc8'
        ORDER BY x.created_at, x.interaction_id
        LIMIT 1
    ) fu ON TRUE
)
SELECT task_id, task_code, task_description, created_at,
       created_at::date AS created_date, started_at, ended_at, planned_at,
       (ended_at::date - created_at::date)::integer AS resolution_days,
       feedback_topic_id, feedback_topic_name, feedback_theme, club_id, club_name,
       funnel_id, funnel_name, department_id, department_name,
       status_id, status_name, state_id, state_name,
       executor_id, executor_name, position_id, position_name,
       client_id, client_code, client_name, client_phone,
       tenure_type_name AS tenure_type, campaign_id, campaign_name, campaign_code,
       channel_name, regulated_interaction_name, cancellation_reason_name,
       comment_text, comment_updated_at, first_followup_at, answered_flag,
       coalesce(first_followup_at, comment_updated_at) AS worked_at,
       coalesce(first_followup_at, comment_updated_at) IS NOT NULL AS worked_flag,
       extract(epoch FROM coalesce(first_followup_at, comment_updated_at) - created_at)
         / 60.0 AS response_minutes
FROM enriched;

CREATE VIEW mart.v_guest_tour AS
SELECT c.interaction_id,
       coalesce(p.phone_at, c.started_at)::date AS interaction_date,
       CASE WHEN c.started_at = TIMESTAMP '0001-01-01'
              THEN c.planned_at::date ELSE c.started_at::date END AS report_date,
       c.task_id, c.client_id, c.club_id, c.client_code, c.client_name,
       c.client_phone, c.state_name AS interaction_state,
       c.status_name AS interaction_status, c.executor_id AS performer_id,
       CASE WHEN c.state_name = 'Закрыто'
                   AND c.status_id = 'b78f16cfde0c1e1f4f7c0ae8d942393d'
                 THEN 'completed'
            WHEN c.state_name = 'Запланировано'
                   AND c.status_id = '83b62b0bd3908a65448b72ca1ec17e94'
                 THEN 'planned'
       END AS tour_kind,
       coalesce(p.phone_reference_id, '') AS phone_reference_id,
       coalesce(p.phone_event_id, '') AS phone_event_id
FROM mart.crm_interaction c
LEFT JOIN mart.crm_interaction_phone p ON p.interaction_id = c.interaction_id
WHERE c.event_type_id = 'b538e5326d9fc9a943c11fd0e7a0e678'
  AND c.funnel_id = '99a9ebb169a4e2a611eecbf18a73ffa6'
  AND ((c.state_name = 'Закрыто'
        AND c.status_id = 'b78f16cfde0c1e1f4f7c0ae8d942393d')
    OR (c.state_name = 'Запланировано'
        AND c.status_id = '83b62b0bd3908a65448b72ca1ec17e94'));

REVOKE ALL ON mart.v_sales_interaction,
              mart.v_feedback_interaction,
              mart.v_guest_tour
FROM PUBLIC;

COMMIT;

-- Full rebuild protocol for the approved runner, not executed here:
-- 1) Open one VM-1 REPEATABLE READ READ ONLY snapshot.
-- 2) Extract the explicit table columns above, evaluating sales_employee_eligible
--    source-side with the three approved role names and current name/date EXISTS.
-- 3) In one VM-2 transaction obtain advisory lock, DELETE children then core,
--    COPY core, phone and comment data, run reconciliation, and COMMIT.
-- 4) Before COMMIT use ROLLBACK on any failed check. After COMMIT, rollback
--    requires a separately approved change; do not automate object deletion.
