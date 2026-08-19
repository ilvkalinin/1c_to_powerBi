# Stage 3 PRODUCT ADMISSION: `mart.administrator_card_gymmy_daily`

Статус: `SQL REVIEW READY / DDL AND DML NOT YET APPROVED`.

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
- preflight VM-2: объекта нет, в схеме `mart` есть право `CREATE`.

## Подготовленный SQL

| Артефакт | Назначение |
|---|---|
| [source extract](../../sql/marts/administrator_card_gymmy_daily_extract.sql) | ограниченный source-side агрегат без персональных данных |
| [source controls](../../sql/marts/administrator_card_gymmy_daily_source_controls.sql) | независимые totals по направлениям до card→club mapping |
| [DDL review](administrator_card_gymmy_daily_ddl_review.sql) | одна таблица, PK и два check constraint; транзакция и rollback указаны в файле |

## Приёмка после отдельного разрешения

1. В одном read-only snapshot 1С зафиксировать source totals по направлениям.
2. Создать таблицу показанным DDL.
3. Передать только дневной агрегат в temporary stage и атомарно заменить
   BR-003 horizon.
4. Сверить totals по направлениям, ключ, required `NULL`, допустимые значения,
   границы горизонта и повторный запуск.
5. Измерить refresh и SLA до 08:30 МСК. Сверка с внешним Excel остаётся
   отдельной Power BI-приёмкой и не блокирует Gymmy.

## Граница разрешения

DDL и DML не запускались. Для запуска требуется одно явное подтверждение
пользователя после просмотра точного DDL; источник 1С остаётся read-only.
