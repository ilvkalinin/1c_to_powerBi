# Incremental design: `group_lesson`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The target key is `group_lesson_id`. The separate runner stages the approved
source extract, derives booking counts from its prerequisite
`mart.prebooking_state_event`, and exact-diffs final rows. No source watermark
or SLA is claimed; runtime and scheduling remain blocked.
