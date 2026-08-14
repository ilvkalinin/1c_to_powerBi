# Stage 3 PRODUCT ADMISSION: `mart.group_lesson`

Статус: `DDL APPROVAL PENDING`.

Пакет `STAGE_3_PRODUCT_ADMISSION — mart.group_lesson` подтверждён
2026-08-14. Граница — один lesson-grain fact для вместимости и итогов
групповых занятий. Состояния записи переиспользуются только через completed
`mart.prebooking_state_event`; план ДПФУ, расписание помещений и Excel в
пакет не входят.

Confirmed evidence: SV-072 PC-V11 (`Document279` ID unique, capacity observed,
no new document-state filter) and PC-V12 (`InfoRg8675` one row per lesson),
current M `Все уроки` / `Запсии на групповые`, BR-003 and BR-018.

Prepared for separate DDL approval: [mapping](../mappings/group_lesson.md),
[ADR](../adr/0030-group-lesson.md), [contract](../data_contracts/group_lesson.md),
[source extract](../../sql/marts/group_lesson_source_extract.sql) and
[DDL](../../sql/marts/group_lesson_ddl_review.sql). DML remains a separate
approval after DDL post-check.
