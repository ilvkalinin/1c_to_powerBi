# Stage 3 PRODUCT ADMISSION: `mart.lesson_room_slot_5m`

Статус: `ACTIVE — DDL APPLIED / DML NOT APPROVED`.

Пользователь подтвердил пакет `STAGE_3_PRODUCT_ADMISSION` 2026-08-14.
Граница — только физический факт занятости залов: одно квалифицированное
занятие `Document279` или `Document329` × один 5-минутный слот. Вместимость,
записи и пришедшие остаются в уже существующих facts и не повторяются здесь.

## Source evidence and design

SV-LS-001 подтвердил source fields, cardinality, две document branches и
отсутствие slot-key duplicates в контрольной неделе. BR-003 bounds на
2026-08-14 — `2025-01-01`—`2027-01-01`; BR-021 расширяет положительный
неполный интервал до последнего полного слота и не создаёт строку для двух
неположительных ГЗ-интервалов.

Повторный узкий source control в admission snapshot дал 1 968 072 ГЗ-слота и
3 456 059 ПЗ-слотов, всего 5 424 131. Контрольная неделя 2026-08-01—08:
22 134 ГЗ и 30 017 ПЗ-слотов, duplicate key = 0.

Extract использует index range scan по датам обеих document branches. Его
`EXPLAIN` показывает обычные joins к малым справочникам и не доказывает
необходимость вторичного индекса на VM-2. Поэтому DDL содержит только primary
key; вопрос вторичного Power BI-index остаётся `NOT MEASURED` до фактического
плана его чтения.

## Prepared for separate approval

VM-2: PostgreSQL 18.3, схема `mart` существует, target table отсутствует.
Подготовлены [extract](../../sql/marts/lesson_room_slot_5m_extract.sql),
[source controls](../../sql/marts/lesson_room_slot_5m_source_controls.sql),
[DDL review](../../sql/marts/lesson_room_slot_5m_ddl_review.sql),
[target replace](../../sql/marts/lesson_room_slot_5m_target_replace.sql) и
[DML loader](../../scripts/load_lesson_room_slot_5m.py). На момент подготовки
DDL и DML ещё не выполнялись.

## DDL applied

После отдельного явного DDL-разрешения 2026-08-14 создана пустая
`mart.lesson_room_slot_5m`. Post-check: 16 колонок, 18 constraints, primary
key `(source_kind, source_lesson_id, slot_start_at)`, rows = 0. Первая
загрузка данных остаётся отдельным DML-разрешением.
