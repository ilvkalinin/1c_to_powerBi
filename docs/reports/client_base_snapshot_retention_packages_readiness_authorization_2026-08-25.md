# Авторизация Stage 2: package-aware snapshot и retention «Клиентской базы»

- Дата: 2026-08-25
- Пакет: `client_base_snapshot_retention_packages_readiness_2026-08-25`
- Этап: `STAGE_2_SERVER_VALIDATION`
- Отчёты: `client_base_snapshot`, `client_base_retention`
- Основание: явное поручение пользователя «добавь пакеты где надо» от
  2026-08-25 после read-only family-coverage audit.

## Цель и scope

Подготовить оба ещё не созданных физически факта к корректному добавлению
child-package ветви. Проверить в одном source `REPEATABLE READ READ ONLY`
snapshot физические типы, ключи, cardinality, состояния и control values для
следующих обязательных ветвей:

1. BR-037/BR-038 package-aware universe: membership и valid child packages
   до club/network dedupe, baseline/current semi-join и группировки;
2. `Reference141X1`, `Reference132`, `InfoRg5654`, `AccumRg7575` и
   `Document325` — только в объёме полей snapshot/retention;
3. calendar, age, gender, tenure-as-of, 30-day activity и retention
   intersection с нулевой tolerance для independently computed controls;
4. mapping, data contract, performance sample и immutable reviewed
   DDL/load/reconciliation/rerun plan для каждого факта, если все поля
   подтверждены.

## Границы этапа

Разрешены только read-only source/target queries, `EXPLAIN (ANALYZE, BUFFERS)`
на ограниченной репрезентативной выборке и документация. Запрещены DDL, DML,
`COPY`, создание объектов, изменение 1С и Power BI. Физические
`mart.client_base_snapshot` и `mart.client_base_retention` пока отсутствуют;
не создавать неполный факт и не скрывать незакрытое поле предположением.

## Критерий закрытия

Для обеих витрин зафиксированы exact mapping и source controls с observed
values, либо конкретный `BLOCKER`; BR-037/BR-038 доказан в нужном universe;
performance sample выполнен до любого full-range плана; создан immutable
implementation plan с объектами, DDL/DML, rollback и reconciliation либо
документирована причина, почему такой план ещё нельзя безопасно утвердить.
Power BI не меняется.
