# Авторизация технического Stage 3 review: «Загрузка сотрудников»

- Дата: 2026-08-27
- Пакет: `employee_activity_interval_stage3_technical_sql_review_2026-08-27`
- Этап: `STAGE_3_TECHNICAL_SQL_REVIEW`
- Отчёт: `employee_workload`
- Основание: пользовательское поручение «Делай витрину полностью до конца».

## Разрешённый scope

Подготовить проверяемый и неизменяемый набор для будущей физической поставки
`mart.employee_activity_interval`: extract, независимые source controls, DDL,
atomic loader, target reconciliation, rollback-стратегию, mapping/contract и
admission evidence. Измерить один репрезентативный
`EXPLAIN (ANALYZE, BUFFERS)` точного extract в fresh `REPEATABLE READ, READ
ONLY` source session. Зафиксировать границы sample, rows, time и I/O.

Пакет не выполняет DDL, DML, `COPY`, target connection, full-range transport,
Power BI/M/DAX change или изменение источника 1С. После фиксации reviewed set
физическая initial load и atomic rerun потребуют отдельного одобрения точных
ссылок, объектов, операций, rollback и критериев приёмки.

## Критерий закрытия

Все колонки будущего physical contract имеют подтверждённые source,
transformation, type, NULL-policy и test; physical key/grain и risk joins
явно сохранены; создан один immutable local SQL set; выполнен и записан
read-only representative exact-extract plan; DDL/DML/COPY отсутствуют.
