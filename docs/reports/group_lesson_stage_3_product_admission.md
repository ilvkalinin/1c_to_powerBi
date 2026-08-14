# Stage 3 PRODUCT ADMISSION: `mart.group_lesson`

Статус: `DML APPROVAL PENDING — empty target table created and verified`.

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
[DDL](../../sql/marts/group_lesson_ddl_review.sql). The separately approved
DML runner and atomic target replace are
[loader](../../scripts/load_group_lesson.py) and
[target SQL](../../sql/marts/group_lesson_target_replace.sql).

After separate DDL approval 2026-08-14, created `mart.group_lesson`.
Post-check passed: 13 columns, 0 rows and primary key `group_lesson_id`.
The first DML load remains a separate approval.

Read-only source control was proven equivalent to the full base extract in one
repeatable-read snapshot: 301,237 lessons, capacity sum 5,951,952 and free
attendance sum 1,351,360. The loader checks these base controls before commit,
requires a non-empty completed GZ branch of `mart.prebooking_state_event`, and
rolls back the entire target transaction on any mismatch.
