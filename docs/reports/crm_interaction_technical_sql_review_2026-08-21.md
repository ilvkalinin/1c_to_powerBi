# CRM technical validation and exact SQL review

Дата: 2026-08-21. Статус: `ACTIVE`.

Пользователь явно одобрил самостоятельный пакет для подготовки технически
проверенного, но ещё не исполняемого плана реализации `mart.crm_interaction`.

## Scope

- выполнить на VM-1 только bounded read-only metadata/cardinality/type/sentinel
  controls для `Reference67`, `Reference106`, `InfoRg7146`, `InfoRg6291`,
  `Reference137` и необходимых CRM dimensions;
- закрепить physical representation core IDs, nullable/timestamp/marked/archive
  profile, phone/HTML/employment multiplicity, PII boundary и stable guest
  funnel key;
- создать локальные reviewed SQL artifacts для core, трёх views, full rebuild,
  reconciliation, privileges and rollback — без их запуска;
- обновить mapping/data contract/ADR и подготовить один exact implementation
  plan для отдельного пользовательского решения.

## Boundaries

Источник 1С — только `READ ONLY`; source queries ограничивают колонки и
горизонт. Не входят исполнение DDL/DML, создание/изменение любых объектов на
VM-2 или 1С, Power BI, внешние Excel/Google Sheets, расписания и incremental
refresh design.

## Closure criterion

Все material source types/keys/joins/sentinels и PII safeguards подтверждены
либо явно ограничены; immutable local SQL plan содержит объектный состав,
операции create/load/reconciliation/rollback и не имеет unmapped columns.
Файлы готовы ровно к одному последующему implementation approval; ничего на
сервере до него не создаётся и не загружается.
