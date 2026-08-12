# Source-to-target mapping: `newcomer_engagement_milestone`

Статус: `BUSINESS MAPPING COMPLETE / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-075`.
SV-075 подтвердил технический ключ visit-строк, но выявил orphan/mismatch
связи с контрактом и невалидные/повторные интервалы заморозки. SQL и
физические объекты не создаются.

Гранулярность одной строки:

> один подходящий контракт × клиент × контрольная точка `7/14/21/28/30`.

Логический ключ:

> `contract_id + client_id + checkpoint_day`.

Единица KPI — пара `клиент × контракт`. Один клиент с двумя подходящими
контрактами учитывается дважды; взрослый и ребёнок, привязанные к одному
контракту, также учитываются как две самостоятельные пары. Посещения и группа
посещений не объединяются между клиентами одного контракта.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|---|
| `contract_id` | стабильный технический ID контракта | `Reference59` | `ID` | hex-представление бинарной ссылки | `text` | нет | contract × client × checkpoint | CONFIRMED source | metadata, текущий SQL | уникальность ID |
| `contract_code` | отображаемый код контракта | `Reference59` | `Code` | явный `text` | `text` | нет | contract × client × checkpoint | CONFIRMED current consumer | текущий M/DAX | дубли кода |
| `client_id` | стабильный технический ID клиента, включая ребёнка детского пакета | `Reference59`, `Reference141X1`, `Document346.VT4913` | `Fld681`, `ID`, `Fld4916` | основная ветка: клиент контракта; детский пакет: ребёнок из строки чека; hex-представление ссылки | `text` | нет | contract × client × checkpoint | CONFIRMED user decision / current child-package query | второй отчёт, решение пользователя 2026-07-28 | orphan, NULL, key duplicates |
| `client_code` | код клиента для детальной выгрузки | `Reference141X1` | `Code` | явный `text` | `text` | нет | contract × client × checkpoint | CONFIRMED consumer | визуалы отчёта | orphan и NULL |
| `access_club_id` | стабильный ID клуба доступа контракта | `Reference59` | `Fld687` | hex-представление ссылки | `text` | нет | contract × client × checkpoint | CONFIRMED metadata | metadata | orphan |
| `access_club_name` | клуб доступа | `Reference132` | `Description` | join `Reference59.Fld687 = Reference132.ID` | `text` | нет | contract × client × checkpoint | CONFIRMED | SQL и модель | одна строка клуба |
| `membership_start_date` | дата начала абонемента | `Reference59`, `Document346` | `Fld671`, `Date_Time` | основная ветка: `Fld671`; детский пакет: `GREATEST(Fld671, Date_Time::date)` | `date` | нет | contract × client × checkpoint | CONFIRMED current child-package query / user decision | второй отчёт, решение пользователя 2026-07-28 | границы и дубли веток |
| `checkpoint_day` | номер завершённого периода членства | generated values | `7,14,21,28,30` | фиксированный набор | `smallint` | нет | contract × client × checkpoint | CONFIRMED | бизнес-описание и решение | только 5 значений |
| `checkpoint_date` | последний день контрольного периода | `membership_start_date` + generated value | — | `membership_start_date + checkpoint_day - 1 день` | `date` | нет | contract × client × checkpoint | CONFIRMED | решение пользователя | date arithmetic |
| `visit_count_to_checkpoint` | посещения за первые N календарных дат | `AccumRg7575` | `Period`, `Fld7576`, `Fld7578`, `Fld7579` | подходящие движения пары контракт + клиент при `Period >= start AND Period < start + checkpoint_day days`; текущая единица совместимости — строка регистра | `integer` | нет, `0` | contract × client × checkpoint | CONFIRMED business boundary / technical semantics pending | решение пользователя, текущий SQL | rows vs documents vs quantity |
| `visit_bucket` | категория посещаемости | вычисление | `visit_count_to_checkpoint` | `0`, `1`, `2`, `3`, `4+` | `text` | нет | contract × client × checkpoint | CONFIRMED | бизнес-описание | границы 0–4+ |
| `target_visit_count` | порог не реже раза в неделю | generated values | — | `1/2/3/4/4` для `7/14/21/28/30` | `smallint` | нет | contract × client × checkpoint | CONFIRMED | бизнес-описание | соответствие checkpoint |
| `below_target_flag` | посещаемость ниже целевой | вычисление | — | `visit_count_to_checkpoint < target_visit_count` | `boolean` | нет | contract × client × checkpoint | CONFIRMED | бизнес-описание | boundary values |
| `frozen_at_checkpoint_flag` | контракт заморожен на контрольную дату | `InfoRg5859`, `AccumRg7478` | `Fld5860`, `Fld5862`, `Fld5863`, движения | interval `EXISTS`, без размножения строк | `boolean` | нет | contract × client × checkpoint | CONFIRMED business rule / join pending | решение пользователя, текущий SQL | интервалы, границы, дубли |
| `eligible_flag` | контракт входит в знаменатель точки | несколько источников | — | валидный New-контракт длительностью ≥ checkpoint, клиент не сотрудник на start, контракт не заморожен на checkpoint | `boolean` | нет | contract × client × checkpoint | CONFIRMED business / technical predicates pending | решения пользователя | причины исключения |
| `age_group` | возрастная категория на дату активации | `Reference141X1`, `Reference59` | `Fld1507`, `Fld670` | точный календарный возраст: `<14`, `14–17`, `18+`; при неизвестной дате `NULL`; для детского пакета используется дата рождения ребёнка | `text` | да | contract × client × checkpoint | CONFIRMED groups / current reference date | решение пользователя, текущий M, child-package query | дни рождения и NULL |

