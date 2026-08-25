# CRM: optimisation review under BR-032

Дата: 2026-08-21. Статус: `IMPLEMENTATION EVIDENCE / PACKAGE ACTIVE`.

## Причина пересмотра

Пользователь уточнил целевое правило BR-032: PostgreSQL не должен быть копией
Power BI или широким зеркалом `Reference67`. Все подтверждённые фильтры, joins,
классификации, normalisation и допустимые агрегации выполняются в одном
`REPEATABLE READ READ ONLY` snapshot VM-1 до передачи; VM-2 получает только
готовые строки и колонки, необходимые Power BI.

Проверка локальных current PBIT перед запуском уточнила границу: `Загрузка
ОП.pbit` отбирает sales-строку по phone date `InfoRg7146.Fld7150`, а при её
отсутствии — по `Reference67.Fld820`; `Fld822` передаётся как план, но не
является source predicate. Один minimum effective date используется только
как безопасный квартальный transport anchor. `Отчет по обращениям.pbit`
группирует feedback по бизнес-полям, включая имя взаимодействия, но не по
CRM/task/client/reference IDs. Эти ID не передаются в compact feedback fact.

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

После уточнения пользователя действует BR-033: общая compact витрина
предпочтительна, если её source-side union не меняет grain и семантику
consumers. У sales, feedback и guest tour совпадает базовое событие
`Reference67.ID`; поэтому вместо трёх независимых широких facts предлагается
один отфильтрованный interaction core. Phone и comment имеют другую кратность
и остаются scoped children.

| Product proposal | Target grain | Выполняется на VM-1 до COPY | Не передаётся |
|---|---|---|---|
| `mart.crm_interaction` | одна `interaction_id` | source-side union sales и guest-tour predicates; shared classifications and derived dates/statuses | все interactions вне union, raw reference copies, raw employment rows |
| `mart.crm_interaction_phone` | одна техническая phone-row | только phone rows interaction, попавших в sales/guest scope; `phone_at` и `answered_flag` готовы до COPY | телефония feedback-only и все несвязанные телефонные записи |
| `mart.feedback_interaction` | final PBIT business group | feedback predicate, HTML→text, phone flag, grouping, first non-feedback follow-up and worked fields | raw HTML, phones, interactions и technical IDs |
| `mart.club_day_metrics` | дата × фактический клуб | additive calls denominator | client/contract visit detail |
| thin report views | report output | только source-prepared fields; VM-2 выполняет проекцию и scoped phone join, без повторного чтения VM-1 | report-specific raw staging |

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
