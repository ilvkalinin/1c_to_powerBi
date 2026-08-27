# Source-to-target mapping: продажи детских пакетов

Статус: `BUSINESS RULES CONFIRMED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-085; Stage 3 deferred`.

Mapping основан на текущем SQL/M/DAX, metadata и решениях пользователя от 2026-07-24. Для 38 строк без доказанной цены/номенклатуры пользователь 2026-08-17 подтвердил fallback `0`; source-артефакт сохранён. `mart.children_package_sale` спроектирован в ADR-0019; реализация по-прежнему требует проверки возврата и source states.

## Stage 2 evidence — SV-085

SV-076: `VT4913` содержит 46 470 unique physical rows; каждая имеет
совпавшие чек и контракт, но 9 933 child-ссылки не совпали с
`Reference141X1`. SV-083: bounded 100 `AccumRg7739` rows равны technical keys
и не имеют orphan-contract. SV-095 нашёл 38 package rows без строки
`VT4924`; fallback `AccumRg7739` по чеку × контракту × ребёнку отсутствует.
Для этих 38 строк согласован fallback `product_id = '0'`,
`product_name = '0'`, `package_amount = 0`; для остальных строк сохраняется
источник `VT4924`. Это закрывает именно gap покрытия цены/номенклатуры, но не
доказывает отдельные правила возврата и source states.

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
| `product_id` | номенклатура пакета | `VT4924.Fld4932`; для отсутствующей строки `VT4924` → `'0'` | `text` | нет | CONFIRMED user fallback 2026-08-17 | SV-095 coverage |
| `product_name` | название пакета | `Reference163.Description`; для отсутствующей строки `VT4924` → `'0'` | `text` | нет | CONFIRMED user fallback 2026-08-17 | SV-095 coverage |
| `package_amount` | итоговая стоимость строки; возврат отражается отрицательной суммой | `VT4924.Fld4938`; для отсутствующей строки `VT4924` → `0` | `numeric` | нет | CONFIRMED user fallback 2026-08-17 | SV-095 coverage; возврат отдельно |
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

1. `DECISION_REQUIRED`: return movements `AccumRg7646` подтверждены только на
   группе чек × взрослый × номенклатура; в fresh snapshot 5 712 child-package
   lines находятся в multi-line sales-group, поэтому знак нельзя распределить
   на `VT4913` child-line
   без нового бизнес-правила. `LIMIT 1` и произвольное распределение запрещены.
   Проверка технических полей за репрезентативный месяц не расширила ключ:
   `AccumRg7646.LineNo` не совпадает с line ребёнка глобально, а
   `VT4913.Fld9108` по metadata означает «ТипДополненияАбонемента» и не может
   служить ключом для полей регистра «Партия», «Договор» или «Абонемент».
   Формальное совпадение их `bytea`-значений не является relationship evidence.
2. `VALIDATED`: в fresh BR-003 snapshot все 19 284 строки current legacy
   status `859cb45b51f9e02c4fb16764c804af3d` проведены и не помечены на
   удаление; все 18 387 соответствующих движений `AccumRg7646` имеют
   `_active = true`. Бизнес-наименование status GUID остаётся `UNKNOWN`, но
   не является пользовательским полем и не требует нового фильтра.
3. Контрольные значения: baseline фиксируются на одном source snapshot до
   любой возможной load; текущие значения приведены в Stage 3 admission evidence.

## Пул возможных методических доработок

`SV-095` сохраняет 38 строк, для которых источник не дал строки
`VT4924` и не подтвердил fallback в `AccumRg7739`. В первом релизе для них
применяется согласованный fallback `0`; при появлении физического источника
цены/номенклатуры его нужно сверить с этими строками отдельным control, не
меняя историческое правило без нового решения.

## Обновление

Частота: один раз в день (`CONFIRMED — user decision 2026-07-24`). Изменяемое окно и способ загрузки будут выбраны при общей архитектуре повторно используемых фактов.
