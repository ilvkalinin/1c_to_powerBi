# Data contract: общий CRM core

Статус: `DRAFT FOR ADMISSION / IMPLEMENTATION NOT AUTHORIZED`.

| Parameter | Value | Status |
|---|---|---|
| Future object | `mart.crm_interaction` | DESIGNED — ADR-0016 |
| Grain / logical key | one `Reference67.ID` / `interaction_id` | CONFIRMED business |
| Consumers | sales, feedback, guest-tour views | CONFIRMED |
| Refresh | no mechanism selected in this package | DECISION_REQUIRED |
| PII | only report-specific views under BR-017 | CONFIRMED policy; physical enforcement pending |

The core provides protected IDs, interaction timestamps and task-side CRM
classifications listed in [the mapping](../mappings/crm_interaction.md). It
must not contain phone-row, HTML/comment, employment-interval, PBIT final
grouping, feedback response, tour conversion or sales KPI grain as its own
row-grain.

Before an implementation package, the exact public columns, PostgreSQL types,
grants and source-to-core encoding must be reviewed together with the three
view contracts. PBIT reconciliation has open `DECISION_REQUIRED` items for
sales `Distinct`/third role, feedback grouping without interaction ID and
guest-tour phone/date semantics. None is resolved by this draft.
