# Разбор текущих запросов: «Отчет по обращениям»

Статус: `BUSINESS REVIEW COMPLETE / STAGE_2 SOURCE VALIDATION PARTIALLY VALIDATED — SV-088, SV-098`.

Источники:

- `Отчет по обращениям.docx`, SHA-1 `bf981ed05fc109a6581c9b1f81c2434c3d332bf4` — описание четырёх страниц;
- `отчетпообращениям.docx`, SHA-1 `9c084cf330d196edb9ec2906e70604fd285b0bff` — Power Query и DAX.

SV-098 добавил narrow read-only evidence для feedback core, HTML,
PK-side dimensions, first-followup ordering, comments и source states.
CR-V05A подтвердил шесть тем и четыре из пяти документированных воронок.
Пользователь подтвердил, что source-название `Продажа клип карты Рецепция`
соответствует документированной воронке; BR-023 фиксирует её единственный
`Reference89._idrref`, поэтому filter не зависит от написания. Непройденные
controls сохраняют свой статус и не считаются пройденными по косвенным
результатам.

## Stage 2 checkpoint — SV-088 (2026-08-12)

Для центрального CRM-path переиспользованы live read-only результаты
SV-024—SV-034: `_reference67._idrref` — physical PK; task и task dimensions
на PK-side не размножают interaction; `InfoRg7146` имеет отдельный technical
key и 3 103 interactions с 2–3 phone rows в 2026. Это подтверждает, что
current direct phone join нельзя схлопывать как технический duplicate.

Новый SQL-контроль [`calls_report_2026-08-12.sql`](../source_metadata/validation_sql/calls_report_2026-08-12.sql)
сохраняется как исходный артефакт. Выполненный
[`SV-098 SQL`](../source_metadata/validation_sql/calls_report_global_review_2026-08-17.sql)
подтвердил HTML cardinality, first non-feedback follow-up ordering и comment
ties на bounded controls. Точные filter scopes, visit denominator и
независимая Power BI reconciliation остаются `VALIDATION_PENDING`.

## Наборы Power Query

| Набор | Источники | Назначение | Наблюдение |
|---|---|---|---|
| `_Даты` | `InfoRg6015` | календарь | источник/модель справочника не включаются в mapping факта |
| `ОСобработкаЗадач2026` | `Reference67`, `Reference106`, темы, CRM-справочники, телефония, HTML | общие данные, рейтинг, вовлечённость | жёстко ограничен 2026 и шестью темами |
| `Задания со звонком` | `Reference67`, `Reference106`, `InfoRg7146`, темы | классификация «Дозвонились / НБТ / Не звонили» | детали M-правила требуют сохранения отдельно от нового набора |
| `Посещения` | `AccumRg7575`, `Document325`, контракт, клиент, клуб | знаменатель 10 000 посещений | считает движения/ссылки, не distinct клиентов |
| `ОС со звонками` | `Reference67`, `Reference106`, телефония, CRM-справочники, HTML | страница отработки | собранный SQL ближе к текущей логике 2025+ |

## Подтверждённая текущая SQL-логика

### Обратная связь

`ОС со звонками` оставляет interactions `Reference67` с type GUID
`9db9fdbf6bd80f2044eb2835157b3bc8` («Обратная связь»), созданные с
`2025-01-01` до текущей даты. Исключается имя interaction с `Jivo`.

Task join поставляет клиента, клуб, воронку, отдел, тему, кампанию, канал,
регламент, должность и стаж. CRM status GUID классифицируются как
«Выполнено», «Не выполнено», «Отменено»; tenure GUID — New/Ex/Renew.

HTML из `Reference137` очищается регулярными выражениями: содержимое `<body>`
без `<p>`, с нормализованными пробелами; когда body отсутствует, сохраняется
исходный HTML. Текст комментария содержит ПДн/содержимое обращения и доступен
всем пользователям, имеющим доступ к отчёту — `CONFIRMED`, решение
пользователя 2026-07-29.

### Схлопывание строк

`grouped` группирует по клиентскому коду, ФИО, клубу, заданию и всем
пользовательским атрибутам, но **не по `Reference67.ID`**. Даты агрегируются
`MAX`, комментарии — `STRING_AGG(DISTINCT ...)`, изменение — `MIN` после
создания. Поэтому несколько разных обратных связей с тем же набором атрибутов
могут быть объединены. Это нельзя принимать как бизнес-grain без проверки.

### Отработка и время ответа

В `connections_out` сохранены все interaction, кроме обратной связи; не
ограничены типом «Исходящий звонок», хотя `CASE` присваивает такое имя только
одному GUID. Значит первый последующий event по клиенту и task может быть не
исходящим звонком. `call_after` выбирает минимальную `createdate` такого
события после создания feedback.

`МинутДоЗвонка = (COALESCE(ДатаПервогоЗвонка, ДатаИзменения) - ДатаСоздания)`.
Колонка `ДатаОтработки` выбирает тот же COALESCE, но текущая мера
`__СреднееВремяОтвета` отбрасывает строки без `ДатаПервогоЗвонка`; название
«среднее» также не соответствует функции `MEDIANX`. Пользователь подтвердил
2026-07-29, что отработка изменением без звонка должна входить в показатель:
целевая мера — медиана `МинутДоЗвонка` по всем строкам с `ДатаОтработки`.

### Посещения

Запрос соединяет `AccumRg7575` с `Document325`, клиентом, контрактом и
клубами; оставляет один GUID вида посещения, клиентов с одним GUID типа и
период с 2025 года до текущего дня. Он группирует по
`Period::date × client code × club visit` и считает ссылку на контракт.
Фактический клуб берётся из `Document325.Fld4167`; основной клуб доступа
присутствует только справочно.

