# Source-to-target mapping: Свод выручка ГК

Статус: `DESIGNED / TECHNICAL VALIDATION REQUIRED / IMPLEMENTATION DEFERRED`.

Этот mapping фиксирует текущий отчётный результат, а не разрешает создание
физической витрины. Никакого SQL/DDL для VM-1 или VM-2 не создано.

Гранулярность одной строки текущего составного факта:

> дата факта × клуб × статья выручки.

`source_branch` нужен до финальной агрегации для проверки суммы и не является
подтверждённым отображаемым полем Power BI. Технический ключ исходного
движения — `(recorder_type, recorder_id, line_no)`; он подтверждён SV-035 для
всех четырёх регистров. Логический ключ внутренней PostgreSQL-части
`(revenue_date, club_id, revenue_article_code)` подтверждён SV-048:
9 623 строки и 0 повторов после агрегации четырёх текущих внутренних ветвей.
Excel-ветви не входят в это утверждение и остаются без анализа по явному
решению пользователя.
В scope входят все текущие статьи `02`–`13` (`CONFIRMED — user decision
2026-07-28`); `01` вычисляется DAX-мерой.

Пакетный audit 2026-08-11 подтвердил, что mapping согласован с полным
PBIT/M/DAX и `SV-035`–`SV-050`. Решение о reuse не изменяется: DPFU и рецепция
расширяют существующий квалифицированный домен, правила ИП переиспользуются
без второй копии, а членство/ДРЦ и прочая выручка остаются частью отдельного
дневного агрегата. Новые read-only запросы на этом локальном этапе не
выполнялись.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Исходная таблица / поле | Преобразование | PostgreSQL тип | NULL | Гранулярность | Статус | Источник подтверждения | Тест |
|---|---|---|---|---|---|---|---|---|---|
| `revenue_date` | день факта | `AccumRg7370/7575/7646/7739.Period`; Excel `Дата` | `::date`; `UNION ALL` ветвей; для ИП сворачивает текущие timestamp-строки без изменения суммы (SV-046) | `date` | нет | дата×клуб×статья | CONFIRMED | M + server result | date bounds |
| `club_id` | устойчивый клуб | ссылки клубов регистров; Excel через `СпрЦЗ` | канонический текстовый hex физической `bytea`-ссылки; текущий PBIT использует отображаемое название клуба | `text` | допускается только для текущей ветки ИП: 17 дневных ключей на её полном диапазоне (SV-049) | то же | CONFIRMED source key — SV-066; текущая модель подтверждена по названию клуба | M + metadata | source type, orphan, unique club dimension |
| `revenue_article_code` | параметр/статья | константа ветви или Excel mapping | `02`–`13`; `01.ВЫРУЧКА ВСЕГО` — только DAX-итог | `text` | нет | то же | CONFIRMED — user decision | M/DAX + decision | coverage, mapping NULL |
| `revenue_amount` | знаковая фактическая выручка | `Fld7377`, `Fld7586`, `Fld7659`, `Fld7749`, Excel `Сумма` | текущие sign CASE/`SUM`; `_active` не фильтруется, как в M | `numeric` | нет | то же | CONFIRMED current rule / SV-036 | M + server result | branch reconciliation |

Технический `source_branch` (membership/DPFU/IP/reception/other) используется
только во временной source-side сверке. Он не является колонкой конечного
факта: после проверки сумм ветви агрегируются до ключа факта.

## Подтверждённые источники

| Объект | Назначение | Статус | Доказательство |
|---|---|---|---|
| `AccumRg7370` | авансы по абонементам: членство и ИП | CONFIRMED source / status distribution validated (SV-036) | M + source metadata |
| `AccumRg7575` | посещения/оказанные услуги: ДПФУ и рецепция | CONFIRMED source / status distribution validated (SV-037) | M + source metadata |
| `AccumRg7646` | продажи: ДПФУ и рецепция | CONFIRMED source / status distribution validated (SV-037) | M + source metadata |
| `AccumRg7739` | расчёты с контрагентами: товары членства | CONFIRMED source / status distribution validated (SV-036) | M + source metadata |
| `InfoRg6612` | дневной текущий план ДПФУ | CONFIRMED source / separate plan grain pending | M + source metadata |
| `Reference59/70/132/134/163` и recorder documents | классификация/клуб/тип движения | CONFIRMED source / join cardinality pending | M + source metadata |
| Excel 2025/2026 прочей выручки и 2 справочника | остальные статьи и mapping ЦФО/статьи | CONFIRMED external / остаётся без анализа и изменений в Power BI | решение пользователя 2026-08-05 |
| бюджеты и текущие планы | отдельные Excel-факты Power BI | CONFIRMED external / remain as is | user decision 2026-07-28 |

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники из `source_objects` | найдены `AccumRg7370/7575/7646/7739`, `InfoRg6612`, клубы/услуги/контракт | CONFIRMED |
| Проверенные продукты из `data_products` | DPFU logical fact и `mart.ancillary_revenue_movement`; `v_reception_revenue_daily` | CONFIRMED |
| Проверенные правила | BR-001, BR-002, BR-003, BR-004, BR-010, BR-013 | CONFIRMED; user selected BR-003 |
| Сравнение гранулярности | общий ancillary факт детальнее; отчёт — дневной клуб×статья. План не совпадает с фактом | CONFIRMED |
| Сравнение ключей | ключ движения `(recorder_type, recorder_id, line_no)` уникален и NOT NULL во всех 4 регистрах (SV-035); ДПФУ и рецепция по текущим фильтрам не пересекаются (SV-039); внутренний агрегат уникален по `(дата, клуб, статья)` (SV-048) | CONFIRMED technical key / anti-overlap validated |
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
| CONFIRMED | ключи/статусы/знаки внутренней PostgreSQL-части | движение, знаки, клубный ключ и итоговый ключ проверены SV-035–SV-048, SV-066 | текущая логика PBIT сохранена; Excel не входит в проверку |
| CONFIRMED current model | схема Power BI | PBIT показывает `_Спр Дата`, `_СпрКлубы`, `_СпрКонсолидаций`, `_ПереключательМер`; факт, план и бюджет связаны только через общие измерения | `Свод выручка ГК.pbit`; покрытие 15 клубов и физическая уникальность названий — SV-049 |
| CONFIRMED current rule | пустой клуб ветки ИП | 17 дневных ключей и 448 907,18 на полном текущем диапазоне PBIT сохраняются без подстановки клуба | SV-049; улучшение допускается только отдельным изменением методики |
| REJECTED | прямой join плана к факту | разные grain, риск раздувания сумм | использовать только общие Date/Club/Article dimensions |
| NOT_APPLICABLE now | клиент, contract, child package, freezes, employee/as-of/ties | текущий вывод не содержит этих joins | не вводить без отдельного mapping и tests |
