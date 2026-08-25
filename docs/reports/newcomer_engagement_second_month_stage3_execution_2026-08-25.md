# Выполнение Stage 3: «Вовлечение новичков — второй месяц»

Статус: `IMPLEMENTED / RECONCILED / RERUN PASSED`.

## Объект и граница

Создана `mart.newcomer_engagement_second_month`. Физический ключ —
`source_row_id`; grain сохраняет technical source row, а KPI business pair —
`contract_id × client_id × month_of_engagement`. Детские строки имеют
`age_category = 'Дети'`; BR-037 исключает отрицательные sale groups и выбирает
максимальную valid повторную стартовую дату. Power BI/PBIT/M/DAX/Excel не
менялись (BR-036).

## Performance и transport

Перед full transport exact July-2026 sample был измерен `EXPLAIN (ANALYZE,
BUFFERS)`: 5 303 rows, 7.792 s. Full source plan: 166 969 rows, 47.806 s;
это baseline full rebuild, не incremental SLA. Target size after rerun: 140 MB.
Месячный target read query выполнился за 112.360 ms (`Seq Scan`, 14 902 hits,
88 reads); index не добавлялся без подтверждённого predicate/SLA.

Transport выполнялся одним временным binary COPY-файлом на месяц: source COPY
полностью завершался, файл загружался в target temporary stage и удалялся до
следующего месяца. Initial run: 166 969 rows, 182.9 s. Rerun: 223.3 s.

## Same-snapshot rerun controls

| Контроль | Expected source | Actual target | Difference |
|---|---:|---:|---:|
| rows | 166 971 | 166 971 | 0 |
| business pairs | 166 971 | 166 971 | 0 |
| `COUNT` register visits | 769 485 | 769 485 | 0 |
| min/max month | 2025-01-01 / 2026-12-01 | same | 0 |
| source identity duplicates | 0 | 0 | 0 |
| mandatory NULL, bucket/range/horizon/future | 0 | 0 | 0 |
| child rows not `Дети` | 0 | 0 | 0 |

Initial and rerun source snapshots differed by two live rows; this is not a
rerun defect: each run was reconciled only against its own snapshot.

## BR-037 controls

- `ФЮ00151485 × И00058515`: returned start `2025-11-22` absent; valid start
  `2026-03-21` present once.
- `ФЮ00159691 × 001305732`: earlier `2026-06-19` absent; maximum valid start
  `2026-07-21` present once.

The table owner has `SELECT`; access-boundary check passed. Full rebuild remains
the only supported refresh method; incremental design is deferred.