## Риски и несостыковки

1. Прямой join `Reference67 → InfoRg7146` и `Reference67 → Reference137` может
   размножить interaction; последующее business grouping скрывает это.
2. Правило первого «звонка» в текущем SQL фактически означает первое
   последующее **не-feedback interaction**. По решению пользователя 2026-07-30
   это правило сохраняется; ограничение только телефонными звонками не вводится.
3. Ассоциация follow-up выполняется по `КодКлиента × КодЗадания`, а не
   стабильным ID; уникальность кода и смысл связи не доказаны.
4. SQL не проверяет `Marked`, archived flags, статусы проведения и удаления.
5. Старый dataset задаёт шесть тем, а набор скорости/качества намеренно иной:
   пользователь подтвердил не объединять эти фильтры. Точные ID/коды его
   воронок, тем и Jivo-исключений всё ещё требуют V-05.
6. Количество обращений — distinct `Комментарий × КодКлиента`, тогда как
   невыполненные — count rows. Пустые/одинаковые комментарии меняют числитель.
7. Пользователь выбрал срок выполнения от creation date до end date. Текущая
   DAX использует planned date, поэтому её группы «01 день», «02–03»,
   «04–07», «больше 7» должны быть пересчитаны только после V-01.
8. В SQL «ОС со звонками» время обновления комментария выбирается как первая
   дата после создания, но не доказано, что это именно действие сотрудника по
   обратной связи.
9. Посещения и обращения связаны лишь через общие дату и отображаемое название
   клуба; модель связей и таблицы 2024/2025 не переданы.

## Пакет будущей read-only валидации

Каждая проверка: `VALIDATION_PENDING`; ожидаемый результат обязателен.

| ID | Проверка | Ожидаемый результат |
|---|---|---|
| V-01 | схема, отношения, колонки и типы всех источников mapping | один однозначный физический объект и зафиксированные типы |
| V-02 | уникальность `Reference67.ID`, `Reference106.ID` и кодов | ID без дублей; код не используется как ключ, если не уникален |
| V-03 | кардинальность phone и HTML по interaction | правило агрегации даёт ровно одну строку на interaction |
| V-04 | candidate fact после всех dimension joins | `COUNT(*) = COUNT(DISTINCT interaction_id)` до intentional bridges |
| V-05 | точный набор type/status/theme/funnel/campaign GUID и Jivo-исключений отдельно для набора шести тем и набора скорости/качества | CR-V05A: шесть тем и четыре воронки имеют ровно один physical match; BR-023 фиксирует пятую воронку через единственный `Reference89._idrref`. Speed/quality, Jivo и state scopes остаются pending. |
| V-06 | первый event после feedback | event имеет подтверждённый type «Исходящий звонок», либо правило уточнено |
| V-07 | HTML update и follow-up call | даты не предшествуют creation, ties имеют deterministic tie-break |
| V-08 | посещения | один и тот же business visit не дублируется join контрактов; дневная сумма сверяется |
| V-09 | состояния/удаления/архивность | допустимые source flags зафиксированы и применены |
| V-10 | сверка с Power BI | count feedback, not done, worked, медиана ответа с отработкой изменением, visits и rate/10k совпадают на согласованном периоде |
| V-11 | изменения, удаления, rerun, объём и ежедневный refresh | результат повторяем, выбранное окно исправлений доказано, ежедневное обновление укладывается в согласованный SLA |

### SQL-шаблоны второго этапа

```sql
-- V-02: уникальность центрального ключа interaction.
-- NOT_EXECUTED — ожидается подключение к корпоративной сети
SELECT _IDRRef, COUNT(*)
FROM <source_schema>._Reference67
GROUP BY _IDRRef
HAVING COUNT(*) > 1;

-- V-03: потенциальное размножение телефонией и HTML.
-- NOT_EXECUTED — ожидается подключение к корпоративной сети
SELECT i._IDRRef AS interaction_id,
       COUNT(DISTINCT p._Fld7151RRef) AS phone_rows,
       COUNT(DISTINCT h._IDRRef) AS html_rows
FROM <source_schema>._Reference67 i
LEFT JOIN <source_schema>._InfoRg7146 p ON p._Fld7151RRef = i._IDRRef
LEFT JOIN <source_schema>._Reference137 h ON h._Fld1462RRef = i._IDRRef
WHERE i._Fld831RRef = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
GROUP BY i._IDRRef
HAVING COUNT(DISTINCT p._Fld7151RRef) > 1
    OR COUNT(DISTINCT h._IDRRef) > 1;

-- V-06: подтвердить, что current first follow-up — первое последующее
-- не-feedback interaction в той же паре task × client.
-- NOT_EXECUTED — ожидается подключение к корпоративной сети
WITH feedback AS (
  SELECT f._IDRRef, f._OwnerIDRRef, f._Fld823
  FROM <source_schema>._Reference67 f
  WHERE f._Fld831RRef = decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
), candidate AS (
  SELECT f._IDRRef AS feedback_id, o._Fld831RRef AS event_type_id,
         o._Fld823 AS followup_created_at,
         ROW_NUMBER() OVER (
           PARTITION BY f._IDRRef ORDER BY o._Fld823, o._IDRRef
         ) AS rn
  FROM feedback f
  JOIN <source_schema>._Reference67 o
    ON o._OwnerIDRRef = f._OwnerIDRRef
   AND o._Fld823 >= f._Fld823
   AND o._Fld831RRef <> decode('9db9fdbf6bd80f2044eb2835157b3bc8', 'hex')
)
SELECT feedback_id, event_type_id, followup_created_at
FROM candidate
WHERE rn = 1;
```
