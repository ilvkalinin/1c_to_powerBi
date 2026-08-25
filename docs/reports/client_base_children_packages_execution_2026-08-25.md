# S3-CBD-PKG-001: execution evidence — детские пакеты в клиентской базе

- Пакет: `client_base_children_packages_implementation_2026-08-25`
- Статус: `VALIDATED`: atomic rerun и final independent target read check passed.
- Power BI: не изменялся. Target DDL: BR-038 `age_check` migrated and validated.

## Выполненная атомарная загрузка

Первый run остановил stage reconciliation до `COMMIT`: месячный batch мог
отфильтровать позднюю sale-строку до `MAX(start)` по `договор × ребёнок`.
Target был rollback и подтверждён неизменным. Формула исправлена так, что
`MAX(GREATEST(contract start, receipt date))` выбирается до ограничения
месячным горизонтом; sample control и source full plan подтверждены до
повторной загрузки.

Второй run на одном `REPEATABLE READ READ ONLY` source snapshot прошёл:

| Контроль | Expected / actual | Статус |
|---|---:|---|
| source daily scope controls | 1 460 | PASS |
| club / network client-days | 64 139 724 / 64 069 364 | PASS |
| monthly bounded batches | 24; 6.69–7.97 MB each | PASS; file removed after each COPY |
| stage rows | 1 699 066 | PASS |
| source = stage = target daily controls | tolerance 0 | PASS |
| target duplicate keys / contract / horizon | 0 / 0 / 0 | PASS |
| target size / read plan | 700 MB / 396.707 ms | MEASURED; not an SLA |

Source sample `[2026-07-01, 2026-08-01)` ran in 6.468 s for the exact
extract; full baseline `[2025-01-01, 2027-01-01)` ran in 19.822 s for
1 699 066 rows. Both plans were captured before COPY. Full plan had bounded
temporary spill; it is full-rebuild evidence, not incremental evidence.

## BR-037 controls and BR-038 decision

The same read-only source control found 18 972 child rows: 399 non-positive
sales rows were excluded, 52 rows without a physical sales group were retained,
18 521 rows had positive sales, and 18 429 `contract × child` ranges remained.

Пользователь подтвердил BR-038: все child packages относятся к `Дети` при
сохранении фактического `age_years`. Extract вычитает package-interval из
обычного membership interval до агрегации. Минимальная migration заменяет
только `client_base_daily_age_ck`, без новой колонки, grain или Power BI.

## BR-038 implementation and rerun evidence

После sample-first review финальный extract дал на full BR-003 plan 1 712 574
агрегатных строк за 24.710 s. Первый BR-038 write run поймал duplicate final
key в stage до DDL/DML и был rollback; причина — схлопывание `is_child` после
исчезновения этого технического атрибута из physical key. Добавлена финальная
агрегация по семи target columns. Повторный sample: 75 842 rows, daily и
package-origin controls с tolerance 0, 6.591 s.

Следующий atomic run committed за 261.829 s:

| Контроль | Expected / actual | Статус |
|---|---:|---|
| source/stage/target daily totals | 1 460; 64 140 331 / 64 069 971 | PASS |
| BR-038 `Дети` age 14+/unknown | 226 025 / 225 846 client-days | PASS |
| stage rows | 1 712 574 | PASS |
| target contract / duplicates / horizon | 0 / 0 / 0 | PASS |
| target read plan | 448.956 ms | MEASURED; not an SLA |
| new `age_check` validation | 1.723 s | PASS |

Atomic rerun then completed in a new source snapshot in 264.574 s, with
`TARGET_BR038_DDL_REUSED`, 1 712 574 staged rows and 1 460 same-run daily
controls. Its source snapshot changed normally between runs: 64 140 082 /
64 069 722 client-days, while BR-038 package-origin control stayed 226 025 /
225 846. Runner passed stage and persisted tolerance-0 controls before commit.
Power BI remained unchanged. После краткого target `ConnectionTimeout`
endpoint восстановился; final read check подтвердил 1 712 574 строк,
64 140 082 / 64 069 722 client-days, BR-038 226 025 / 225 846,
0 contract violations и `client_base_daily_uq`. `age_check` имеет
`convalidated = true`.
