# Query review: «Титульный лист»

Статус: `COMPLETE / NOT_EXECUTED — ожидается подключение к корпоративной сети`.

## Переданные технические материалы

Получены четыре Power Query: `Посещения`, `ДПФУ`, `Рецепция`, `Членство`; и
девять DAX-мер: выручка всего/график, выручка фитнес/график, доля фитнеса,
выручка на м², активная база и максимум ЧК. PBIT дополнил это моделью из
19 содержательных таблиц и 15 активных связей: дата фильтрует посещения,
общий справочник клубов — все компоненты; связи клуб → площади и клуб →
мощность КБ в текущем отчёте двунаправленные. Ролей RLS в PBIT нет.
Внешние наборы расходов, характеристик клуба, КБ, Renew, оборудования и
шкафчиков остаются в Power BI; их источники не переносятся в PostgreSQL.

## Инвентаризация M/SQL

| Набор | Физические источники | Гранулярность результата | Текущая логика | Риски |
|---|---|---|---|---|
| `Посещения` | `AccumRg7575`, `Document325`, `Reference132`, `Reference141X1`, `Reference59` | день × клуб × час прихода × час ухода × пол × возраст | `COUNT(Document325.ID)` и сумма минут; текущие текстовые/жёсткие фильтры | join может размножить документ; час теряет минуты; нет state filter |
| `ДПФУ` | `AccumRg7575`, `AccumRg7646`, `AccumRg7370`, `Reference59/70/132/163` | месяц × имя клуба | штатные разрешённые услуги плюс оплаты ИП | дублирует домен DPFU; text/GUID filters; знак/`RecordKind` pending |
| `Рецепция` | `AccumRg7575`, `AccumRg7646`, `Reference70/132/163` | месяц × имя клуба | разрешённые категории рецепции; нулевые суммы удаляются | пересечение с DPFU не доказано; text/GUID filters |
| `Членство` | `AccumRg7370`, `AccumRg7739`, `Reference59/132/134/163`, 13 документов-регистраторов | месяц × имя клуба | контракты, прочие услуги и товары; sign CASE по `RecordKind` | полиморфные joins, знак и states не проверены |

Все четыре M используют строковые имена клуба как ключ и собственный
календарный диапазон. Это не переносится в целевой слой: источники должны
сначала отдавать стабильный `club_id`, а дата/клуб связаны через общие
измерения Power BI.

## Подтверждённые наблюдения

1. Логика трёх выручечных наборов соответствует потребности в составе
   `членство + фитнес + рецепция`, но не доказывает отсутствие одного
   технического движения в двух категориях.
2. Текущая `ДПФУ` включает оплаты ИП; это существенно для числителя доли
   фитнеса и не должно без решения заменяться только штатной статьёй DPFU.
3. Текущий M выручки читает «прошлый год + текущий + будущий год», а
   посещения — только 2026 год. Оба диапазона расходятся с BR-003.
4. `МаксЧКвКлубе` считает документы, а не уникальных клиентов. Визуал и DAX
   подтверждают именно это текущее правило.
5. `Время прихода < час` исключает вход ровно в границе часа, а
   `Время ухода >= час` включает уход в границе. До контрольной сверки такую
   асимметрию не исправлять.
6. В M fallback для незакрытого посещения влияет на `Всего минут`, но мера
   максимальной ЧК использует исходный `Время ухода`; итог в этом случае
   может не учитывать человека.
7. DAX выручки использует `MIN('_Спр_даты'[Date])`; при нештатном выборе
   нескольких дат расчёт привязывается к ранней дате. В отчёте указан
   одиночный выбор, поэтому это не меняет подтверждённый сценарий.
8. `АктивнаяБаза` не доказывает определение «факт КБ»: в документах отсутствуют
   M-код, ключ и фильтры таблицы `КБ факт`.

## Доказанное расхождение с существующими продуктами

`mart.revenue_group_summary_daily` уже проектируется как день × клуб × статья
и включает статьи членства, штатной DPFU, аренды ИП и рецепции. Он годится
как источник дневных компонентов титульного листа, но TS не создаёт новую
статью и не меняет фильтры без TS-V01–TS-V03. `mart.client_base_snapshot` не
годится для произвольного дня; подходящий кандидат —
`mart.client_base_daily`. Часовой результат совпадает с кандидатом «Работы с
посещаемостью», а не с `mart.visit_client_day`, который не содержит интервал
входа/выхода.

## Непроведённый пакет read-only проверок

Все запросы имеют статус `NOT_EXECUTED — ожидается подключение к корпоративной
сети`. Имя схемы и физические типы сначала подтверждаются preflight через
`pg_catalog`; выполнение допустимо только на STAGE_2_SERVER_VALIDATION.

