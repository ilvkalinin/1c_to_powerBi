# Incremental design: `lesson_room_slot_5m`

Status: `INCREMENTAL_CANDIDATE / RUNNER_IMPLEMENTATION_IN_PROGRESS`.

The confirmed slot key is `(source_kind, source_lesson_id, slot_start_at)`.
Late cancellation and interval corrections prevent a date watermark. The new
runner will use one read-only snapshot and exact target row diff; BR-021 and
the existing full loader remain unchanged.
