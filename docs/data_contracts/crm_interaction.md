# Data contract: общий CRM core

Статус: `SUPERSEDED BY BR-032 / EMPTY LEGACY OBJECTS ONLY`.

| Parameter | Value | Status |
|---|---|---|
| Legacy objects | `mart.crm_interaction`, `mart.crm_interaction_phone`, `mart.crm_interaction_comment` | Created empty on VM-2 by the superseded plan; no CRM DML committed |
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

BR-032 replaces this shared-core contract: before a further implementation
package, three minimal report-specific contracts and their source-side
projections must be reviewed. PBIT reconciliation remains evidence for the
sales `Distinct`/third role, feedback grouping and guest-tour phone/date
semantics; it does not justify a raw CRM transfer.
