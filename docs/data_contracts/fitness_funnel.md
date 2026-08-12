# Data contract: «Фитнес воронка»

Статус: `DESIGNED COMPOSITE MODEL / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-079 / IMPLEMENTATION DEFERRED`.

SV-079 подтверждает client-start dedupe bounded cohort, но не полный cohort
или source-key исходов. Контракт сохраняет client-level outcome semantics;
физические объекты не создавались.

## Объекты

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.fitness_funnel_client_start` | `Старт клиентов` | клиент × дата начала / `(client_key, membership_start_date)` |
| `mart.fitness_funnel_client_outcome` | `Исходы клиентов` | клиент × дата исхода × тип × source key |

Старт содержит `client_key text`, `membership_start_date date`, `club_id text`,
`tenure_type text`, возрастные/договорные срезы из mapping и `client_count = 1`.
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
states, PII, rerun и SLA.
