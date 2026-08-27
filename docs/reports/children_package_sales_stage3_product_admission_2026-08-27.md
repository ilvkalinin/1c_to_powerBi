# Авторизация Stage 3: продажи детских пакетов

- Дата: 2026-08-27
- Пакет: `children_package_sales_product_admission_2026-08-27`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: `children_package_sales`
- Основание: явное поручение пользователя «ну давай детские пакеты» после
  закрытия предыдущего Stage 3 пакета.
- Текущий technical status: `VALIDATION_IN_PROGRESS`; DDL/DML/COPY не
  начинались.

## Разрешённый scope

Для `mart.children_package_sale` выполнить полный product-admission: reuse
review, проверку старых technical gaps (возвраты и source states) в рамках
admission-preflight, immutable mapping/ADR/data contract, measured source
sample/full plans, source controls, DDL, atomic bounded load, reconciliation,
rollback strategy и rerun. Все детские пакеты принадлежат типу `Дети` согласно
пользовательскому правилу BR-038; это не меняет grain отчёта и не добавляет
Power BI-логику. Power BI и источник 1С не изменяются.

DDL/DML/COPY допускаются только после закрытия всех mapped-column, key,
cardinality, return/state и plan checks в этом документе. Если current SQL не
даёт доказанного источника знака возврата или states, это `BLOCKER`, а не
основание для inventing filter/amount rule.

## Admission blocker: возврат по строке ребёнка

Read-only admission control на BR-003 горизонте ранее вернул 19 265, а fresh
source snapshot текущего запуска — 19 284 current-sale строк и точную `1:1`
связь `VT4913._fld4917 → VT4924._fld4929`. В `VT4924` нет отрицательных
amount/quantity ни в одном status чека. Подтверждённые return
движения живут в `AccumRg7646` только на группе `исходный чек × взрослый ×
номенклатура`: для 5 712 строк fresh snapshot приходится multi-line
sales-group.
Следовательно, существующее evidence не определяет, как отнести возврат к
одному ребёнку. Arbitrary allocation и `LIMIT 1` запрещены. До явного правила
target grain/return attribution DDL/DML/COPY не выполняются.

BR-037 full-horizon control в fresh snapshot: 19 284 child-package lines, из
них 18 700 имеют положительный net sales-group, 532 — неположительный и 52 не
имеют sales-group; 5 712 строк находятся в multi-line group. Ранние значения
19 265 / 18 683 / 530 / 52 / 5 719 принадлежат предыдущему source snapshot и
не смешиваются с текущим. Правило BR-037 может безопасно
исключить неположительные lines из набора действующих пакетов, но не создаёт
отрицательную строку для отчёта продаж.

### Проверка технического ключа возврата — `VALIDATION_IN_PROGRESS`

На репрезентативном месяце `2025-08-01..2025-09-01` (2 000 candidate lines)
проверена утверждённая BR-037 связь с `AccumRg7646`: взрослый для sales-group
берётся из `Reference59.Fld681`, а не из `VT4913.Fld4915` (это ссылка на
абонемент). Read-only агрегированный test выполнился за 4.03 s; он не
передавал строк в mart и не создавал объекты.

Сопоставление ключа строки теперь использует `(receipt_id, LineNo4914)`, а не
неглобальный `VT4913.KeyField`. В sales-group попали 1 998 строк месяца.
`Accumulator.LineNo` совпал с номером child/stock line только для 50 строк, а
совпадение recorder + line — только для 5 строк; следовательно, эти technical
поля не являются доказанным line-level ключом. Поле `VT4913.Fld9108` формально
совпало с несколькими полями регистра почти во всех строках; до проверки
ненулевых значений оно имеет статус `UNKNOWN`, поскольку совпадение может быть
служебным zero GUID.

Локальная metadata дополнительно исключает трактовку этого совпадения как
relationship: `VT4913.Fld9108` — «ТипДополненияАбонемента», тогда как
`AccumRg7646.Fld7650/Fld7654/Fld7655` — соответственно «Партия», «Договор» и
«Абонемент». Совпадение одинакового technical типа `bytea` между разными
бизнес-сущностями не доказывает line-level attribution.

