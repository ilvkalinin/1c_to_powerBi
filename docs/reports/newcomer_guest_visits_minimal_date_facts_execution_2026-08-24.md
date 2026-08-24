# Execution evidence: минимальные date-facts «Новички и гостевые визиты»

Статус: `VALIDATED`.

Пакет создан по BR-035 и [авторизации](newcomer_guest_visits_minimal_date_facts_authorization_2026-08-24.md). Power BI не переключался и 1С не изменялась.

## Atomic load and rerun

В обоих прогонах source extract выполнен в одном `REPEATABLE READ, READ ONLY` snapshot с BR-003 horizon `[2025-01-01, 2027-01-01)`; target load использовал одну транзакцию, табличную блокировку на rebuild и binary `COPY`.

| Fact | source COPY | target after rerun | min date | max date |
|---|---:|---:|---|---|
| `mart.new_first_visit` | 95 984 | 95 984 | 2025-01-01 | 2026-08-24 |
| `mart.guest_visit_conversion` | 103 974 | 103 974 | 2025-01-02 | 2026-08-24 |

Target outcome controls: `accuniq_same_day_flag = true` — 86 строк; `purchase_activation_date IS NOT NULL` — 8 356 строк. Эти значения получены из того же source snapshot и после rerun не изменились.

## Source-to-target reconciliation

| Control | Expected | Result |
|---|---|---|
| NV-R01 transport counts | source rows = target rows | PASS |
| NV-R02 logical keys | 0 duplicates | PASS |
| NV-R03 required fields and 0…44-day outcomes | 0 violations | PASS |
| NV-R04 BR-003 dates | 0 outside horizon | PASS |
| NV-R05 minimal date contract/profile | 0 violations | PASS |
| NV-R06 public access | 0 public SELECT grants | PASS |

Initial load and the subsequent complete rebuild produced the same counts and passed all six controls. Current source-side club audit is retained: for 31 tied first-visit contracts there are 0 multi-club groups; for 1 249 duplicate guest client-date groups 21 have multiple clubs. Guest club is not a column of the minimal fact by BR-035.

## Performance and retry policy

The measured full rebuild rerun took 62.36 seconds. It is a full rebuild, not an incremental refresh; daily ≤1 minute SLA is therefore not claimed.

| Query | Actual plan | Execution |
|---|---|---:|
| August count on `mart.new_first_visit` | sequential scan of 95 984 rows; 2 508 returned | 7.169 ms |
| August count on `mart.guest_visit_conversion` | sequential scan of 103 974 rows; 3 456 returned | 10.244 ms |

Table sizes are 22 970 368 bytes and 28 147 712 bytes respectively. No date index is added: no Power BI switch is in scope and current measured scans are small. `scripts/check_connection_retry_policy.py` passed for all 18 production runners, including the new loader: initial connection attempt plus five `OperationalError` retries.
