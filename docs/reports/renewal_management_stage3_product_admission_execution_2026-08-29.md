# RM-LOAD-001—006: `mart.renewal_management_contract`

Статус: `VALIDATED`.

Дата: 2026-08-29.

## Итог

Согласованный Stage 3 product-admission пакет завершён. Создан и принят
`mart.renewal_management_contract` с grain «один текущий исходный договор».
Power BI и источник 1С не изменялись.

## Initial load и rerun

- Initial `CREATE TABLE + COPY + RM-R01—RM-R05` committed успешно.
- Первый atomic rerun committed успешно; в его source snapshot были 240,968
  строк и столько же distinct contract IDs.
- Финальный clean rerun выполнен после очистки оборванных собственных target
  sessions. В одном `REPEATABLE READ, READ ONLY` source snapshot independent
  control и binary `COPY` согласились на 240,967 строк. Derived transport
  занял 127,376,799 bytes, меньше hard cap 1 GiB.
- Target получил advisory lock, выполнил transactional `TRUNCATE`, binary COPY
  и RM-R01—RM-R05 без отклонений; `TARGET_COMMIT_PASS` зафиксирован.
- Чистое end-to-end время final full rebuild: 131.40 s. Это baseline полной
  пересборки, не incremental refresh и не SLA ≤1 minute.

## Final target controls

| Control | Значение |
|---|---:|
| rows | 240,967 |
| distinct `expiring_contract_id` | 240,967 |
| distinct `expiring_contract_code` | 240,967 |
| `membership_end_date` range | 2024-01-02 — 2027-01-31 |
| `pg_total_relation_size` | 136,839,168 bytes |
| full target read plan | 86.737 ms |

После rerun нет временного transport-каталога. На VM-2 нет старых
`renewal_management` backend sessions, которые раньше удерживали
advisory/relation locks.

## Incident и rollback evidence

Предыдущая time-captured попытка после source COPY потеряла target socket. Её
зависший `COPY` и четыре собственные диагностические сессии были точно
идентифицированы по `pg_stat_activity` и завершены через
`pg_terminate_backend`; незавершённая transaction откатилась. До очистки
текущий rerun ожидал advisory lock. Финальный clean rerun подтвердил, что это
был session-cleanup incident, а не mismatch источника, изменения source SQL
или повреждение committed fact.

## Семантическая граница

Это current-state продукт: next-contract, last interaction, rating и tenure
пересчитываются на дату refresh. Отдельный as-of snapshot, если он понадобится,
остаётся самостоятельным продуктом `DECISION_REQUIRED`; см.
[RM-ARCH-001](renewal_management_architecture_reassessment_2026-08-29.md).

## Связанные артефакты

- [admission](renewal_management_stage3_admission_2026-08-29.md)
- [source extract](../../sql/marts/renewal_management_contract_source_extract.sql)
- [runner](../../scripts/load_renewal_management_contract.py)
- [reconciliation](../../sql/tests/renewal_management_contract_reconciliation.sql)
