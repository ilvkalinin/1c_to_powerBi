# Source-to-target mapping: `renewal_management_as_of_snapshot`

Статус: `STAGE 1 COMPLETE / local temporal design; server validation NOT_EXECUTED`.

## Назначение и граница смысла

Продукт фиксирует **наблюдаемое при ежедневном refresh состояние** уже
реализованной current-state витрины `mart.renewal_management_contract`.
Он не выдаёт нынешние строки 1С за снимок прошлого и не обещает восстановить
то, что было известно в 2025 году до первого сохранённого наблюдения.

Термин `as_of` в первом выпуске означает: «последнее зафиксированное состояние
не позднее указанного `observed_at`». Это не равнозначно source-effective
history до проверки первичных исторических полей.

## Grain и ключ

Одна строка — одно изменение наблюдаемого состояния одного исходного договора:

> `expiring_contract_id × observed_at`.

Логический key: `(expiring_contract_id, observed_at)`.

`observed_at` — момент успешного refresh snapshot-продукта в московском
времени; точный PostgreSQL type и timezone policy — `VALIDATION_PENDING` для
следующего технического пакета. Для одного договора за один observation run
допускается не более одной строки.

## Reuse review

| Candidate | Grain / semantics | Решение |
|---|---|---|
| `mart.renewal_management_contract` | один текущий исходный договор, уже содержит согласованные BR-050 поля | `REUSE / CONFIRMED`: единственный upstream first-release snapshot. |
| `mart.visit_client_day` | date × club × client, без contract ID | `NOT_APPLICABLE`: не воспроизводит contract visit semantics. |
| `mart.membership_contract_kpi_unit` | prepay contract или recurring KPI month | `NOT_APPLICABLE`: иной contract/renewal grain. |
| `mart.crm_interaction` | ограниченный sales/guest interaction core | `NOT_APPLICABLE`: scope не доказан эквивалентным №16. |
| VM-1 raw `Reference59`, `Reference67`, `InfoRg*` | source records/current values | не копировать на VM-2; допустимы только будущие read-only controls для проверки retrospective effective-date reconstruction. |

## Колонки observation fact

| Target | Бизнес-смысл / преобразование | Source | Status | Проверка перед SQL |
|---|---|---|---|---|
| `expiring_contract_id` | stable исходный договор | current mart PK | CONFIRMED | non-null, one current row |
| `observed_at` | момент, когда состояние было замечено | controlled successful observation run | ASSUMPTION | timezone, monotonicity, one run timestamp |
| `observation_kind` | `BASELINE`, `CHANGED`, `REMOVED` | comparison current mart ↔ latest observation | DESIGNED | allowed values, no duplicate key |
| `state_hash` | hash only analytic fields ниже; PII не включается | deterministic target expression | DESIGNED | unchanged rows do not append |
| `membership_end_date`, `contract_end_month`, `client_id`, `access_club_id` | cohort and slice keys на момент наблюдения | current mart | CONFIRMED upstream | NULL/key consistency |
| `next_contract_id`, `next_contract_code`, `renewal_activation_date`, `next_contract_start_date`, `next_contract_term_days`, `renewal_type`, two Renew flags, lag/return fields | current selected renewal outcome | current mart / BR-050 | CONFIRMED upstream current-state | comparison/hash and flag controls |
| `last_interaction_at`, `last_interaction_type`, `current_funnel_stage`, `current_fail_reason` | current latest eligible interaction outcome | current mart / BR-050 | CONFIRMED upstream current-state | comparison/hash and NULL semantics |
| `current_rating`, `current_tenure` | current client attributes | current mart | CONFIRMED upstream current-state | comparison/hash and domain coverage |

PII (`client_name`, `client_phone`, birth date) и raw visits/prices в history
не переносятся: они не нужны для temporal renewal outcome и повышают risk
ретроспективного PII drift.

## Forward capture

1. После успешного atomic refresh `mart.renewal_management_contract` сравнить
   его analytic columns с latest observation того же `expiring_contract_id`.
2. Вставить только `BASELINE`/`CHANGED`; contracts, исчезнувшие из current mart,
   записать `REMOVED`, не удаляя предыдущие observation rows.
3. При Power BI as-of фильтре брать последнюю observation row договора не
   позднее выбранной даты; `REMOVED` исключает договор после события удаления.
4. Если current refresh не завершился, observation run не начинается. Никакой
   частичной snapshot-версии не принимается.

Так сохраняется update поведения: следующий договор, CRM interaction,
rating и tenure могут меняться после окончания договора, но каждое замеченное
изменение получает свой `observed_at`.

## Retrospective effective-date reconstruction — не включено

| Поле | Local evidence | Статус / будущая проверка |
|---|---|---|
| tenure | `InfoRg5654.Period` и validated local precedent `client_base_snapshot_extract.sql` строят effective intervals before report date | `VALIDATION_PENDING`: tie, boundary and correction control against contract-end date |
| rating | `InfoRg6861.Period` существует; current mart берёт latest period | `VALIDATION_PENDING`: as-of selector, ties and current no-Active behaviour |
| interaction timestamp/type | `Reference67.Fld820` (started) и `Fld823` (created) известны в current extract | `DECISION_REQUIRED`: «known at» по created, started или обоим; task funnel/fail fields могут быть mutable current state |
| next contract | current selector uses same-client dates and BR-050 | `DECISION_REQUIRED` + `VALIDATION_PENDING`: activation/start constraint and proof that backdated/corrected contract was known then |
| cohort contract attributes | `Reference59` current record | `BLOCKER` for claiming historical 2025 universe without version/source-history evidence |

## Stage 2 control list (NOT_EXECUTED)

- ASOF-V01: current mart key and selected analytic column coverage.
- ASOF-V02: one observation per `(contract, observed_at)`, state-hash and
  `BASELINE/CHANGED/REMOVED` transitions.
- ASOF-V03: atomic ordering — no observation after failed parent refresh.
- ASOF-V04: Power BI as-of selector returns the last nonremoved observation.
- ASOF-V05: `InfoRg5654` and `InfoRg6861` effective-date cardinality/ties.
- ASOF-V06: `Reference67` created/start timestamps and task/funnel mutability.
- ASOF-V07: `Reference59` activation/start/backdating history and deletion/
  correction behaviour for retrospective next-contract selection.

No SQL is created in Stage 1.
