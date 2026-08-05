# Data contract: «Загрузка ОП»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

| Параметр | Значение | Статус |
|---|---|---|
| Core | `mart.crm_interaction` | ADR-0016 |
| Report view | `mart.v_sales_interaction` | ADR-0016 |
| Таблица Power BI | `Взаимодействия с клиентами` | CONFIRMED |
| Grain / ключ | одно `Reference67.ID` / `interaction_id` | CONFIRMED business; technical validation pending |
| Даты | активная `interaction_date`; неактивная `planned_date` | DESIGNED |
| Обновление | `08,10,12,14,16,18,20,22` | CONFIRMED |
| Power BI | Import | DESIGNED |

## Поля report view

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `interaction_id` | `ID взаимодействия` | text | нет | ключ | да |
| `task_id` | `ID задания` | text | нет | task | да |
| `interaction_date` | `Дата взаимодействия` | date | нет | активный FK даты | нет |
| `created_at` | `Дата создания` | timestamp | нет | detail | нет |
| `planned_date` | `Плановая дата` | date | да | неактивный FK даты | нет |
| `duration_seconds` | `Длительность, сек` | integer | да | показатель | нет |
| `answered_flag` | `Есть ответ` | boolean | нет | признак | нет |
| `event_type_id`, `event_type_name` | `ID вида события`, `Вид события` | text | да | срез | ID |
| `interaction_state_id`, `interaction_state_name` | `ID состояния`, `Состояние` | text | да | срез | ID |
| `interaction_status_id`, `interaction_status_name` | `ID статуса`, `Статус` | text | да | срез | ID |
| `manager_id`, `manager_name` | `ID менеджера`, `Менеджер` | text | нет | FK/detail | ID |
| `operator_club_id` | `ID клуба оператора` | text | нет | FK клуба | да |
| `network_name` | `Сеть` | text | нет | срез | нет |
| `client_key`, `client_code`, `client_name`, `client_phone` | `Ключ клиента`, `Код клиента`, `Клиент`, `Телефон` | text | да | PII-detail | key |
| `tenure_type` | `Вид стажа` | text | да | срез | нет |
| `client_status` | `Статус клиента` | text | да | срез | нет |
| `funnel_id`, `funnel_name` | `ID воронки`, `Воронка` | text | нет | срез | ID |
| `campaign_id`, `campaign_name` | `ID кампании`, `Кампания` | text | да | срез | ID |
| `channel_id` | `ID канала` | text | да | FK/срез | да |
| `cancellation_reason` | `Причина отмены` | text | да | detail | нет |
| `interaction_count` | `Количество взаимодействий` | smallint | нет | аддитивный вклад | нет |

Календарь, клуб, менеджер, тип события, воронка и кампания фильтруют факт
`1:*`, single direction. Нормативы остаются внешним Power BI-фактом.
PostgreSQL нормализует телефонию и кадровый отбор; DAX считает среднюю/медиану,
manager-day, нормативные минуты, загрузку и backlog. PII доступна пользователям
отчёта по BR-017.

Приёмка: уникальный `interaction_id`, deterministic phone row, отсутствие
размножения кадровыми интервалами, корректные статусы/воронки, обе роли даты,
контрольные значения и каждый из восьми refresh.