```sql
-- TS-V01. Уникальность кандидата ключа и NULL в четырёх регистрах выручки.
WITH x AS (
  SELECT '7575' AS source_kind, _RecorderRRef AS recorder, _LineNo AS line_no FROM _AccumRg7575 WHERE _Period>=:from_ts AND _Period<:to_ts
  UNION ALL SELECT '7646', _RecorderRRef, _LineNo FROM _AccumRg7646 WHERE _Period>=:from_ts AND _Period<:to_ts
  UNION ALL SELECT '7370', _RecorderRRef, _LineNo FROM _AccumRg7370 WHERE _Period>=:from_ts AND _Period<:to_ts
  UNION ALL SELECT '7739', _RecorderRRef, _LineNo FROM _AccumRg7739 WHERE _Period>=:from_ts AND _Period<:to_ts
)
SELECT source_kind, count(*) AS rows_total,
       count(*) FILTER (WHERE recorder IS NULL OR line_no IS NULL) AS null_key_rows,
       count(*) - count(DISTINCT (recorder, line_no)) AS duplicate_rows
FROM x GROUP BY source_kind;
-- Expected: null_key_rows = 0 and duplicate_rows = 0, else reject the key.
```

```sql
-- TS-V02. Сохранение строк/сумм после присоединения клуба и номенклатуры.
WITH before_join AS (
  SELECT '7575' AS source_kind, count(*) AS rows_before, sum(_Fld7586) AS amount_before FROM _AccumRg7575 WHERE _Period>=:from_ts AND _Period<:to_ts
  UNION ALL SELECT '7646', count(*), sum(_Fld7659) FROM _AccumRg7646 WHERE _Period>=:from_ts AND _Period<:to_ts
), after_join AS (
  SELECT '7575' AS source_kind, count(*) AS rows_after, sum(a._Fld7586) AS amount_after
  FROM _AccumRg7575 a LEFT JOIN _Reference132 c ON c._IDRRef=a._Fld7577RRef
                       LEFT JOIN _Reference163 s ON s._IDRRef=a._Fld7579RRef
  WHERE a._Period>=:from_ts AND a._Period<:to_ts
  UNION ALL
  SELECT '7646', count(*), sum(a._Fld7659)
  FROM _AccumRg7646 a LEFT JOIN _Reference132 c ON c._IDRRef=a._Fld7653RRef
                       LEFT JOIN _Reference163 s ON s._IDRRef=a._Fld7649RRef
  WHERE a._Period>=:from_ts AND a._Period<:to_ts
)
SELECT b.*, a.rows_after, a.amount_after,
       a.rows_after-b.rows_before AS row_delta,
       a.amount_after-b.amount_before AS amount_delta
FROM before_join b JOIN after_join a USING (source_kind);
-- Expected: row_delta = 0 and amount_delta = 0 for one-to-one dimensions.
```

```sql
-- TS-V03. Кандидаты пересечения двух классификаций 7575/7646.
-- После source-side применения текущих фильтров DPFU и Рецепции:
SELECT source_kind, recorder, line_no, count(DISTINCT report_category) AS category_count
FROM :title_sheet_qualified_revenue_rows
GROUP BY source_kind, recorder, line_no
HAVING count(DISTINCT report_category) > 1;
-- Expected: 0 rows. :title_sheet_qualified_revenue_rows is a one-time
-- read-only CTE reproducing the supplied filters, not a production object.
```

```sql
-- TS-V04. Кратность и допустимые интервалы текущего набора посещений.
SELECT a._RecorderRRef AS recorder,
       count(*) AS register_rows,
       count(DISTINCT d._IDRRef) AS document_rows,
       count(*) FILTER (WHERE d._Fld4172=d._Fld4174) AS equal_time_rows,
       count(*) FILTER (WHERE d._Fld4174 IS NULL OR d._Fld4174 <= timestamp '0001-01-01') AS open_rows
FROM _AccumRg7575 a
JOIN _Document325 d ON d._IDRRef=a._RecorderRRef
WHERE a._Period >= :from_ts AND a._Period < :to_ts
GROUP BY a._RecorderRRef;
-- Expected: register/document cardinality is explicitly classified before
-- COUNT(Document325.ID) becomes a target metric.
```

```sql
-- TS-V05. Контроль границ максимальной ЧК по согласованному клубу/дню.
SELECT d._Fld4172 AS entry_at, d._Fld4174 AS exit_at, count(*) AS documents
FROM _AccumRg7575 a
JOIN _Document325 d ON d._IDRRef=a._RecorderRRef
WHERE a._Period::date=:report_date AND a._Fld7577RRef=:club_id
GROUP BY 1,2 ORDER BY 1,2;
-- Expected: вручную подтверждены случаи на целый час, с минутами и открытый
-- вход; результат зафиксирован против карточки Power BI того же refresh.
```

Внешние источники расходов, характеристик, КБ, Renew и оборудования сначала
требуют файла либо полного M/модели; поэтому исполнимый SQL для них пока
`UNKNOWN`, а не вымышленный placeholder.
