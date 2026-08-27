# Авторизация Stage 3: продажи детских пакетов

- Дата: 2026-08-27
- Пакет: `children_package_sales_product_admission_2026-08-27`
- Этап: `STAGE_3_PRODUCT_ADMISSION`
- Отчёт: `children_package_sales`
- Основание: явное поручение пользователя «ну давай детские пакеты» после
  закрытия предыдущего Stage 3 пакета.
- Текущий technical status: `VALIDATED`; source preflight, bounded atomic rerun,
  reconciliation и target read-plan завершены.

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

## Возвратный source path: BR-039, `READY_FOR_INITIAL_LOAD`

Пользователь 2026-08-27 уточнил, что витрина должна работать как Power BI, а
переданный отчёт 1С «Продажи доп пакетов» учитывает возвраты. Его локальная
распаковка подтвердила точный алгоритм: `AccumRg7646.Fld7660 < 0` означает
`Расход`; значение количества и стоимости меняет знак по `CASE` отчёта.
Строка запасов связана с child-package строкой по `КлючСтроки`, но final join
отчёта — `ДокументПродажи × Контрагент`, без line/product/party allocation.
Это принято как report-grain BR-039; BR-037 остаётся только reuse-правилом
действующих пакетов и не участвует в extract продаж.

Measured `EXPLAIN (ANALYZE, BUFFERS)` exact source control:

| Scope | Rows with child | Return rows | Return amount | Time | Temp blocks |
|---|---:|---:|---:|---:|---:|
| `2025-08-01..2025-09-01` | 2 001 | 1 | −1 000 | 620.745 ms | 0 |
| BR-003 `[2025-01-01, 2026-08-28)` | 19 412 | 123 | −227 500 | 1,756.905 ms | 0 |

598 full-range intermediate rows не имеют ребёнка; по BR-038 они исключаются
из `mart.children_package_sale`. Никакие данные не передавались и DDL/DML/COPY
не выполнялись.

Финальный immutable extract повторно прошёл обязательную последовательность
месяц → полный горизонт: `2025-08` — 2 001 строк, 634.512 ms,
115 527 shared-hit blocks; полный горизонт — 19 412 строк, 1 756.905 ms,
1 549 154 shared-hit blocks. В обоих планах `shared read = 0` и
`temp written = 0`; transport параллельно с plan не запускался. Independent
source control текущего snapshot: 19 412 строк, 123 `Расход`, количество
19 168, сумма 23 492 000, возврат −227 500, `report_row_id` duplicates = 0,
обязательные reference orphans = 0 и 28 nullable `club_name`.

## Reviewed immutable implementation set

- [extract](../../sql/marts/children_package_sale_extract.sql);
- [independent source control](../../sql/marts/children_package_sale_erf_source_control.sql);
- [DDL](../../sql/marts/children_package_sale_ddl.sql);
- [loader](../../scripts/load_children_package_sale.py): один temporary binary
  COPY-файл на месяц, fresh source-reader из exported snapshot на batch,
  180-second limit, bounded retry, target transaction/advisory lock/rollback;
- [reconciliation](../../sql/tests/children_package_sale_reconciliation.sql)
  и [target controls](../../sql/tests/children_package_sale_target_controls.sql).

Initial path создаёт таблицу и temporary target stage в одной транзакции.
Rerun применяет `DELETE + INSERT` в той же транзакции: ошибка возвращает
прежнее содержимое; persistent raw/stage на VM-2 не создаётся. Индексы в этом
пакете не создаются по явному решению пользователя. Historical preflight
предполагал отсутствующую таблицу; фактическое pre-execution inventory и
последующий atomic rerun зафиксированы в execution evidence ниже.

## Superseded return-allocation investigation

