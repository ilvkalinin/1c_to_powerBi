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
| tenure | `InfoRg5654.Period`; ASOF-V05: 0 tied `(client, period)` groups in the 151,573-client current cohort | `VALIDATED` for a deterministic effective-period order; correction/audit history is still not evidenced |
| rating | `InfoRg6861.Period`; ASOF-V05: 0 tied `(client, period)` groups in the same cohort | `VALIDATED` for a deterministic effective-period order; current no-Active behaviour remains unchanged |
| interaction timestamp/type | `Reference67.Fld820` (started) и `Fld823` (created); ASOF-V06: both non-null in 1,483,951 eligible rows, but 45,719 have `created > started` | `CONFIRMED` current timestamp; user says either timestamp is acceptable, so the first release preserves current-M `Fld820` (started). `BLOCKER` only for historical task funnel/fail state: no temporal state source is confirmed. |
| next contract | current selector uses same-client dates and BR-050; ASOF-V07 confirms four current timestamp columns but no history semantics | `BLOCKER` for claiming a past known-at next contract: no creation/audit or backdating/correction history is confirmed. |
| cohort contract attributes | `Reference59` current record | `BLOCKER` for claiming historical 2025 universe without version/source-history evidence |

## Stage 2 control list (executed 2026-08-29)

- ASOF-V01: `VALIDATED` — 240,967 current rows, all unique non-null contract IDs.
- ASOF-V02: `VALIDATED` for the upstream comparison key; the future uniqueness
  constraint and transition tests remain Stage 3 acceptance because no object exists.
- ASOF-V03: `VALIDATED DESIGN PREREQUISITE` — source drift (240,965 source
  cohort vs 240,967 committed target) confirms that an observation may only read
  the committed parent target; end-to-end failure ordering is Stage 3 acceptance.
- ASOF-V04: `VALIDATION_PENDING` — observation relation correctly absent in
  Stage 2; selector/`REMOVED` test requires the approved physical object.
- ASOF-V05: `VALIDATED` — zero rating and tenure same-period ties in scope.
- ASOF-V06: `BLOCKER` for retrospective funnel/fail state only; forward
  observation remains valid and preserves the current-M started timestamp.
- ASOF-V07: `BLOCKER` for retrospective next-contract/cohort claims; current
  timestamp fields do not prove record-known-at or correction history.

Exact SQL and aggregate results: [Stage 2 execution](../reports/renewal_management_as_of_snapshot_stage2_execution_2026-08-29.md).
