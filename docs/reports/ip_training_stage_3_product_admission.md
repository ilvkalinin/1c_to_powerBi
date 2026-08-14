# Stage 3 PRODUCT ADMISSION: `mart.ip_training_daily`

Статус: `DECISION REQUIRED — client_key method`.

Пользователь явно подтвердил самостоятельный пакет
`STAGE_3_PRODUCT_ADMISSION — mart.ip_training_daily` 2026-08-14. Граница
пакета — только общий факт тренировок ИП с grain
`дата тренировки × клуб × сотрудник × клиент × услуга` и метрикой
`training_count`.

В пакет не входят `mart.ip_revenue_daily`, `mart.dpfu_plan_assignment`,
views потребителей, внешние источники, DDL или DML. До отдельного разрешения
на опасную операцию выполняются только mapping, read-only source controls,
проект DDL и проект reconciliation.

## Подтверждённая основа

- reuse: один общий физический факт для «Отчёта по ИП», KPI Фитнеса,
  «Выручки ДПФУ» и загрузки сотрудников; отдельные копии запрещены ADR-0025;
- source: `InfoRg7006`, две текущие ветви `Document329` (ПЗ) и
  `Document279` (ГП), `Reference141X1`, `Reference132`, `Reference225`,
  `Reference163`, `Enum448`; `Document329.VT4352` сохраняет observed
  legacy-множество строк ПЗ по BR-018;
- Stage 2: SV-058/SV-068 подтвердили состояние cohort, отсутствие пересечения
  ветвей и current target grain за legacy-период. Их значения не являются
  контролем нового горизонта BR-003.

## Admission controls

1. подтвердить на source физические типы и заполненность каждого компонента
   grain, а также stable representation `client_key`;
2. пересчитать две ветви в пределах BR-003, сохранив current multiplicity
   `Document329.VT4352`, и проверить технический ключ/пересечение ветвей;
3. сверить source-row count с `SUM(training_count)` после целевой агрегации;
4. проверить цель VM-2, затем подготовить DDL и reconciliation для отдельного
   review. Никаких DDL/DML в этом admission не выполняется.

## Выполненное evidence

`S3-IP-ADMISSION-001`, source `REPEATABLE READ READ ONLY`, 2026-08-14,
dynamic BR-003 horizon на дату запуска `2025-01-01`—`2027-01-01`:

| Контроль | Фактический результат | Статус |
|---|---:|---|
| Физические типы | IDs — `bytea`; даты документов — `timestamp`; `_Code` доступен | PASS |
| ПЗ | 39 532 rows; 39 397 events; legacy `VT4352` excess 135 | PASS — BR-018 preserved |
| ГП | 103 106 rows; 103 106 events; excess 0 | PASS |
| Технический ключ между ветвями | overlap 0 | PASS |
| Состояния строк | inactive / unposted / marked = 0 в обеих ветвях | PASS |
| Итоговый grain | 142 638 source rows → 141 326 rows; `SUM(training_count)` = 142 638; NULL components 0 | PASS |
| `_Code` клиента | 7 797 scoped clients; NULL/blank 0; duplicates 0 | PASS — техническая пригодность |

Источник проверки: `docs/source_metadata/validation_sql/ip_training_2026-08-11.sql`.
Контрольные значения получены из независимого source snapshot; будущая
reconciliation сверит загрузку с этим источником, а не с самой загрузочной SQL.

VM-2: схема `mart` существует, `mart.ip_training_daily` отсутствует, право
создания в схеме есть. DDL/DML не выполнялись.

## Единственное решение для продолжения

Для `mart.ip_training_daily` требуется зафиксировать `client_key`:
техническая проверка подтвердила, что `Reference141X1._Code::text` заполнен и
уникален в полной ИП-когорте, но BR-007 пока утверждает этот метод только для
DPFU. Без решения нельзя подготовить детерминированный DDL и загрузочный SQL.
