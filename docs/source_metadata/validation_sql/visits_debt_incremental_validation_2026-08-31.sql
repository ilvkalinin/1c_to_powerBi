-- VD-INC-001..005. Read-only metadata and aggregate evidence only.
BEGIN ISOLATION LEVEL REPEATABLE READ, READ ONLY;
SET LOCAL statement_timeout = '30000';

-- VD-INC-001/002: physical columns and types for the movement register and
-- both document branches. Expected: complete metadata; a candidate change
-- watermark must be evidenced by a suitable physical column, not its name.
SELECT table_name, ordinal_position, column_name, data_type, udt_name,
       is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('_accumrg7509', '_document329', '_document279')
ORDER BY table_name, ordinal_position;

-- VD-INC-002: relations whose physical names may indicate a registered
-- change feed for this register. Name matches are discovery only.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND (table_name LIKE '%7509%' OR table_name LIKE '%chng%' OR table_name LIKE '%change%')
ORDER BY table_name;

-- VD-INC-003/005: current state and event-date distribution. `_period` is an
-- event date; this query does not promote it to a change watermark.
SELECT count(*)::bigint AS rows,
       count(*) FILTER (WHERE NOT _active)::bigint AS inactive_rows,
       count(DISTINCT (_period, _recordertref, _recorderrref, _lineno))::bigint AS keys,
       min(_period) AS min_event_at,
       max(_period) AS max_event_at
FROM public._accumrg7509;

-- VD-INC-004: verify whether any discovered source column can provide a
-- historical change timestamp. Metadata is the independent evidence; no
-- lag is calculated from event dates alone.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('_accumrg7509', '_document329', '_document279')
  AND data_type IN ('timestamp without time zone', 'timestamp with time zone', 'date')
ORDER BY table_name, ordinal_position;

ROLLBACK;