Предыдущий read-only control на BR-003 горизонте вернул 19 265, а fresh
source snapshot текущего запуска — 19 284 current-sale строк и точную `1:1`
связь `VT4913._fld4917 → VT4924._fld4929`. В `VT4924` нет отрицательных
amount/quantity ни в одном status чека. Подтверждённые return
движения живут в `AccumRg7646` только на группе `исходный чек × взрослый ×
номенклатура`: для 5 712 строк fresh snapshot приходится multi-line
sales-group.
Он не определял, как отнести возврат к одной `VT4913`-строке. Это не является
blocker после BR-039: arbitrary allocation и `LIMIT 1` по-прежнему запрещены,
но повторяется именно report-grain 1С. До output-key/PBI-field controls
DDL/DML/COPY всё ещё не выполняются.

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

### Return-recorder trace — `VALIDATED / LINE KEY BLOCKED`

У неположительных BR-037 groups есть три типа регистраторов: 403 движения
`Document315` («Отчёт о розничных продажах»), 119 — `Document275`
 («Возврат от покупателя») и 131 — исходный `Document346` (строки могут
входить в одни и те же groups, поэтому эти значения не суммируются). Full
actual plan выполнился за 4.103 s без temporary spill.

`Document275` даёт доказуемую связь возврата только до исходного чека:
119/119 movement rows нашли основной документ, и у 119/119
`ОснованиеВозврата = исходный чек`. Это не идентифицирует ребёнка. Metadata
показывает line-level candidates `Document315.VT3887.ДополнительныеПакеты`
(`ДокументПродажи`, `Клиент`, `КлючСтроки`) и
`Document275.VT3122.Запасы` (`ДокументОснование`, `КлючСтроки`), но обе
физические tabular parts отсутствуют. Отсутствие зарегистрировано только в
`docs/source_metadata/missing_source_objects.md`. Следовательно, ни
`Document275`, ни `Document315` нельзя использовать для распределения
negative amount/count между детьми без нового источника или правила.

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

## Execution evidence — `VALIDATED`

Перед execution read-only inventory обнаружил уже существующую
`mart.children_package_sale`, хотя старый admission text описывал её как
отсутствующую. Её contract совпал с reviewed DDL, а содержимое — 19 412
уникальных строк — уже проходило fresh read-only reconciliation без отклонений.
Происхождение прежней initial load не выдано за доказательство: текущий факт
полностью заменён только reviewed atomic rerun ниже.

`2026-08-27` runner `scripts/load_children_package_sale.py --rerun` открыл
один exported `REPEATABLE READ, READ ONLY` source snapshot, передавал один
месяц за раз единственным temporary binary COPY file и удалял его после каждой
порции. Target transaction взяла advisory lock, собрала temporary stage,
прошла reconciliation до commit и выполнила `DELETE + INSERT`; persistent
raw/stage и индексы не создавались. Rerun: 19 412 строк, 17.264 s.

| Control | Expected / rule | Actual | Status |
|---|---|---:|---|
| `CPS_ROW_COUNT` / `CPS_DISTINCT_KEY` | independent ERF output / unique `report_row_id` | 19 412 / 19 412 | PASS |
| `CPS_RETURN_ROWS` / `CPS_RETURN_AMOUNT` | BR-039 return output | 123 / −227 500.00 | PASS |
| `CPS_QUANTITY` / `CPS_AMOUNT` | independent ERF output | 19 168.000 / 23 492 000.00 | PASS |
| `CPS_MIN_DATE` / `CPS_MAX_DATE` | source snapshot horizon | 2025-01-13 / 2026-08-27 | PASS |
| `CPS_NULLABLE_ACCESS_CLUB_NAMES` | confirmed permitted orphan names | 28 | PASS |
| `CPS_FUTURE_DATES` / `CPS_CONTRACT_VIOLATIONS` | zero | 0 / 0 | PASS |

All 11 pre-commit source-to-stage-to-target controls passed with tolerance 0;
the post-commit read-only target control reproduced the listed values. The
target read probe over the BR-003 horizon took 21.255 ms (`shared hit = 3,800`,
`shared read = 0`); current total relation size is 33,144,832 bytes. This is a
full-rebuild baseline, not an incremental SLA. Power BI/M/DAX/connections were
not changed under BR-036.
