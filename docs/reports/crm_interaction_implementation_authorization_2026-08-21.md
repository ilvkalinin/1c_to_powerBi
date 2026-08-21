# CRM implementation authorization

Дата: 2026-08-21. Статус: `ACTIVE`.

Пользователь явно подтвердил самостоятельный implementation-пакет для общего
CRM core и трёх compatibility views.

## Полный scope

1. Проверить на VM-2 отсутствие шести новых объектов и read-only получить
   существующие роли/privileges, не раскрывая секреты.
2. Выполнить неизменяемый reviewed SQL
   [`crm_interaction_reviewed_plan.sql`](../../sql/marts/crm_interaction_reviewed_plan.sql):
   создать `mart.crm_interaction`, `mart.crm_interaction_phone`,
   `mart.crm_interaction_comment`, `mart.v_sales_interaction`,
   `mart.v_feedback_interaction`, `mart.v_guest_tour`; закрыть их от `PUBLIC`.
3. Из одного `REPEATABLE READ READ ONLY` snapshot VM-1 выполнить полный
   client-side `COPY` трёх таблиц на VM-2 и source-to-target/key/null/view
   reconciliation; повторить full rebuild для rerun equality и измерить
   end-to-end duration.
4. Если в VM-2 уже есть однозначно определённая least-privilege BI role,
   выдать ей `SELECT` только на три views; иначе не выдавать доступ и
   зафиксировать отсутствие имени как внешний `BLOCKER` после всех безопасных
   implementation controls.
5. Обновить mapping, contracts, ADR, catalog, ledger и runbook только
   фактическими результатами, выполнить отдельный атомарный commit.

## Boundaries and rollback

Не менять 1С, PBIT/model, Power BI schedules, Excel/Google Sheets, инкремент,
guest ACCUNIQ/contract outcomes (BR-031), существующие mart objects или
бизнес-логику. До `COMMIT` любой сбой откатывается `ROLLBACK`; post-commit
drop/change не выполняется этим пакетом.

## Closure criterion

Все шесть объектов созданы, three-table full rebuild и независимые controls
passed, rerun совпадает, measured duration recorded, `PUBLIC` has no access,
а доступ BI-role либо выдан однозначно подтверждённой роли, либо единственный
remaining external blocker documented.
