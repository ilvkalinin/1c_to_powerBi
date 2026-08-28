# Source-to-target mapping: применения промокодов

Статус: `BUSINESS MAPPING COMPLETE / ARCHITECTURE DESIGNED — ADR-0018 / CARDINALITY RECHECK EXECUTED 2026-08-28; DECISION_REQUIRED; Stage 3 deferred`.
Спроектирован `mart.promo_application`; SQL не создаётся.

## Гранулярность

Одна логическая строка — одно квалифицированное применение промокода или
выдача подарка клиенту на дату применения из `AccumRg7606` либо `AccumRg7615`.

Кандидат технического ключа: `(source_kind, recorder_id, line_no)`. В текущем
SQL этих полей нет, поэтому уникальность и даже точный исходный grain —
`VALIDATION_PENDING`, а не подтверждённый ключ.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Источник / преобразование | PostgreSQL тип | NULL | Статус | Проверка |
|---|---|---|---|---|---|---|
| `application_date` | дата применения | `AccumRg7606.Period::date` / `AccumRg7615.Period::date` | `date` | нет | CONFIRMED current SQL | timezone, sentinel |
| `source_kind` | ветвь применения | константы `promo_gift` / `discount` по источнику | `text` | нет | CONFIRMED BY DESIGN | полнота union |
| `recorder_id`, `line_no` | техническая идентификация движения | physical `RecorderTRef`, `RecorderRRef`, `LineNo` | `bytea`, `bytea`, numeric | нет | VALIDATED — SV-091 | уникальность |
| `client_key` | обезличенный клиент для distinct | ссылка регистра → `Reference141X1.ID`; не переносить код/ФИО | UNKNOWN | нет | CONFIRMED need / source pending | orphan, стабильность |
| `club_id`, `club_name` | клуб применения | `Fld7612`/`Fld7616` → `Reference132` | UNKNOWN, `text` | да | CONFIRMED current SQL | смысл поля и orphan |
| `membership_id`, `membership_code` | связанный исходный абонемент | `Fld7610`/`Fld7621` → `Reference59` | UNKNOWN, `text` | да | CONFIRMED current SQL | valid interval, orphan |
| `promo_id`, `promo_name` | применённый промокод | `Fld7608` через `Reference135.Fld1457` / `Fld7623` → `Reference163` | UNKNOWN, `text` | нет | CONFIRMED current SQL | кардинальность |
| `serial_id`, `serial_name` | серия промокода | ключ скидки / `Reference218`; null → «без серии» только для меры | UNKNOWN, `text` | да | CONFIRMED current SQL | orphan, uniqueness |
| `discount_id`, `discount_name` | скидка/наценка и связь с акцией | `Reference220.ID/Description` | UNKNOWN, `text` | да | CONFIRMED current SQL | связь `Document298` |
| `discount_method_id` | способ предоставления | `Reference220.Fld2439` | UNKNOWN | да | CONFIRMED current SQL | расшифровка перечислений |
| `discount_amount` | сумма скидки | `AccumRg7615.Fld7626`, текущий `MAX` в агрегате | `numeric` | да | CONFIRMED current calculation / source pending | знак, grain, sum/max |
| `price_before_discount` | цена до скидки | `Document332.VT4465` / `Document346.VT4924` | `numeric` | да | CONFIRMED current SQL / join pending | связать по строке |
| `service_id`, `service_name` | номенклатура применения | `Fld7611`/`Fld7619` → `Reference163` | UNKNOWN, `text` | да | CONFIRMED current SQL | orphan |
| `business_direction_id` | направление номенклатуры | `Reference163.Fld1733` → `Reference70` | UNKNOWN | да | CONFIRMED current SQL | GUID-to-name mapping |
| `gift_id`, `gift_name`, `gift_recipient_client_key` | выданный подарок и друг | `AccumRg7606`, `AccumRg7553`, `Reference187`, `Reference59` | UNKNOWN, `text`, UNKNOWN | да | CONFIRMED current SQL | grain/meaning/cardinality |
| `bought_membership_45d_flag` | клиент купил иной абонемент строго в 1–44 дни после применения | `Reference59.Fld670`, current `check_subscription` | `boolean` | нет | CONFIRMED current SQL | interval, exclusions |
| `bought_dpfu_45d_flag` | клиент купил ДПФУ строго в 1–44 дни после применения | `AccumRg7575`/`AccumRg7646`, current `check_dpfu` | `boolean` | нет | CONFIRMED current SQL | qualified services |
| `friend_bought_membership_45d_flag` | друг купил абонемент строго в 1–44 дни после активации подаренного ему абонемента | `friend_activation_date`, current `check_friend` | `boolean` | да | CONFIRMED — user decision 2026-07-31 | interval and exclusions |

