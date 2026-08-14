# Stage 3 PRODUCT ADMISSION: `mart.ip_revenue_daily`

Статус: `DECISION REQUIRED — club attribution`.

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

## S3-IP-REVENUE-001 — source evidence

В актуальном BR-003 snapshot `2025-01-01`—`2027-01-01` подтверждены:

- `AccumRg7370` хранит дату как `timestamp`, технический ключ как
  `(RecorderTRef, RecorderRRef, LineNo)`, деньги как `numeric`; ключ не имеет
  повторов в 178 022 qualified movements;
- услуга берётся только через договор
  `7371 → Reference59.685 → Reference163`; прямое поле `7378` не служит
  fallback по ранее подтверждённым SV-019—SV-022;
- `RecordKind = 0`, current text qualification услуги и отсутствие нового
  `_Active` filter воспроизводят legacy: 3 inactive, 82 738 negative и 4
  zero movements сохраняются;
- 178 022 source movements сворачиваются в 47 151 candidate date × club ×
  service rows; сумма до и после группировки совпадает — 268 944 858,22.

### Единственное решение

Current Power Query делает `LEFT JOIN` к клубу движения и сохраняет пустой
клуб. В актуальной qualified выборке 92 049 оплат на 1 973 090,65 не имеют
клуба движения, но имеют клуб договора; ещё в 19 строках оба клуба есть, но
различаются (44 990,00). Поэтому подставить клуб договора автоматически
нельзя: это изменит атрибуцию выручки. До решения не готовятся DDL/DML.
