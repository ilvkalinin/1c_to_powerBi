# S3-IP-REMEDIATION-001: точный scope выручки ИП и продолжение свода

Дата согласования: 2026-08-20. Статус: `COMPLETED / VALIDATED`.

Пользователь выбрал remediation общего факта вместо локального дублирования
ветви в «Своде выручка ГК». Решение фиксирует один exact current-M scope для
всех потребителей `mart.ip_revenue_daily`.

## Полный scope

1. Изменить только predicate квалификации ИП в
   `sql/marts/ip_revenue_daily_extract.sql` и независимом source control:
   `ILIKE '%ИП%'` → `LIKE '%ИП%'`.
2. Атомарно пересобрать существующий `mart.ip_revenue_daily` за BR-003 из
   одного `REPEATABLE READ, READ ONLY` source snapshot, выполнить source,
   stage, target, key, null, date-boundary и rerun-сверки.
3. После успешной сверки возобновить `mart.revenue_group_summary_daily`:
   сначала обновить без изменения логики второй reused факт
   `mart.ancillary_revenue_movement` статьи 03 тем же reviewed loader, затем
   reuse статей 03/04 из independently reconciled shared facts, временные source-side ветви 02/05/06,
   атомарная загрузка, key/branch/sum/rerun controls и измерение SLA.

## Граница и rollback

Меняется существующий `mart.ip_revenue_daily`, затем без изменения source
правил пересобирается существующий `mart.ancillary_revenue_movement`, затем existing пустая
`mart.revenue_group_summary_daily`; DDL, Excel, Power BI, отдельный
рецепционный detailed fact и источник 1С не изменяются. До commit каждого
replace rollback — `ROLLBACK`; source остаётся read-only.

Измеренный технический факт: старый promotion `INSERT ... SELECT` для
508 557 staged rows держал target connection более семи минут и был прерван
без commit. Loader переключён на эквивалентный client-side binary `COPY` из
того же validated temporary stage в той же target-транзакции; бизнес-колонки,
grain, источник и target object не меняются.

## Критерий закрытия

IP shared fact совпадает с exact-M source control и стабилен на rerun;
ancillary shared fact также проходит свой independently recorded refresh;
затем «Свод выручка ГК» совпадает с source control по всем статьям 02–06,
не имеет duplicate/contract violations и фиксирует измеренное время refresh.

## Фактический результат 2026-08-20

- `mart.ip_revenue_daily` после точного `LIKE` содержит 1 253 строки,
  `revenue_amount = 142 374 861,98`; source/stage/target controls совпали,
  duplicate keys и contract violations равны нулю. Повторный прогон дал тот же результат.
- `mart.ancillary_revenue_movement` успешно пересобран повторно. Во втором
  актуальном снимке: 508 574 строки; `7575` — 508 076 строк и 645 047 823,27,
  `7646` — 498 строк и 27 835,00. Target controls совпали.
- `mart.revenue_group_summary_daily` загружен из общих фактов для статей 03/04
  и временных exact-M ветвей 02/05/06: 25 339 строк, без duplicate/contract
  violations. Первый полный refresh занял 52,34 с, повторный — 38,02 с.
