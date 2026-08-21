# Data contract: общий CRM core

Статус: `TECHNICAL SQL REVIEW COMPLETE / IMPLEMENTATION NOT AUTHORIZED`.

| Parameter | Value | Status |
|---|---|---|
| Future objects | `mart.crm_interaction`, `mart.crm_interaction_phone`, `mart.crm_interaction_comment` | DESIGNED — ADR-0016, no DDL executed |
| Grain / logical key | one `Reference67.ID` / `interaction_id` | CONFIRMED business |
| Consumers | sales, feedback, guest-tour views | CONFIRMED |
| Refresh | no mechanism selected in this package | DECISION_REQUIRED |
| PII | only report-specific views under BR-017 | `REVOKE FROM PUBLIC` is required; named BI role/grant remains DECISION_REQUIRED |

The core provides protected IDs, interaction timestamps and task-side CRM
classifications listed in [the mapping](../mappings/crm_interaction.md). Its
key is `interaction_id text`; source `bytea` IDs are explicitly hex-encoded.
`mart.crm_interaction_phone` has the validated candidate key
`(interaction_id, phone_reference_id, phone_event_id)`, and
`mart.crm_interaction_comment` has `(interaction_id, comment_id)`. Neither
child changes core grain. The core must not contain phone-row, HTML/comment,
employment-interval, PBIT final grouping, feedback response, tour conversion
or sales KPI grain as its own row-grain.

Before an implementation package, the exact public columns, named BI role and
guest-outcome tie policy must be reviewed together with the three view
contracts. PBIT reconciliation has resolved the sales `Distinct`/third role,
feedback grouping without interaction ID and guest-tour phone/date semantics.
Physical CRM types and hidden child keys were confirmed read-only on
2026-08-21; guest ACCUNIQ/contract ties remain a decision that changes output
rows or selected detail.
