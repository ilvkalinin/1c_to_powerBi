# Stage 3 PRODUCT ADMISSION: `mart.ip_revenue_daily`

Статус: `IN PROGRESS — source service-link controls`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.ip_revenue_daily` 2026-08-14. Граница
пакета — только компактный факт выручки ИП с candidate grain
`дата оплаты × клуб × услуга`.

В пакет не входят `mart.ip_training_daily`, `mart.dpfu_plan_assignment`,
report-specific views, внешние источники, DDL или DML. До отдельного
разрешения выполняются только mapping, read-only source controls, проект DDL
и проект reconciliation.

## Admission controls

1. подтвердить физические источники, даты, денежные поля и связь договора ИП
   с услугой;
2. проверить candidate grain/key и кардинальность каждой source-связи;
3. пересчитать bounded объём и сумму по BR-003, не перенося статические даты
   из legacy SQL/M;
4. после source evidence проверить VM-2 и подготовить DDL/reconciliation для
   отдельного review. DDL/DML в admission не выполняются.
