# Полная авторизация пакета: «Вовлечение новичков»

Статус: `CLOSED — IMPLEMENTED / RECONCILED / RERUN PASSED`.

## Подтверждённый scope

Пользователь 2026-08-24 подтвердил весь продукт
`mart.newcomer_engagement_milestone` до критериев закрытия и разрешил
автономную работу без промежуточных согласований. Пакет включает reuse-review
и source-to-target mapping, read-only source controls, ADR/data contract,
immutable DDL/source extract/independent controls/loader/reconciliation,
initial DDL/load, measured full rebuild, atomic rerun и execution evidence.
Остановка допускается только при реальном критичном конфликте бизнес-правил,
неразрешимом по существующим подтверждённым материалам.

## Граница

1С остаётся read-only. На VM-2 передаётся только компактный source-side fact;
raw-регистры и client-level staging не создаются. Power BI, PBIT, M, DAX,
Excel и подключения не меняются по BR-036. Первый релиз сохраняет current
M/DAX и решения BR-018; новые фильтры states, дедупликация или методическая
смена допускаются только при уже подтверждённом правиле.

## Критерий закрытия

До DDL фиксируются полный mapping без `UNKNOWN` SQL-колонок, reviewed
implementation set, bounded transport, transaction/rollback и independent
source expected controls. Initial load и rerun должны пройти source-to-target,
key/NULL/range/join/state/horizon/access controls с нулевым отклонением;
source/target performance измерены, Power BI boundary обозначена deferred.
