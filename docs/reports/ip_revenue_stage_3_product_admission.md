# Stage 3 PRODUCT ADMISSION: `mart.ip_revenue_daily`

Статус: `COMPLETE — initial BR-003 load VALIDATED`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.ip_revenue_daily` 2026-08-14. Граница
пакета — только компактный факт выручки ИП с candidate grain
`дата оплаты × клуб × услуга`.

В пакет не входят `mart.ip_training_daily`, `mart.dpfu_plan_assignment`,
report-specific views и внешние источники. DDL и DML требуют отдельных явных
разрешений.

## Admission controls

1. подтвердить физические источники, даты, денежные поля и связь договора ИП
   с услугой;
2. проверить candidate grain/key и кардинальность каждой source-связи;
3. пересчитать bounded объём и сумму по BR-003, не перенося статические даты
   из legacy SQL/M;
4. после source evidence проверить VM-2 и подготовить DDL/reconciliation для
   отдельного review. DDL/DML в admission не выполняются без отдельного
   разрешения.

## S3-IP-REVENUE-001 — source evidence

В актуальном BR-003 snapshot `2025-01-01`—`2027-01-01` подтверждены:

- `AccumRg7370` хранит дату как `timestamp`, технический ключ как
  `(RecorderTRef, RecorderRRef, LineNo)`, деньги как `numeric`; ключ не имеет
  повторов в 178 022 qualified movements;
- услуга берётся только через договор
  `7371 → Reference59.685 → Reference163`; прямое поле `7378` не служит
  fallback по ранее подтверждённым SV-019—SV-022;
- `RecordKind = 0`, current text qualification услуги и отсутствие нового
  `_Active` filter воспроизводят legacy: 3 inactive, 82 738 negative и 4
  zero movements сохраняются;
- 178 022 source movements сворачиваются в 47 151 candidate date × club ×
  service rows; сумма до и после группировки совпадает — 268 944 858,22.

### Подтверждённое правило клуба

Current Power Query делает `LEFT JOIN` к клубу движения и сохраняет пустой
клуб. В актуальной qualified выборке 92 049 оплат на 1 973 090,65 не имеют
клуба движения, но имеют клуб договора; ещё в 19 строках оба клуба есть, но
различаются (44 990,00). BR-018 требует сохранить пустой `club_id`: клуб
договора не подставляется. Вариант такой атрибуции внесён в mapping как
возможная методическая доработка и не меняет первый релиз.

## DDL review and application completed

Из `sql/marts/ip_revenue_daily_extract.sql` в повторяемом read-only snapshot
получены те же control values: 47 151 итоговая строка, 268 944 858,22,
14 321 строка без клуба и 92 zero groups. VM-2 — PostgreSQL 18; схема `mart`
доступна для создания, `mart.ip_revenue_daily` отсутствует.

Для отдельного DDL approval были подготовлены:

- [DDL](ip_revenue_daily_ddl_review.sql): пять колонок и уникальность
  `(revenue_date, club_id, service_id)` с literal nullable `club_id`;
- [source extract](../../sql/marts/ip_revenue_daily_extract.sql) и
  [atomic target replace](../../sql/marts/ip_revenue_daily_target_replace.sql);
- [loader](../../scripts/load_ip_revenue_daily.py), который откажется от DML
  без `--apply` и сверяет grain, сумму, пустой клуб и zero groups.

После отдельного явного DDL approval 2026-08-14 создана
`mart.ip_revenue_daily`. Post-check: пять колонок, table rows = 0 и
`UNIQUE NULLS NOT DISTINCT (revenue_date, club_id, service_id)` — passed.

Следующее ограничение: первая загрузка данных на VM-2 остаётся отдельным DML
approval. Loader выполнит bounded rebuild и source-to-target reconciliation
в одной контролируемой операции.

## Load and reconciliation result

Пользователь отдельно одобрил DML 2026-08-14. Loader выполнил атомарный
bounded rebuild из одного `REPEATABLE READ, READ ONLY` source snapshot.

`S3-IP-REVENUE-001—004`, 2026-08-14, BR-003 `2025-01-01`—`2027-01-01`:

| Контроль | Фактический результат | Статус |
|---|---:|---|
| Source → target grain | 178 022 source movements → 47 151 target rows | PASS |
| Выручка source / stage / target | 268 944 858,22 / 268 944 858,22 / 268 944 858,22 | PASS |
| Staging | 47 151 rows; duplicate keys 0; contract violations 0 | PASS |
| Nullable movement-club | 14 321 target rows; сумма 1 973 090,65 | PASS — BR-018 preserved |
| Zero groups / BR-003 horizon | 92 / out-of-horizon rows 0 | PASS |

`sql/tests/ip_revenue_daily_reconciliation.sql` фиксирует повторяемые
read-only проверки. Subsequent refresh возможен только через
`scripts/load_ip_revenue_daily.py --apply` при отдельном разрешении на DML.
