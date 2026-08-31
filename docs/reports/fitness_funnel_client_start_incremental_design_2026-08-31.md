# Incremental design: `fitness_funnel_client_start`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed `(client_key, membership_start_date)` cohort key and BR-048
selection depend on current contract attributes, so no date watermark is safe.
The separate runner reuses the reviewed derived snapshot and controls, stages
it, applies only exact row differences, and requires reconciliation plus
`EXCEPT ALL` equality before commit. The full admission runner is unchanged.
