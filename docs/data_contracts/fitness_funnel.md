# Data contract: «Фитнес воронка»

Статус: `DESIGNED COMPOSITE MODEL / STAGE_3 TECHNICAL SQL REVIEW VALIDATED / PHYSICAL ADMISSION DECISION_REQUIRED`.

SV-079 подтверждает client-start dedupe bounded cohort, но не полный cohort
или source-key исходов. Контракт сохраняет client-level outcome semantics;
физические объекты не создавались.

## Объекты

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.fitness_funnel_client_start` | `Старт клиентов` | клиент × дата начала / `(client_key, membership_start_date)` |
| `mart.fitness_funnel_client_outcome` | `Исходы клиентов` | клиент × дата исхода × тип × source key |

Старт содержит `client_key text`, `membership_start_date date`,
`access_club_id text`, `tenure_type text` и `client_count smallint = 1`.
Возрастные, договорные и PII-атрибуты остаются contract-detail полями и не
могут появиться в client-start fact без отдельного доказанного grain. Полный
admission обязан подтвердить отсутствие multi-contract конфликтов
`access_club_id`/`tenure_type` для каждого ключа cohort. Full-horizon control
2026-08-28 не прошёл это условие (32 multi-club, 24 multi-tenure, 46 duplicate
target keys); новый grain или business selector требует отдельного решения.
Исход содержит `outcome_source_key text`, `client_key text`, `outcome_date
date`, `outcome_type text`, `club_id text`, `service_id text`,
`outcome_count numeric`. Технические keys скрыты; подтверждённая detail
проекция клиента доступна по BR-017, но не меняет cohort grain.

Календарь имеет отдельные роли start/outcome; клубы фильтруют применимые факты
`1:*`, single direction. Физической client-key связи fact-to-fact нет.
PostgreSQL квалифицирует cohort/outcomes; DAX применяет period/as-of окна,
distinct клиентов и конверсии.

Приёмка: уникальный cohort, source key исхода, несколько контрактов в одну
дату схлопываются, один клиент может иметь несколько исходов, оконные границы,
states, PII, rerun и SLA. В текущем пакете PBIT read-only проверен, но
Power BI connection, relationships и measures остаются `DESIGNED` по BR-036.