Категория промокода, группа скидки, количество дней подарка, применения,
выпуск и конверсии остаются DAX-правилами отчёта: они зависят от визуального
контекста и не являются атрибутами одной исходной строки.

## Отбор и временная политика

- `AccumRg7606`: `RecordKind = 1`, `Fld7613 = 1`, заполнены промокод и
  подарок; действительный связанный абонемент в текущем SQL.
- `AccumRg7615`: заполнен промокод; строка без абонемента сохраняется, со
  ссылкой на абонемент — только при его действительном интервале.
- Текущий нижний предел — 2025-01-01. Целевая история использует BR-003;
  физическая parameterized реализация не входит в текущий этап.
- `Active`, Posted, Marked, возвраты и сторно — `VALIDATION_PENDING`.

## Reuse review

| Проверка | Результат | Статус / доказательство |
|---|---|---|
| Проверенные источники | `AccumRg7606`, `AccumRg7615`, `AccumRg7553`, `Reference135`, `Reference218`, `Reference220`, `Reference59`, `Reference132`, `Reference141X1`, `Reference163`, `Reference70`, `Reference187`, `Document298`, `Document332`, `Document346` | CONFIRMED current SQL; физические поля pending |
| Проверенные продукты | `mart.ancillary_revenue_movement`, детские пакеты, contract usage, DPFU | CONFIRMED catalog |
| Проверенные правила | BR-001, BR-002, BR-003, BR-007, BR-013, BR-014 | CONFIRMED catalog |
| Сравнение гранулярности и ключей | У промокодов отдельные регистры, скидка/подарок и outcome на применение; ни один существующий продукт не хранит эту семантику и ключ | CONFIRMED current mapping / technical key pending |
| Сравнение бизнес-семантики | ДПФУ является только последующим исходом; детские пакеты и ancillary revenue описывают продажи, не применение промокода | CONFIRMED |
| Решение | `NEW` — `mart.promo_application`; переиспользовать только календарь, клубы и стабильный `client_key` | DESIGNED — ADR-0018 |
| Затронутые потребители | только «Отчет по промокодам»; нового общего потребителя не доказано | CONFIRMED |

## Блокер и проверки

| Статус | Элемент | Риск / причина | Следующее действие |
|---|---|---|---|
| VALIDATED | источник ключа и grain | candidate `(RecorderTRef, RecorderRRef, LineNo)` unique/non-null in both registers | SV-091; business grain retains current M aggregation |
| VALIDATED | связь с маркетинговой акцией `Document298.VT3596` | PC-V04 2026-08-28: 7,904 action rows, parent/null-discount = 0/0 | `promo_application_stage2_cardinality_execution_2026-08-28.md`; no new filter follows |
| VALIDATION_FAILED | joins и суммы скидки | PC-V02 2026-08-28 repeats 7,535 technical discount rows → 7,568 current-M joined rows (excess 33); PC-V04 repeats gift-join excess 406 | preserve current `MAX`/`SUM`/`Table.Distinct`; methodology decision required before implementation |
| VALIDATED observation | состояния и сторно | SV-091 measured active/posted/marked state; no new filter follows | preserve current source filters |
| PARTIALLY VALIDATED | текстовые категории/дни | 100+ day gifts absent; source predicates total, but current DAX fallback and join multiplicity remain | preserve current DAX; methodology decision required for change |

## Stage 3 technical decision — 2026-08-28

User-approved BR-046 resolves the earlier methodology decision: target grain
is the final post-M report row, not an arbitrary technical register line.
`sql/marts/promo_application_source_extract.sql` reproduces both exact PBIT
branches, including their aggregation and multiplicity, then assigns a
full-snapshot `report_row_id`. This does not change source filters, state
policy, joins, DAX categories, or Power BI relationships.

The accepted source plan is a semantic candidate only after successful
one-day-to-six-month ladder: it materializes the shared 45-day outcome inputs
once and pushes the final application-date horizon into branch base inputs.
Full BR-003 `[2025-01-01, 2026-08-29)` actual plan: 132,801 rows,
39,236.433 ms execution, 16,678,651 shared-hit blocks, 0 reads, and
68,767/62,606 temp read/write blocks. It is a full-rebuild baseline, not an
incremental SLA. Physical delivery remains separately unapproved.
