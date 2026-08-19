# Query review: «Свод выручка ГК»

Статус: `COMPLETE / SHARED SCHEMA IMPLEMENTED 2026-08-19 / INITIAL LOAD NOT REQUESTED`.

## Пакетный audit 2026-08-11

Пакет работ для «Свод выручка ГК» подтверждён пользователем. Локально
сопоставлены полный PBIT-след (SHA-256 указан в
[`revenue_group_summary.md`](revenue_group_summary.md)), извлечённые из него
M/SQL и DAX с текущим report, mapping и реестром серверных доказательств.
Текущий результат воспроизводит 13 статей `02`–`13`, а `01.ВЫРУЧКА ВСЕГО`
остается DAX-итогом; новых бизнес-правил или методических изменений не
внесено.

Read-only доказательства сохранены в `SV-035`–`SV-050` и `SV-066`: технические
ключи, знаки и состояния внутренних регистров, anti-overlap ДПФУ/рецепции,
ветви членства, уникальность дневного ключа, связи PBIT и устойчивый ключ
клуба. В текущем `STAGE_2_SERVER_VALIDATION` SV-066 повторно выполнил только
read-only metadata-проверку.
Excel-факты прочей выручки, планов и бюджетов намеренно остались вне анализа и
без изменений согласно подтвержденной границе проекта.

## Уточнение product admission — 2026-08-19

Логический отчёт сохраняет все статьи `02`–`13`, но физический PostgreSQL-факт
содержит лишь внутренние `02`–`06`. Статьи `07`–`13` не копируются: их текущие
Excel-наборы остаются частью Power BI `Факт`. Это исключает создание таблицы
для Excel и не меняет DAX-итог `01`.

Проверка реализованных продуктов уточнила reuse. `03.ДПФУ (ШТАТ)` сворачивается
из `mart.ancillary_revenue_movement`; `04.ДПФУ (АРЕНДА ИП)` — из
`mart.ip_revenue_daily` после исключения пустого клуба, как в M-коде свода.
`05.РЕЦЕПЦИЯ` не может быть взята из ancillary: его scope — шесть
фитнес-направлений, тогда как рецепция использует непересекающийся набор.
Поэтому её exact current-M фильтр остаётся только временной source-side
ветвью загрузки одного дневного факта, а не второй постоянной витриной.

## Инвентаризация текущих M/SQL

| Запрос | Физические источники | Текущая логика | Риски / тяжёлые операции |
|---|---|---|---|
| ДПФУ факт | `AccumRg7575`, `AccumRg7646`, `Reference132`, `Reference163`, `Reference70` | два агрегата по дню/имени клуба, `UNION ALL`, статья 03 | повторяет домен DPFU; text filters и нет key/state filter |
| ДПФУ факт ИП | `AccumRg7370`, `Reference59`, `Reference163`, `Reference132` | услуга по названию `%ИП%`, `RecordKind=0`, статья 04 | сопоставление услуги текстом; знак и RecordKind требуют DB-сверки |
| ДПФУ тек план | `InfoRg6612`, `Reference132` | `SUM(Fld6620)` по дню/клубу, с 1 января предыдущего года без верхней границы | `Active`, ключ и будущие строки не проверены |
| Рецепция факт | `AccumRg7575`, `AccumRg7646`, справочники | два набора по дню/имени клуба, статья 05 | пересекается с DPFU, нет технического ключа/anti-overlap проверки |
| Членство факт | `AccumRg7370`, `AccumRg7739`, `Reference59/132/134/163` и 13 типов документов | подписывает суммы по `RecordKind` и типу recorder; union контрактов, прочих услуг и товаров | полиморфные joins, знак/состояния/взаимоисключаемость документов не проверены |
| Прочая выручка25/26 | 2 внешних Excel + 2 Excel-справочника | transpose → headers → left join → FillDown → unpivot → текстовые замены | неявный ключ, FillDown после непопавшего mapping может присвоить предыдущую статью |

Все 1С-запросы используют полный календарный диапазон и `CAST(...Description AS
TEXT)` в фильтрах. В приложенном M нет фильтра `Active`, `Marked` или
`Posted`. Не считать отсутствие таких строк бизнес-правилом: это обязательная
техническая проверка.

## Меры и модель Power BI

`_ПереключательМер` содержит 13 статей. PBIT подтверждает его активные
однонаправленные связи с объединёнными `Факт`, `Тек план` и `Бюджет` по полю
статьи. `_Факт` и `_ТекПлан` имеют отдельную ветку только для итога; ветви
02–13 закомментированы и fallback опирается на фильтрацию соответствующих
таблиц. `_ТекПлан2` содержит явные ветви всех 13 статей, но его потребитель
в визуалах не доказан.

Недоступны M-код следующих таблиц: календарь, среднесрочный бюджет,
текущие планы членства/рецепции/ДРЦ/прочих статей, бюджеты DPFU/IP/рецепции/
ДРЦ/прочих и таблица актуальности. Пользователь подтвердил, что это внешние
Excel-факты той же структуры и периода, которые остаются в Power BI; поэтому
это не блокирует контракт PostgreSQL-факта. Их ключи, типы, связи и правила
месяц/день всё ещё требуют model/Excel validation перед implementation.

