# Полная авторизация пакета: «Подготовка к продлению»

Статус: `ACTIVE — STAGE_3_PRODUCT_ADMISSION`.

## Подтверждённый scope

Пользователь 2026-08-24 явно подтвердил всю витрину
`mart.preparation_renewal_checkpoint` до конца и разрешил автономное
выполнение без промежуточных согласований. Пакет включает source-to-target
mapping и reuse-review, source-side controls, ADR и Power BI contract,
reviewed DDL/source extract/loader/reconciliation, initial DDL/load, measured
full rebuild, atomic rerun и execution evidence. Остановка допустима только
при реальном критическом конфликте бизнес-правил, который нельзя разрешить
имеющимися подтверждёнными материалами.

## Граница

Источник 1С остаётся read-only. На VM-2 передаются только компактные
source-side results; raw-регистры и client-level staging не создаются.
Внешний Excel-план, Power BI/PBIT/M/DAX и их подключения не меняются по
BR-036. Сохраняется current logic BR-018: current pair contract+client,
границы окна и отсутствие непроверенных state-фильтров; нельзя самостоятельно
дедуплицировать заморозки или менять правило исключения.

## Preflight и критерий закрытия

До DDL фиксируются immutable reviewed mapping, ADR, DDL, source extract,
loader и reconciliation; все SQL-колонки имеют закрытый mapping. Загрузка
использует единственный read-only snapshot, initial + five OperationalError
retries, bounded binary COPY без постоянной второй копии, одну target
transaction с rollback и независимые expected controls до target COPY.

Критерий закрытия: source-to-target expected values, key/NULL/range/join/state/
horizon/access controls имеют нулевое отклонение; initial load и atomic rerun
успешны; source и target performance измерены; Power BI boundary отмечена как
deferred by BR-036.

## Reviewed implementation set

- `sql/marts/preparation_renewal_checkpoint_ddl.sql`;
- `sql/marts/preparation_renewal_checkpoint_extract.sql`;
- `sql/marts/preparation_renewal_checkpoint_source_controls.sql`;
- `sql/tests/preparation_renewal_checkpoint_reconciliation.sql`;
- `scripts/load_preparation_renewal_checkpoint.py`.
