# CRM technical validation and exact SQL review

Дата: 2026-08-21. Статус: `ACTIVE`.

Пользователь явно одобрил самостоятельный пакет для подготовки технически
проверенного, но ещё не исполняемого плана реализации `mart.crm_interaction`.

## Scope

- выполнить на VM-1 только bounded read-only metadata/cardinality/type/sentinel
  controls для `Reference67`, `Reference106`, `InfoRg7146`, `InfoRg6291`,
  `Reference137` и необходимых CRM dimensions;
- закрепить physical representation core IDs, nullable/timestamp/marked/archive
  profile, phone/HTML/employment multiplicity, PII boundary и stable guest
  funnel key;
- создать локальные reviewed SQL artifacts для core, трёх views, full rebuild,
  reconciliation, privileges and rollback — без их запуска;
- обновить mapping/data contract/ADR и подготовить один exact implementation
  plan для отдельного пользовательского решения.

## Boundaries

Источник 1С — только `READ ONLY`; source queries ограничивают колонки и
горизонт. Не входят исполнение DDL/DML, создание/изменение любых объектов на
VM-2 или 1С, Power BI, внешние Excel/Google Sheets, расписания и incremental
refresh design.

## Closure criterion

Все material source types/keys/joins/sentinels и PII safeguards подтверждены
либо явно ограничены; immutable local SQL plan содержит объектный состав,
операции create/load/reconciliation/rollback и не имеет unmapped columns.
Файлы готовы ровно к одному последующему implementation approval; ничего на
сервере до него не создаётся и не загружается.

## Read-only result

Control SQL: [CRM technical review](../source_metadata/validation_sql/crm_interaction_technical_sql_review_2026-08-21.sql).
Every source transaction used `REPEATABLE READ READ ONLY` and rolled back.

| Check | Observed result | Status / consequence |
|---|---:|---|
| Core, July-2026 | 342 824 rows = 342 824 distinct IDs; 0 missing tasks | `VALIDATED`: core key is one `Reference67.ID`; task join is mandatory for this period. |
| Source representation | IDs `bytea`; CRM dates `timestamp without time zone`; client phone nullable | `VALIDATED`: target protected IDs are explicit hex `text`; timestamps retain source type. |
| Sentinel / state profile | started 228 834; ended 232 344; planned 124 221; marked/archive 0 | `VALIDATED`: no new source state filter; views keep PBIT sentinel logic. |
| Phone child, bounded sales sample | 1 000 rows = 1 000 `(interaction, phone reference, phone event)` keys; 0 null key parts | `VALIDATED` candidate child key; full-rebuild reconciliation still required. |
| Feedback comments, July | 11 279 HTML rows for 6 326 interactions; 3 961 interactions have >1 comment | `VALIDATED`: comments cannot join directly to core or be discarded. |
| Feedback tie controls | 1 earliest-follow-up tie; 0 same-interaction comment timestamp ties in full July | `VALIDATED`: follow-up needs `(timestamp, physical ID)`; the same comment order is a reproducibility safeguard. |
| Guest funnel | `99a9ebb169a4e2a611eecbf18a73ffa6` resolves exactly once to `Продажа клубной карты` | `VALIDATED`: stable physical filter is available. |

## Reviewed physical design

No SQL below has been executed on VM-2. The next implementation package must
create exactly these objects, after resolving the guest outcome choice below:

| Object | Grain / key | Purpose |
|---|---|---|
| `mart.crm_interaction` | one `interaction_id text` / primary key | CRM core: hex-encoded source IDs, source timestamps and mapped task-side classifications only. |
| `mart.crm_interaction_phone` | `(interaction_id, phone_reference_id, phone_event_id)` / primary key | Preserves direct `InfoRg7146` phone-row multiplicity for sales and guest detail. |
| `mart.crm_interaction_comment` | `(interaction_id, comment_id)` / primary key | Preserves feedback HTML/comments, deterministically ordered by `(comment_updated_at, comment_id)`. |
| `mart.v_sales_interaction` | current PBIT phone-row grain | Three sales roles, existing funnel/Jivo rules and source-side employment `EXISTS`; technical exact duplicates only may be removed. |
| `mart.v_feedback_interaction` | final PBIT business grouping without `interaction_id` | First follow-up ordered by `(created_at, interaction_id)`; comment order as above. |
| `mart.v_guest_tour` | direct phone row, otherwise interaction | Meeting / confirmed funnel / state-status / report-date PBIT rules. ACCUNIQ and contract outcomes stay in Power BI by BR-031. |

The future reviewed implementation script must run one full rebuild: create or
replace the six objects, revoke all privileges from `PUBLIC`, load the three
tables from a single source read-only snapshot, run reconciliation, then grant
only the specifically approved BI role. Rollback is `DROP VIEW` followed by
`DROP TABLE` for the six named new objects; it does not touch 1C or existing
mart objects. Neither an incremental refresh nor an SLA is included.

## Resolved guest outcomes

The approved PBIT preserves two ambiguous source behaviours in the guest-tour
outcome:

- ACCUNIQ keeps all rows tied at the latest prebooking timestamp: the checked
  source had 8 such ties and 128 extra rows relative to `client × visit date`.
- A contract is selected by minimum conversion lag in 0–44 days, but PBIT does
  not specify an ID order when more than one contract shares that minimum lag.

Пользователь 2026-08-21 решил оставить этот результат exactly as current
Power BI: ties и multiplicity не переносятся в PostgreSQL первого релиза.
Поэтому exact reviewed SQL для `v_guest_tour` останавливается на CRM-tour
base; ACCUNIQ/contract branches остаются в текущем PBIT по BR-031. Возможная
доработка — стабильный выбор ACCUNIQ по `(_recordertref, _recorderrref,
_lineno)` после latest timestamp и договора по `Reference59.ID` после minimum
lag — записана в пул, не является частью текущего SQL plan и не меняет отчёт.
