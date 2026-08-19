# Stage 3 PRODUCT ADMISSION: `mart.administrator_card_gymmy_daily`

Статус: `IMPLEMENTED / INITIAL BR-003 LOAD VALIDATED — AC-REC-001—002`.

## Решение

Создать одну физическую таблицу `mart.administrator_card_gymmy_daily`.
Одна строка — `дата события × канонический клуб × направление`; показатель —
сумма успешных срабатываний карт. Это минимальный слой для Gymmy: журнал
администраторов и его Excel/Power Query остаются в Power BI.

Целевой ключ `(event_date, club_id, direction)` совпадает с grain. Он не
смешивает источник Gymmy с внешним журналом и не переносит ФИО, код карты,
терминал, идентификатор события, GUID направления или поле успеха.

## Что подтверждено

- 12 карт, два GUID направления, physical event key и `success IS NOT FALSE`
  подтверждены SV-100;
- текущая last-word карта → клуб однозначна для всех 12 карт — AC-V05;
- правила счёта: `SUM(usage_count)`, не `DISTINCTCOUNT`, — подтверждены
  владельцем отчёта;
- BR-003 вычисляет динамический bounded rebuild; на 2026-08-19 это
  `[2025-01-01, 2027-01-01)`;
- VM-2: DDL выполнен после явного разрешения владельца; создан
  `mart.administrator_card_gymmy_daily`;
- начальная загрузка 2026-08-19 в одном source snapshot: `Вход = 107583`,
  `Выход = 86694`; эти же суммы сохранены в целевой таблице.

## Подготовленный SQL

| Артефакт | Назначение |
|---|---|
| [source extract](../../sql/marts/administrator_card_gymmy_daily_extract.sql) | ограниченный source-side агрегат без персональных данных |
| [source controls](../../sql/marts/administrator_card_gymmy_daily_source_controls.sql) | независимые totals по направлениям до card→club mapping |
| [DDL review](administrator_card_gymmy_daily_ddl_review.sql) | одна таблица, PK и два check constraint; транзакция и rollback указаны в файле |
| [target replacement](../../sql/marts/administrator_card_gymmy_daily_target_replace.sql) | временная stage-таблица и атомарная замена только BR-003 horizon |
| [loader](../../scripts/load_administrator_card_gymmy_daily.py) | единственный запуск с `--apply`; без флага отказывается от DDL/DML |

## Выполненная приёмка

1. В одном read-only snapshot 1С зафиксированы независимые source totals по
   направлениям.
2. Таблица создана согласованным DDL.
3. Передан только дневной агрегат в temporary stage и атомарно заменён
   BR-003 horizon.
4. Сверены totals по направлениям, ключ, required `NULL`, допустимые значения
   и границы горизонта; evidence —
   [reconciliation](../../sql/tests/administrator_card_gymmy_daily_reconciliation.sql).
5. Сверка с внешним Excel остаётся отдельной Power BI-приёмкой и не блокирует
   Gymmy. Плановый refresh и SLA проверяются при настройке расписания, а не
   при начальной загрузке.

## Граница реализации

Источник 1С оставался read-only. В PostgreSQL создана только согласованная
таблица и загружен ограниченный BR-003 агрегат; Excel, Power Query, DAX и
другие витрины не изменялись.
