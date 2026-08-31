# ADR-0021: движения задолженности по неподтверждённым услугам

- Статус: `IMPLEMENTED / VALIDATED — VD-LOAD-001 / Power BI unchanged`
- Дата: 2026-08-03
- Отчёт: №22 «Посещаемость клиентов с долгами»

## Решение

Создать физическую таблицу `mart.unconfirmed_service_debt_movement` с grain:

> одно движение `AccumRg7509`: период × регистратор × номер строки.

Подтверждённый физический ключ `(debt_event_at, recorder_type, recorder_id,
recorder_line_no)`. Посетительская
когорта REUSE `mart.visit_client_day`; PII туда не добавляется. Движение и
когорта остаются разными фактами, связанными только общими датой, клубом и
защищённым client key на уровне мер/контролируемой модели.

Физическая таблица выбрана для воспроизводимого as-of над ограниченным
историческим горизонтом. Source-side запрос квалифицирует документные ветки и
знак до атомарной загрузки; постоянный staging не создаётся. View над VM-1 и
предрассчитанный ежедневный snapshot долга отклонены: первый повторяет тяжёлый
as-of, второй теряет произвольный момент и раздувает хранение.

## Обновление и Power BI

Full atomic rebuild по BR-003 — операция приёмки, не ежедневный incremental
SLA. PostgreSQL хранит движения и report-specific
detail; DAX считает остаток на начало/конец, погашение, новые долги и distinct
клиентов в выбранной когорте. PII выдаётся по BR-017.

Read-only validation `VD-INC-001—005` от 2026-08-31 не нашла у
`_accumrg7509` change timestamp/version или отдельный change feed. `_active`
не предоставляет tombstones, а event date `_period` не доказывает время
исправления. Поэтому отдельная incremental-настройка имеет статус `BLOCKED`;
текущий loader и full-rebuild решение не меняются.

Явным решением пользователя 2026-08-31 отдельно принят bounded
sliding-window: новый config/runner полностью заменяет текущий и два предыдущих
месяца, сохраняя более раннюю BR-003 историю. Это обрабатывает исчезнувшие
ключи только внутри окна и не снимает `BLOCKED` для настоящего change
watermark. Первый прогон до 2026-08-30 прошёл за 92.673 s.

## Риски

Физические relations, `RecordKind`, ключ/state/sign регистра, полиморфные
документы и source-side as-of подтверждены SV-099/SV-110/DV-V05B. При
недоказанной общей форме client key модель не
связывает два факта скрытым many-to-many.

## Доказательства

- [Требования](../reports/visits_debt.md)
- [Mapping](../mappings/visits_debt.md)
- [Incremental validation](../reports/visits_debt_incremental_validation_execution_2026-08-31.md)
- [Bounded refresh execution](../reports/visits_debt_bounded_incremental_execution_2026-08-31.md)
