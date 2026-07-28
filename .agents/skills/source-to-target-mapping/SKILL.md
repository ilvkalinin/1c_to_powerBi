---
name: source-to-target-mapping
description: Analyse PostgreSQL/1C source metadata and create evidence-based source-to-target mappings for analytical marts. Use before designing or changing any mart column, join, transformation, business rule, or source dependency.
---

# Source-to-target mapping

## Workflow

1. Read the report requirements and list missing inputs.
2. Inspect only supplied evidence: documentation, catalog metadata, DDL, sample rows, user-designated reference SQL/Power Query/DAX/reports and confirmed control values.
3. Inventory source tables, columns, types, keys, volumes, date ranges and 1C technical flags.
4. Test proposed keys and joins for uniqueness, nullability and cardinality. Name the exact evidence.
5. Define the target row grain before mapping columns.
6. Add every target column to `docs/mappings/<mart_name>.md` using the project template.
7. Record unknown fields, rejected links, risks and next verification actions.

## Evidence rules

- Use `CONFIRMED` only with a source: metadata query, DDL, documentation, sample evidence, control value or user decision.
- Use `ASSUMPTION` with a verification method; never hide it in production SQL.
- Use `UNKNOWN` when work can continue without the fact.
- Use `BLOCKER` only when a named workflow gate cannot proceed.
- Use `DECISION_REQUIRED` when facts exist but the user must choose.

Do not infer 1C semantics from technical names. A name match is not proof of a relationship. Do not treat a row as a business fact until its meaning, grain, duplicates, posting/deletion behavior, corrections and movement/balance/turnover role are established.

## Required mapping fields

For each target column record: target name, business description, source table and column, transformation, PostgreSQL type, `NULL` policy, row grain, status, evidence and test. Do not allow an unmapped column into SQL.

## Output

Return one mapping, confirmed source list, unknown fields, risks, blockers and explicit verification queries. Do not create mart SQL or invent business logic.
