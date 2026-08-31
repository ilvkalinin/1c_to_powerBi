# Авторизация Stage 2: incremental refresh для движений долга

- Пакет: `visits_debt_incremental_validation_2026-08-31`
- Этап: `STAGE_2_SERVER_VALIDATION`
- Отчёт: `visits_debt`
- Объект будущей настройки: `mart.unconfirmed_service_debt_movement`
- Основание: пользователь подтвердил отдельный read-only validation-пакет.

## Scope

Только read-only metadata и aggregate controls на VM-1 для `_accumrg7509` и
зависимых document/reference relations. Проверить наличие физического change
watermark/change feed, технические state/deletion признаки, возможность
обнаружить исчезнувшие строки и доказательность окна late changes. Текущий
loader, VM-2 target, Power BI и источник 1С не изменяются.

Точный SQL: [visits_debt_incremental_validation_2026-08-31.sql](../source_metadata/validation_sql/visits_debt_incremental_validation_2026-08-31.sql).

## Предварительно зафиксированные ожидания

| Check | Ожидание до исполнения | Критерий |
|---|---|---|
| VD-INC-001 | metadata перечислит все физические колонки источника | `PASS` при полном результате |
| VD-INC-002 | пригодный watermark должен иметь временной/монотонный тип и меняться при исправлении | иначе `BLOCKED` |
| VD-INC-003 | механизм deletions должен обнаруживать исчезновение ранее загруженного ключа | `_active` без журнала исчезновений недостаточен |
| VD-INC-004 | late-change window требует исторических пар `changed_at` × event date | без них глубина остаётся `ASSUMPTION` |
| VD-INC-005 | event date `_period` не считается change watermark только по имени | пригодность требует независимого evidence |

## Критерий закрытия

Сохранены snapshot/time/results и один однозначный вывод: либо `VALIDATED`
спецификация отдельной incremental-настройки без изменения текущего loader,
либо named `BLOCKED` с точным отсутствующим source mechanism. Реализация,
DDL/DML, schedule и SLA в пакет не входят.
