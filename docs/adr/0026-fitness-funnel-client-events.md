# ADR-0026: клиентская фитнес-воронка через cohort и события исходов

- Статус: `DESIGNED / TECHNICAL VALIDATION REQUIRED / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёт: №11 «Фитнес воронка»

## Решение

Создать два физических компактных объекта:

- `mart.fitness_funnel_client_start`: клиент × дата начала нового контракта;
- `mart.fitness_funnel_client_outcome`: клиент × дата исхода × тип исхода ×
  source key.

Отчёт считает outcome на уровне клиента, а не назначает его конкретному
контракту. Один wide cohort с флагами отклонён: он фиксировал бы окно и
размножался при нескольких исходах. Сырые записи/посещения/продажи не
копируются; source-side запросы формируют только квалифицированные события.

Физические таблицы выбраны из-за двух VM и повторных as-of/period расчётов.
Постоянный staging/core и materialized views не создаются без измерений.

## Обновление и Power BI

Ежедневный bounded rebuild BR-003. Общие календарь, клуб и client key
обслуживают два факта; физическая fact-to-fact relationship не создаётся.
DAX считает cohort size, исходы в выбранном окне, конверсии и накопительные
показатели. PII-detail доступна только report-specific представлению по
BR-017.

## Риски

Ключ исхода, client key, source states, связи документов и контрольные окна —
`VALIDATION_PENDING`. Если один исход не имеет стабильного source key,
контракт пересматривается до реализации.

## Доказательства

- [Требования](../reports/fitness_funnel.md)
- [Mapping](../mappings/fitness_funnel.md)
