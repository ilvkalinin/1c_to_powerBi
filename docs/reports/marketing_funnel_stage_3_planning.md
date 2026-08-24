# Stage-3 planning: «Маркетинговая воронка»

Статус: `COMPLETED / SQL REVIEW READY / NO DDL OR DML`.

## Зафиксированный scope

Planning package 2026-08-24 фиксирует минимальные `mart.marketing_funnel_task`
и `mart.marketing_funnel_task_contract`, их atomic full rebuild, rollback и
source-to-target reconciliation. Никакие CRM, выручечные, external-plan или
Power BI объекты этим planning package не меняются.

Пользователь 2026-08-24 отклонил расширение scope до общего task-core
маркетинговой и fitness-leads воронок. `mart.fitness_leads_funnel_task` и
его future outcomes остаются вне этого пакета.

Source columns и exact current transformations доказаны в
`/Users/ilia/Downloads/Telegram Desktop/Воронка.docx`: task/contract source
relations, 15 GUID first-interaction mapping, M-classification, two exact
duplicate-reason exclusions and BR-020. Полный mapping закреплён в
[mapping](../mappings/marketing_funnel.md), архитектура — в
[ADR-0032](../adr/0032-marketing-funnel-task-contract-mart.md).

## Готовая часть runnable package

После решения retention exact package будет содержать только:

- `sql/marts/marketing_funnel_reviewed_plan.sql`: DDL двух таблиц, constraints,
  public-access boundary и reversible first-load rollback;
- `sql/marts/marketing_funnel_source_extract.sql`: two source-side filtered
  extracts from one read-only snapshot with explicit horizon;
- `scripts/load_marketing_funnel.py`: binary COPY and one atomic target
  transaction; no incremental watermark or permanent staging;
- `sql/tests/marketing_funnel_reconciliation.sql`: independent source totals,
  task and pair keys, nulls, horizon, BR-020, month control, target counts and
  rerun comparison.

Expected test statuses before execution are `NOT_EXECUTED`; the package may
close only with zero differences against independently recorded controls and
against a rerun of the same contract.

## Retention decision — confirmed

Current PBIT contains task history 2024–2026 and cumulative-traffic input
`UNION(Задания 2024, Задания 2025)`. Пользователь 2026-08-24 подтвердил
BR-003 rather than a legacy exception: current extraction uses
`[2025-01-01, 2027-01-01)`. The July-2025 PBIT control remains an independent
acceptance value; no Power BI query, DAX or external plan is changed.
