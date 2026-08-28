-- REVIEWED DDL — execute only through the future approved employee-presence loader.
CREATE SCHEMA IF NOT EXISTS mart;
CREATE TABLE mart.employee_presence_day (
  presence_date date NOT NULL, club_id text NOT NULL, employee_id text NOT NULL, presence_minutes numeric NOT NULL,
  PRIMARY KEY (presence_date, club_id, employee_id), CHECK (presence_minutes >= 0)
);
CREATE TABLE mart.employee_presence_unattributed_day (
  presence_date date NOT NULL, club_id text NOT NULL, attribution_status text NOT NULL, presence_minutes numeric NOT NULL,
  PRIMARY KEY (presence_date, club_id, attribution_status),
  CHECK (attribution_status IN ('NO_EMPLOYEE', 'MULTIPLE_EMPLOYEES')), CHECK (presence_minutes >= 0)
);
REVOKE ALL ON mart.employee_presence_day, mart.employee_presence_unattributed_day FROM PUBLIC;
