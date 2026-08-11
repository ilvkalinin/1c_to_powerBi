# Data contract: «Отчёт по промокодам»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION BLOCKED — source registry`.

| Параметр | Значение |
|---|---|
| Объект | `mart.promo_application` |
| Таблица Power BI | `Применения промокодов` |
| Grain | одно квалифицированное применение/подарок |
| Ключ | `(source_kind, recorder_id, line_no)` candidate |
| Обновление | ежедневно, bounded rebuild BR-003 |
| Режим | Import |

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `application_date` | `Дата применения` | date | нет | FK даты | нет |
| `source_kind`, `recorder_id`, `line_no` | `Вид источника`, technical | text/text/integer | нет | ключ | IDs |
| `client_key` | `Ключ клиента` | text | нет | distinct | да |
| `club_id`, `club_name` | `ID клуба`, `Клуб` | text | да | FK/detail | ID |
| `membership_id`, `membership_code` | `ID абонемента`, `Код абонемента` | text | да | detail | ID |
| `promo_id`, `promo_name` | `ID промокода`, `Промокод` | text | нет | срез | ID |
| `serial_id`, `serial_name` | `ID серии`, `Серия` | text | да | срез | ID |
| `discount_id`, `discount_name`, `discount_method_id` | `ID скидки`, `Скидка`, `ID способа` | text | да | срез | IDs |
| `discount_amount`, `price_before_discount` | `Сумма скидки`, `Цена до скидки` | numeric | да | показатели | нет |
| `service_id`, `service_name`, `business_direction_id` | `ID услуги`, `Услуга`, `ID направления` | text | да | FK/срез | IDs |
| `gift_id`, `gift_name`, `gift_recipient_client_key` | `ID подарка`, `Подарок`, technical client | text | да | outcome/detail | IDs/client |
| `bought_membership_45d_flag` | `Купил абонемент 1–44 дня` | boolean | нет | признак | нет |
| `bought_dpfu_45d_flag` | `Купил ДПФУ 1–44 дня` | boolean | нет | признак | нет |
| `friend_bought_membership_45d_flag` | `Друг купил абонемент 1–44 дня` | boolean | да | признак | нет |

Календарь, клубы, промокоды, серии, скидки, услуги и направления фильтруют
факт `1:*`, single direction. DAX рассчитывает категории, distinct, доли,
выпуски и filter-dependent конверсии. PostgreSQL рассчитывает fixed outcomes.
PII не входит.

Приёмка: ключ, branch reconciliation, document-line joins, signs/states,
границы 1/44/45, контрольные категории и дни, rerun и SLA.
