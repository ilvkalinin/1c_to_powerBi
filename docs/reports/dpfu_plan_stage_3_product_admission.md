# Stage 3 PRODUCT ADMISSION: `mart.dpfu_plan_assignment`

Статус: `COMPLETE — initial BR-003 load VALIDATED`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.dpfu_plan_assignment` 2026-08-14. Граница
пакета — один shared detail fact текущего плана ДПФУ из `InfoRg6612`.

В пакет не входят внешние бюджеты, report-specific views, DDL и DML.
DDL/DML требуют отдельных явных разрешений.

## S3-PLAN-001 — source admission controls

В актуальном BR-003 snapshot `2025-01-01`—`2027-01-01` подтверждены:

- физические поля даты, денежных сумм и key components существуют;
- 528 482 source rows дают 722 999 695,41 плановой выручки;
- технический key не имеет повторов; detail grain без `Fld6619` теряет
  95 357 строк, с ним повторов 0;
- club/activity/employee/client и plan-period joins имеют 100% coverage;
- `Fld6617` — клиент: 14 132 scoped codes, blank/duplicate 0;
  `Fld6619` не совпадает ни с одним клиентом и сохраняется discriminator;
- inactive rows 0, negative rows 30 и zero amounts 0; новые фильтры не
  добавляются по BR-018.

VM-2: PostgreSQL 18, схема `mart` доступна для создания;
`mart.dpfu_plan_assignment` отсутствует. DDL/DML не выполнялись.

## DDL review and application completed

Для отдельного DDL approval были подготовлены [DDL](dpfu_plan_assignment_ddl_review.sql),
[source extract](../../sql/marts/dpfu_plan_assignment_extract.sql),
[atomic target replace](../../sql/marts/dpfu_plan_assignment_target_replace.sql)
и [loader](../../scripts/load_dpfu_plan_assignment.py). Loader отказывается
от DML без `--apply` и сверяет строки, сумму, отрицательные и нулевые суммы,
logical key и контракт.

После отдельного явного DDL approval 2026-08-14 создана
`mart.dpfu_plan_assignment`. Post-check: восемь колонок, table rows = 0 и
primary key из шести logical-key components — passed.

Следующее ограничение: первая загрузка данных на VM-2 остаётся отдельным DML
approval. Loader выполнит bounded rebuild и source-to-target reconciliation
в одной контролируемой операции.

## Load and reconciliation result

Пользователь отдельно одобрил DML 2026-08-14. Loader выполнил атомарный
bounded rebuild из одного `REPEATABLE READ, READ ONLY` source snapshot.

`S3-PLAN-001—004`, 2026-08-14, BR-003 `2025-01-01`—`2027-01-01`:

| Контроль | Фактический результат | Статус |
|---|---:|---|
| Source → target rows | 528 482 → 528 482 | PASS |
| Planned revenue source / target | 722 999 695,41 / 722 999 695,41 | PASS |
| Staging and persistent key | duplicate keys 0; contract violations 0 | PASS |
| Sign preservation | negative rows 30; zero rows 0 | PASS — BR-018 preserved |
| BR-003 horizon | out-of-horizon rows 0 | PASS |

`sql/tests/dpfu_plan_assignment_reconciliation.sql` фиксирует повторяемые
read-only проверки. Subsequent refresh возможен только через
`scripts/load_dpfu_plan_assignment.py --apply` при отдельном разрешении DML.
