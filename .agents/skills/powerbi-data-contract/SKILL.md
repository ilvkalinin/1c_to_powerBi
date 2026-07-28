---
name: powerbi-data-contract
description: Define and review stable Power BI data contracts for PostgreSQL marts. Use after mart design or when checking columns, types, grain, keys, relationships, refresh fields, additivity, star-schema fitness, and the PostgreSQL/Power BI calculation boundary.
---

# Power BI data contract

## Modes

- In pre-design review, inspect the known report structure, mark missing mapping/ADR facts as `UNKNOWN` or a specific `BLOCKER`, and return findings only. Do not fabricate or save a contract.
- In contract authoring, require requirements, mapping and ADR, then build the contract.
- In read-only post-implementation review, compare artifacts and return findings or a proposed patch to the main/write agent; do not write files.

## Workflow

1. Read the requirements, mapping and ADR.
2. State object name, purpose and exact row grain.
3. Define logical/physical key, retention, refresh mode, SLA, correction and deletion behavior.
4. Document each mapped column: PostgreSQL type, Power BI type, business meaning, `NULL`, role, additivity and visibility.
5. Document relationships, expected cardinality, filter direction and date dimension/date field.
6. Identify the incremental-refresh field only when the mapping proves it is reliable.
7. Separate precomputed PostgreSQL logic from interactive DAX measures.
8. Detect ambiguous identifiers, mixed grains, hidden many-to-many and Power Query work over large raw tables.
9. In authoring mode, save `docs/data_contracts/<mart_name>.md` using the project template. In read-only review mode, return the proposed patch instead.

Only include necessary Power BI fields. Prefer stable types that Power BI interprets predictably. Mark fields that must not be summed and technical fields that should be hidden.

## Exit gate

The contract is incomplete if a column lacks mapping, type, meaning or `NULL` rule; the grain/key is unclear; a relationship lacks evidence; or refresh semantics are invented.

## Output

- Pre-design review: return findings, `UNKNOWN` items and specific blockers; do not return a fabricated contract.
- Contract authoring: return one contract plus blocking issues and a concise connection recommendation.
- Read-only post-implementation review: return findings, acceptance status and a proposed patch when needed.

For a complete contract or acceptance, cover object, connection mode, grain, key, relationships, date logic, refresh field, types, hidden fields, DAX needs and PostgreSQL calculations.
