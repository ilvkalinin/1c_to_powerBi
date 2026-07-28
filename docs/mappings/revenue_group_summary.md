# Source-to-target mapping: Свод выручка ГК

Статус: `DESIGNED / TECHNICAL VALIDATION REQUIRED / IMPLEMENTATION DEFERRED`.

Этот mapping фиксирует текущий отчётный результат, а не разрешает создание
физической витрины. Никакого SQL/DDL для VM-1 или VM-2 не создано.

Гранулярность одной строки текущего составного факта:

> дата факта × клуб × статья выручки.

`source_branch` нужен до финальной агрегации для проверки суммы и не является
подтверждённым отображаемым полем Power BI. Логический ключ конечной строки
`(revenue_date, club_id, revenue_article_code)` — `ASSUMPTION`: текущий M
использует имена клубов, а стабильность ID и непересечение ветвей не проверены.
В scope входят все текущие статьи `02`–`13` (`CONFIRMED — user decision
2026-07-28`); `01` вычисляется DAX-мерой.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица / поле | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `revenue_date` | день факта | `AccumRg7370/7575/7646/7739.Period`; Excel `Дата` | `::date`; `UNION ALL` ветвей | `date` | нет | дата×клуб×статья | CONFIRMED | M | date bounds |
| `club_id` | устойчивый клуб | ссылки клубов регистров; Excel через `СпрЦЗ` | канонический текстовый hex ключ из физической ссылки; Excel mapping возвращает тот же ключ | `text` | нет | то же | ASSUMPTION — физический тип подтверждается pg_catalog | M + metadata | source type, orphan, unique club dimension |
| `revenue_article_code` | параметр/статья | константа ветви или Excel mapping | `02`–`13`; `01.ВЫРУЧКА ВСЕГО` — только DAX-итог | `text` | нет | то же | CONFIRMED — user decision | M/DAX + decision | coverage, mapping NULL |
| `revenue_amount` | знаковая фактическая выручка | `Fld7377`, `Fld7586`, `Fld7659`, `Fld7749`, Excel `Сумма` | текущие sign CASE/`SUM`; до финала по branch | `numeric` | нет | то же | CONFIRMED current rule / states pending | M | branch reconciliation |

Технический `source_branch` (membership/DPFU/IP/reception/other) используется
только во временной source-side сверке. Он не является колонкой конечного
факта: после проверки сумм ветви агрегируются до ключа факта.

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `AccumRg7370` | авансы по абонементам: членство и ИП | CONFIRMED source / sign validation pending | M + source metadata |
| `AccumRg7575` | посещения/оказанные услуги: ДПФУ и рецепция | CONFIRMED source / state validation pending | M + source metadata |
| `AccumRg7646` | продажи: ДПФУ и рецепция | CONFIRMED source / state validation pending | M + source metadata |
| `AccumRg7739` | расчёты с контрагентами: товары членства | CONFIRMED source / state validation pending | M + source metadata |
| `InfoRg6612` | дневной текущий план ДПФУ | CONFIRMED source / separate plan grain pending | M + source metadata |
| `Reference59/70/132/134/163` и recorder documents | классификация/клуб/тип движения | CONFIRMED source / join cardinality pending | M + source metadata |
| Excel 2025/2026 прочей выручки и 2 справочника | остальные статьи и mapping ЦФО/статьи | CONFIRMED external / schema pending | M |
| бюджеты и текущие планы | отдельные Excel-факты Power BI | CONFIRMED external / remain as is | user decision 2026-07-28 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `source_objects` | найдены `AccumRg7370/7575/7646/7739`, `InfoRg6612`, клубы/услуги/контракт | CONFIRMED |
| Проверенные продукты из `data_products` | DPFU logical fact и `mart.ancillary_revenue_movement`; `v_reception_revenue_daily` | CONFIRMED |
| Проверенные правила | BR-001, BR-002, BR-003, BR-004, BR-010, BR-013 | CONFIRMED; user selected BR-003 |
| Сравнение гранулярности | общий ancillary факт детальнее; отчёт — дневной клуб×статья. План не совпадает с фактом | CONFIRMED |
| Сравнение ключей | ancillary candidate `(source_kind,recorder,line)`; current report keys text-only | BLOCKER: uniqueness/cardinality pending |
| Сравнение бизнес-семантики | DPFU и рецепция совпадают с существующим доменом; членство, ДРЦ и прочая выручка имеют отдельные правила/источники | CONFIRMED |
| Решение (`REUSE` / `EXTEND` / `NEW` / `NOT_APPLICABLE`) | `EXTEND` ancillary для DPFU/рецепции; `REUSE` IP source rule only; `NEW` compact report aggregate для членства/ДРЦ/прочей выручки | CONFIRMED — ADR-0010 |
| Причина решения | не дублировать 7575/7646; не объединять планы с фактами; все 13 статей сохраняются | CONFIRMED evidence + decision |
| Затронутые существующие потребители | Выручка ДПФУ, Выручка рецепции, Записи администраторов | CONFIRMED catalogs/ADR-0004/0005 |

## Неизвестные поля, риски и отклонённые связи

| Статус | Элемент | Риск / причина | Проверка / следующее действие |
|---|---|---|---|
| CONFIRMED | scope | статьи 02–13 сохраняются; 01 — DAX-итог | user decision 2026-07-28 |
| CONFIRMED | история | применяется BR-003, не текущий широкий M-диапазон | user decision 2026-07-28 |
| NOT_APPLICABLE | планы/бюджеты PostgreSQL | Excel-факты остаются в Power BI; прямой join с фактом запрещён | user decision 2026-07-28 |
| BLOCKER | ключи/статусы/знаки | агрегации скрывают дубли и состояние движений | read-only пакет в query review |
| UNKNOWN | схема Power BI | нет diagram/relationships | экспорт модели или read-only inspection PBIX |
| REJECTED | прямой join плана к факту | разные grain, риск раздувания сумм | использовать только общие Date/Club/Article dimensions |
| NOT_APPLICABLE now | клиент, contract, child package, freezes, employee/as-of/ties | текущий вывод не содержит этих joins | не вводить без отдельного mapping и tests |
