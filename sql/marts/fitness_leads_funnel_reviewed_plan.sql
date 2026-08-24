-- REVIEWED DDL — execute only through the approved atomic loader.
-- Objects: mart.fitness_leads_funnel_task and mart.fitness_leads_funnel_task_service.
BEGIN;

CREATE TABLE mart.fitness_leads_funnel_task (
  task_id text PRIMARY KEY,
  task_code text NOT NULL UNIQUE,
  task_created_at timestamp without time zone NOT NULL,
  task_date date NOT NULL,
  closed_at timestamp without time zone NOT NULL,
  forced_closed_at timestamp without time zone NOT NULL,
  funnel_id text NOT NULL,
  funnel_name text NOT NULL,
  club_id text,
  club_name text,
  client_key text,
  client_code text,
  tenure_type text,
  campaign_id text,
  campaign_name text,
  parent_campaign_name text NOT NULL,
  unsuccessful_reason text,
  funnel_stage_name text,
  first_interaction_type text,
  has_booking boolean NOT NULL,
  training_count bigint,
  has_paid_training_45d boolean NOT NULL,
  task_count smallint NOT NULL DEFAULT 1,
  CHECK (task_date = task_created_at::date),
  CHECK (task_count = 1),
  CHECK (has_paid_training_45d = (coalesce(training_count, 0) > 0))
);

CREATE TABLE mart.fitness_leads_funnel_task_service (
  task_id text NOT NULL REFERENCES mart.fitness_leads_funnel_task(task_id),
  service_name text NOT NULL,
  service_source text NOT NULL,
  service_date date,
  PRIMARY KEY (task_id, service_name, service_source),
  CHECK (service_source IN ('DIRECT_CURRENT', 'FALLBACK_EARLIEST_DAX_MIN'))
);

REVOKE ALL ON mart.fitness_leads_funnel_task,
              mart.fitness_leads_funnel_task_service FROM PUBLIC;
COMMIT;
