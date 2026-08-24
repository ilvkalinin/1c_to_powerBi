# Полномочие пакета планирования Stage 3: «Маркетинговая воронка» — 2026-08-24

Статус: `COMPLETED — STAGE3_PLANNING_AUTHORIZED / NO DDL OR DML`.

## Подтверждённый scope

Пользователь 2026-08-24 подтвердил самостоятельный пакет
«Маркетинговая воронка»: review переиспользования CRM/выручечных продуктов,
фиксацию mapping и grain, затем минимальную витрину, атомарную загрузку и
source-to-target reconciliation с нулевыми отклонениями по утверждённым
control values и rerun.

Поскольку точный reviewed SQL-план ещё не существовал, настоящее
подтверждение открывает **только этап планирования**. Его результатом должны
стать один неизменяемый план DDL/DML, исходные extraction SQL, rollback и
независимые reconciliation controls. После этого потребуется отдельное
пользовательское одобрение полного runnable Stage-3 admission-пакета до
подключения к источнику, DDL, DML или загрузки.

## Разрешённые действия

- локальный evidence-based reuse review текущих CRM и выручечных продуктов;
- уточнение source-to-target mapping, grain, архитектуры, контракта Power BI
  и ADR без изменения подтверждённой бизнес-логики;
- подготовка reviewed SQL, rollback и тестов с `NOT_EXECUTED` / `VALIDATION_PENDING`;
- документирование точных независимых control values, необходимых для
  будущей source-to-target reconciliation и rerun.

## Запрещённые действия

- подключение к PostgreSQL/1С или любое server-side validation;
- DDL/DML, создание объектов, загрузка, schedule, выдача прав и изменение
  исходных объектов;
- утверждение test result, control value или rerun без независимого факта.

## Критерий закрытия planning package

Непротиворечивые mapping, grain, ADR, Power BI contract, точный SQL-план,
rollback и reconciliation design готовы к единому runnable Stage-3 approval;
все остающиеся внешние факты помечены `NOT_EXECUTED`, `VALIDATION_PENDING`,
`UNKNOWN` или `BLOCKER` без объявления реализации выполненной.
