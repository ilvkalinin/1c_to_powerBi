# Query review: «Воронка»

Статус: `EVIDENCE REVIEWED / GLOBAL-GATE SOURCE CONTROLS CLOSED — SV-080, SV-101, SV-103, MF-V10A`.

Рассмотрены текущие SQL/M/DAX, PBIT и бизнес-описание. PBIT
`Pbit_old/Воронка.pbit` (SHA-256
`ddf6115ed9f8f8c017c0ca0cb0ce61c61f1694aaf5bbfe6665147280b8e2d0c3`)
утверждён пользователем 2026-08-18 как базовая DAX-логика первого релиза для
накопленного трафика. В gymdb выполнены согласованные source controls
`SV-080`, `SV-101`, `SV-103` и `MF-V10A`; старые шаблоны ниже сохраняются как
реестр будущей реализации и не отменяют закрытие текущего global-gate scope.

## Power Query

Наборы `Задания 2024`, `Задания 2025` и `Задания 2026` повторяют один SQL с
годовым фильтром `Reference106.Fld1193`, после чего объединяются в `Задания`.
Это подтверждает task grain, но ежегодная фиксация дат создаёт риск пропуска
нового года до ручного изменения модели.

В CTE `contracts` `InfoRg6798` связывает задачу с `Reference59` и поставляет
наименование, клиентский код, возрастную группу, тип оплаты, длительность и
дату активации. Основной запрос берёт CRM-задачу `Reference106`, клиент,
клуб, воронку, кампанию и её родителя, причину неуспеха и этап. После SQL:

- исключаются две причины «Найдено аналогичное задание»;
- `NULL` родителя кампании заменяется на `НетРодителя`;
- 15 GUID типов первого взаимодействия маппятся в названия, а затем M
  укрупняет их до визуальных категорий;
- `ДатаАктивации` приводится к `date`.

Raw current SQL отбирает `ДатаАктивации >= 2024-01-01`, но не сопоставляет её
с `ДатаСоздания` задания. Пользователь 2026-08-13 явно утвердил BR-020:
строка конверсии допустима только при `ДатаАктивации >= ДатаСоздания`.
Это намеренное исключение из воспроизведения legacy SQL по BR-018.

## DAX и модель

- `ВсегоЗаданий` и `ВсегоЗаданийДляКонверсии` используют distinct task code и
  снимают фильтры возраста, оплаты и длительности. Это реализует правило
  независимости заданий от contract-срезов.
- current DAX `Абонементы` агрегирует по `КодЗадания`; BR-020 фиксирует
  первичную единицу future SQL как qualified `task × contract`, чтобы каждая
  связь учитывалась после временной квалификации, без global dedup контракта.
- Планы задач и контрактов суммируются из таблицы `Новые планы` по
  категориям «Взаимодействия» и «Контракты». План по типу взаимодействия
  берётся из `Подневный план по трафику` только для встречи, входящего звонка,
  обратной связи и мероприятий.
- `Накопленный трафик факт2` — точное `UNION('Задания 2024','Задания 2025')`;
  основной `Задания` включает 2026. Это согласованная текущая реализация и
  риск отсутствия накопленного трафика после смены года.
- `ФактЗаявкиНакопленныйТрафик` берёт distinct task code с датой создания в
  двух календарных месяцах перед первым днём текущего месяца; из них вычитает
  distinct отмены (`ЭтапВоронки IN ('Отказ','Отмена')`, закрытые до месяца) и
  сумму distinct клиентов по task с активированным до месяца контрактом.
  Фильтры оплаты, длительности и возраста снимаются. Для обеих категорий
  «Накопленный трафик (вх.)» и «Накопленный трафик (исх.)» мера возвращает
  один и тот же итог; для остальных типов — 0.
- В отчёте есть служебные/тестовые меры. Они не рассматриваются как целевая
  бизнес-логика без потребителя в визуале.

## Несоответствия и риски

| Статус | Наблюдение | Влияние |
|---|---|---|
| `CONFIRMED business rule / VALIDATION_PENDING physical` | `InfoRg6798` содержит более одного контракта на задание. Ошибочный technical пример `0000302905 → 008259075/008854940` исключён: MF-V03G дал 2 связи и 0 qualifying по BR-020. | BR-020 задаёт counting unit `task × contract`; старый абонемент не может быть конверсией более позднего задания. Перед Stage 3 остаются physical code/join/state controls. |
| `VALIDATED in report scope` | Current DAX uses `task_code`; SV-101 found no null or duplicate code among 1 382 845 tasks in the report funnel. Physical task-to-contract join remains `InfoRg6798.Fld6799RRef → Reference106.ID`. | Code remains a display/DAX field, not a physical bridge key. |
| `VALIDATED on one source control month` | Точная мера накопленного трафика использует `UNION(Задания 2024, Задания 2025)`, двухмесячное окно, отмены и ранее активированные контракты. | MF-V08 на 2025-07-01 подтвердил source inputs и итог меры 23 864; это не сверка с фактическим числом Power BI. |
| `CONFIRMED user-approved PBIT` | Задания для накопленного трафика ограничены 2024–2025. | После 2026 требуется ручная корректировка; historical result сохраняется по BR-018. |
| `VALIDATED WITH ANOMALY` | В report funnel одна qualified contract-link имеет неположительную длительность, `NULL` нет. | Границы длительности физически измерены; строка не исключается и не получает новую категорию без отдельного правила. |
| `VALIDATED` | Тип оплаты договора следует единому BR-024: exact `Fld699` рекарринга определён текущим M-кодом поступлений. | MF-V07C: 9 238 рекарринговых, 191 625 предоплатных связей, `NULL` = 0; частота и порядок не используются. |
| `VALIDATION_PENDING` | Общий mapping сети/кластера клуба подтверждён пользователем 2026-07-30; физические поля и покрытие клубов ещё не проверены. Excel-планы остаются в Power BI. | Не проектировать загрузку и watermark планов в PostgreSQL; на MF-V01 проверить mapping клуба. |
| `UNKNOWN` | Визуальные категории «Отдел маркетинга» и «Отдел продаж» описаны, но явная таблица и порядок типов не переданы. | Категоризация в M воспроизводит текущие типы, но не доказывает иерархию/порядок. |
| `UNKNOWN` | Наименование пятой страницы расходится между описанием и снимком. | Только навигация/название, не расчёты. |

