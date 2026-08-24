# Исполнение Stage 3: «Воронка. Лиды. Фитнес»

Статус: VALIDATED.

## Созданные объекты и граница данных

Созданы только mart.fitness_leads_funnel_task (one Reference106.ID) и
mart.fitness_leads_funnel_task_service (current task×service attribution).
VM-1 оставалась REPEATABLE READ, READ ONLY; на VM-2 не переносились сырые
регистры, документы, клиенты или PII за пределами минимального task fact.
Power BI/M/DAX/PBIT и Excel не менялись.

## Source change and control baseline

Stage-2 snapshot 12390148:12390148: содержал 166 720 задач и 65 659
stage-booking задач. Перед initial load источник изменился: raw four-funnel
scope стал 166 794 вместо 166 792, valid task scope — 166 722.
Следующий source snapshot для загрузки фиксирует:

| Control | Value |
|---|---:|
| tasks | 166 722 |
| task×service rows | 27 131 |
| stage-booking tasks | 65 662 |
| positive-training tasks | 12 157 |
| training count sum | 63 142 |

Это физическое изменение source data, а не изменение правила. Поэтому FL-R05
сравнивает four current-PBIT controls, вычисленные в том же immutable source
snapshot, что и binary COPY; FL-R01 отдельно доказывает точный
source-to-target transport.

## Atomic initial load and rerun

Initial load создал обе таблицы и передал 78 727 634 task bytes и
2 795 015 service bytes. В одной VM-2 транзакции прошли:

| Control | Result |
|---|---|
| FL-R01 transport counts | PASS |
| FL-R02 task/bridge keys and orphans | 0 / 0 / 0 |
| FL-R03 null and outcome invariants | 0 / 0 / 0 |
| FL-R04 BR-003 and bridge semantics | 0 / 0 / 0 |
| FL-R05 same-snapshot PBIT controls | PASS |
| FL-R06 PUBLIC SELECT grants | 0 |

Mandatory --rebuild повторил полный BR-003 source snapshot, child-first
delete, обе COPY и FL-R01—FL-R06. Все результаты совпали с initial load и
закончились TARGET_COMMIT_PASS. Это full rebuild; incremental refresh и
ежедневный SLA ≤1 минута не заявляются.

## Performance evidence

Read-only VM-2 measurement after rerun:

| Object | Rows | Total size |
|---|---:|---:|
| mart.fitness_leads_funnel_task | 166 722 | 178 733 056 bytes |
| mart.fitness_leads_funnel_task_service | 27 131 | 12 869 632 bytes |

GROUP BY task_date with booking/training flags used a parallel sequential
scan, no spill, and completed in 126.247 ms. Existing PK/unique indexes
cover the confirmed task and bridge keys. No index is proposed without a
measured selective Power BI predicate.
