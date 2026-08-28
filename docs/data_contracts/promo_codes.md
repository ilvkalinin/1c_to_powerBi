# Data contract: «Отчёт по промокодам»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / CARDINALITY DECISION_REQUIRED — PC-V02, PC-V04 rechecked 2026-08-28`.

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

Приёмка Stage 2: physical key, states, 1/44/45 boundaries, source input and
gift-day parser completed in SV-091. Document-line and gift joins have
observed one-to-many risks; legacy result remains unchanged under BR-018.
The 2026-08-28 recheck repeats PC-V02 excess 33 and PC-V04 gift excess 406;
Stage 3 remains deferred and requires a methodology decision on source-side
protection of those joins.
