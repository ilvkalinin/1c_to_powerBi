# Data contract: «Посещаемость клиентов с долгами»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

## Движения долга

| Параметр | Значение |
|---|---|
| Объект | `mart.unconfirmed_service_debt_movement` |
| Таблица Power BI | `Движения задолженности` |
| Grain / key | движение регистра / `(debt_event_at, recorder_id, recorder_line_no)` candidate |

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `debt_event_at` | `Дата и время движения` | timestamp | нет | event/as-of | нет |
| `recorder_id`, `recorder_line_no`, `record_kind` | technical | text/integer/smallint | нет | ключ/sign | да |
| `client_key`, `client_code`, `client_name` | `Ключ клиента`, `Код клиента`, `Клиент` | text | code/name да | PII-detail | key |
| `club_id` | `ID клуба` | text | нет | FK клуба | да |
| `prebooking_id` | `ID предварительной записи` | text | нет | as-of group | да |
| `service_id`, `service_name` | `ID услуги`, `Услуга` | text | да | FK/detail | ID |
| `employee_id`, `employee_name` | `ID сотрудника`, `Сотрудник` | text | да | FK/detail | ID |
| `service_start_at`, `service_end_at` | `Начало услуги`, `Окончание услуги` | timestamp | да | detail | нет |
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