Воспроизводимый контроль сохранён в
`sql/marts/children_package_sale_source_controls.sql`. При следующем доступном
read-only snapshot он обязан воспроизвести current baseline: 19 284 lines и
logical keys, 0 строк без product из `VT4924`, 0 отрицательных stock lines, 52
lines без sales-group, 532 lines с неположительной sales-group и 5 712 lines в
sales-group с несколькими child lines. Любое отклонение от этих контрольных
значений фиксируется отдельно и не маскируется загрузкой. Эти values относятся
к конкретному source snapshot и переизмеряются перед любой будущей нагрузкой.

Первый контроль ненулевых technical values на месячном sample `2025-08`
подтвердил, что `VT4913.Fld9108` заполняется zero GUID, но не принимается как
admission evidence: в его пробном SQL стоял `Reference59.Fld674 IS NOT NULL`
вместо current-M фильтра `Reference59.Fld670 IS NOT NULL`. На full-range
проверке пробный набор составил 19 284 вместо раннего 19 265. После исправления
на current-M `Fld670` fresh snapshot также вернул 19 284; следовательно,
разницу 19 строк нельзя приписывать этой одной ошибке фильтра. Нужное
сопоставление source snapshots отсутствует, поэтому причина расхождения
остаётся `UNKNOWN`. Ни результат, ни plan ошибочной области не используются
для mapping, control values или load. Исправленный control повторил
последовательность месяц → full range; data transport и DML отсутствовали.

Тесты выполняются через потенциально нестабильный корпоративный VPN: каждый
control — короткая fresh read-only session с bounded retry; прерванная сессия
не переиспользуется и её результат не принимается частично. Правило будущих
batch/COPY зафиксировано в `.agents/playbooks/safety.md`.

### Performance review source control — `VALIDATION_IN_PROGRESS`

Первый exact full-range plan для source control завершился за 4.639 s, но
показал 45 715 temporary blocks: planner строил hash из всего
`AccumRg7646` (около 4.9 млн движений), хотя набор sale keys значительно
меньше. До транспорта control переписан на tuple `IN (sale_keys)`, чтобы
использовать semi-join и строить hash по малому keyset. На месяце `2025-08`
значения остались идентичны (2 000 lines, 2 без sales-group, 15
неположительных, 550 multi-line), время — 1.879 s, temporary blocks — 0.
Fresh full-range plan после оптимизации: 2.540 s, `temp read/written = 0`;
один последовательный scan `AccumRg7646` прочитал 4 915 291 движение. Он
не требует индекса для этого admission control: measured time укладывается в
3 s, а новый индекс на read-only source не создаётся.

### Source states — `VALIDATED`

Независимый receipt-state control без предфильтра `Posted/Marked` на месяце
`2025-08` вернул ровно 2 000 строк (`Posted = true`, `Marked = false`) за
86.873 ms; full-range control вернул ровно 19 284 строк с теми же state за
625.352 ms, без temporary blocks. Full BR-037 movement-state control вернул
18 387 движений и 16 206 sales-groups; у каждого движения `_active = true`
(`temp written = 0`, 2.825 s). Поэтому `Posted`, `Marked` и `_active` не
являются новым способом интерпретировать возврат: они лишь подтверждают
состояние набора, а знак по-прежнему берётся только из net sales-group.
Бизнес-наименование legacy status GUID не установлено, но это технический
отбор, а не поле контракта отчёта.

Следующий read-only control для ненулевых значений не стартовал: источник
отклонил все 6 попыток TCP admission с `Operation not permitted` до открытия
сессии. Это не даёт основания считать связь подтверждённой или менять
return-rule; при восстановлении доступа проверка продолжится с тем же месяцем.
Отдельная короткая probe после этого также не открыла сессию. Внешняя причина
доступа не установлена: это может быть сетевой маршрут/VPN либо ограничение
исполняющей среды; данных для утверждения одной из причин нет.

После восстановления доступа последующая read-only probe успешно открыла
сессию. Проверка return-attribution продолжена с сохранённого месячного
sample; прежний transport/DML blocker снят только для этой read-only стадии.

## Критерий закрытия

Нулевые source/stage/target independent deviations, доказанный знак возврата
и states, ключ и contract/horizon/future-date controls, measured source and
target plans, successful atomic rerun и отсутствие изменений Power BI.
