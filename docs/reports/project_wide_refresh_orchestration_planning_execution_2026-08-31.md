# Execution: planning общего refresh-orchestrator VM-2

- Пакет: `project_wide_refresh_orchestration_planning_2026-08-31`
- Статус: `VALIDATED / NO VM-2 CHANGE`
- Основание: [authorisation](project_wide_refresh_orchestration_planning_authorization_2026-08-31.md)

## Static inventory

`config/project_refresh_orchestration.json` содержит 29 atomic job-единиц.
Они покрывают ровно 40 реализованных физических объектов `mart`; пять
реализованных views (`v_sales_interaction`, `v_feedback_interaction`,
`v_guest_tour`, `v_dpfu_ancillary_revenue`, `v_reception_revenue`) намеренно
не являются jobs.

Composite jobs не разбиваются: `client_base_snapshot_retention` (2 факта),
`crm_br032` (4), `newcomer_guest_visits` (2), оба funnels (по 2),
`membership_receipts` (2), `revenue_refresh_chain` (3) и
`renewal_management_observation_chain` (2). Их existing runner сам задаёт
transaction/commit boundary, поэтому отдельная Task Scheduler job на дочерний
объект нарушила бы эту границу.

Единственная подтверждённая меж-job edge: `prebooking_state_event →
group_lesson`; она отражена в manifest. Цепочки revenue и renewal остаются
внутри собственных fail-closed runner'ов. Другие target-level зависимости не
добавлялись по предположению.

## Runtime evidence and no-SLA finding

Существующие measured full/bounded baselines: `client_base_daily` 264.574 s,
`visit_client_day` 313.035 s, `administrator_bookings_daily` 40.08 s,
`newcomer_guest_visits` 62.36 s, `renewal_management_contract` 131.40 s и
bounded debt window 92.673 s. Это разнородные приёмочные значения, а не общий
timeout и не доказательство daily incremental SLA.

Из 29 jobs: 16 имеют только full-rebuild runner, 7 — composite full-rebuild,
2 не имеют rerun entry point, 2 требуют admission token, 1 — parent full
rebuild перед append, 1 — bounded debt window. Для большинства нет
сопоставимого current runtime evidence. Следовательно, нельзя честно назначить
timeouts, heavy/light concurrency budget или критический путь к BR-014 08:30.

В частности, debt runner читает versioned `as_of_date=2026-08-30`; без
отдельного reviewed dynamic-as-of policy его повторный запуск не становится
обновлением на текущую дату. У 28 остальных jobs отсутствует подтверждённый
incremental design с watermark, late changes/deletions и reconciliation.

## Fail-closed result

`scripts/compile_refresh_orchestration_plan.py --plan` подтвердил: 40
physical objects, 29 jobs, 5 views-not-jobs, 29 `BLOCKED` jobs и ацикличный
DAG. Скрипт имеет только `--plan`; он не вызывает loader и отвергает manifest
с `AUTOMATION_APPROVED` job. VM-2 Task Scheduler, target/source data, `.env`,
Power BI и 1С не изменялись.

Следующий installation-пакет возможен только после explicit decision о
допустимой частоте full rebuild, либо после per-job incremental designs и
runtime evidence. До этого создание 40 automatic tasks создаст ложную
свежесть и не соответствует подтверждённой операционной модели.
