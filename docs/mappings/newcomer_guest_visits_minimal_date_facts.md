# Source-to-target mapping: минимальные date-facts «Новички и гостевые визиты»

Статус: `CONFIRMED FOR STAGE 3 IMPLEMENTATION`.

Основание: BR-003, BR-035, PBIT
`Pbit_old/Новички и гостевые визиты.pbit` (SHA-256
`3d54a392bec0d3feed21f998c91bf4607886ca101eac7b0adc94d6bbce180796`) и
явное решение пользователя 2026-08-24. Источник 1С читается только в одном
`REPEATABLE READ, READ ONLY` snapshot.

## Reuse review

`mart.visit_client_day` не содержит contract-key первого посещения; CRM core
не содержит гостевой регистр. Оба продукта — `NEW`, но используют только
подтверждённые source rules, а не копии raw-регистров.

## `mart.new_first_visit`

Grain: одна строка на `contract_id`. В одном договоре сохраняется минимальная
`Period::date` квалифицированного посещения; клиент, document и момент внутри
даты не выходят в target и не служат tie-break.

| Target column | Source / transform | Type / NULL | Status and test |
|---|---|---|---|
| `contract_id` | `encode(AccumRg7575.Fld7578, 'hex')` | `text NOT NULL` | CONFIRMED; PK/duplicate check NV-R02 |
| `first_visit_date` | `min(AccumRg7575.Period::date)` после current-PBI qualification: New contract, document kind «посещение», current contract/client exclusions and non-ДРЦ/УК club | `date NOT NULL` | CONFIRMED by BR-035; horizon/null/date control NV-R03/R04 |

Read-only club control on the BR-003 scope: 31 contracts had a tied earliest
timestamp, and none had more than one club after qualification; 28 had more
than one client. Club is intentionally not a target column under the minimal
rule, so client ties cannot alter the row.

## `mart.guest_visit_conversion`

Grain: одна строка на physical `client_id × guest_visit_date`. Guest-registry
rows are reduced with `DISTINCT` only on this approved key before outcomes.
Registration, status, period/time and recorder are excluded from target.

| Target column | Source / transform | Type / NULL | Status and test |
|---|---|---|---|
| `client_id` | `encode(InfoRg7064.Fld7065, 'hex')` | `text NOT NULL` | CONFIRMED physical key; PK/duplicate NV-R02 |
| `client_code` | `Reference141X1.Code` for the same physical client | `text NULL` | CONFIRMED current PBI consumer; required-source profile NV-R05 |
| `guest_visit_date` | `InfoRg7064.Fld7068::date` | `date NOT NULL` | CONFIRMED user rule; horizon NV-R04 |
| `accuniq_same_day_flag` | existence of approved PBIT ACCUNIQ group `client_id × Period::date`, signed total in `(1,2)` | `boolean NOT NULL` | CONFIRMED SV-102; invariant NV-R03 |
| `purchase_activation_date` | minimum suitable `Reference59.Fld670::date` by current PBI client-code rule in `[guest_visit_date, guest_visit_date + 44]` | `date NULL` | CONFIRMED SV-108; range NV-R03 |
| `purchase_lag_days` | `purchase_activation_date - guest_visit_date` | `smallint NULL` | CONFIRMED SV-108; range 0…44 NV-R03 |

Read-only club control found 1,249 duplicated physical client-date groups and
21 groups with more than one club. Club is deliberately omitted: it is derived
from the document whose choice BR-035 makes irrelevant. Current PBI remains
unchanged; no Power BI switch is part of this package.

## Source constraints and boundaries

- BR-003 scope is `[2025-01-01, 2027-01-01)` at the run date 2026-08-24.
- No status, `Active`, posting, deletion, document or recorder filter is added
  to the guest branch because current PBI does not use one and BR-035 excludes
  those fields from the minimal fact.
- No raw registry/table is replicated to VM-2. Exact source result columns are
  copied through temporary binary files only.