## Отбор контрактов

`CONFIRMED`:

- стаж контракта `Reference59.Fld694` соответствует `New`;
- детские пакеты добавляются второй веткой: ребёнок берётся из
  `Document346.VT4913.Fld4916`, дата начала — максимум даты начала контракта
  и даты чека, стаж — текущий as-of расчёт `InfoRg5654`;
- единица результата — контракт;
- длительность должна позволять дожить до соответствующей контрольной точки;
- пустой клиент, контракт ИП и контракт сотрудника исключаются;
- статус сотрудника проверяется на дату начала абонемента;
- заморозка не сдвигает даты, а делает соответствующую точку недопустимой;
- для точки `N` посещения считаются в полуинтервале
  `[membership_start_date, membership_start_date + N дней)`; последний день
  периода — `checkpoint_date`.

Технические GUID текущих фильтров сохраняются как доказательство текущей
реализации, но до production SQL проверяются по значениям справочников.

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `Reference59` | контракт, клиент, даты, клуб, стаж, номенклатура | CONFIRMED | metadata и текущий SQL |
| `Reference141X1` | код клиента и дата рождения | CONFIRMED current physical source | текущий SQL; физическое имя проверить каталогом |
| `Reference132` | клуб доступа | CONFIRMED | metadata и текущий SQL |
| `Reference163` | номенклатура контракта и услуга посещения | CONFIRMED | metadata и текущий SQL |
| `Document346`, `Document346.VT4913` | чек и строка детского пакета; ребёнок и дата начала | CONFIRMED current source / join pending | query отчёта «Вовлечение новичков Второй месяц», решение пользователя 2026-07-28 |
| `InfoRg5654` | текущий as-of стаж ребёнка детского пакета | CONFIRMED current source / boundary pending | query отчёта «Вовлечение новичков Второй месяц», решение пользователя 2026-07-28 |
| `AccumRg7575` | движения посещений | CONFIRMED | metadata и текущий SQL |
| `AccumRg7478`, `InfoRg5859` | движения и интервалы заморозок | CONFIRMED source / join pending | metadata и текущий SQL |
| `InfoRg6291`, `Reference225`, `Reference101` | периоды трудоустройства | CONFIRMED source / historical rule pending | metadata, текущий SQL, решение пользователя |
| внешний Excel плана | доля плана по клубу и году | CONFIRMED external source | текущий M; в PostgreSQL-витрину не входит |

