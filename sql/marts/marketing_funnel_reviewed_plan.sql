-- REVIEW ONLY — do not execute before one explicit Stage-3 admission approval.
-- Objects: mart.marketing_funnel_task and mart.marketing_funnel_task_contract.
-- Initial load has no replacement target: verify both relations are absent before
-- applying this transactional DDL. The separately reviewed rollback script is
-- allowed only for these two objects created by this package.

BEGIN;

CREATE TABLE mart.marketing_funnel_task (
    task_id                        text PRIMARY KEY,
    task_code                      text NOT NULL UNIQUE,
    task_created_at                timestamp without time zone NOT NULL,
    task_date                      date NOT NULL,
    closed_at                      timestamp without time zone,
    forced_closed_at               timestamp without time zone,
    funnel_id                      text NOT NULL,
    funnel_name                    text NOT NULL,
    club_id                        text,
    club_name                      text,
    client_key                     text,
    client_code                    text,
    tenure_type                    text,
    campaign_id                    text,
    campaign_name                  text,
    parent_campaign_name           text NOT NULL,
    unsuccessful_reason            text,
    funnel_stage_name              text,
    first_interaction_type_raw     text,
    first_interaction_type         text NOT NULL,
    traffic_direction              text NOT NULL,
    task_count                     smallint NOT NULL DEFAULT 1,
    CHECK (task_date = task_created_at::date),
    CHECK (task_count = 1),
    CHECK (traffic_direction IN ('Накопленный трафик (вх.)',
                                'Накопленный трафик (исх.)'))
);

CREATE TABLE mart.marketing_funnel_task_contract (
    task_id                        text NOT NULL
                                   REFERENCES mart.marketing_funnel_task(task_id),
    contract_id                    text NOT NULL,
    contract_name                  text,
    contract_client_key            text,
    contract_client_code           text,
    activation_date                date NOT NULL,
    is_conversion_qualified        boolean NOT NULL,
    contract_age_group             text NOT NULL,
    contract_payment_type          text NOT NULL,
    contract_duration_group        text NOT NULL,
    contract_count                 smallint NOT NULL DEFAULT 1,
    PRIMARY KEY (task_id, contract_id),
    CHECK (contract_count IN (0, 1)),
    CHECK (contract_count = CASE WHEN is_conversion_qualified THEN 1 ELSE 0 END),
    CHECK (contract_payment_type IN ('Рекарринг', 'Предоплата')),
    CHECK (contract_duration_group IN ('001-007', '008-030', '031-180',
                                       '181-364', '365+'))
);

REVOKE ALL ON mart.marketing_funnel_task,
              mart.marketing_funnel_task_contract
FROM PUBLIC;

COMMIT;
