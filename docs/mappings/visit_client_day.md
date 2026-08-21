# Source-to-target mapping: `mart.visit_client_day`

Статус: `IMPLEMENTED / initial BR-003 load validated — S3-VISIT-CLIENT-DAY-001`.

## Grain and scope

Одна строка — `visit_date × фактический club_id × обезличенный client_key`.
Это только client-level событие посещения из `AccumRg7575 → Document325` с
операцией посещения. Пушкинские категории — атрибуты того же события; флаги
независимы и могут одновременно быть `true`.

| Target column | Source / transform | Type | NULL | Status / evidence |
|---|---|---:|---:|---|
| `visit_date` | `AccumRg7575.Period::date` | date | no | CONFIRMED: current PBIT «Посещения всего» |
| `club_id` | фактический `Document325.Fld4167`, `encode(...,'hex')` | text | no | CONFIRMED: current PBIT «Посещения всего» |
| `client_key` | `md5(encode(Document325.Fld4171,'hex'))` on VM-1 | text | no | CONFIRMED technical representation; raw ID never reaches VM-2 |
| `has_visit` | `Document325.Fld4164 = 9a5a…c43`, client type `9e8e…fa1` | boolean | no | CONFIRMED: both current PBIT templates |
| `has_member_visit` | Pushkinsky actual/home-club membership branch; service `89de…373` | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |
| `has_guest_visit` | Pushkinsky actual club; guest-service branch excluding `гость кафе` | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |
| `has_vip_visit` | Pushkinsky actual club, home `Пушкинский VIP`, exclude employee contract | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |
| `has_drc_visit` | Pushkinsky actual club, home ДРЦ, exclude employee / продлёнка / Умняшки | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |
| `has_after_school_visit` | Pushkinsky actual club, home ДРЦ, service contains either spelling of продлёнка | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |
| `has_umnyashki_visit` | Pushkinsky actual club, home ДРЦ, service contains `умняши` | boolean | no | CONFIRMED: current PBIT «Посещения Пушкинский» |

## Facts intentionally outside this mart

Проверены 2026-08-21 шаблоны
`Pbit_old/Посещения Физкульт.pbit` (SHA-256 `93dc…b7cf`) и
`Pbit_old/Посещения Пушкинский.pbit` (SHA-256 `1281…ea15`). В каждой модели
следующие таблицы импортируются отдельно и связаны с календарём/клубами, но не
с фактом посещения по клиенту:

| Current PBIT table / measure | Why not a `visit_client_day` flag | Current handling |
|---|---|---|
| `Посещения по купону` | отдельный запрос и `DISTINCTCOUNT` клиента; DAX вычитает его как самостоятельную меру | не создаётся и не объединяется в этом пакете |
| `Посещения проверка ДПФУ` | отдельный запрос по `AccumRg7575` и датам `Document279/329`, без join к `Document325`; отдельный `DISTINCTCOUNT` | не создаётся и не объединяется в этом пакете |
| `Посещения ГП` | отдельный факт `date × club`, без client key | существует отдельный `mart.group_lesson` |
| `Посещения ИП` / `ОбщаяРС` | самостоятельная таблица и мера в «Физкульт» | существует отдельный `mart.ip_training_daily` |

Таким образом, `UNION ALL` между этими наборами и раздача `has_coupon` /
`has_paid_service` противоречат текущему PBIT/DAX. Отдельные компактные факты
для Power BI могут быть спроектированы только отдельным пакетом после полного
project-stage review; настоящая витрина их не дублирует.

`DQ-VC-002` показал именно ожидаемую неэквивалентность множеств: coupon
`7 863 / 17 outside`, ДПФУ `149 338 / 28 492 outside` на первом блоке
2025-01-01…2025-07-01. Это не defect базовой витрины и не повод сравнивать
факты между собой.

All source relations remain read-only. The BR-003 horizon is a bounded full
rebuild; daily incremental design is deferred until all marts are ready.

## Implementation evidence

`S3-VISIT-CLIENT-DAY-001` completed on 2026-08-21. The physical table has the
mapped primary key `(visit_date, club_id, client_key)` and all ten mapped
columns. Two atomic BR-003 rebuilds used the unchanged projection and
quarterly source-to-target binary COPY blocks. Every block had equal source and
target COPY row counts. The final target snapshot has 7,172,391 rows, no null
contract fields, no rows outside `[2025-01-01, 2027-01-01)`, and dates through
2026-08-21. Evidence: [initial-load authorization](../reports/visit_client_day_initial_load_authorization_2026-08-20.md).
