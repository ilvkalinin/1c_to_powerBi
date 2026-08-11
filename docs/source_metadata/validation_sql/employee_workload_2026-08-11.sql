-- SV-074: «Загрузка сотрудников» — read-only source controls.
-- Run in BEGIN TRANSACTION READ ONLY, statement_timeout = 30000.
SELECT count(*) AS duty_rows,
       count(*) FILTER (WHERE _fld7111 <= _fld7110) AS nonpositive_intervals
FROM public._inforg7107
WHERE _fld7110 >= DATE '2024-01-01' AND _fld7110 < DATE '2027-01-01';

WITH employee_client AS (
  SELECT _fld2504rref AS client_id, count(*) AS employees
  FROM public._reference225 WHERE _fld2504rref IS NOT NULL GROUP BY 1
), visits AS (
  SELECT _idrref AS visit_id, _fld4171rref AS client_id
  FROM public._document325 WHERE _date_time >= DATE '2024-01-01' AND _date_time < DATE '2027-01-01'
)
SELECT count(*) AS visits, count(*) FILTER (WHERE e.client_id IS NULL) AS visits_without_employee_link,
       count(*) FILTER (WHERE e.employees > 1) AS visits_with_multiple_employee_links
FROM visits v LEFT JOIN employee_client e ON e.client_id = v.client_id;

WITH intervals AS (
  SELECT _fld6292rref AS employee_id, _fld6293rref AS club_id, _fld6296rref AS position_id,
         _fld6298 AS start_at, CASE WHEN _fld6299 = TIMESTAMP '0001-01-01 00:00:00'
         THEN TIMESTAMP '2099-12-31 00:00:00' ELSE _fld6299 END AS end_at
  FROM public._inforg6291
)
SELECT count(*) AS rows, count(*) FILTER (WHERE end_at <= start_at) AS nonpositive_intervals
FROM intervals;
