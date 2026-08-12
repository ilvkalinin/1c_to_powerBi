# ADR-0021: движения задолженности по неподтверждённым услугам

- Статус: `DESIGNED / TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-089 / IMPLEMENTATION DEFERRED`
- Дата: 2026-08-03
- Отчёт: №22 «Посещаемость клиентов с долгами»

## Решение

Создать физическую таблицу `mart.unconfirmed_service_debt_movement` с grain:

> одно движение `AccumRg7509`: период × регистратор × номер строки.

Ключ-кандидат `(debt_event_at, recorder_id, recorder_line_no)`. Посетительская
когорта REUSE `mart.visit_client_day`; PII туда не добавляется. Движение и
когорта остаются разными фактами, связанными только общими датой, клубом и
защищённым client key на уровне мер/контролируемой модели.

Физическая таблица выбрана для воспроизводимого as-of над ограниченным
историческим горизонтом. Source-side запрос квалифицирует документные ветки и
знак до атомарной загрузки; постоянный staging не создаётся. View над VM-1 и
предрассчитанный ежедневный snapshot долга отклонены: первый повторяет тяжёлый
as-of, второй теряет произвольный момент и раздувает хранение.

## Обновление и Power BI

Ежедневный bounded rebuild BR-003. PostgreSQL хранит движения и report-specific
detail; DAX считает остаток на начало/конец, погашение, новые долги и distinct
клиентов в выбранной когорте. PII выдаётся по BR-017.

## Риски

Физические relations, `RecordKind` и PK-side visit branch подтверждены
SV-089 через existing source evidence; ключ/state/sign регистра, полиморфные
документы и контрольный as-of — `VALIDATION_PENDING`. При недоказанной общей форме client key модель не
связывает два факта скрытым many-to-many.

## Доказательства

- [Требования](../reports/visits_debt.md)
- [Mapping](../mappings/visits_debt.md)
