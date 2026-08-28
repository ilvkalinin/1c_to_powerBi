# ADR-0026: клиентская фитнес-воронка через cohort и события исходов

- Статус: `IMPLEMENTED / OUTCOME PHYSICAL ADMISSION VALIDATED / POWER BI DESIGNED`
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

Общие календарь, клуб и client key обслуживают два факта; физическая
fact-to-fact relationship не создаётся. Для outcome измерен только
source-first месячный full rebuild через временный derived binary COPY pool.
Ежедневный SLA и incremental refresh не заявляются: нет доказанных watermark,
late changes и deletions.
DAX считает cohort size, исходы в выбранном окне, конверсии и накопительные
показатели. PII-detail доступна только report-specific представлению по
BR-017.

## Physical admission outcome — 2026-08-28

`mart.fitness_funnel_client_outcome` создан и дважды атомарно загружен.
Initial и rerun прошли independent source/stage/target controls. Выбран
source-first пул из 32 месячных derived files: он не хранит raw 1С и открывает
target transaction только после закрытия source readers. Final rerun содержит
1 037 064 unique source keys, обязательных/horizon deviations = 0. Target
August read = 288.341 ms; table 973 MB после `DELETE + INSERT` rerun.
Следовательно, текущая стратегия — full-rebuild baseline, а не ежедневная
операция. Evidence:
`docs/reports/fitness_funnel_client_outcome_stage3_product_admission_execution_2026-08-28.md`.

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
совпадает при разных атрибутах. Пользователь выбрал больший `Fld693` срок
договора как второй ранг. Равенство обоих рангов пока не проверено на полном
горизонте, поэтому physical admission остаётся `VALIDATION_PENDING`.

## Доказательства

- [Требования](../reports/fitness_funnel.md)
- [Mapping](../mappings/fitness_funnel.md)
- [Stage 3 technical review](../reports/fitness_funnel_client_start_stage3_technical_review_execution_2026-08-28.md)
