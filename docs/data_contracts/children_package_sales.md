# Data contract: «Продажа детских пакетов»

Статус: `VALIDATED — BR-039`.

Контракт сохраняет current-Power-BI scope взрослого абонемента и календарную
политику BR-003. Возвратная строка повторяет переданный 1С-отчёт
`ПродажиДопПакетов.erf`; Power BI в этом пакете не меняется (BR-036).

| Параметр | Значение |
|---|---|
| Объект | `mart.children_package_sale` |
| Таблица Power BI | `Продажи детских пакетов` |
| Grain | distinct output `ПродажиДопПакетов.erf` с ребёнком, после current-PBI filters взрослого абонемента |
| Ключ | `report_row_id`: MD5 нормализованных raw output-values; full source control: duplicate = 0 |
| Обновление | daily full bounded rebuild по BR-003; не incremental SLA |
| Режим | Import; switch в Power BI — после всех витрин по BR-036 |

| PostgreSQL | Power BI | Тип | NULL | Роль | Скрыть |
|---|---|---|---|---|---|
| `report_row_id` | technical | text | нет | primary key | да |
| `sale_at`, `sale_date` | `Дата и время продажи`, `Дата продажи` | timestamp/date | нет | detail/FK даты | нет |
| `source_sale_club_id` | technical | text | да | сохраняет distinct report output | да |
| `source_sale_employee_id` | technical | text | да | сохраняет distinct report output | да |
| `club_id`, `club_name` | `ID клуба`, `Клуб` | text | id нет; name да | PBI разрез основного клуба доступа абонемента | ID да |
| `membership_id`, `membership_code`, `membership_name` | `ID абонемента`, `Код абонемента`, `Абонемент` | text | нет | detail | ID да |
| `membership_purchase_date`, `membership_activation_date` | `Дата покупки абонемента`, `Дата активации` | date | purchase нет; activation нет | detail | нет |
| `membership_start_date`, `membership_end_date` | technical | date | нет | source-output key | да |
| `adult_client_id`, `adult_client_code`, `adult_client_name` | `Ключ взрослого`, `Код взрослого`, `Взрослый` | text | нет | adult из движения 1С | ID да |
| `child_client_id`, `child_client_code`, `child_client_name` | `Ключ ребёнка`, `Код ребёнка`, `Ребёнок` | text | нет | detail | ID да |
| `product_id`, `product_name` | `ID пакета`, `Пакет` | text | нет | product из движения 1С | ID да |
| `package_amount` | `Сумма пакета` | numeric(15,2) | нет | signed measure BR-039 | нет |
| `package_amount_without_discount` | technical | numeric(15,2) | нет | source-output key | да |
| `package_count` | `Количество пакетов` | numeric(15,3) | нет | signed measure BR-039 | нет |
| `sold_correctly_flag` | `Продано корректно` | boolean | нет | sale month = membership purchase month | нет |
| `movement_kind` | technical | text | нет | `Приход` / `Расход` source trace | да |

`club_id` сохраняется из `Reference59.Fld687`, как в current Power BI; 28
source rows не находят name в `Reference132`, поэтому `club_name` nullable и
строка не отбрасывается. Adult/product из movement нельзя заменять данными
абонемента/запаса: full control зафиксировал соответственно 4 и 54
расхождения. Связи календаря, клуба и продукта проектируются `1:*`, single
direction; PII остаётся под BR-017.

Immutable extract, independent source controls, source plans, atomic rerun,
source-to-target reconciliation и target read-plan завершены с нулевым
отклонением. Power BI connection/relationships остаются
`VALIDATION_PENDING` по BR-036.
