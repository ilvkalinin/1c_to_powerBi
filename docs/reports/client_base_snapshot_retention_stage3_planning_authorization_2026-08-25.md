# Авторизация Stage 3 planning: физические snapshot и retention

- Дата: 2026-08-25
- Пакет: `client_base_snapshot_retention_stage3_planning_2026-08-25`
- Этап: `STAGE_3_PLANNING`
- Отчёты: `client_base_snapshot`, `client_base_retention`
- Основание: пользователь подтвердил «завершение этих витрин» 2026-08-25
  после закрытого Stage 2 package-aware readiness checkpoint.

## Разрешённый scope

Подготовить один immutable reviewed admission set для двух новых физических
facts: source extracts, independent source controls, target DDL, target
replacement DML, rollback, bounded binary-COPY runner, reconciliation tests,
full-rerun procedure и exact performance evidence. Использовать подтверждённые
BR-037/BR-038 rules, contracts and Stage 2 results; Power BI не менять.

## Явная граница

Это planning package. Разрешены local artifacts и read-only source/target
metadata/plans; запрещены target DDL/DML, COPY, создание `mart` objects,
изменения 1С и Power BI. После readiness требуется отдельное явное одобрение
immutable reviewed SQL-plan до любых опасных statement.

## Критерий закрытия

Оба факта имеют полный mapped/reviewed set с точным списком объектов и
операций, rollback, independent controls, batch transport, performance plan и
reconciliation/rerun acceptance. Никакой physical object не создан.
