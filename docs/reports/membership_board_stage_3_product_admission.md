# Stage 3 PRODUCT ADMISSION: «Членство для правления»

Статус: `SHARED SCHEMA IMPLEMENTED 2026-08-19 / INITIAL LOAD NOT REQUESTED`.

## Граница пакета

Создаются только два общих продукта домена поступлений:

- `mart.membership_receipt_movement` — текущая детальная M-группа денежного
  контура поступлений;
- `mart.membership_contract_kpi_unit` — контракт предоплаты или ежемесячная
  KPI-единица рекарринга.

Board-отчёт не получает отдельную таблицу. Его `___Итого по сети` —
calculated performance cache Power BI: PBIT объединяет в нём факты и внешние
планы, а также хранит неаддитивные helpers. Он не переносится в PostgreSQL
как источник истины или третий факт (BR-026).

Так же не создаётся физический аналог «Таблицы активных контрактов»: это
потребительский фильтр старого PBIT, а не самостоятельный бизнес-факт. Две
общие таблицы обязаны обслужить оба отчёта без table/view, подогнанных под
конкретные визуалы.

## Подтверждённый target grain движения

Строка `mart.membership_receipt_movement` — не необработанная строка регистра,
а одна текущая M-группа «Отчёта по поступлениям». Она определяется branch,
датой, договором, полным текстом `АналитикаУчета`, типом оплаты, техническими
IDs атрибутов договора/продукта и исходным `source_object` до его отображаемой
классификации. Исходные движения остаются source-side evidence;
`source_movement_count` позволяет сверять их число.

Это не меняет методику. Текущий M уже группирует именно так перед вычетом
со-доступа; попытка записать этот вычет в каждую сырую строку завысила бы его
в 37 сочетаниях «договор × дата» на 92 630,00.

| Control | Среда / снимок | Результат | Статус |
|---|---|---|---|
| S3-MB-ADMISSION-001 | PBIT Board + PBIT поступлений | `___Итого по сети` — две DAX-агрегированные ветки с фактом, внешними планами и non-additive helpers; business source не создаёт | CONFIRMED / BR-026 |
| S3-MB-ADMISSION-002 | VM-1, repeatable-read, BR-003 `[2025-01-01, 2027-01-01)` | 178 079 `дата × договор`; 14 444 имеют >1 current-M-группы (15 035 лишних групп) | CONFIRMED |
| S3-MB-ADMISSION-003 | тот же control | у 37 таких сочетаний есть со-доступ; повторный вычет изменил бы сумму на 92 630,00 | CONFIRMED |
| S3-MB-ADMISSION-004 | тот же control | по полному current-M ключу 193 116 групп; дублей 0 | CONFIRMED |
| S3-MB-ADMISSION-005 | VM-2 read-only catalog | PostgreSQL 18.0.3; есть `CREATE` в `mart`, поэтому точный `UNIQUE NULLS NOT DISTINCT` доступен для nullable group drivers | CONFIRMED |
| S3-MB-ADMISSION-006 | local DDL/mapping review | ровно две общие `CREATE TABLE`; report-specific table/view/cache отсутствуют; все confirmed contract fields присутствуют в review DDL | CONFIRMED / BR-026 |
| S3-MB-DDL-001 | VM-2, approved DDL | созданы `mart.membership_receipt_movement` (43 колонки, 15 constraints) и `mart.membership_contract_kpi_unit` (30 колонок, 13 constraints); в обеих таблицах 0 строк | VALIDATED |

## Следствие для реализации

DDL review должен использовать полный natural key M-группы с
`UNIQUE NULLS NOT DISTINCT`, а не суррогатный hash и не raw
`(source_kind, recorder_id, line_no)`. Для строк membership-услуг physical
recorder/line остаются частью key; для агрегированных веток авансов они
пусты. Это сохраняет exact M результат и не передаёт на VM-2 лишние raw rows.

Пользователь отдельно подтвердил DDL 2026-08-19. Объекты созданы одной
транзакцией, без DML и без загрузки данных. Initial load и настройка
обновления не входят в этот пакет и требуют нового явного решения.

Исполненный DDL: [membership receipts DDL](/Users/ilia/Desktop/Cursor/База%20sql%20НФГ/sql/marts/membership_receipts_ddl.sql).
