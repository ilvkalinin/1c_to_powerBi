# Readiness перехода из Stage 2 в Stage 3 — 2026-08-13

Статус: `DECISION_REQUIRED — отдельное разрешение на STAGE_3_IMPLEMENTATION`.

## Граница решения

Этот документ не переводит проект на Stage 3 и не является разрешением на
DDL/DML. Он фиксирует доказательную готовность после закрытия всех
checkpoint-пакетов Stage 2. Реестр физических отсутствий закрыт SV-090: на
2026-08-13 в `gymdb.public` нет доказанно отсутствующего relation из contract
scope. Это не отменяет report-specific controls и не меняет текущие SQL/M/DAX
без решения по BR-018.

Переход следует разделять на два решения:

1. `PROGRAM ENTRY` — разрешить начать Stage 3 только с отчётных продуктов
   класса `A` ниже; перед каждой опасной операцией показывается SQL.
2. `PRODUCT ADMISSION` — разрешить конкретный продукт после выполнения его
   обязательных предреализационных условий. Строка класса `B` или `C` не
   становится SQL-задачей автоматически.

## Классы готовности

| Класс | Значение | Допустимое действие после PROGRAM ENTRY |
|---|---|---|
| A | Stage 2 evidence в contract scope `COMPLETE`; известного report-specific implementation blocker нет | можно подготовить отдельный Stage-3 пакет реализации с mapping/data contract как границей |
| B | source-side checkpoint закрыт, но остаются физические/контрольные условия, не требующие изменения методики | отдельный Stage-3 пакет возможен только после явного перечисления этих условий в его плане |
| C | известен implementation blocker, `DECISION_REQUIRED` либо риск, для которого current result нельзя выбрать без явного BR-018 решения | не начинать реализацию продукта до закрытия указанного условия |

Класс — не оценка важности отчёта и не изменение договорного scope. Он нужен
только для безопасного порядка реализации.

## Матрица 31 договорного отчёта

