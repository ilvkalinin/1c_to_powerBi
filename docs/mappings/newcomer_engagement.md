# Source-to-target mapping: `newcomer_engagement_milestone`

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`.
SQL и физические объекты пока не создаются.

Гранулярность одной строки:

> один подходящий контракт × контрольная точка `7/14/21/28/30`.

Логический ключ:

> `contract_id + checkpoint_day`.

Единица KPI — контракт. Один клиент с двумя подходящими контрактами
учитывается дважды.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица | Исходная колонка | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|---|
| `contract_id` | стабильный технический ID контракта | `Reference59` | `ID` | hex-представление бинарной ссылки | `text` | нет | контракт | CONFIRMED source | metadata, текущий SQL | уникальность ID |
| `contract_code` | отображаемый код контракта | `Reference59` | `Code` | явный `text` | `text` | нет | контракт | CONFIRMED current consumer | текущий M/DAX | дубли кода |
| `client_code` | код клиента для детальной выгрузки | `Reference141X1` | `Code` | явный `text` | `text` | нет | контракт | CONFIRMED consumer | визуалы отчёта | orphan и NULL |
| `access_club_id` | стабильный ID клуба доступа контракта | `Reference59` | `Fld687` | hex-представление ссылки | `text` | нет | контракт | CONFIRMED metadata | metadata | orphan |
| `access_club_name` | клуб доступа | `Reference132` | `Description` | join `Reference59.Fld687 = Reference132.ID` | `text` | нет | контракт | CONFIRMED | SQL и модель | одна строка клуба |
| `membership_start_date` | дата начала абонемента | `Reference59` | `Fld671` | приведение к дате | `date` | нет | контракт | CONFIRMED | metadata, бизнес-описание | sentinel и диапазон |
| `checkpoint_day` | номер завершённого периода членства | generated values | `7,14,21,28,30` | фиксированный набор | `smallint` | нет | checkpoint | CONFIRMED | бизнес-описание и решение | только 5 значений |
| `checkpoint_date` | последний день контрольного периода | `Reference59.Fld671` + generated value | — | `membership_start_date + checkpoint_day - 1 день` | `date` | нет | contract × checkpoint | CONFIRMED | решение пользователя | date arithmetic |
| `visit_count_to_checkpoint` | посещения за первые N календарных дат | `AccumRg7575` | `Period`, `Fld7576`, `Fld7578`, `Fld7579` | подходящие движения контракта при `Period >= start AND Period < start + checkpoint_day days`; текущая единица совместимости — строка регистра | `integer` | нет, `0` | contract × checkpoint | CONFIRMED business boundary / technical semantics pending | решение пользователя, текущий SQL | rows vs documents vs quantity |
| `visit_bucket` | категория посещаемости | вычисление | `visit_count_to_checkpoint` | `0`, `1`, `2`, `3`, `4+` | `text` | нет | contract × checkpoint | CONFIRMED | бизнес-описание | границы 0–4+ |
| `target_visit_count` | порог не реже раза в неделю | generated values | — | `1/2/3/4/4` для `7/14/21/28/30` | `smallint` | нет | checkpoint | CONFIRMED | бизнес-описание | соответствие checkpoint |
| `below_target_flag` | посещаемость ниже целевой | вычисление | — | `visit_count_to_checkpoint < target_visit_count` | `boolean` | нет | contract × checkpoint | CONFIRMED | бизнес-описание | boundary values |
| `frozen_at_checkpoint_flag` | контракт заморожен на контрольную дату | `InfoRg5859`, `AccumRg7478` | `Fld5860`, `Fld5862`, `Fld5863`, движения | interval `EXISTS`, без размножения строк | `boolean` | нет | contract × checkpoint | CONFIRMED business rule / join pending | решение пользователя, текущий SQL | интервалы, границы, дубли |
| `eligible_flag` | контракт входит в знаменатель точки | несколько источников | — | валидный New-контракт длительностью ≥ checkpoint, клиент не сотрудник на start, контракт не заморожен на checkpoint | `boolean` | нет | contract × checkpoint | CONFIRMED business / technical predicates pending | решения пользователя | причины исключения |
| `age_group` | возрастная категория на дату активации | `Reference141X1`, `Reference59` | `Fld1507`, `Fld670` | точный календарный возраст: `<14`, `14–17`, `18+`; при неизвестной дате `NULL` | `text` | да | контракт | CONFIRMED groups / current reference date | решение пользователя, текущий M | дни рождения и NULL |

## Отбор контрактов

`CONFIRMED`:

- стаж контракта `Reference59.Fld694` соответствует `New`;
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
| `AccumRg7575` | движения посещений | CONFIRMED | metadata и текущий SQL |
| `AccumRg7478`, `InfoRg5859` | движения и интервалы заморозок | CONFIRMED source / join pending | metadata и текущий SQL |
| `InfoRg6291`, `Reference225`, `Reference101` | периоды трудоустройства | CONFIRMED source / historical rule pending | metadata, текущий SQL, решение пользователя |
| внешний Excel плана | доля плана по клубу и году | CONFIRMED external source | текущий M; в PostgreSQL-витрину не входит |

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
8. контрольные контракты на границах 7/14/21/28/30 дней.
9. контракт с посещением ровно в `checkpoint_date`: такое посещение входит.
10. контракт, замороженный ровно в `checkpoint_date`: точка недопустима.
11. возраст в дни 14-летия и 18-летия.
12. объём, диапазоны дат и время source-side агрегации.
