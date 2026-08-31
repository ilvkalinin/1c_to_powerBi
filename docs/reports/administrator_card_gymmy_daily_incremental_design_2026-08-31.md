# Incremental design: `administrator_card_gymmy_daily`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The physical key is `(event_date, club_id, direction)`. The separate runner
keeps one-to-one card mapping validation and source direction controls, stages
the current horizon, and exact-diffs the target instead of its full rebuild.
No watermark/SLA is claimed; runtime and scheduling remain blocked.
