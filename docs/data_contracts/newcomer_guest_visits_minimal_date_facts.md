# Power BI data contract: минимальные date-facts «Новички и гостевые визиты»

Статус: `IMPLEMENTATION CONTRACT APPROVED`.

## Objects and grains

| Object | Grain / key | Refresh | Power BI boundary |
|---|---|---|---|
| `mart.new_first_visit` | one `contract_id`; PK `contract_id` | atomic full BR-003 rebuild | current PBI is not switched in this package |
| `mart.guest_visit_conversion` | one `client_id × guest_visit_date`; composite PK | atomic full BR-003 rebuild | current PBI is not switched in this package |

## Columns

| Object | Column | PostgreSQL / Power BI type | NULL | Role |
|---|---|---|---|---|
| first visit | `contract_id` | `text` / text | no | hidden stable business key |
| first visit | `first_visit_date` | `date` / date | no | date relationship candidate, not additive |
| guest conversion | `client_id` | `text` / text | no | hidden stable physical key |
| guest conversion | `client_code` | `text` / text | yes | current DAX distinct-consumer field |
| guest conversion | `guest_visit_date` | `date` / date | no | date relationship candidate, not additive |
| guest conversion | `accuniq_same_day_flag` | `boolean` / true-false | no | outcome flag, not summed |
| guest conversion | `purchase_activation_date` | `date` / date | yes | outcome date |
| guest conversion | `purchase_lag_days` | `smallint` / whole number | yes | outcome interval, not additive |

No relationship is created by this package. A future Power BI switch needs a
separate contract for club, demographic and detail fields because they are not
in these minimal facts. There is no incremental watermark: a full rebuild
handles corrected and deleted source rows atomically.