## Read-only пакет проверок

Это исходный перечень проверок. Его внутренние PostgreSQL-ветви выполнены и
документированы в SV-035—SV-050 и SV-066; `:schema` и `:table` заменяются
результатом preflight `pg_catalog`. Пункты про Excel остаются
`NOT_APPLICABLE` по подтверждённой границе проекта.

| Проверка | Точный запрос / действие | Ожидаемый результат |
|---|---|---|
| Metadata | `select n.nspname,c.relname,c.reltuples from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relname in ('_AccumRg7370','_AccumRg7575','_AccumRg7646','_AccumRg7739','_InfoRg6612','_Reference59','_Reference70','_Reference132','_Reference134','_Reference163');` | ровно один разрешённый relation на каждую используемую таблицу; типы/столбцы фиксируются из `pg_attribute` |
| Технические ключи | для каждого регистра: `select _RecorderRRef,_LineNo,count(*) from :register group by 1,2 having count(*)>1;` | 0 строк либо documented exception до любого join |
| NULL/orphan | `select count(*) filter (where club_ref is null), count(*) filter (where club_ref is not null and club.id is null) from :register r left join :clubs club on r.club_ref=club.id;` | orphan = 0 либо явный карантин; NULL объяснён для каждой ветви |
| Кардинальность и сумма | сравнить `sum(amount),count(*)` до/после каждого join и по каждой ветви `UNION ALL` | строки/сумма не размножаются; отклонение 0 либо зафиксированное правило |
| Состояния и знак | разрез `Active`, `Marked`, `Posted`, `RecordKind`, тип recorder, знак `Fld7377/Fld7586/Fld7659/Fld7749` | все включённые/исключённые статусы и правило PKO/возврата подтверждены; не NULL |
| Даты | `min(period),max(period), count(*) filter (where period < :start or period >= :end)` для текущей и BR-003 границ | выбранная пользователем политика имеет 0 строк вне `[start,end)`; отдельно проверить 1 января и 31 декабря |
| Членство | перекрёстный разрез 13 document joins и `Document332` | recorder относится к ожидаемой ветви, sign rule взаимоисключаема, исключение `Document332` не скрывает нужные движения |
| DPFU/рецепция | anti-join и пересечение `(register,recorder,line)` двух наборов классификации | один технический ключ попадает не более чем в одну категорию отчёта либо двойной учёт обоснован |
| Excel | `group by date, mapped_club, article having count(*)>1`; число NULL после каждого mapping и до/после FillDown | 0 неразрешённых NULL/дублей; FillDown не меняет unmapped строку на чужую статью |
| Планы | проверить ключ, `Active`, date/month, club/article coverage и сумму по дню/месяцу каждого плана | отдельные plan facts имеют известный grain; месячный план не присоединяется к факту |
| Power BI | проверить `Календарь`, `Клубы`, `Статьи` на unique key и coverage, затем связи `1:*` в одну сторону | 0 orphan; нет fact-to-fact, двунаправленных и many-to-many |
| Узкие случаи | отдельные выборки: границы дат; один contract с несколькими clients; child package; ties; as-of history; несколько freeze; employee на границе; отсутствующая ссылка | в текущем отчёте нет таких joins — ожидается `NOT_APPLICABLE`; если связь вводится, каждая выборка должна либо сохранить одну строку дневного агрегата, либо быть отклонена |
| Rerun/изменения | повторить extract в одинаковой точке времени и сверить checksum/суммы; затем проверить изменённые/удалённые recorder за рабочее окно | идентичный rerun даёт 0 различий; стратегия исправлений установлена до implementation |
| Performance | `EXPLAIN (ANALYZE, BUFFERS)` source aggregate с фактической границей и итогового view | SLA, строки и buffer usage записаны; индексы не предлагаются без этого плана |

Скриншоты используются как контроль Power BI после фиксации snapshot: для
июля-2026 на 12.07.2026 итоговые 220,8 млн / 235,5 млн / 68,5 млн / 189,6 млн.
Сверка без той же даты обновления не считается пройденной.

## Исполнимые запросы ключевых проверок

Эти запросы используют имена и поля ровно как в приложенном M. Запускать
только после preflight подтвердит search path/имена с ведущим `_`.

```sql
-- GK-R02: ключ движения и NULL ключа.
WITH x AS (
  SELECT '7575' AS source_kind, _RecorderRRef AS recorder, _LineNo AS line_no FROM _AccumRg7575
  UNION ALL SELECT '7646', _RecorderRRef, _LineNo FROM _AccumRg7646
  UNION ALL SELECT '7370', _RecorderRRef, _LineNo FROM _AccumRg7370
  UNION ALL SELECT '7739', _RecorderRRef, _LineNo FROM _AccumRg7739
)
SELECT source_kind, count(*) AS rows_total,
       count(*) FILTER (WHERE recorder IS NULL OR line_no IS NULL) AS null_key_rows,
       count(*) - count(DISTINCT (recorder, line_no)) AS duplicate_rows
FROM x GROUP BY source_kind;
-- Expected: null_key_rows = 0 and duplicate_rows = 0; otherwise key is rejected.
```

