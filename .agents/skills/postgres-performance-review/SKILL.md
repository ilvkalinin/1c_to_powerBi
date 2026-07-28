---
name: postgres-performance-review
description: Review PostgreSQL mart performance using actual sizes, selectivity, indexes, query plans, execution time and Power BI refresh SLA. Use when choosing or validating views/materialization/tables, refresh queries, joins, filters, indexes, or recurring Power BI loads.
---

# PostgreSQL performance review

## Entry gate

This skill is prohibited during `STAGE_1_LOCAL_ANALYSIS`. Until the user has
explicitly authorized `STAGE_2_SERVER_VALIDATION`, do not connect to a server,
read system catalogs, execute SQL or use `EXPLAIN`. If invoked before that
authorization, return only a concise future measurement plan with status
`VALIDATION_PENDING`.

Actual performance review is allowed only after confirmed SQL or a real object
exists for measurement.

## Safety

Start with catalog facts and `EXPLAIN`. Use `EXPLAIN ANALYZE` only when execution is safe, read-only side effects are understood, expected cost is acceptable and the environment is authorized. Never run write statements under `EXPLAIN ANALYZE` in production.

If actual execution evidence cannot be collected safely, mark performance validation `BLOCKED / NOT MEASURED`. Return only explicitly labelled hypotheses and a measurement plan; do not recommend a production change or claim a bottleneck, improvement or SLA result.

## Workflow

1. Collect table sizes, row counts, typical-period counts, filter selectivity, existing indexes, result volume, refresh frequency, concurrency and SLA.
2. Capture the exact query and plan with environment, parameters and timestamp.
3. Check estimates versus actuals when safe, scan types, join order and cardinality, repeated scans, sorts, spills, functions on filtered columns and row multiplication.
4. Attribute a bottleneck only to actual execution evidence.
5. Recommend the smallest change supported by measured facts.
6. If proposing an index, state the query predicate/join it serves, write cost, storage cost and validation plan.
7. Re-measure with the same data window and record before/after values.

Do not label every sequential scan a problem. Do not propose an index, materialized view or physical table based only on intuition. Do not claim SLA compliance without measured end-to-end evidence.

## Output

Return environment facts, plan evidence, prioritized findings, re-test query and remaining unknowns. Include a proposed change and trade-offs only when actual execution evidence supports it; otherwise return labelled hypotheses and a measurement plan. Keep production changes separate and require explicit user approval.
