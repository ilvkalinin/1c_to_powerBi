# Stage 3 PRODUCT ADMISSION: `mart.ip_training_daily`

Статус: `IN PROGRESS — source admission controls`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.ip_training_daily` 2026-08-14. Граница
пакета — только общий факт тренировок ИП с grain
`дата тренировки × клуб × сотрудник × клиент × услуга` и метрикой
`training_count`.

В пакет не входят `mart.ip_revenue_daily`, `mart.dpfu_plan_assignment`,
views потребителей, внешние источники, DDL или DML. До отдельного разрешения
на опасную операцию выполняются только mapping, read-only source controls,
проект DDL и проект reconciliation.

## Подтверждённая основа

- reuse: один общий физический факт для «Отчёта по ИП», KPI Фитнеса,
  «Выручки ДПФУ» и загрузки сотрудников; отдельные копии запрещены ADR-0025;
- source: `InfoRg7006`, две текущие ветви `Document329` (ПЗ) и
  `Document279` (ГП), `Reference141X1`, `Reference132`, `Reference225`,
  `Reference163`, `Enum448`; `Document329.VT4352` сохраняет observed
  legacy-множество строк ПЗ по BR-018;
- Stage 2: SV-058/SV-068 подтвердили состояние cohort, отсутствие пересечения
  ветвей и current target grain за legacy-период. Их значения не являются
  контролем нового горизонта BR-003.

## Admission controls

1. подтвердить на source физические типы и заполненность каждого компонента
   grain, а также stable representation `client_key`;
2. пересчитать две ветви в пределах BR-003, сохранив current multiplicity
   `Document329.VT4352`, и проверить технический ключ/пересечение ветвей;
3. сверить source-row count с `SUM(training_count)` после целевой агрегации;
4. проверить цель VM-2, затем подготовить DDL и reconciliation для отдельного
   review. Никаких DDL/DML в этом admission не выполняется.