```sql
-- GK-R03: текущая граница M и состояния/знаки.
WITH bounds AS (
  SELECT date_trunc('year', current_date) - interval '2 years' AS fact_from,
         date_trunc('year', current_date) + interval '1 year' AS fact_to
), x AS (
  SELECT '7575' AS source_kind,_Period,_Active,NULL::integer AS record_kind,_Fld7586 AS amount FROM _AccumRg7575
  UNION ALL SELECT '7646',_Period,_Active,NULL::integer,_Fld7659 FROM _AccumRg7646
  UNION ALL SELECT '7370',_Period,_Active,_RecordKind,_Fld7377 FROM _AccumRg7370
  UNION ALL SELECT '7739',_Period,_Active,_RecordKind,_Fld7749 FROM _AccumRg7739
)
SELECT source_kind,_Active,record_kind,min(_Period),max(_Period),
       count(*) FILTER (WHERE _Period < fact_from OR _Period >= fact_to) AS out_of_current_horizon,
       count(*) FILTER (WHERE amount IS NULL) AS null_amount_rows,
       count(*) FILTER (WHERE amount=0) AS zero_amount_rows,
       count(*) FILTER (WHERE amount<0) AS negative_amount_rows
FROM x CROSS JOIN bounds GROUP BY source_kind,_Active,record_kind;
-- Expected: result records the distribution; the selected final policy then has 0 rows outside [from,to).
```

```sql
-- GK-R04: orphan клуб/услуга для двух общих регистров.
SELECT '7575.club' AS check_name,count(*) AS orphan_rows
FROM _AccumRg7575 a LEFT JOIN _Reference132 c ON c._IDRRef=a._Fld7577RRef
WHERE a._Fld7577RRef IS NOT NULL AND c._IDRRef IS NULL
UNION ALL
SELECT '7575.service',count(*) FROM _AccumRg7575 a LEFT JOIN _Reference163 s ON s._IDRRef=a._Fld7579RRef
WHERE a._Fld7579RRef IS NOT NULL AND s._IDRRef IS NULL
UNION ALL
SELECT '7646.club',count(*) FROM _AccumRg7646 a LEFT JOIN _Reference132 c ON c._IDRRef=a._Fld7653RRef
WHERE a._Fld7653RRef IS NOT NULL AND c._IDRRef IS NULL
UNION ALL
SELECT '7646.service',count(*) FROM _AccumRg7646 a LEFT JOIN _Reference163 s ON s._IDRRef=a._Fld7649RRef
WHERE a._Fld7649RRef IS NOT NULL AND s._IDRRef IS NULL;
-- Expected: 0 in every row or an explicit source-side quarantine rule.
```

```sql
-- GK-R06: кандидаты пересечения 7575 и 7646; не дедуплицировать автоматически.
WITH v AS (
  SELECT _Period::date AS event_date,_Fld7577RRef AS club_id,_Fld7579RRef AS service_id,
         _Fld7578_RRRef AS basis_id,_Fld7585 AS qty,_Fld7586 AS amount,
         _RecorderTRef AS recorder_type,_RecorderRRef AS recorder,_LineNo AS line_no
  FROM _AccumRg7575
), s AS (
  SELECT _Period::date AS event_date,_Fld7653RRef AS club_id,_Fld7649RRef AS service_id,
         _Fld7647_RRRef AS sale_document_id,_Fld7657 AS qty,_Fld7659 AS amount,
         _RecorderTRef AS recorder_type,_RecorderRRef AS recorder,_LineNo AS line_no
  FROM _AccumRg7646
)
SELECT v.event_date,v.club_id,v.service_id,v.basis_id,v.recorder,v.line_no,s.recorder,s.line_no,v.qty,v.amount
FROM v JOIN s ON s.sale_document_id=v.basis_id AND s.event_date=v.event_date
            AND s.club_id=v.club_id AND s.service_id=v.service_id AND s.qty=v.qty AND s.amount=v.amount;
-- Expected: each result row is reviewed and the two report categories stay mutually exclusive.
```

```sql
-- GK-R07: source grain текущего плана ДПФУ.
SELECT _Fld6613::date AS plan_date,_Fld6615RRef AS club_id,_Fld6614RRef AS segment_id,
       _Fld6616RRef AS employee_id,_Fld6617RRef AS client_id,_Fld6618 AS planning_period,
       count(*) AS rows,sum(_Fld6620) AS revenue
FROM _InfoRg6612
GROUP BY 1,2,3,4,5,6 HAVING count(*)>1;
-- Expected: 0 duplicates at raw business-dimension grain, or an explicit aggregation rule before club/day output.
```