## Пакет будущей read-only валидации

| ID | Проверка | Ожидаемый результат |
|---|---|---|
| MF-V01 | схема, типы и технические имена `Reference106`, `InfoRg6798`, CRM-справочников и контрактов | все колонки mapping существуют и имеют зафиксированные типы |
| MF-V02 | уникальность `Reference106.ID` и `Reference106.Code` | `ID` уникален; пригодность `Code` для связи доказана либо связь заменена на ID |
| MF-V03 | кардинальность `task → InfoRg6798 → contract` после current filters и BR-020 | сохранить каждую qualifying связь, без global dedup; key/code join подтверждён физически |
| MF-V04 | сохранение task rows после всех CRM joins и исключений | `COUNT(*) = COUNT(DISTINCT task_id)` до intentional contract bridge |
| MF-V05 | GUID-справочники воронки, стажа, типа взаимодействия, контракта и оплаты | названия/GUID соответствуют текущей модели и контрольному месяцу |
| MF-V06 | `Marked`, `Active` и семантика даты создания/активации | включаются только допустимые записи, дата соответствует мере |
| MF-V07 | возраст, длительность и тип оплаты контракта на граничных значениях | категории совпадают с current M на согласованной выборке |
| MF-V08 | алгоритм накопленного трафика | на согласованном месяце совпадают distinct task codes за два предыдущих месяца, отмены, distinct clients по task с контрактом и итог меры для обеих traffic-категорий |
| MF-V09 | сверка Power BI | задания, абонементы, конверсия и план–факт совпадают для одного месяца/клуба/типа |
| MF-V10A | metadata изменений источника | выполнено 2026-08-19: у CRM-задачи только `_version`/`_marked`, у bridge только `_period`; даты изменения нет, поэтому watermark не обоснован и сохраняется bounded full rebuild BR-003 |
| MF-V10B | rerun и SLA созданной витрины | будущая приёмка Stage 3 после создания объекта и расписания; не source-side blocker |

`MF-V03` выполнен как `SV-080` в gymdb в read-only режиме. MF-V03G/MF-V03H
добавили user-approved BR-020 и его техническое наблюдение; остальные
незапущенные проверки не считаются пройденными.

### SQL-шаблоны второго этапа

```sql
-- MF-V02: ключи CRM-задачи.
-- VALIDATION_PENDING
SELECT _IDRRef AS task_id, COUNT(*)
FROM <source_schema>._Reference106
GROUP BY _IDRRef
HAVING COUNT(*) > 1;

SELECT _Code AS task_code, COUNT(DISTINCT _IDRRef) AS task_ids
FROM <source_schema>._Reference106
GROUP BY _Code
HAVING COUNT(DISTINCT _IDRRef) > 1 OR _Code IS NULL;

-- MF-V03: число подходящих контрактов на задачу.
-- VALIDATION_PENDING; bounded control executed as SV-080 and failed one-to-one
SELECT r._Fld6799RRef AS task_id,
       COUNT(DISTINCT r._Fld6800_RRRef) AS contract_count
FROM <source_schema>._InfoRg6798 r
JOIN <source_schema>._Reference59 c
  ON c._IDRRef = r._Fld6800_RRRef
JOIN <source_schema>._Reference106 t
  ON t._IDRRef = r._Fld6799RRef
JOIN <source_schema>._Reference89 f
  ON f._IDRRef = t._Fld1191RRef
WHERE r._Fld6802 = true
  AND c._Fld696RRef <> decode('9b656ee141a764e44de79e83cd30c1b2', 'hex')
  AND c._Fld699RRef <> decode('96976725cebf51f7461429d74d3f6cbe', 'hex')
  AND f._Description = 'Продажа клубной карты'
GROUP BY r._Fld6799RRef
HAVING COUNT(DISTINCT r._Fld6800_RRRef) > 1;

-- MF-V04: после dimension joins не должно быть больше одной строки на задачу.
-- VALIDATION_PENDING
SELECT COUNT(*) AS rows_after_joins,
       COUNT(DISTINCT t._IDRRef) AS distinct_tasks
FROM <source_schema>._Reference106 t
LEFT JOIN <source_schema>._Reference89 f ON f._IDRRef = t._Fld1191RRef
LEFT JOIN <source_schema>._Reference132 c ON c._IDRRef = t._Fld1195RRef
LEFT JOIN <source_schema>._Reference145 m ON m._IDRRef = t._Fld1197RRef
LEFT JOIN <source_schema>._Reference201 r ON r._IDRRef = t._Fld1201RRef
LEFT JOIN <source_schema>._Reference264 s ON s._IDRRef = t._Fld1205RRef
WHERE f._Description = 'Продажа клубной карты'
  AND t._Marked = false;
```
