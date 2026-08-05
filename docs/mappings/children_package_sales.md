# Source-to-target mapping: продажи детских пакетов

Статус: `BUSINESS RULES CONFIRMED / TECHNICAL VALIDATION REQUIRED`.

Mapping основан на текущем SQL/M/DAX, metadata и решениях пользователя от 2026-07-24. `mart.children_package_sale` спроектирован в ADR-0019; реализация заблокирована до проверки связи строки с суммой/номенклатурой, возврата и source states.

## Подтверждённая гранулярность

Одна строка:

> один дополнительный пакет одного ребёнка из строки `Document346.VT4913`; две строки детей в одном чеке считаются двумя пакетами.

Кандидат логического ключа:

> `(receipt_id, additional_package_line_no)`.

## Предварительные целевые поля

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип PostgreSQL | NULL | Статус | Проверка до SQL |
|---|---|---|---|---|---|---|
| `receipt_id` | стабильный чек | `Document346.ID` | UNKNOWN | нет | CONFIRMED source | уникальность |
| `package_line_no` | номер строки дополнительного пакета | `Document346.VT4913.LineNo4914` | UNKNOWN | нет | CONFIRMED metadata | уникальность в чеке |
| `package_line_key` | ключ связи со строкой чека | `Document346.VT4913.Fld4917` | UNKNOWN | да | CONFIRMED metadata | связь с `VT4924.Fld4929` |
| `sale_at` | дата и время продажи | `Document346.Date_Time` | UNKNOWN | нет | CONFIRMED source | timezone |
| `sale_date` | календарная дата продажи | `Document346.Date_Time::date` | `date` | нет | CONFIRMED BY DESIGN | timezone |
| `receipt_status_id` | статус чека для отбора | `Document346.Fld4910` | UNKNOWN | нет | current filter | бизнес-наименование GUID |
| `club_id` | основной клуб доступа взрослого абонемента | `Reference59.Fld687` | UNKNOWN | нет | CONFIRMED — user decision | orphan rows |
| `membership_id` | взрослый абонемент | `VT4913.Fld4915` | UNKNOWN | нет | CONFIRMED source | orphan rows |
| `membership_code` | код взрослого абонемента | `Reference59.Code` | `text` | нет | CONFIRMED need | дубли |
| `membership_name` | название взрослого абонемента | `Reference59.Description` | `text` | нет | CONFIRMED need | переименования |
| `membership_purchase_date` | дата приобретения абонемента | `Reference59.Fld674::date` | `date` | нет | CONFIRMED source | sentinel/null |
| `membership_activation_date` | дата активации/оплаты | `Reference59.Fld670::date` | `date` | да | CONFIRMED need | sentinel/null |
| `adult_client_key` | стабильный взрослый | `Reference59.Fld681` | UNKNOWN | нет | CONFIRMED source | orphan rows |
| `adult_client_code` | код взрослого | `adult.Reference141X1.Code` | `text` | нет | CONFIRMED need | PII access |
| `adult_client_name` | ФИО взрослого | `adult.Reference141X1.Description` | `text` | нет | CONFIRMED need | PII access |
| `child_client_key` | стабильный ребёнок | `VT4913.Fld4916` | UNKNOWN | нет | CONFIRMED source | orphan rows |
| `child_client_code` | код ребёнка | `child.Reference141X1.Code` | `text` | нет | CONFIRMED need | PII access |
| `child_client_name` | ФИО ребёнка | `child.Reference141X1.Description` | `text` | нет | CONFIRMED need | PII access |
| `product_id` | номенклатура пакета | `AccumRg7739.Fld7743` либо `VT4924.Fld4932` | UNKNOWN | нет | VALIDATION_PENDING — implementation blocker | доказать приоритет и связь |
| `product_name` | название пакета | `Reference163.Description` | `text` | нет | CONFIRMED need / source pending | стабильный product ID |
| `package_amount` | итоговая стоимость строки; возврат отражается отрицательной суммой | `AccumRg7739.Fld7749` либо `VT4924.Fld4938` | `numeric` | нет | CONFIRMED rule / source VALIDATION_PENDING — implementation blocker | связь строки, скидки, знак возврата |
| `package_count` | одна продажная строка ребёнка — один пакет; возврат использует доказанный знак движения источника | `1` для подтверждённой продажи; знак возврата из `AccumRg7739.Fld7748` либо иного доказанного признака | `integer` | нет | CONFIRMED grain / source VALIDATION_PENDING — implementation blocker | количество > 1, знак возврата |
| `sold_correctly_flag` | продажа в том же месяце и году, что приобретение взрослого абонемента | `date_trunc('month', sale_at) = date_trunc('month', Reference59.Fld674)`; активация не участвует | `boolean` | нет | CONFIRMED — report description | null/sentinel purchase date |

## Отбор

Текущий фильтр:

- чек с `Document346.Fld4910 = 859cb45b51f9e02c4fb16764c804af3d`;
- действительный интервал взрослого абонемента `Fld672 > Fld671`;
- активация не `NULL`;
- взрослый клиент не `NULL`;
- тип номенклатуры `Дополнительный клиент`;
- дата чека от `2025-06-01`.

Целевой период следует общей календарной политике. Возврат не исключается: его сумма должна поступать со знаком минус. Статус, sentinel, проведение и технический признак возврата проверяются на источнике.

## Power BI

Имя факта: `Продажи детских пакетов`.

Пользовательские поля и меры называются по-русски. Технические ключи скрываются.

Один факт используется обеими страницами. Для сводной страницы:

- общее количество = `SUM(package_count)` с удалением только фильтра стоимости;
- общая сумма = `SUM(package_amount)` с удалением только фильтра стоимости;
- выбранное количество и сумма учитывают весь набор выбранных стоимостей;
- динамика и рейтинг клубов используют тот же факт.

## Не переносить

- даты рождения;
- вычисленные возрасты;
- телефон взрослого;
- SMS-согласие;
- полный чек и все его табличные части;
- полный регистр расчётов с контрагентами.

## Возможное повторное использование

До разбора остальных отчётов не создавать универсальный факт продаж. Проверить общий grain и правила с отчётами поступлений, рецепции, ДПФУ и сводной выручки.

## Блокеры

1. Доказанная связь `VT4913` с `AccumRg7739`/`VT4924`.
2. Стоимость после скидок и несколько строк номенклатуры.
3. Технический признак и знак количества возврата.
4. Бизнес-наименование статуса чека и состояния проведения/удаления/архивности/активности.
5. Контрольные значения.

## Обновление

Частота: один раз в день (`CONFIRMED — user decision 2026-07-24`). Изменяемое окно и способ загрузки будут выбраны при общей архитектуре повторно используемых фактов.
