-- Source extract for mart.dpfu_plan_assignment.
-- REVIEW ONLY. The runner binds $1 = BR-003 horizon_start and
-- $2 = BR-003 horizon_end and streams this explicit projection from one
-- REPEATABLE READ, READ ONLY VM-1 snapshot to a VM-2 temp stage.
-- LEFT JOIN preserves a source row if the client reference later becomes
-- orphaned; the stage contract then fails instead of silently dropping it.

SELECT r._fld6613::date AS plan_date,
       encode(r._fld6615rref, 'hex') AS club_id,
       encode(r._fld6614rref, 'hex') AS activity_id,
       encode(r._fld6616rref, 'hex') AS employee_id,
       encode(r._fld6617rref, 'hex') AS planned_client_key,
       CAST(client._code AS varchar(1000)) AS planned_client_code,
       encode(r._fld6619, 'hex') AS plan_line_discriminator,
       r._fld6620::numeric(18,2) AS planned_revenue
FROM public._inforg6612 r
LEFT JOIN public._reference141x1 client ON client._idrref = r._fld6617rref
WHERE r._fld6613 >= $1::date
  AND r._fld6613 < $2::date;
