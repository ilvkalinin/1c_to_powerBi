# Stage 3 execution: bounded refresh движений долга

- Пакет: `visits_debt_bounded_incremental_2026-08-31`
- Настройка: срез 2026-08-30, окно `[2026-06-01, 2026-08-31)`
- BR-003 target horizon: `[2025-01-01, 2026-08-31)`
- Current full loader / Power BI / source 1С: не изменялись

## Source plan ladder до DML

| Горизонт exact extract | Rows | Execution | Shared hit/read | Temp |
|---|---:|---:|---:|---:|
| 2026-06-01—2026-07-01 | 59 890 | 1 372.123 ms | 413 149 / 4 261 | 0 |
| 2026-06-01—2026-08-01 | 105 595 | 1 001.806 ms | 350 121 / 2 483 | 0 |
| 2026-06-01—2026-08-31 | 149 453 | 1 239.973 ms | 491 032 / 2 103 | 0 |

Stop signals отсутствовали: все три actual plans завершились, temp spill = 0.

## Atomic refresh

Один exported `REPEATABLE READ, READ ONLY` source snapshot передал binary COPY
по месяцам: июнь 59 890, июль 45 705, август до 31-го exclusive 43 858 строк.
Independent controls каждого batch совпали с COPY; суммарно stage = 149 453.
В target transaction под advisory lock окно и строки вне BR-003 были удалены,
stage вставлен, история до 2026-06-01 сохранена. `VD-REC-001—007` прошли до
commit и после commit. End-to-end elapsed = **92.673 s**, включая 40 секунд
transport preflight.

## Post-commit audit

| Control | Actual | Status |
|---|---:|---|
| rows / physical keys | 1 211 074 / 1 211 074 | PASS |
| `sum(amount_delta)` | -148 205.00 | PASS against same-snapshot reconciliation |
| min / max `debt_event_at` | 2025-01-01 05:00:01 / 2026-08-30 23:48:56 | PASS |
| window rows | 149 453 | PASS |
| horizon violations | 0 | PASS |
| table size | 1 008 992 256 bytes | OBSERVED |
| target window read plan | 149 453 rows / 483.704 ms | PASS; temp = 0 |

## Ограничение

Это bounded sliding-window с явно принятым методологическим риском, а не
change-watermark incremental SLA. Исправления/удаления внутри окна
обрабатываются полной заменой окна; изменения до 2026-06-01 этим запуском не
обнаруживаются. Scheduler не создавался.
