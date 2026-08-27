# Source-to-target mapping: продажи детских пакетов

Статус: `VALIDATED — Stage 3 product admission 2026-08-27`.

Mapping сохраняет отображаемый contract current Power BI и применяет для
возвратов точный алгоритм переданного 1С-отчёта `ПродажиДопПакетов.erf` по
BR-039. Для 38 строк без доказанной цены/номенклатуры пользователь 2026-08-17
подтвердил fallback `0`; source-артефакт сохранён. Physical rerun,
source-to-target reconciliation и target contract закрыты с нулевым
отклонением; подробные execution values — в Stage 3 admission evidence.

## Active Stage 3 mapping — BR-039

Этот раздел имеет приоритет над историческим SV-085 mapping ниже. Он
воспроизводит одновременно current-Power-BI eligibility взрослого абонемента
и return branch отчёта 1С; `BR-037` в нём не используется.

| Target | Source / transformation | NULL | Status / control |
|---|---|---|---|
| `report_row_id` | MD5 canonical raw values final `DISTINCT` output BR-039 | нет | VALIDATED full: duplicate = 0 |
| `sale_at`, `sale_date` | `AccumRg7646.Fld7647 → Document346.Date_Time`, calendar date | нет | CONFIRMED ERF / current PBI horizon |
| `source_sale_club_id`, `source_sale_employee_id` | `Document346.Fld4895/Fld4909` | да | CONFIRMED ERF; hidden output-key fields |
| `club_id`, `club_name` | `VT4913.Fld4915 → Reference59.Fld687 → Reference132` | ID нет; name да | CONFIRMED current PBI; 28 name orphans preserved |
| membership fields | `VT4913.Fld4915 → Reference59` | нет | CONFIRMED; PBI filters `end > start`, activation and adult non-null |
| adult fields | `AccumRg7646.Fld7648 → Reference141X1` | нет | CONFIRMED ERF; 4 mismatches prohibit membership substitution |
| child fields | `VT4913.Fld4916 → Reference141X1` | нет | VALIDATED full: orphan = 0 after scope |
| product fields | `AccumRg7646.Fld7649 → Reference163` | нет | CONFIRMED ERF; 54 mismatches prohibit stock substitution |
| `package_amount`, `package_amount_without_discount`, `package_count`, `movement_kind` | exact `CASE` of `ПродажиДопПакетов.erf` from `Fld7657/7659/7660` and matched stock amount/quantity | нет | VALIDATED source output: 123 returns / −227 500 |
| `sold_correctly_flag` | month(sale date) = month(`Reference59.Fld674`) | нет | CONFIRMED current report rule; null/sentinel = 0 |

Final source set filters `child_ref IS NOT NULL`, so the 598 no-child rows of
the external-report intermediate output do not become a mart fact by BR-038.

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

Одна строка — результат переданного 1С-отчёта после его двух `DISTINCT`:

> movement `AccumRg7646` × child-package row, соединённые по
> `ДокументПродажи × Контрагент`; child row предварительно связана со строкой
> запасов строго по `receipt_id × КлючСтроки`.

Это намеренно не line-level allocation возврата: так устроен подтверждённый
отчёт 1С (BR-039). После current-PBI filters в месяце `2025-08` он дал 2 001
output row с ребёнком, включая 1 возврат; full BR-003 current snapshot —
19 412 rows с ребёнком, включая 123 возвратных. Технический deterministic key
конечного output validated: duplicate = 0; все columns final extract имеют
mapped source/type/NULL-policy/control.

## Исторический SV-085 mapping (не используется в реализации BR-039)

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
| `package_count` | количество строки output со знаком | точный `CASE` `ПродажиДопПакетов.erf`: сверить `AccumRg7646.Fld7657` и `VT4924.Fld4930`; для `Fld7660 < 0` умножить итог на `-1` | `numeric` | нет | CONFIRMED BR-039 / output-key validation pending | return and multiplicity reconciliation |
| `sold_correctly_flag` | продажа в том же месяце и году, что приобретение взрослого абонемента | `date_trunc('month', sale_at) = date_trunc('month', Reference59.Fld674)`; активация не участвует | `boolean` | нет | CONFIRMED — report description | null/sentinel purchase date |

## Отбор

Текущий фильтр:

- чек с `Document346.Fld4910 = 859cb45b51f9e02c4fb16764c804af3d`;
- действительный интервал взрослого абонемента `Fld672 > Fld671`;
- активация не `NULL`;
- взрослый клиент не `NULL`;
- тип номенклатуры `Дополнительный клиент`;
- дата чека от `2025-06-01`.

Целевой период следует общей календарной политике. Возврат не исключается:
его сумма и количество считаются точным `CASE` `ПродажиДопПакетов.erf` по
BR-039. `AccumRg7739` не является источником знака возврата в этой витрине.
Статус, sentinel, проведение и output-key проверяются на источнике.

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

## Открытые technical controls

1. `VALIDATED`: BR-039 снимает прежний `DECISION_REQUIRED` по
   line-level allocation. Распаковка `.erf` подтвердила фактический report join
   `ДокументПродажи × Контрагент`, без line/product/party matching. Попытка
   «улучшить» его через партию неэквивалентна: на месяце 548 из 2 000 child
   lines всё ещё делят один movement key. Full ERF control доказал стабильный
   `DISTINCT` output-key (duplicate = 0); exact report multiplicity сохраняется,
   а не преобразуется в line allocation.
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
