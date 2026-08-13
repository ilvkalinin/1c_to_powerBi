# ADR-0018: факт применений промокодов

- Статус: `DESIGNED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-090, SV-091 / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёт: №14 «Отчёт по промокодам»

## Решение

Создать физическую таблицу `mart.promo_application` с grain:

> одно квалифицированное применение промокода или выдача подарка из одной
> исходной ветви.

Ключ-кандидат `(source_kind, recorder_id, line_no)`. Скидка, подарок и три
45-дневных outcome-флага материализуются в этой строке после source-side
защиты от one-to-many. Общие факты продаж/ДПФУ используются только для
вычисления outcomes и не связываются с фактом в Power BI.

Отдельный `core` не создаётся: второй потребитель этого grain не доказан.
Физическая таблица предпочтительна удалённому view из-за многократных
44-дневных поисков на другой VM. Materialized view не выбирается без
измерений.

## Обновление и граница

Ежедневный атомарный rebuild BR-003 до подтверждения watermark. PostgreSQL
квалифицирует source states, нормализует скидку/подарок и рассчитывает fixed
outcomes. DAX считает категории, distinct-клиентов, доли, выпуски и
filter-dependent конверсии. Технические ID скрыты, PII не выводится.

## Риски

Physical source key, states and 1–44-day outcomes are validated in SV-091.
Document-line and gift joins have observed one-to-many multiplicity; current
M/DAX remains the first-release rule under BR-018. Any protection that changes
aggregation, grain or category result requires a separate methodology decision.

## Доказательства

- [Требования](../reports/promo_codes.md)
- [Mapping](../mappings/promo_codes.md)
