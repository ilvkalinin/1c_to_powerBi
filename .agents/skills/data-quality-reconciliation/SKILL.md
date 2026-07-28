---
name: data-quality-reconciliation
description: Create and review SQL data-quality and reconciliation checks for PostgreSQL marts against confirmed 1C sources. Use when validating row counts, keys, duplicates, nulls, sums, dates, joins, corrections, deletions, posting state, reruns, and expected control values.
---

# Data quality reconciliation

## Integrity rule

Never call a test passed without an expected result recorded before execution. Distinguish `NOT RUN`, `PASS`, `FAIL` and `BLOCKED`; do not turn missing access or control values into success.
Require the expected/control value and its business filters to be independently obtained and marked `CONFIRMED`. Do not derive the expectation with the same SQL, join path or business formula under test. If independent evidence is absent, mark reconciliation `BLOCKED`.

## Workflow

1. Read requirements, mapping, data contract and implementation.
2. For every check record stable `check_id`, purpose, SQL file/query reference, environment, data snapshot/watermark, execution time, expected result, tolerance, independent evidence source and actual result.
3. Cover at minimum:
   - row and distinct business-object counts;
   - logical-key uniqueness and unexpected duplicates;
   - required/allowed `NULL`;
   - referential integrity and orphan behavior;
   - minimum/maximum dates, future dates and missing dates;
   - source-to-target sums and document counts;
   - row preservation and multiplication across every risky `JOIN`;
   - deleted, unposted, corrected, reversed and missing-dimension cases;
   - repeat run, changed rows and deletions.
4. Use the same confirmed filters, period and units on both sides of reconciliation.
5. Report discrepancies with reproducible samples; do not silently widen tolerances.

Avoid destructive queries. Use read-only SQL unless the user has authorized a disposable test environment.

## Output

Prepare focused test files for `sql/tests/` only after an implementation exists. A read-only reviewer must return the proposed files or patch to the main/write agent; a write-capable caller may persist them. Return a results table with `check_id`, status, SQL reference, environment/snapshot, `executed_at`, expected, actual, difference, independent evidence and next action. State which validations remain blocked and why.
