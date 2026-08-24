-- Stage-2, read-only only. Execute in one BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY transaction.
-- Scope and expected outcomes are fixed before execution in
-- docs/reports/fitness_leads_funnel_stage_2_server_validation_authorization_2026-08-24.md.

-- FL-V01: physical objects, columns, types and technical flags required by the
-- current task and booking paths. Expected: every named relation is resolved
-- once and the observed columns/types are recorded before downstream controls.
SELECT c.relname AS relation_name,
       c.relkind,
       n.nspname AS schema_name,
       a.attnum,
       a.attname AS column_name,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
       a.attnotnull
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attribute AS a
  ON a.attrelid = c.oid
 AND a.attnum > 0
 AND NOT a.attisdropped
WHERE n.nspname = 'public'
  AND c.relname IN (
    '_reference106', '_reference89', '_reference141x1', '_reference132',
    '_reference145', '_reference201', '_reference264', '_reference163',
    '_inforg7006', '_document329', '_document279', '_document329_vt4352',
    '_accumrg7575', '_accumrg7646'
  )
ORDER BY c.relname, a.attnum;

-- FL-V01B: 1C table constraints/indexes are evidence only; no inference of
-- business uniqueness is permitted from names.
SELECT c.relname AS relation_name,
       i.relname AS index_name,
       ix.indisprimary,
       ix.indisunique,
       pg_catalog.pg_get_indexdef(ix.indexrelid) AS index_definition
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_index AS ix ON ix.indrelid = c.oid
LEFT JOIN pg_catalog.pg_class AS i ON i.oid = ix.indexrelid
WHERE n.nspname = 'public'
  AND c.relname IN ('_reference106', '_reference141x1', '_inforg7006',
                     '_document329', '_document279', '_document329_vt4352',
                     '_accumrg7575', '_accumrg7646')
ORDER BY c.relname, i.relname;

-- FL-V02: BR-003 task-key and task-code control. Expected: no duplicate IDs;
-- task-code uniqueness is measured independently.
WITH t AS (
  SELECT _idrref, _code
  FROM public._reference106
  WHERE _fld1191rref IN (
    decode('99ad9b75dc73f34911eee5eefdcdd3b4','hex'),
    decode('99f6efa9e59a276811f0fcebecd498be','hex'),
    decode('99b19ba3029d764511ef394a0464555f','hex'),
    decode('99ad9b75dc73f34911eee5ea6f34a13b','hex')
  ) AND _fld1193 >= DATE '2025-01-01' AND _fld1193 < DATE '2027-01-01'
    AND NOT _marked
)
SELECT count(*) AS tasks, count(DISTINCT _idrref) AS distinct_ids,
       count(DISTINCT _code) AS distinct_codes,
       count(*) FILTER (WHERE _code IS NULL) AS null_codes,
       count(*) - count(DISTINCT _code) AS duplicate_code_rows
FROM t;

-- FL-V04: all task dimensions are one-row lookup joins. Expected: join_excess=0.
WITH t AS (
  SELECT _idrref,_fld1191rref,_fld1195rref,_fld1196rref,_fld1197rref,
         _fld1201rref,_fld1205rref
  FROM public._reference106
  WHERE _fld1191rref IN (
    decode('99ad9b75dc73f34911eee5eefdcdd3b4','hex'),
    decode('99f6efa9e59a276811f0fcebecd498be','hex'),
    decode('99b19ba3029d764511ef394a0464555f','hex'),
    decode('99ad9b75dc73f34911eee5ea6f34a13b','hex')
  ) AND _fld1193 >= DATE '2025-01-01' AND _fld1193 < DATE '2027-01-01'
    AND NOT _marked
), j AS (
  SELECT t._idrref FROM t
  LEFT JOIN public._reference89 f ON f._idrref=t._fld1191rref
  LEFT JOIN public._reference132 club ON club._idrref=t._fld1195rref
  LEFT JOIN public._reference141x1 client ON client._idrref=t._fld1196rref
  LEFT JOIN public._reference145 campaign ON campaign._idrref=t._fld1197rref
  LEFT JOIN public._reference201 reason ON reason._idrref=t._fld1201rref
  LEFT JOIN public._reference264 stage ON stage._idrref=t._fld1205rref
)
SELECT (SELECT count(*) FROM t) AS task_rows, count(*) AS joined_rows,
       count(DISTINCT _idrref) AS distinct_task_ids,
       count(*) - count(DISTINCT _idrref) AS join_excess
FROM j;

-- FL-V05: exact current task-service source join. Expected before execution:
-- no multivalued task. Actual multivalued tasks must not be silently deduped.
WITH t AS MATERIALIZED (
  SELECT t._idrref,t._fld1192 AS closed_at,c._code AS client_code
  FROM public._reference106 t LEFT JOIN public._reference141x1 c ON c._idrref=t._fld1196rref
  WHERE t._fld1191rref IN (decode('99ad9b75dc73f34911eee5eefdcdd3b4','hex'),decode('99f6efa9e59a276811f0fcebecd498be','hex'),decode('99b19ba3029d764511ef394a0464555f','hex'),decode('99ad9b75dc73f34911eee5ea6f34a13b','hex'))
    AND t._fld1193>=DATE '2025-01-01' AND t._fld1193<DATE '2027-01-01' AND NOT t._marked
), matched AS MATERIALIZED (
  SELECT rr._period,t.client_code,coalesce(d329._fld4316rref,d279._fld3226rref) AS service_ref
  FROM t JOIN public._inforg7006 rr ON rr._period=t.closed_at
  JOIN public._reference141x1 c ON c._idrref=rr._fld7008rref AND c._code=t.client_code
  LEFT JOIN public._document329 d329 ON d329._idrref=rr._fld7007_rrref AND d329._fld4306>=DATE '2025-01-01' AND d329._fld4306<DATE '2027-01-01'
  LEFT JOIN public._document279 d279 ON d279._idrref=rr._fld7007_rrref AND d279._fld3218>=DATE '2025-01-01' AND d279._fld3218<DATE '2027-01-01'
), z AS MATERIALIZED (
  SELECT _period,client_code,service_ref FROM matched GROUP BY 1,2,3
), j AS (
  SELECT t._idrref,z.service_ref FROM t LEFT JOIN z ON z._period=t.closed_at AND z.client_code=t.client_code
), a AS (
  SELECT _idrref,count(*) AS joined_rows,count(DISTINCT service_ref) AS service_refs FROM j GROUP BY _idrref
)
SELECT count(*) AS tasks,sum(joined_rows) AS joined_rows,sum(joined_rows)-count(*) AS join_excess,
       count(*) FILTER (WHERE joined_rows>1) AS multirow_tasks,
       count(*) FILTER (WHERE service_refs>1) AS multiservice_tasks,
       count(*) FILTER (WHERE joined_rows=1 AND service_refs=0) AS no_service_match
FROM a;

-- FL-V06/V07/V08/V09/V11 preserve the literal PBIT source filters and DAX
-- expressions in Pbit_old/ВоронкаЛидыФитнес.pbit / DataModelSchema. Their
-- snapshot IDs, expected values, actual results and reconciliation status are
-- recorded in ../fitness_leads_funnel_stage2_validation_2026-08-24.md.
