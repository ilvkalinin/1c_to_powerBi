# Data contract: историческое наблюдение «Управления продлением»

Статус: `IMPLEMENTED / Power BI unchanged`.

| Параметр | Значение | Статус |
|---|---|---|
| Proposed object | `mart.renewal_management_contract_observation` | REVIEWED |
| Grain | `expiring_contract_id × observed_at`, only state change/removal | CONFIRMED design |
| Source | `mart.renewal_management_contract` after successful refresh | CONFIRMED upstream |
| Refresh | append after parent fact commit; ASOF-V03 source drift evidence confirms target-only handoff | CONFIRMED design prerequisite |
| Retention | append-only; no deletion job or period has been approved | DECISION_REQUIRED |
| Power BI mode | Import; as-of date chooses latest observation ≤ selected date | DESIGNED / Power BI unchanged |
| PII | not copied | CONFIRMED design |
| Historical 2025 claim | no claim before first observation; source retrospective reconstruction is blocked | CONFIRMED boundary |

Power BI получает отдельный observation fact, не соединённый bidirectional с
current fact. Для as-of visual выбирается latest observation per contract at
or before a selected observation date; `REMOVED` suppresses a contract after
its removal observation. Contract calendar, observation calendar and current
refresh calendar — отдельные role-playing dates.

## Physical and Power BI fields

The physical contract is exactly the reviewed DDL. `expiring_contract_id` and
`observed_at` are the technical composite key (hide both only if the model
exposes a user-friendly observation date). `observation_kind` and `state_hash`
are technical/non-additive fields. The remaining PII-free attributes are
non-additive state slices, not amounts: dates, IDs, flags, text outcome,
rating, tenure and latest-interaction fields. `REMOVED` retains the previous
state values when available and must suppress the contract in an as-of measure.

Use a separate observation calendar on `observed_at` and keep contract-end
calendar role on `membership_end_date`; relationships are single-direction
one-to-many from dimensions to this fact. No bidirectional relationship or
automatic relation to the current fact is approved. Power BI import/connection,
relationships, labels and DAX changes remain outside this package.

The reviewed as-of read is `GROUP BY expiring_contract_id, MAX(observed_at)`
then join to the composite primary key. At the initial 240,967-row baseline it
returned the same 240,967 live contracts as `DISTINCT ON ... observed_at DESC`
but measured 460.592 ms versus 2,755.651 ms. It is a query recommendation for
a future consumer, not a Power BI change or an incremental-refresh SLA.

Проценты и median остаются DAX над выбранным observation fact. PostgreSQL
должен выполнить comparison, tombstone detection and deterministic versioning;
Power Query только назначает типы/русские имена. До Stage 2 не объявляются
type, index, schedule, retention or incremental SLA.

ASOF-V01/V02/V05 are validated in Stage 2. Selector uniqueness, physical
transition constraints and failure ordering are acceptance controls for a
separately approved Stage 3 object; no observation relation exists yet.
