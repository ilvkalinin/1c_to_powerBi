# Incremental design: `fitness_funnel_client_outcome`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The fact has stable `outcome_source_key`, but its five source branches include
current registers and later corrections. No validated modified watermark spans
the full composed outcome. The new runner reuses the existing source-first
monthly derived pool and independent controls, then stages it and applies only
exact full-row differences to the existing target. Exact `EXCEPT ALL` and the
approved target reconciliation are required before commit. No SLA or watermark
is claimed; the admission-token full rebuild remains unchanged.
