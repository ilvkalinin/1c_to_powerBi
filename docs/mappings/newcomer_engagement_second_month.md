# Source-to-target mapping: `newcomer_engagement_second_month`

Статус: `MAPPING COMPLETE / STAGE_3 SOURCE CONTROLS VALIDATED — 2026-08-25 / IMPLEMENTATION IN PROGRESS`.
Физический объект — `mart.newcomer_engagement_second_month` по ADR-0009.

Гранулярность одной строки: подходящий контракт × клиент × месяц вовлечения ×
техническая исходная строка. `source_row_id` сохраняет legacy child `RANK()` ties.

Логический ключ KPI: `(contract_id, client_id, month_of_engagement)`.
Физический ключ: `source_row_id` (`main:<contract>:<client>` либо
`child:<receipt>:<line>`).

Единица KPI — пара `клиент × контракт`. Взрослый и ребёнок, привязанные к
одному контракту, считаются раздельно; их посещения и группы не объединяются.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|---|
| `АбонементСсылка` | техническая ссылка контракта | `Reference59` | `ID` | `encode(..., 'hex')` в current SQL | `text` | нет | контракт | VALIDATED 2026-08-25 | full source control | source identity |
| `АбонементКод` | отображаемый код контракта | `Reference59` | `Code` | явное преобразование в текст | `text` | нет | контракт | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `КлиентСсылка` | техническая ссылка клиента | `Reference141X1` | `ID` | `encode(..., 'hex')` | `text` | нет | клиент | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `КлиентКод` | отображаемый код клиента | `Reference141X1` | `Code` | current SQL | `text` | нет | клиент | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `Клиент` | имя клиента для списка | `Reference141X1` | `Description` | current SQL | `text` | нет | клиент | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `ДатаРождения` | дата рождения клиента | `Reference141X1` | `Fld1507` | текущий SQL | `date` | UNKNOWN | клиент | CONFIRMED current query | текущий SQL | sentinel; подтверждение PII |
| `ДатаНачала` | дата начала контракта | `Reference59` | `Fld671`; для детских пакетов также `Document346.Date_Time` | main: `Fld671`; children: maximum eligible `GREATEST(Fld671, Date_Time)` under BR-037 | `date` | UNKNOWN | контракт | CONFIRMED user decision 2026-08-25 | BR-037; reused reviewed child-sales logic | границы; valid sale/return and repeated-sale controls |
| `ДатаВовлечения` | первый день второго календарного месяца | вычисление | `ДатаНачала` | `Date.StartOfMonth(Date.AddMonths(ДатаНачала, 1))` | `date` | нет | контракт | CONFIRMED current M | запрос `АбонементыИсходный` | даты на границах месяца |
| `IDКлубаДоступа` | техническая ссылка клуба доступа | `Reference59` | `Fld687` | `encode(..., 'hex')` | `text` | нет | контракт | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `КлубДоступа` | клуб доступа контракта | `Reference59` → `Reference132` | `Fld687` → `Description` | left join | `text` | нет | контракт | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `ВозрастнаяКатегория` | возрастной разрез | `Reference87`; для детских пакетов константа | `Description` | main: номенклатура → `Reference87`; children: `'Дети'` | `text` | да | контракт | VALIDATED 2026-08-25 | full source control | NULL=998; child=`Дети` |
| `Стаж` | вид стажа контракта | `Reference59`; `InfoRg5654` для детских пакетов | `Fld694`; `Fld5656` | GUID → `New`/`Ex`/`Renew`; для отсутствия history — `New` | `text` | нет | контракт | VALIDATED 2026-08-25 | full source control | NULL=0 |
| `КоличествоПосещений` | число посещений во втором календарном месяце | `AccumRg7575` | `Period`, `Fld7576`, `Fld7578`, `Fld7579` | `COUNT` строк при связи контракт + клиент и интервале второго месяца | `bigint` | нет (`0`) | контракт × клиент | CONFIRMED user decision | `ПосещенияНовичков_Агрегат`; решение пользователя 2026-07-28 | техническая сверка без изменения правила |
| `ПоследнийВизит` | последняя дата посещения во втором календарном месяце | `AccumRg7575` | `Period` | `MAX(Period::date)` в том же интервале | `date` | да | контракт × клиент | CONFIRMED current query | `ПосещенияНовичков_Агрегат` | interval; future dates |
| `ГруппаПосещений` | категория посещений | вычисление | `КоличествоПосещений` | `0`, `1`, `2`, `3`, `4+` | `text` | нет | контракт × клиент | CONFIRMED current M | `Абонементы` | границы 0–4+ |
| `ПрошелСПТ` | признак прохождения стартовой тренировки | `InfoRg7006`, `Document329`, `Document325`, `Reference59` | несколько полей | совпадение клиента и даты занятия/посещения, затем contract as-of | `text` | нет (`Не прошел`) | контракт × клиент | CONFIRMED user decision | `СПТ_Уникальные`; решение пользователя 2026-07-28 | техническая сверка без изменения правила |
| `source_row_id` | скрытая physical identity | `Reference59`; для child `Document346.VT4913` | contract/client либо receipt/line | `main:<contract>:<client>`; `child:<receipt>:<line>` | `text` | нет | исходная строка | CONFIRMED design | BR-018; source control 2026-08-25 | uniqueness |

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference59` | контракт, даты, клуб, стаж, клиент, номенклатура | CONFIRMED current source | Power Query в приложенном DOCX |
| `Reference141X1` | клиент, код, имя, дата рождения | CONFIRMED current source | Power Query в приложенном DOCX |
| `Reference132` | клуб доступа | CONFIRMED current source | Power Query в приложенном DOCX |
| `Reference163`, `Reference87` | фильтры/категория номенклатуры | CONFIRMED current source / semantics pending | Power Query в приложенном DOCX |
| `InfoRg5654`, `Document346`, `Document346.VT4913`, `Document346.VT4924`, `AccumRg7646` | детские пакеты, стаж и sales/return eligibility | CONFIRMED user-approved reuse / join pending | PBIT; BR-037; решение пользователя 2026-08-25 |
| `AccumRg7575` | посещения | CONFIRMED current source / states and unit pending | Power Query в приложенном DOCX |
| `InfoRg7006`, `Document329`, `Enum448`, `Document325` | признак СПТ | CONFIRMED current source / relation pending | Power Query в приложенном DOCX |
| `InfoRg6015` | календарь | CONFIRMED current source | Power Query в приложенном DOCX |
| Excel «Доля выпускников с целевой регулярностью» | текущая Power Query-зависимость без подтверждённого потребителя | NOT_APPLICABLE к плановой формуле | Power Query в приложенном DOCX; решение пользователя 2026-07-28 |

`SV-076` (live read-only, 2026-08-11) подтвердил существование 11 physical
relations и технические ключи 3 180 662 visit-строк 2026. Но 240 296 строк
имеют orphan-контракт, 146 131 — client-owner mismatch; child-ветка содержит
3 144 повторные пары `contract × child` (7 093 строки, максимум 11) и 9 933
orphan child-ссылки. История `InfoRg5654` имеет 1 084 849 строк, `NULL=0` и
0 ties `client × period`. NM-V08 подтвердил формулу полного второго месяца
на 100 мартовских контрактах без duplicate output key. Эти результаты не
разрешают dedupe или изменение current-rule без отдельного решения по BR-018.

## Подтверждённые source-side правила текущего отчёта

Пользователь подтвердил, что текущие SQL-фильтры являются полными для
бизнес-логики отчёта. При реализации они воспроизводятся как единый
source-side набор без добавления гипотетических условий по статусам.

| Ветка | Зафиксированное текущее правило | Статус / доказательство |
|---|---|---|
| основной контракт | `Reference59.Fld671 >= 2023-12-01`; дата окончания позже начала; длительность более 30 дней; клиент существует; текущие GUID-фильтры типа абонемента и исключённой служебной номенклатуры; `Fld693 > 30` | CONFIRMED current SQL и решение пользователя 2026-07-28 |
| New-когорта | стаж контракта `New`; детская ветка использует текущий as-of расчёт `InfoRg5654` и `COALESCE(..., 'New')` | CONFIRMED user decision и current SQL |
| детские пакеты | строки `Document346.VT4913` соединяются с чеком, контрактом, клубом и ребёнком; возрастная категория — константа `Дети`; eligibility и повторная дата продажи применяют BR-037 через sales-group `чек × взрослый × продукт`, а legacy `RANK() = 1` ties сохраняются после eligibility | CONFIRMED user decision 2026-08-25; BR-037; кардинальность — техническая валидация |
| квалифицированное посещение | `AccumRg7575` соединяется с `Reference163`; используются текущие фильтры `Period >= 2023-12-01`, услуга `посещение клуба`, исключения `%ИП%` и `%Контракт сотрудника%`; связь с фактом — `Fld7578 = contract_id` и `Fld7576 = client_id` | CONFIRMED current SQL и решение пользователя 2026-07-28 |
| интервал посещений | от первого дня месяца после месяца старта до первого дня ещё следующего месяца, верхняя граница исключается | CONFIRMED business description и current SQL |
| СПТ | текущая связь клиента и даты предварительной записи/посещения, затем действующий контракт на эту дату | CONFIRMED user decision и current SQL |

Техническая валидация проверяет воспроизведение этих правил на контрольной
выборке; она не меняет их смысл без конкретного доказанного расхождения.

## Reuse review

Архитектурное решение `NEW` подтверждено пользователем 2026-07-28. Этот
mapping не разрешает SQL до технической валидации источников.

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `docs/catalogs/source_objects.md` | Общие с `newcomer_engagement_milestone`: `Reference59`, `Reference141X1`, `Reference132`, `Reference163`, `AccumRg7575`; также каталогизируются `InfoRg5654`, `Document346`, `Document325`, `Document329`, `InfoRg7006`. | CONFIRMED catalog and current query; `Reference87` и `InfoRg6015` в каталоге отсутствуют |
| Проверенные продукты из `docs/catalogs/data_products.md` | `mart.newcomer_engagement_milestone`, `mart.visit_client_day`, `mart.contract_usage`. | CONFIRMED catalog |
| Проверенные правила из `docs/catalogs/business_rules.md` | BR-003 (история), BR-007 (стабильный ключ), BR-008 (возраст), BR-012 (source-rule связи посещения и контракта), BR-013 (календарь/клубы). | CONFIRMED catalog; применимость исключения сотрудников UNKNOWN |
| Сравнение гранулярности | Current candidate: контракт × клиент × месяц вовлечения. `newcomer_engagement_milestone`: контракт × клиент × checkpoint; `visit_client_day`: дата × фактический клуб × клиент; `contract_usage`: контракт. | CONFIRMED comparison; current key/uniqueness pending |
| Сравнение ключей | Второму месяцу необходимы контракт и клиент; milestone имеет `contract_id + client_id + checkpoint_day`, client-day не имеет contract ID. Текущая связь визит → контракт/клиент подтверждена пользователем. | CONFIRMED user decision; техническая кардинальность проверяется перед реализацией |
| Сравнение бизнес-семантики | Второй календарный месяц не равен первым 30 календарным дням и не выводится из checkpoint-накоплений. | CONFIRMED by current query and business description |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `NEW`: `mart.newcomer_engagement_second_month`. | CONFIRMED user decision 2026-07-28; ADR-0009 |
| Причина решения | Нужен контрактный результат за полный календарный месяц после месяца старта; существующие продукты этого не содержат. Общая source-side квалификация контрактов/визитов может быть переиспользована только после технической проверки. | CONFIRMED comparison / implementation UNKNOWN |
| Затронутые существующие потребители | «Вовлечение новичков» уже расширен детскими пакетами и той же контракт × клиент детализацией; физические факты остаются раздельными из-за разных временных интервалов. | CONFIRMED user decision 2026-07-28 |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | связь `AccumRg7575.Fld7578 → Reference59` и `Fld7576 → клиент` | это правило текущего отчёта, подтверждённое пользователем | техническая проверка cardinality перед реализацией |
| CONFIRMED | единица посещения | `COUNT` строк `AccumRg7575` в заданном интервале — утверждённый расчёт | техническая сверка без замены правила |
| CONFIRMED | статусы 1С | все фильтры текущих SQL признаны полными для отчёта | не добавлять неподтверждённые условия без реального расхождения |
| CONFIRMED | New-когорта | контракт со стажем `New`; текущая ветка детских пакетов сохраняется как есть | зафиксировать место применения фильтра при экспорте модели |
| VALIDATED | ключ целевого набора | 166 969 source rows, 166 969 business pairs и 0 duplicate technical identities после BR-037 на BR-003 horizon | physical PK = `source_row_id`; не обещать такую же уникальность при future source change |
| CONFIRMED current model | связи Power BI | PBIT: дата вовлечения, клуб доступа и возрастная категория связаны с `_Даты`, `_Клубы` и `Возраст` активными однонаправленными связями; `Выпускники план` связан с клубами | `Вовлечение_новичков_Второй_месяц.pbit`, 2026-07-31; уникальность измерений — read-only validation |
| CONFIRMED | возраст | сохраняются категория номенклатуры и константа `Дети` для детских пакетов | не заменять расчётом по дате рождения |
| CONFIRMED | СПТ | сохраняется текущая связь по клиенту и дате с поиском действующего контракта | техническая сверка без изменения правила |
| CONFIRMED | план | плановая доля = доля прошлого года `+ 2 п.п.`; Excel не является источником правила | не включать Excel в расчёт плановой доли |
| PARTIALLY VALIDATED | ключ целевого набора | NM-V08: 100 control-строк без duplicate key; child-ветка физически содержит повторные пары | перед Stage 3 измерить результат после точных current GUID-фильтров, не дедуплицируя без решения |
| TECHNICAL VALIDATION REQUIRED | календарь и клубы Power BI | схема связей подтверждена PBIT, уникальность измерений не измерена | проверить уникальность дат и ID клуба перед созданием связей `1:*` |
| REJECTED | вывод количества второго месяца из `mart.newcomer_engagement_milestone` | факт хранит только накопления первых 30 дней и иной grain | требуется отдельный продукт либо подтверждённый общий intermediate-слой |
