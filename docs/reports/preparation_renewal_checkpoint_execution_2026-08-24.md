# Execution evidence: `mart.preparation_renewal_checkpoint`

Статус: `VALIDATED`.

Дата: 2026-08-24.

## Реализация

Создана физическая таблица `mart.preparation_renewal_checkpoint` с grain
`contract_id × checkpoint_day (7/14/21/28/30)`. VM-1 рассчитывает только
компактный source-side checkpoint fact; raw-регистры и client-level staging на
VM-2 не создавались. Один `REPEATABLE READ, READ ONLY` source snapshot и одна
target transaction используют восемь квартальных binary COPY batches. Каждый
временный файл копируется на VM-2 и удаляется до следующей порции; крупнейший
файл — 37 186 783 bytes.

До каждого COPY отдельный legacy-M control фиксирует expected rows, visits,
frozen и below-target totals. Он использует bucket-cumulative visit path и
DAX-natural freeze path, тогда как extract использует technical contract flag,
эквивалентность которого доказана PR-V13. Все runner'ы используют initial
attempt + пять `OperationalError` retries.

Power BI, PBIT, M, DAX, Excel-план и подключения не менялись по BR-036.

## Контрольные результаты

| Прогон | Checkpoint rows | Накопительные посещения | Frozen points | Below target | Результат |
|---|---:|---:|---:|---:|---|
| Initial load | 857 515 | 1 644 883 | 60 002 | 598 327 | PR-R01—PR-R06 PASS |
| Atomic rerun | 857 515 | 1 644 887 | 60 002 | 598 327 | PR-R01—PR-R06 PASS; 165,58 s |

Разница в четырёх посещениях возникла в live 1С между двумя независимыми
source snapshots; в каждом прогоне expected control был получен до COPY в том
же snapshot и точно совпал с target. Это не target deviation.

PR-R01 подтвердил independent source-to-target totals; PR-R02 — ключ;
PR-R03 — required fields, buckets, targets, flags, age и tenure; PR-R04 —
DAX checkpoint formula и BR-003; PR-R05 — contract point set; PR-R06 —
отсутствие `PUBLIC SELECT`.

## Производительность и rollback

- Full atomic rebuild baseline: 165,58 s; это не incremental SLA.
- Target: 238 MB (`249 765 888` bytes). Power-BI-подобный group query за
  июль 2026 обработал 42 754 строки за 185,191 ms; parallel sequential scan
  без spill. Дополнительный индекс не создавался, так как измеренный Import
  read-path не показал потребности.
- Source freeze monthly index scan: 28 718 rows за 473,693 ms. Bounded July
  extract дал 42 754 rows; independent legacy control после set-based rewrite
  занял 3,57 s.
- `TRUNCATE` rollback проверен отдельно под advisory lock: внутри транзакции
  строк `0`, после rollback восстановлено `857 515` строк.

## Артефакты

- [mapping](../mappings/preparation_renewal.md);
- [source validation](../source_metadata/preparation_renewal_stage3_validation_2026-08-24.md);
- [DDL](../../sql/marts/preparation_renewal_checkpoint_ddl.sql);
- [extract](../../sql/marts/preparation_renewal_checkpoint_extract.sql);
- [independent source controls](../../sql/marts/preparation_renewal_checkpoint_source_controls.sql);
- [reconciliation](../../sql/tests/preparation_renewal_checkpoint_reconciliation.sql);
- [runner](../../scripts/load_preparation_renewal_checkpoint.py).
