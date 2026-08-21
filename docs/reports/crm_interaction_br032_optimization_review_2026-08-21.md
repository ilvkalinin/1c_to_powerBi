# CRM: optimisation review under BR-032

Дата: 2026-08-21. Статус: `DESIGN PROPOSAL / DML NOT AUTHORIZED`.

## Причина пересмотра

Пользователь уточнил целевое правило BR-032: PostgreSQL не должен быть копией
Power BI или широким зеркалом `Reference67`. Все подтверждённые фильтры, joins,
классификации, normalisation и допустимые агрегации выполняются в одном
`REPEATABLE READ READ ONLY` snapshot VM-1 до передачи; VM-2 получает только
готовые строки и колонки, необходимые Power BI.

Исходный approved plan этому не соответствует: его runner выбирал все CRM
interactions по `Reference67.Fld823` за BR-003 и уже на VM-2 применял
report-specific views. Первый запуск остановлен по вопросу пользователя до
target commit. Source не менялся; CRM DML откатился; три созданные target
таблицы подтверждённо пусты.

## Измеренный риск широкого scope

Read-only `EXPLAIN (FORMAT JSON)` на VM-1 за BR-003
`[2025-01-01, 2027-01-01)` дал следующие planner estimates. Это не control
value и не результат загрузки, а достаточное evidence направления для
перепроектирования.

| Source candidate | Estimated interaction rows | Смысл |
|---|---:|---|
| Текущий широкий core: все `Reference67` по `created_at` | 6 739 259 | исходный runner до phone/comment expansion |
| Sales: три approved funnels | 969 049 | до phone-row expansion и точной роли даты |
| Feedback: PBIT-ветка «Обратная связь» + шесть тем | 16 854 | только иллюстрация узкого PBIT branch; final report scope сверяется с calls mapping |
| Guest tour: встреча в `Продажа клубной карты` | 33 390 | до final state/status и роли report date |
| Outgoing follow-up к feedback-кандидату | 5 390 | input к source-side feedback calculation |

Даже до исключения ненужных колонок и source-side агрегации широкая выборка
на порядок больше доказанного report scope. Exact counts и source-to-target
reconciliation будут рассчитаны только по пересмотренным final projections.

## Предлагаемая физическая граница

Общий CRM-core не переиспользуется автоматически: BR-002 требует совпадения
grain и семантики, которого здесь нет.

| Product proposal | Target grain | Выполняется на VM-1 до COPY | Не передаётся |
|---|---|---|---|
| `mart.sales_interaction` | одна техническая phone-row; без телефона — marker-row interaction | funnel/Jivo/кадровый `EXISTS`, effective interaction date, duration, answered flag, нужные display classifications | все interactions вне sales scope, raw employment rows, отдельный phone child |
| `mart.feedback_interaction` | final business attributes × нормализованный comment, с одной null-comment строкой при отсутствии comment | feedback scope, comment HTML→text, deterministic follow-up, answered/worked fields, report grouping | raw HTML, raw phone/comment children, unrelated interactions |
| `mart.guest_tour` | одна техническая phone-row; без телефона — marker-row interaction | meeting/funnel/state/status scope, report date, `tour_kind` | all non-tour interactions, raw phone child, ACCUNIQ/contract outcomes by BR-031 |

Для feedback source projection обязана сохранять достаточную детализацию для
динамического distinct `client × normalized comment`; `STRING_AGG` допустим
лишь как display field, но не как замена fact grain без отдельной DAX
reconciliation. Точное правило feedback scope берётся из approved calls
mapping, а не из случайного сохранённого PBIT-slicer state.

## Необходимое новое решение

Изменение затрагивает approved physical objects, source predicates,
transform-boundary и reconciliation. До следующего DDL/DML нужны revised
mapping, contracts, immutable SQL и отдельное подтверждение нового
implementation scope. Пустые объекты исходного плана не удаляются и не
меняются этим review.
