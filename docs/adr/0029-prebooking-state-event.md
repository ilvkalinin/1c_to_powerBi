# ADR-0029: факт событий предзаписи с legacy-кратностью ПЗ

- Статус: `STAGE_3 ADMISSION / DDL REVIEW PENDING`
- Дата: 2026-08-14
- Потребитель: «Контроль предварительной записи»

## Решение

Создать `mart.prebooking_state_event` как shared fact для состояния записи.
Его physical grain сохраняет current M: state-event ПЗ разворачивается по
qualifying `Document329.VT4352` line; state-event ГЗ остаётся одной строкой.
Логический key включает технический key `InfoRg7006`, branch и nullable
`legacy_settlement_line_no` (`NULLS NOT DISTINCT` на VM-2 PostgreSQL 18).

Значения клуба/услуги берутся из регистра, время/сотрудник — из document
branch. Это не смешение источников: именно такой набор полей использует M, а
SV-072 доказал, что документные club/service иногда отличаются.

## Архитектура и refresh

`read-only source qualification → temporary target stage → mart table → Power
BI Import`. Полный atomic rebuild BR-003 хранит записи для занятий внутри
dynamic horizon. Постоянный staging, raw replication и watermark не создаются.

PostgreSQL рассчитывает текущую категорию времени, delta и признаки branches;
DAX сохраняет net measures, доли, рейтинги и план-факт. Fact-to-fact joins не
создаются; используются общие calendar/club/activity/employee/service.

## Риски

- physical rows ПЗ не равны unique state-events по намеренному BR-018;
- orphan-enum, unposted/marked и document mismatches не «исправляются»;
- DDL и DML потребуют отдельных approvals; initial load — reconciliation.

## Evidence

- [mapping](../mappings/prebooking_state_event.md)
- [admission](../reports/prebooking_state_event_stage_3_product_admission.md)
- [current-query review](../reports/prebooking_control_query_review.md)