`SV-075` (live read-only, 2026-08-11): в 2026 `AccumRg7575` содержит
3 180 564 строк, равных числу технических ключей, но 240 290 строк имеют
orphan-контракт и 146 127 — клиента, отличающегося от владельца контракта.
В `InfoRg5859` обнаружены 1 602 769 интервалов, включая 71 обратный и
12 274 точных повторных. Поэтому current join `contract + client` и
текущая обработка заморозок сохраняются как доказанная legacy-логика;
их замена требует отдельного решения по BR-018.

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из каталога | `Document346`, `Document346.VT4913` и `InfoRg5654` уже используются вторым отчётом вовлечения; базовые источники и посещения уже используются текущим фактом. | CONFIRMED catalog и mapping второго отчёта |
| Проверенные продукты | `mart.newcomer_engagement_second_month` имеет ту же контракт × клиент детализацию, но иной календарный интервал. | CONFIRMED ADR-0009 и data contract второго отчёта |
| Сравнение гранулярности | Первый факт меняется с контракт × checkpoint на контракт × клиент × checkpoint; второй факт — контракт × клиент × месяц вовлечения. | CONFIRMED user decision |
| Сравнение ключей | Оба факта используют `contract_id + client_id` как техническую основу; третий компонент различается по временной семантике. | CONFIRMED BY DESIGN |
| Решение | `EXTEND` существующего `mart.newcomer_engagement_milestone` детской веткой и `client_id` в grain. | CONFIRMED user decision 2026-07-28 |
| Причина решения | Детские пакеты расширяют ту же New-когорту, контрольные точки и KPI; новый физический продукт не нужен. | CONFIRMED user decision |

## Повторное использование

- общий календарь и справочник клубов переиспользуются;
- правила связи посещения с контрактом переиспользуются из mapping
  `renew_contract_usage`, но проходят ту же техническую проверку;
- `mart.visit_client_day` не используется: в нём нет контракта;
- `3м/90дней` не входят в этот mapping и переносятся в разбор отчёта
  «Подготовка к продлению»;
- сырой `AccumRg7575` на VM витрин не копируется.

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| BLOCKER before SQL | `AccumRg7575.Fld7578 → Reference59.ID` | основание может быть полиморфным | тип ссылки, orphan и кардинальность |
| BLOCKER before SQL | единица посещения | текущий отчёт считает строки; ресурс количества и документы не сверены | сравнить row count, recorder distinct и `SUM(Fld7585)` |
| BLOCKER before SQL | состояния посещения и контракта | `Active`, удаление, проведение, сторно не проверены | metadata, контрольные строки и сверка |
| BLOCKER before SQL | интервалы заморозки | current join и границы интервала могут размножать строки | `EXISTS`, latest/cancel semantics, контроль нескольких интервалов |
| BLOCKER before SQL | историческое трудоустройство | текущий запрос знает только действующих сейчас | доказать периоды приёма/увольнения и interval join |
| TECHNICAL VALIDATION REQUIRED | детские пакеты | `RANK() = 1` может сохранять ties; as-of стаж и строка чека могут размножить контракт × ребёнка | проверить дубли `(contract_id, client_id, checkpoint_day)` после child branch |
| UNKNOWN | дата возраста | текущая модель использует дату активации; бизнес подтвердил только группы | сохранить совместимость до отдельного решения |
| UNKNOWN | отсутствующая дата рождения | текущая модель ошибочно относит к взрослым | целевое значение `NULL`, сверить количество |
| REJECTED | `NATURALLEFTOUTERJOIN` по заморозкам | неявный ключ и размножение контрактов | заменить interval `EXISTS` после mapping |
| REJECTED | связи по `contract_code` | уникальность не доказана | технический ключ — `contract_id` |
| CONFIRMED ERROR | `Reference59.Fld701` как основной клуб продажи | metadata определяет его как точку продаж | не включать |
| CONFIRMED ERROR | `Reference59.Fld696` как тип контракта | metadata определяет тип абонемента | не использовать без потребителя |

## Проверки перед SQL

1. Физические типы и `NULL` всех используемых колонок.
2. Уникальность `Reference59.ID`, дубли `Code`.
3. Кардинальность `visit → contract` и orphan.
4. `COUNT(rows)` против документов и ресурса количества.
5. влияние `Active`, проведения, удаления и сторно.
6. версия и отмена интервалов заморозки, несколько интервалов одного контракта.
7. исторические интервалы трудоустройства.
8. контрольные контракты и детские пакеты на границах 7/14/21/28/30 дней.
9. контракт с посещением ровно в `checkpoint_date`: такое посещение входит.
10. контракт, замороженный ровно в `checkpoint_date`: точка недопустима.
11. возраст в дни 14-летия и 18-летия.
12. объём, диапазоны дат и время source-side агрегации.
