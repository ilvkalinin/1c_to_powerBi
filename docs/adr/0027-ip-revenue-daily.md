# ADR-0027: общий факт выручки ИП

- Статус: `STAGE_3 DDL APPROVAL PENDING / source admission controls CONFIRMED`
- Дата: 2026-08-14
- Потребители: KPI Фитнеса и «Выручка ДПФУ»

## Решение

Создать один физический факт `mart.ip_revenue_daily` с grain:

> дата оплаты × клуб движения (включая отсутствие клуба) × услуга договора ИП.

`AccumRg7370` не объединяется с `mart.ip_training_daily`: их даты и
измерения описывают разные бизнес-события. Источник квалифицируется по
current M: `RecordKind = 0`, услуга только через договор
`7371 → Reference59.685 → Reference163`, описание услуги `%ИП%`; `_Active`
не добавляется как новый фильтр. BR-003 определяет динамический горизонт.

Клуб берётся только из движения `Fld7372`. Если ссылка не находит клуб,
`club_id` в факте становится `NULL`, как в current M с `LEFT JOIN`. Клуб
договора `Reference59.Fld687` не подставляется: это методическая доработка,
которая изменила бы 92 049 строк current snapshot.

`UNIQUE NULLS NOT DISTINCT (revenue_date, club_id, service_id)` защищает
логический ключ и сохраняет nullable club literally; VM-2 PostgreSQL 18
поддерживает этот синтаксис. Технический ключ исходного движения не хранится
после дневной агрегации.

## Архитектура и refresh

`read-only source aggregation → temporary target stage → mart table → Power BI
Import`. Постоянный staging/core не создаётся. Ежедневный полный bounded
rebuild BR-003 выбран потому, что watermark/окно поздних изменений не
подтверждены. PostgreSQL выполняет qualification и сумму; Power BI выполняет
план-факт, доли и прочие filter-dependent меры.

## Риски и пересмотр

- text qualification услуги сохраняется по BR-018; стабильный классификатор
  услуги — отдельная техническая доработка;
- подстановка клуба договора для строк без movement-club — отдельное явное
  методическое решение;
- DDL и DML требуют отдельных approvals, а первый load — reconciliation.

## Evidence

- [Mapping](../mappings/ip_revenue.md)
- [Admission](../reports/ip_revenue_stage_3_product_admission.md)
- [KPI composite ADR](0012-kpi-fitness-composite-model.md)
