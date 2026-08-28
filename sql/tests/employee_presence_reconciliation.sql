-- Planned in-transaction reconciliation. $1..$8 are independent source expected values; $11/$12 horizon.
WITH p AS (SELECT count(*) rows, coalesce(sum(presence_minutes),0) minutes, min(presence_date) min_date, max(presence_date) max_date,
  count(*) FILTER (WHERE presence_date < $11::date OR presence_date >= $12::date OR club_id IS NULL OR employee_id IS NULL OR presence_minutes < 0) bad
  FROM mart.employee_presence_day),
u AS (SELECT count(*) rows, coalesce(sum(presence_minutes),0) minutes, min(presence_date) min_date, max(presence_date) max_date,
  count(*) FILTER (WHERE presence_date < $11::date OR presence_date >= $12::date OR club_id IS NULL OR attribution_status NOT IN ('NO_EMPLOYEE','MULTIPLE_EMPLOYEES') OR presence_minutes < 0) bad
  FROM mart.employee_presence_unattributed_day)
SELECT id, expected, actual, CASE WHEN expected IS NOT DISTINCT FROM actual THEN 'PASS' ELSE 'FAIL' END status
FROM p CROSS JOIN u CROSS JOIN LATERAL (VALUES
 ('EP-R01_PERSONAL_ROWS',$1::text,p.rows::text),('EP-R02_PERSONAL_MINUTES',$2::text,p.minutes::text),
 ('EP-R03_PERSONAL_MIN_DATE',$3::text,p.min_date::text),('EP-R04_PERSONAL_MAX_DATE',$4::text,p.max_date::text),
 ('EP-R05_PERSONAL_CONTRACT','0',p.bad::text),('EP-R06_UNATTR_ROWS',$5::text,u.rows::text),
 ('EP-R07_UNATTR_MINUTES',$6::text,u.minutes::text),('EP-R08_UNATTR_MIN_DATE',$7::text,u.min_date::text),
 ('EP-R09_UNATTR_MAX_DATE',$8::text,u.max_date::text),('EP-R10_UNATTR_CONTRACT','0',u.bad::text)
) v(id,expected,actual);
