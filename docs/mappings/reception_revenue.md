# Source-to-target mapping: выручка рецепции

Статус: `BUSINESS MAPPING COMPLETE / TECHNICAL VALIDATION DEFERRED`.

SQL и физические объекты не создаются в рамках текущего этапа.

Архитектурное направление после mapping зафиксировано в
[`ADR-0005`](../adr/0005-shared-ancillary-revenue.md); реализация отложена до
технической валидации.

## Компонент A: факт

Предварительная гранулярность:

> дата движения × клуб × сотрудник × номенклатура × вид деятельности ×
> категория рецепции × тип исходного регистра.

Логический ключ:

> `(revenue_date, club_id, employee_id, service_id, activity_id,
> reception_category_key, source_kind)`.

До агрегации кандидат технического ключа:

> `(source_kind, Recorder, LineNo)`.

| Целевая колонка | Бизнес-описание | Источник / преобразование | Тип PostgreSQL | NULL | Статус / доказательство | Проверка |
|---|---|---|---|---|---|---|
| `revenue_date` | дата факта | `AccumRg7575.Period::date` / `AccumRg7646.Period::date` | `date` | нет | CONFIRMED current rule | диапазон и timezone |
| `source_kind` | регистр-источник | константа `visit/sale` | `smallint`/`text` | нет | CONFIRMED BY DESIGN | пересечение |
| `club_id` | клуб движения | `Fld7577` / `Fld7653` | UNKNOWN | нет | CONFIRMED metadata | orphan |
| `employee_id` | сотрудник продажи для рейтинга | `AccumRg7575`: через `Fld7578 Основание → Document346.Fld4909`; `AccumRg7646`: `Fld7652`, сверить с `Document346.Fld4909` | UNKNOWN | да | screenshot rejects Fld7582 / target ASSUMPTION | контрольный чек и consultant |
| `service_id` | номенклатура | `Fld7579` / `Fld7649` | UNKNOWN | нет | CONFIRMED metadata | orphan |
| `activity_id` | вид деятельности | `Reference163.Fld1733 → Reference70.ID` | UNKNOWN | да | CONFIRMED metadata | scope |
| `reception_category_key` | категория рецепции | сохранить текущие категории; позднее закрепить по service/activity ID вместо текста | UNKNOWN | нет | CONFIRMED current / technical mapping pending | полнота и уникальность |
| `sold_quantity` | знаковое количество | `SUM(Fld7585)` / `SUM(Fld7657)` | `numeric` | нет | CONFIRMED current | единицы и знак |
| `revenue_amount` | знаковая выручка | `SUM(Fld7586)` / `SUM(Fld7659)` | `numeric` | нет | CONFIRMED current | сумма и знак |

## Компонент B: план

План остаётся внешней Excel-таблицей и используется как есть. Его физическая
структура не переносится в PostgreSQL.

| Целевая колонка | Бизнес-описание | Источник | Тип | NULL | Статус |
|---|---|---|---|---|---|
| `plan_date` | дата дневного плана | Excel `План` | `date` | нет | EXTERNAL / schema pending |
| `club_id` | клуб | Excel `План` | UNKNOWN | нет | EXTERNAL / schema pending |
| `activity_id` | вид деятельности | Excel `План` | UNKNOWN | нет | EXTERNAL / schema pending |
| `planned_revenue` | дневной план | Excel `[План на день]` | `numeric` | нет | CONFIRMED DAX / EXTERNAL |

План не присоединяется к строкам факта. Power BI связывает его с общими датой,
клубом и видом деятельности; точная схема связей проверяется при сборке модели.

## Повторное использование

Оба исходных регистра уже входят в `docs/mappings/dpfu_revenue.md`. Кандидат —
общий факт движений дополнительных услуг и товаров, а не отдельные копии
«ДПФУ» и «Рецепция». Для рецепции общий факт должен сохранить `employee_id` и
стабильную классификацию услуги.

Прямое объединение с «Записями администраторов» отклонено: там сотрудник —
автор записи и другая гранулярность.

## Не переносить

- код, ФИО и дату рождения клиента;
- признак клиента;
- тип оплаты;
- код и название контракта;
- полное имя сотрудника внутри факта;
- текстовые названия клуба/услуги как ключи;
- среднюю цену, долю, прогноз и накопительные итоги;
- сырые регистры на VM-2;
- отдельные факты для пяти страниц.

## Блокеры

1. Связь основания `AccumRg7575` с чеком и выбор `Document346.Сотрудник` либо
   `Консультант`; `Fld7582` отклонён как исполнитель.
2. Пересечение товаров и состояния строк.
3. Физическое соответствие service/activity ID текущим категориям и scope.
4. Схема связей внешнего Excel-плана.
5. Контрольные значения.

Обновление: один раз в день.
