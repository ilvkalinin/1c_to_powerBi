-- Execute only if the same package created these objects and did not commit a valid load.
BEGIN;
DROP TABLE IF EXISTS mart.fitness_leads_funnel_task_service;
DROP TABLE IF EXISTS mart.fitness_leads_funnel_task;
COMMIT;
