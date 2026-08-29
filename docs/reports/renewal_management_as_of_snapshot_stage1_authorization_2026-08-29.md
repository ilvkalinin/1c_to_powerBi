# RM-ASOF-S1-001: authorization record

Дата: 2026-08-29.

## User authorization

Пользователь подтвердил отдельный пакет `renewal_management_as_of_snapshot`
после завершения current-state витрины.

## Scope

- локально разобрать current-state mapping, Power BI contract, available source
  metadata и reuse кандидаты;
- определить, какие поля можно или нельзя воспроизвести as-of даты окончания
  договора: next contract, interaction, rating, tenure, funnel/fail state;
- спроектировать grain, `as_of_date`, retention и Power BI boundary отдельного
  snapshot-продукта;
- подготовить mapping/ADR и список будущих read-only server controls с
  `NOT_EXECUTED` / `VALIDATION_PENDING` status;
- зафиксировать evidence, risks и `BLOCKER`/`DECISION_REQUIRED`, если history
  не позволяет достоверный as-of расчёт.

## Safety boundary

Только Stage 1 local analysis. Подключения к PostgreSQL/1С, schema discovery,
SQL/EXPLAIN, DDL/DML/COPY, новые mart-объекты, schedule и Power BI change не
разрешены.

## Closure criterion

Есть один рекомендованный temporal design, mapping с явными
`CONFIRMED`/`ASSUMPTION`/`VALIDATION_PENDING` полями, reuse decision и
конкретный список server controls для следующего пакета либо доказанный
`BLOCKER`.
