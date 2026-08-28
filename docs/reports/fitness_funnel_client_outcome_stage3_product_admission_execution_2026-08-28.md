# Physical admission execution: `mart.fitness_funnel_client_outcome`

Статус: `IMPLEMENTED / VALIDATED / FULL-REBUILD BASELINE ONLY`.

Пакет создал только `mart.fitness_funnel_client_outcome`. Источник 1С оставался
read-only, Power BI не менялся. Правило BR-049 сохранено: разные услуги ИП —
отдельные outcome-события. Raw-реплика 1С, новые source indexes, `DROP` и
изменения иных mart-объектов не выполнялись.

## Граница и независимая сверка

Load использует exact extract и отдельный source-control path:

- `FF-O01` — IP source key, обязательные атрибуты и horizon;
- `FF-O02` — уникальность физических ключей исходных регистров;
- `FF-O03` — независимые expected rows по ветвям `DPFU7575`, `DPFU7646`,
  `IPPZ`, `IPGZ`, `SPT`;
- `FF-O-R01`—`FF-O-R09` — rows, source key, contract/horizon и пять branch
  totals target-таблицы до commit.

Первоначальный loader ошибочно получал expected total из проверяемого extract.
До физического commit это заменено на `FF-O03`: expected values вычисляются
отдельным SQL, а target сравнивает их с source-key префиксами. Ошибки ранних
DDL/stage probes и VPN-обрывы до commit откатили свои transaction; проверка
`to_regclass` после них показывала отсутствие target-таблицы.

## План и transport

Все source планы выполнялись в `REPEATABLE READ, READ ONLY`,
`statement_timeout = 300s`, `work_mem = 64MB`; это session-local параметр,
не увеличение server cache.

| Extract window | Rows | Execution time | Temp I/O | Результат |
|---|---:|---:|---:|---|
| 2026-07 | 27 085 | 1 565.380 ms | 0 | sample PASS |
| 2026-06…07 | 61 147 | 5 494.575 ms | 0 | ladder PASS |
| 2026-05…07 | 94 303 | 8 112.400 ms | 0 | ladder PASS |
| 2024-01-01…2026-08-29 | 1 036 842 | 32 813.452 ms | read/write 23 096/61 578 | full baseline PASS |

Пользователь указал использовать VPN-safe source-first pool. Runner формирует
32 месячных binary COPY files только из восьми target-колонок, каждый после
своего independent control и в fresh reader того же exported snapshot. Target
не открывается до готовности пула. В успешном initial snapshot: 1 037 060
rows, 346 829 941 bytes, самый большой месяц 13 920 625 bytes; aggregate cap
`512 MiB` не превышен. Один source batch был повторён целиком после
`OperationalError`; один target transaction был повторён по тому же пулу.
Ни один partial target snapshot не был опубликован.

## Atomic loads и приёмка

| Run | Source rows | Branch expected rows | Результат |
|---|---:|---|---|
| Initial | 1 037 060 | 821 539 / 892 / 49 758 / 149 981 / 14 890 | `FF-O-R01`—`R09` PASS, commit |
| Atomic rerun | 1 037 064 | 821 543 / 892 / 49 758 / 149 981 / 14 890 | `FF-O-R01`—`R09` PASS, commit |

Разница четырёх строк между runs — изменение live source между разными
exported snapshots, не reconciliation failure: каждый run сравнивался только
со своими independent controls.

Final target audit after rerun:

- rows = distinct `outcome_source_key` = **1 037 064**;
- required/`outcome_count` violations = **0**;
- horizon: **2024-01-01…2026-08-28**;
- table size = **973 MB**;
- August target read (`22 921` rows) = **288.341 ms**, parallel sequential
  scan, shared hit/read `13 887/73 480`, temp `0`.

## Ограничения и решение по производительности

`DELETE + INSERT` доказан как атомарный initial/rebuild механизм, но после
rerun размер вырос с 603 MB до 973 MB. Поэтому эта поставка — только
измеренный full-rebuild baseline. Не заявляются ежедневный SLA,
incremental refresh, watermark, обработка late changes/deletions или
эффективность будущих rebuild. `VACUUM FULL`, `TRUNCATE`, swap strategy и
индекс по дате не выполнялись: они не входили в reviewed plan и требуют
отдельного измеренного пакета. Текущий August read 288 ms сам по себе не
доказывает необходимость индекса.

Power BI connection, relationships и меры остаются `DESIGNED` по BR-036.

## Критерий закрытия

Критерии physical admission выполнены: source/stage/target independent
controls, два atomic commits, contract/key/horizon checks, bounded transport,
cleanup/rollback evidence и target read plan зафиксированы. Витрина принята
как физический факт без Power BI switch.
