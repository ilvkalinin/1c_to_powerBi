# ADR-0032: минимальный task/contract mart маркетинговой воронки

- Статус: `IMPLEMENTED / INITIAL LOAD AND RERUN VALIDATED 2026-08-24`
- Дата: 2026-08-24
- Отчёт: №27 «Маркетинговая воронка»

## Контекст и доказанный reuse review

Маркетинговая «Воронка» считает два несовместимых уровня: одно CRM-задание
и каждую квалифицированную связь `задание × абонемент` (BR-020). Существующие
продукты проверены в порядке `REUSE → EXTEND → NEW`:

| Кандидат | Grain / scope | Решение |
|---|---|---|
| `mart.crm_interaction` | одно CRM-взаимодействие; только sales/guest scope, а не все задания воронки «Продажа клубной карты» | `NOT_APPLICABLE`: join к task размножит core и не покроет scope |
| `mart.ancillary_revenue_movement`, `mart.ip_revenue_daily` | денежное/service движение | `NOT_APPLICABLE`: не содержат CRM-задачу или contract-attribution BR-020 |
| `mart.fitness_leads_funnel_task` | только спроектирован, физически отсутствует; будущий consumer требует четыре funnel scope и task-outcomes | `NOT_APPLICABLE` для physical reuse: запуск его широкого scope расширил бы пакет и не был бы минимальным для отчёта №27 |

Пользователь 2026-08-24 подтвердил минимальный изолированный core. Поэтому
`NEW` — единственное решение текущего пакета, не меняющее бизнес-логику:
два компактных факта без raw-копии 1С. Будущий общий `crm_funnel_task` не
создаётся и не является скрытой зависимостью маркетинговой витрины.

## Решение

После отдельного runnable admission создать:

1. `mart.marketing_funnel_task`, grain — одно непомеченное CRM-задание
   `Reference106.ID` в воронке «Продажа клубной карты», после текущих
   исключений клуба и двух exact причин дубля.
2. `mart.marketing_funnel_task_contract`, grain — одна candidate пара
   `(task_id, contract_id)` из `InfoRg6798`; она проходит active-флаг,
   scope contract type/payment и непустой `activation_date`; сохраняется
   историческая activation date, необходимая current-DAX контролю.
   `is_conversion_qualified` отдельно фиксирует
   `activation_date >= task_created_at` (BR-020), а `contract_count` равен
   `1` только для этого qualifying subset, иначе `0`.

Такой один bridge сохраняет оба подтверждённых current inputs без нового
join: DAX накопленного трафика использует candidate contract client до
месяца, а меры «Абонементы факт» суммируют только `contract_count = 1`.
`task_id` — единственный physical bridge key. `task_code` остаётся
unique display/DAX key, но не участвует в source join. Полный технический
повтор projected bridge row удаляется reviewed `DISTINCT`: MF-DIAG-001—002
подтвердил 19 идентичных source повторов. Global dedup по абонементу не
допускается; иной повтор `(task_id, contract_id)` делает acceptance check
`FAIL`.

Power BI импортирует две таблицы: `task` фильтрует `task_contract` отношением
`1:*`, single direction. Меры заданий считают `DISTINCTCOUNT(task_id)` из
task fact и удаляют contract-slices; меры абонементов считают bridge rows.
Планы, network/cluster dimension и интерактивные DAX остаются в Power BI.

## Обновление и атомарность

Watermark отсутствует: MF-V10A не нашёл modification timestamp для CRM task
или bridge. Поэтому допустим только bounded full rebuild в одном
`REPEATABLE READ READ ONLY` source snapshot: source-side filtered rows →
временные binary COPY files → одна target transaction со swap/replace обеих
таблиц → reconciliation до `COMMIT`. Любая ошибка, включая ключ, null,
control или rerun mismatch, откатывает target transaction.

## Retention boundary — решение 2026-08-24

Текущий утверждённый PBIT определяет накопленный трафик как
`UNION(Задания 2024, Задания 2025)`; MF-V08 на 2025-07-01 даёт
`66 404 − 27 319 − 15 221 = 23 864`. Пользователь подтвердил, что retention
должен соответствовать BR-003: в августе 2026 source extraction хранит
`[2025-01-01, 2027-01-01)`. Исторический PBIT остаётся evidence текущей
логики и контролем месяца 2025-07, но не является исключением для static
2024 boundary и не запускает изменение DAX в этом пакете.
