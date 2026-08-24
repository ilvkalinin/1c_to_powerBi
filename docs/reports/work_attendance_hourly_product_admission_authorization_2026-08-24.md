# Авторизация: почасовая посещаемость клуба

Статус: `ACTIVE`.

Дата: 2026-08-24.

## Подтверждённый scope

Пользователь подтвердил полный пакет для следующей витрины после явного
уточнения, что Power BI изменяется только после подготовки и приёмки всех
витрин. Пакет охватывает только отчёт №24 «Работа с посещаемостью» и его
минимальный объект `mart.club_attendance_hourly`.

## Разрешённые действия

- Проверить и актуализировать mapping, reuse-review, ADR и data contract по
  уже подтверждённым source rules; новый бизнес-rule не вводить.
- Создать одну физическую таблицу `mart.club_attendance_hourly` с grain
  `visit_date × club_id × start_hour × end_hour/NULL × sex_code/NULL × age_years/NULL`.
- Создать immutable source extract, DDL, atomic loader и reconciliation SQL.
- Выполнить read-only source controls, initial DDL/load, source-to-target
  reconciliation, measured full rebuild и rerun на VM-1/VM-2.
- Применить для нового runner общую policy: initial connection attempt plus
  five `OperationalError` retries.

## Граница и rollback

1С остаётся read-only. На VM-2 не передаются raw-регистры или client-level
события; в таблицу передаётся только source-side hourly aggregate. Не меняются
Power BI, PBIT, M, DAX, Excel-источники, внешний locker/capacity контур или
инкрементальная стратегия. Initial DDL и каждый rebuild выполняются одной
целевой транзакцией; rebuild очищает только эту table через transactional
`TRUNCATE` под advisory refresh-lock, затем выполняет COPY. При ошибке
выполняется rollback. После commit удаление
объекта не автоматизируется и требует отдельного решения.

## Reviewed implementation set

- `sql/marts/club_attendance_hourly_ddl.sql`;
- `sql/marts/club_attendance_hourly_extract.sql`;
- `sql/tests/club_attendance_hourly_reconciliation.sql`;
- `scripts/load_club_attendance_hourly.py`.

## Критерий закрытия

В одном `REPEATABLE READ, READ ONLY` source snapshot до target commit
зафиксированы control values. После COPY без отклонений совпадают count и сумма минут,
ключ/NULL/hour/horizon/access controls проходят, а атомарный rerun сохраняет
те же итоговые значения. Измеряется фактическое время полного rebuild без
заявления incremental SLA.