| № | Отчёт | Stage 2 evidence | Класс | Условие перед product admission |
|---:|---|---|---|---|
| 1 | KPI Фитнеса | COMPLETE SV-054—SV-061 | A | отдельный Stage-3 пакет и разрешение опасных операций |
| 2 | Вовлечение новичков | PARTIALLY VALIDATED SV-075, SV-092 | B | class-B учёт закрыт: перенести existing source controls в план реализации, без нового user decision |
| 3 | Вовлечение новичков Второй месяц | PARTIALLY VALIDATED SV-076 | C | class-C review: нового решения нет — product plan сохраняет legacy `RANK()` ties и source-row identity; без silent dedup |
| 4 | Подготовка к продлению | PARTIALLY VALIDATED SV-077 | B | class-B учёт закрыт: product plan сохраняет current pair/границы, technical keys и запрет silent state/dedup changes |
| 5 | Воронка лиды фитнес | PARTIALLY VALIDATED SV-078 | B | class-B учёт закрыт: product plan сохраняет `task_id`, client-code/date attribution и observed task→service cardinality |
| 6 | Загрузка сотрудников | PARTIALLY VALIDATED SV-074 | C | class-C review: нового решения нет; не вводить historical rank без отдельного auditable source control |
| 7 | Контроль предварительной записи | PARTIALLY VALIDATED SV-072 | C | class-C review: product plan сохраняет legacy VT4352 multiplicity, orphan-enum inner join и current document/registry branches |
| 8 | Отчёт по ИП | PARTIALLY VALIDATED SV-058, SV-068 | B | class-B учёт закрыт: общий IP-факт сохраняет observed branch multiplicity по BR-018 |
| 9 | Посещения Физкульт | PARTIALLY VALIDATED SV-070 | B | class-B учёт закрыт: product plan сохраняет client-day grain, actual club и пересекающиеся current categories |
| 10 | Уроки и расписание | PARTIALLY VALIDATED SV-073 | C | class-C review: product plan сохраняет current interval/state branches и orphan dimensions без silent normalization |
| 11 | Фитнес воронка | PARTIALLY VALIDATED SV-079 | B | class-B учёт закрыт: product plan сохраняет cohort `client × start`, outcome dates и отсутствие contract attribution |
| 12 | Загрузка ОП | PARTIALLY VALIDATED SV-084 | B | class-B учёт закрыт: product plan сохраняет interaction/phone grain, role dates и внешние нормативы |
| 13 | Отчёт по поступлениям | PARTIALLY VALIDATED SV-083 | C | class-C review: product plan сохраняет analytics_sequence, predecessor `MIN(ID)` и current state/sign cases; physical key remains control |
| 14 | Отчёт по промокодам | PARTIALLY VALIDATED SV-090, SV-091 | C | class-C review: product plan сохраняет legacy MAX/SUM/Table.Distinct и DAX fallback; без silent document-line/action/gift dedup |
| 15 | Продажа детских пакетов | PARTIALLY VALIDATED SV-085 | C | class-C review: no user decision; SQL remains blocked pending line-to-line price/product, return-sign and source-state control |
| 16 | Управление продлением | PARTIALLY VALIDATED SV-081 | C | class-C review: preserve current same-client/first-start rule and source cases; SQL awaits independent full-cardinality controls |
| 17 | Отчёт по %Renew | PARTIALLY VALIDATED SV-082 | B | class-B учёт закрыт: product plan сохраняет current window/`COUNT(*)`, `Fld693` и closed-month finalization |
| 18 | Выручка рецепции | COMPLETE SV-050—SV-053 | A | отдельный Stage-3 пакет; `_document294` не добавлять без решения о смене атрибуции |
| 19 | Записи администраторов | PARTIALLY VALIDATED SV-086 | C | class-C review: сохранять document grain и current кадровое правило; SQL ждёт controls записи × движения, не автоматический historical match |
| 20 | Новички и гостевые визиты | PARTIALLY VALIDATED SV-087 | C | class-C review: сохранять current `Distinct`/окна и отсутствие status-filter; SQL ждёт controls ключей, states и outcomes |
| 21 | Отчёт по обращениям | PARTIALLY VALIDATED SV-088 | C | определить deterministic aggregation `Reference67 → Reference137`; не скрывать source multiplicity |
| 22 | Посещаемость клиентов с долгами | PARTIALLY VALIDATED SV-089 | C | подтвердить key/state `AccumRg7509`, document branches и as-of control values |
| 23 | Посещения Пушкинский | PARTIALLY VALIDATED SV-071 | B | class-B учёт закрыт: общий visit/day layer сохраняет snapshot, categories и approved DRC exclusion |
| 24 | Работа с посещаемостью | PARTIALLY VALIDATED SV-065, SV-067 | B | class-B учёт закрыт: product plan сохраняет daily client-base и documented historical-performance control |
| 25 | Карта администратора | PARTIALLY VALIDATED SV-002 | C | выполнить Stage-3 controls: Gymmy success, 12 club codes, sums before/after aggregation, rerun |
| 26 | Титульный лист | COMPLETE SV-062—SV-064 | A | отдельный Stage-3 пакет реализации |
| 27 | Маркетинговая воронка | PARTIALLY VALIDATED SV-080 | C | решение по aggregation/deduplication before implementation |
| 28 | Клиентская база | PARTIALLY VALIDATED SV-069 | C | states/types/keys и control values for both snapshot dates |
| 29 | Выручка ДПФУ | COMPLETE SV-054—SV-057 | A | отдельный Stage-3 пакет реализации общего ancillary product |
| 30 | Членство для правления | PARTIALLY VALIDATED SV-083 | C | inherited receipt key/states plus board KPI reconciliation and non-additive aggregation controls |
| 31 | Свод выручка ГК | PARTIALLY VALIDATED SV-035—SV-050, SV-066 | B | class-B учёт закрыт: product plan реализует только validated internal PostgreSQL branches; external Excel branches остаются в Power BI |

## Очередность после разрешения Stage 3

1. Первая волна — только класс A: `Выручка ДПФУ` как переиспользуемый факт,
   затем `Выручка рецепции`, `KPI Фитнеса` и `Титульный лист` в отдельных
   утверждённых пакетах. Порядок не разрешает DDL без просмотра SQL.
2. Вторая волна — класс B только после product-admission checklist в каждом
   пакете; это не повторный Stage-2 прогон без нового триггера.
3. Класс C остаётся вне реализации, пока не закрыт ровно названный blocker или
   не принято решение BR-018. Нельзя подменить это решение технической
   эвристикой.

## Общие условия PROGRAM ENTRY

- явное разрешение пользователя на `STAGE_3_IMPLEMENTATION`;
- отдельный Stage-3 пакет с ограниченным составом продуктов;
- review SQL перед любой опасной операцией, отдельные миграции и rollback;
- исходный `gymdb` остаётся read-only; полная копия raw-регистров запрещена;
- Power BI external Excel и его Power Query не анализируются и не переносятся;
- BR-018 сохраняет current SQL/M/DAX до отдельного решения о методике.

## Evidence

- [contract scope](contract_scope.md);
- [.agents/report_checkpoint_ledger.tsv](../../.agents/report_checkpoint_ledger.tsv);
- [missing source objects](../source_metadata/missing_source_objects.md);
- [server validation](../source_metadata/server_validation_2026-08-05.md).
