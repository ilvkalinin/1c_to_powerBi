# Stage 3 execution: движения долга по неподтверждённым услугам

- Пакет: `visits_debt_product_admission_2026-08-27`
- Объект: `mart.unconfirmed_service_debt_movement`
- Горизонт BR-003: `[2025-01-01, 2026-08-28)`
- Power BI: не изменялся.

## Delivered immutable implementation

Initial load и rerun выполнены
[`load_unconfirmed_service_debt_movement.py`](../../scripts/load_unconfirmed_service_debt_movement.py)
по reviewed extract/control/DDL/replace/reconciliation SQL. В каждом прогоне
runner открыл новый read-only `REPEATABLE READ` source snapshot, последовательно
передал месячные binary COPY buffers через temporary target stage, а затем в
одной target transaction проверил `VD-REC-001`—`VD-REC-007`, выполнил full
`DELETE + INSERT` и post-commit reconciliation. Любое ненулевое отклонение или
ошибка COPY завершило бы transaction rollback до commit; автоматического `DROP`
нет.

## Initial load и rerun

| Прогон | Результат | Строки / ключи | Сумма `amount_delta` | Min / max `debt_event_at` | Contract/key/horizon deviation |
|---|---|---:|---:|---|---:|
| Initial load | `COMMITTED` | 1 206 622 / 1 206 622 | 549 390.00 | 2025-01-01 05:00:01 / 2026-08-27 22:00:00 | 0 |
| Atomic rerun | `COMMITTED` | 1 206 628 / 1 206 628 | 550 140.00 | 2025-01-01 05:00:01 / 2026-08-27 22:00:00 | 0 |

`VD-REC-001`—`VD-REC-005` сравнивают rows, physical keys, signed amount и
min/max с independent source controls **того же exported snapshot**;
`VD-REC-006` проверяет duplicate key, `VD-REC-007` — required fields,
`record_kind` и BR-003 horizon. Ненулевой результат отменил бы commit, поэтому
зафиксированный rerun означает нулевое source/stage/target deviation для его
snapshot.

Через несколько секунд после rerun отдельный fresh source snapshot дал
1 206 630 строк/ключей и 544 840.00 (на 2 строки и -5 300.00 относительно
persisted rerun). Это ожидаемая live-source change между snapshot, а не
transport deviation: acceptance не сравнивает разные snapshots. В обоих
наблюдениях строк с не-единственной legacy document branch было 3 459; они
намеренно не входят в current-M-compatible fact и не являются target loss.

## Performance evidence

| Проверка | Результат |
|---|---|
| Exact source sample plan, July 2026 | 45 705 rows, 947.491 ms, 317 758 shared-hit, 3 722 reads |
| Exact source full plan | 1 206 620 rows, 8 604.852 ms, 3 824 482 shared-hit, 0 reads, 21 862 temp reads |
| Independent-control full plan | 6 713.238 ms; после rewrite sample 256.743 ms / 137 396 shared-hit вместо 1 523.589 ms / 2 772 089 shared-hit |
| Final target read plan | 1 206 628 rows, 602.570 ms, 16 038 shared-hit, 92 405 reads, 0 temp reads |
| Final physical size | 1 008 558 080 bytes |

Full rebuild остаётся приёмочной операцией, а не заявленным daily incremental
SLA. Индексы, кроме обязательного PK contract, этим пакетом не создавались.
