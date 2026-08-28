-- REVIEWED DDL — execute only through the separately approved physical-admission runner.
CREATE SCHEMA IF NOT EXISTS mart;
CREATE TABLE mart.employee_presence_day (
  presence_date date NOT NULL,
  club_id text NOT NULL,
  employee_id text NOT NULL,
  presence_minutes numeric NOT NULL,
  PRIMARY KEY (presence_date, club_id, employee_id),
  CHECK (presence_minutes >= 0)
);
REVOKE ALL ON mart.employee_presence_day FROM PUBLIC;
