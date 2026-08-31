# Авторизация Stage 3: bounded refresh движений долга

- Пакет: `visits_debt_bounded_incremental_2026-08-31`
- Объект: `mart.unconfirmed_service_debt_movement`
- Решение пользователя: принять bounded sliding-window risk без заявления
  watermark или incremental SLA; текущий loader не менять.

## Immutable scope

- [config](../../config/unconfirmed_service_debt_movement_incremental.json):
  срез 2026-08-30, окно `[2026-06-01, 2026-08-31)`;
- [separate runner](../../scripts/load_unconfirmed_service_debt_movement_incremental.py):
  `--plan-only` и `--run`, существующий loader не вызывается и не меняется;
- existing exact extract/source controls и target reconciliation;
- [window replace SQL](../../sql/marts/unconfirmed_service_debt_movement_incremental_target_replace.sql):
  в одной transaction удаляет окно и строки вне BR-003, затем вставляет stage;
  история `[2025-01-01, 2026-06-01)` сохраняется;
- до DML progressive exact-extract plans на 1/2/3 месяца; затем bounded binary
  COPY в exported read-only snapshot, pre/post-commit reconciliation и замер
  end-to-end elapsed time.

DDL, source 1С, current loader, Power BI и scheduler не изменяются. Rollback
target transaction сохраняет предыдущий факт при любой ошибке. Методический
риск: изменения старше 1 июня не обнаруживаются; это явное решение, а не
подтверждённый watermark.

## Критерий закрытия

1/2/3-month plan ladder успешно измерен без stop signal; atomic window refresh
до 30 августа committed; source/stage/target controls, key/contract/horizon и
post-commit reconciliation прошли; записаны rows/sum/min/max и elapsed time.
