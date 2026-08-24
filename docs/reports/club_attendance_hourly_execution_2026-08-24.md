# Execution evidence: `mart.club_attendance_hourly`

Статус: `VALIDATED`.

Дата: 2026-08-24.

## Реализация

Создана физическая таблица `mart.club_attendance_hourly` с grain
`visit_date × club_id × start_hour × end_hour/NULL × sex_code/NULL ×
age_years/NULL`. Source-side SQL агрегирует только необходимые поля из
`AccumRg7575`, `Document325`, клуба, клиента и договора в одном
`REPEATABLE READ, READ ONLY` snapshot; raw/client-level события на VM-2 не
переносятся. Power BI, M, DAX, PBIT и внешние Excel-наборы не изменялись.

В loader применяется общая policy соединений: initial attempt и пять retries
только для `OperationalError`. Для production full rebuild применён
transactional `TRUNCATE + COPY` под advisory refresh-lock: таблица видит новый
snapshot только после commit. Source transport разделён на месячные binary
COPY-файлы: это устранило зависание psycopg на одном многогигабайтном result
portal; каждый файл удаляется автоматически после его target COPY.

## Контрольные результаты

| Прогон | Source aggregate rows | Посещения | Минуты | Результат |
|---|---:|---:|---:|---|
| Initial load | 5 965 645 | 6 983 868 | 792 146 818,650000 | WA-R01—WA-R06 PASS |
| Atomic rerun | 5 966 022 | 6 984 279 | 792 104 875,033333 | WA-R01—WA-R06 PASS; 413,22 s |

Разница между прогонами — изменение live 1С между независимыми snapshot, а не
расхождение витрины: в каждом snapshot WA-R01 точно сопоставил source count,
число посещений и сумму минут с target; WA-R02—WA-R06 дали ноль нарушений
ключа, контракта, горизонта BR-003, sentinel BR-019 и public access.

История: `2025-01-01 ≤ visit_date < 2027-01-01`; фактические данные дошли до
2026-08-24, будущие месяцы корректно обработаны как пустые.

## Производительность

Read-only source `EXPLAIN (ANALYZE, BUFFERS)` на 2026-07-15: 323,522 ms.
На месячном control period отключение hash join в рамках read-only source
session уменьшило exact-query время с 5 414,917 до 3 806,506 ms; source
индексы не менялись. Full rebuild 413,22 s — измеренный baseline, не
incremental SLA и не соответствие минутному daily-refresh требованию.

## Артефакты

- [`DDL`](../../sql/marts/club_attendance_hourly_ddl.sql);
- [`source extract`](../../sql/marts/club_attendance_hourly_extract.sql);
- [`reconciliation`](../../sql/tests/club_attendance_hourly_reconciliation.sql);
- [`atomic runner`](../../scripts/load_club_attendance_hourly.py).
