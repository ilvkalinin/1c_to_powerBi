# ADR-0020: первые посещения, гостевые визиты и туры новичков

- Статус: `SUPERSEDED FOR FIRST/GUEST FACTS — Power BI selection retained 2026-08-24`
- Дата: 2026-08-03
- Отчёт: №20 «Новички и гостевые визиты»

## Контекст

Отчёт объединяет три бизнес-процесса с разными grain. Их нельзя хранить одной
таблицей без размножения конверсий и PII-detail.

## Первоначальное решение

Создать два физических факта и один локальный view:

- `mart.new_first_visit` — контракт × первое квалифицированное посещение;
- `mart.guest_visit_conversion` — гость × дата гостевого визита;
- REUSE `mart.v_guest_tour` из ADR-0016 на grain CRM-взаимодействия.

First/guest outcomes на покупку в окне `[0,44]` дней и ACCUNIQ рассчитываются
source-side до загрузки. Полные регистры посещений, гостей и CRM на VM-2 не
копируются. Постоянный staging не создаётся. Физические таблицы нужны из-за
ранжирования первого события и 44-дневных lookups; materialized views без
измерений не выбираются.

## Уточнение решения — 2026-08-24

Read-only diagnostic показал materially different rows при одинаковом первом
`Period` и при одинаковой паре `client_code × guest_visit_date`. Пользователь
выбрал «оставить как в Power BI». Поэтому первоначальное решение о создании
`mart.new_first_visit` и `mart.guest_visit_conversion` отменено для первого
физического выпуска: их selection остаётся в M/DAX (BR-035), DDL/DML не
выполняются. `mart.v_guest_tour` остаётся реализованным reusable CRM view.

## Обновление и Power BI

Ежедневный атомарный rebuild BR-003. Общие календарь и клуб фильтруют три
набора однонаправленно; fact-to-fact связей нет. Внешний план встреч остаётся
в Power BI. PostgreSQL фиксирует first-event, as-of стаж и outcome-поля; DAX
считает distinct, конверсии и план-факт.

Код/ФИО клиента и телефон тура доступны только report-specific таблицам по
BR-017 и не добавляются в общий обезличенный факт посещений.

## Риски

Tie-break первого посещения, ключ/статус гостевого регистра, 44-дневные
границы, CRM normalization и ACCUNIQ states — `VALIDATION_PENDING`. При
недоказанном ключе гостевого события физический объект не реализуется.

NV-V01/NV-V03/NV-V04/NV-V07/NV-V08 выполнены в read-only snapshot: physical
guest key и history ties подтверждены, но guest candidate key материально
неуникален; у регистра четыре статуса и присутствуют аномальные даты. CRM-туры
не размножаются телефонией в проверенном current-M контуре. Это не разрешает
Stage 3: ACCUNIQ, первый визит и 0/44/45 outcomes остаются pending.

## Доказательства

- [Требования](../reports/newcomer_guest_visits.md)
- [Mapping](../mappings/newcomer_guest_visits.md)
- [CRM core](0016-shared-crm-interaction-core.md)
