# Data contract: «Фитнес воронка»

Статус: `DESIGNED COMPOSITE MODEL / OUTCOME PHYSICAL ADMISSION VALIDATED / POWER BI DESIGNED`.

SV-079 подтверждает client-start dedupe bounded cohort, но не полный cohort
или source-key исходов. Контракт сохраняет client-level outcome semantics;
`mart.fitness_funnel_client_outcome` физически создан, а Power BI boundary
остаётся неизменной.

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
target keys). Пользователь подтвердил выбор более поздней `Fld674` даты
приобретения, а при равенстве — больший `Fld693` срок договора. До full-horizon
контроля равенств второго ранга target contract не меняется.
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

## Условие реализации outcome

Статус `mart.fitness_funnel_client_outcome`: `PHYSICAL ADMISSION VALIDATED / FULL-REBUILD BASELINE ONLY`.
Для ИП current PBIT хранит один client-day, но не определяет, какой из
нескольких клубов/услуг/сотрудников остаётся в этой строке. Full-horizon
control 2026-08-28 нашёл 481 такой client-day. Пользователь принял BR-049:
разные услуги сохраняются отдельными source-event строками. Поэтому
`outcome_source_key` включает физический source key и branch discriminator,
а `outcome_count = 1`; distinct-клиенты не меняются, legacy `COUNTROWS` может
увеличиться. Technical evidence:
`docs/reports/fitness_funnel_client_outcome_stage3_technical_review_execution_2026-08-28.md`.
Physical evidence:
`docs/reports/fitness_funnel_client_outcome_stage3_product_admission_execution_2026-08-28.md`.
Final target rerun has 1 037 064 unique source keys and zero required/horizon
violations. Refresh is a measured full rebuild only; no incremental field/SLA
is declared. Power BI remains unchanged by BR-036.
