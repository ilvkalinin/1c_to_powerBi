# Incremental design: `visit_client_day`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed key is `(visit_date, club_id, client_key)`. The separate runner
retains the source loader’s six-month blocks but sends them to a target stage,
then uses exact full-row diff rather than truncating the fact. No source
watermark/SLA is claimed; runtime and scheduling remain blocked.
