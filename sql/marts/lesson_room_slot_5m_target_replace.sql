-- APPLIED 2026-08-14 through scripts/load_lesson_room_slot_5m.py after
-- separate explicit DML approval.
-- The loader obtains a source REPEATABLE READ snapshot, verifies its narrow
-- controls, then streams the extract with binary COPY directly into this table.
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('mart.lesson_room_slot_5m:refresh'));
DELETE FROM mart.lesson_room_slot_5m;
-- COPY mart.lesson_room_slot_5m (...) FROM STDIN WITH (FORMAT BINARY);
COMMIT;
