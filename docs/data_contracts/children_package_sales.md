# Data contract: «Продажа детских пакетов»

Статус: `DESIGNED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-085 / IMPLEMENTATION DEFERRED`.

SV-085 дал source-side evidence physical package row и technical расчётного
ключа. Контракт не реализуется, пока не доказана line-to-line связь с
номенклатурой и суммой, а также source states и знак возврата.

| Параметр | Значение |
|---|---|
| Объект | `mart.children_package_sale` |
| Таблица Power BI | `Продажи детских пакетов` |
| Grain / ключ | строка ребёнка в чеке / `(receipt_id, package_line_no)` |
| Обновление | ежедневно, bounded rebuild BR-003 |
| Режим | Import |

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `receipt_id`, `package_line_no`, `package_line_key` | technical | text/integer/text | key по mapping | ключ/source link | да |
| `sale_at`, `sale_date` | `Дата и время продажи`, `Дата продажи` | timestamp/date | нет | detail/FK даты | нет |
| `receipt_status_id` | `ID статуса чека` | text | нет | filter | да |
| `club_id` | `ID клуба` | text | нет | FK клуба | да |
| `membership_id`, `membership_code`, `membership_name` | `ID абонемента`, `Код абонемента`, `Абонемент` | text | нет | detail | ID |
| `membership_purchase_date`, `membership_activation_date` | `Дата покупки абонемента`, `Дата активации` | date | activation да | detail | нет |
| `adult_client_key/code/name` | `Ключ взрослого`, `Код взрослого`, `Взрослый` | text | нет | PII-detail | key |
| `child_client_key/code/name` | `Ключ ребёнка`, `Код ребёнка`, `Ребёнок` | text | нет | PII-detail | key |
| `product_id`, `product_name` | `ID пакета`, `Пакет` | text | нет | FK/detail | ID |
| `package_amount` | `Сумма пакета` | numeric | нет | показатель | нет |
| `package_count` | `Количество пакетов` | integer | нет | показатель | нет |
| `sold_correctly_flag` | `Продано корректно` | boolean | нет | признак | нет |

Связи календаря, клуба и продукта — `1:*`, single direction. PII доступна по
BR-017. PostgreSQL рассчитывает знаки и корректность; DAX — суммы, количества,
выбор стоимости, динамику и рейтинг.

Реализация заблокирована до доказательства связи `VT4913` с продуктом/суммой,
знака возврата и states. Приёмка также включает уникальность ключа,
reconciliation по чеку, отсутствие дублей, rerun и SLA.
