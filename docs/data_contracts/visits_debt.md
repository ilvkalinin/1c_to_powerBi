# Data contract: «Посещаемость клиентов с долгами»

Статус: `IMPLEMENTED COMPOSITE MODEL / STAGE_3 PRODUCT ADMISSION VALIDATED — VD-LOAD-001 / Power BI unchanged`.

SV-089/SV-099/SV-110/DV-V05B подтверждают physical relation, ключ,
`RecordKind`, документные ветки, states/sign и source-side as-of component.
Initial load, rerun и target read-plan выполнены с нулевыми deviations;
evidence — `visits_debt_stage3_execution_2026-08-27.md`. Power BI в этом
пакете не изменяется.

## Движения долга

| Параметр | Значение |
|---|---|
| Объект | `mart.unconfirmed_service_debt_movement` |
| Incremental refresh | `BLOCKED`: нет change watermark/feed, deletion capture и измеренного late-change lag; VD-INC-001—005 |
| Bounded refresh | отдельный config/runner; current + two previous months atomic replace; accepted methodology risk, не incremental SLA; первый прогон 92.673 s |
| Schedule | VM-2 only: on-demand Task Scheduler job prepared, no own trigger, `PT5M`, same-object `IgnoreNew`; current machine is not scheduler host; VM-2 installation/orchestration `BLOCKED / NOT INSTALLED` |
| Таблица Power BI | `Движения задолженности` |
| Grain / key | движение регистра / `(debt_event_at, recorder_type, recorder_id, recorder_line_no)` |

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `debt_event_at` | `Дата и время движения` | timestamp | нет | event/as-of | нет |
| `recorder_type`, `recorder_id`, `recorder_line_no`, `record_kind` | technical | bytea/bytea/integer/smallint | нет | ключ/sign | да |
| `client_key`, `client_code`, `client_name` | `Ключ клиента`, `Код клиента`, `Клиент` | bytea/text/text | code/name да | PII-detail | key |
| `club_id` | `ID клуба` | bytea | нет | FK клуба | да |
| `prebooking_id` | `ID предварительной записи` | bytea | нет | as-of group | да |
| `service_id`, `service_name` | `ID услуги`, `Услуга` | bytea/text | имя да | FK/detail | ID |
| `employee_id`, `employee_name` | `ID сотрудника`, `Сотрудник` | bytea/text | имя да | FK/detail | ID |
| `service_start_at`, `service_end_at` | `Начало услуги`, `Окончание услуги` | timestamp | нет | detail | нет |
| `quantity_delta`, `amount_delta` | `Изменение количества`, `Изменение суммы` | numeric | нет | аддитивные движения | нет |

## Когорта

REUSE `mart.visit_client_day` с `visit_date`, `visit_club_id`, `client_key` и
постоянным вкладом `visit_client_count = 1`. PII в общий факт не добавляется.

Календарь и клуб фильтруют оба факта `1:*`, single direction. Client key не
создаёт физическую M2M relationship; пересечение применяется контролируемой
DAX-логикой/as-of. PostgreSQL квалифицирует движения. DAX считает остатки,
погашение, новые долги, distinct клиентов и посещений. PII — BR-017.

Приёмка: ключ/state/sign, document branches, as-of на контрольных датах,
закрытие каждой ПЗ, client key consistency, отсутствие размножения, rerun и
SLA до 08:30.
