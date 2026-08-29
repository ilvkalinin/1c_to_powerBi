# Data contract: историческое наблюдение «Управления продлением»

Статус: `DESIGNED / Stage 1 complete; no physical object`.

| Параметр | Значение | Статус |
|---|---|---|
| Proposed object | `mart.renewal_management_contract_observation` | DESIGNED |
| Grain | `expiring_contract_id × observed_at`, only state change/removal | DESIGNED |
| Source | `mart.renewal_management_contract` after successful refresh | CONFIRMED upstream |
| Refresh | append after parent fact commit | DESIGNED |
| Retention | append-only, exact policy pending volume/SLA evidence | DECISION_REQUIRED |
| Power BI mode | Import; as-of date chooses latest observation ≤ selected date | DESIGNED |
| PII | not copied | CONFIRMED design |
| Historical 2025 claim | no claim before first observation | CONFIRMED boundary |

Power BI получает отдельный observation fact, не соединённый bidirectional с
current fact. Для as-of visual выбирается latest observation per contract at
or before a selected observation date; `REMOVED` suppresses a contract after
its removal observation. Contract calendar, observation calendar and current
refresh calendar — отдельные role-playing dates.

Проценты и median остаются DAX над выбранным observation fact. PostgreSQL
должен выполнить comparison, tombstone detection and deterministic versioning;
Power Query только назначает типы/русские имена. До Stage 2 не объявляются
type, index, schedule, retention or incremental SLA.
