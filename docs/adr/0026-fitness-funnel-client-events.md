# ADR-0026: клиентская фитнес-воронка через cohort и события исходов

- Статус: `DESIGNED / STAGE_3 TECHNICAL SQL REVIEW VALIDATED / PHYSICAL ADMISSION DECISION_REQUIRED`
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

SV-079 (live read-only, 2026-08-11) подтвердил на bounded cohort, что 100
eligible contract rows дают 98 client-start строк: две cohort-группы содержат
по два контракта. Это поддерживает выбранный client-start grain и не
разрешает выбирать один контракт или атрибутировать ему исходы.

Ключ исхода, client key, source states, связи документов и контрольные окна —
`VALIDATION_PENDING`. Если один исход не имеет стабильного source key,
контракт пересматривается до реализации.

Full-horizon admission 2026-08-28 показал 32 client-date cohorts с разными
клубами и 24 с разными tenure type, что даёт 46 duplicate target keys при
текущем PK. Это `DECISION_REQUIRED`: нельзя ни выбрать главный контракт, ни
создать текущую таблицу до нового business-rule решения. Evidence:
`docs/reports/fitness_funnel_client_start_stage3_product_admission_execution_2026-08-28.md`.

Пользователь 2026-08-28 выбрал договор с более поздней `Reference59.Fld674`
датой приобретения. Полный read-only control подтверждает, что поле заполнено
и устраняет 40 из 46 ambiguous cohort, но у шести cohort максимальная дата
совпадает при разных атрибутах. До явного правила для этой ничьей physical
admission остаётся `DECISION_REQUIRED`.

## Доказательства

- [Требования](../reports/fitness_funnel.md)
- [Mapping](../mappings/fitness_funnel.md)
- [Stage 3 technical review](../reports/fitness_funnel_client_start_stage3_technical_review_execution_2026-08-28.md)
