# Stage 3 PRODUCT ADMISSION: `mart.client_base_daily`

Статус: `SCHEMA IMPLEMENTED / INITIAL LOAD, REFRESH AND POWER BI RECONCILIATION NOT AUTHORIZED`.

## Один продукт и его потребители

`mart.client_base_daily` — один общий дневной знаменатель для «Работы с
посещаемостью», KPI Фитнеса и «Титульного листа». Он не заменяет широкий
`client_base_snapshot` и retention: в них нужны стаж, активность и другая
временная логика. Эти продукты не создаются в данном пакете.

Строка факта: `scope_level × report_date × club_id (только club) × age_years
× age_group × gender`. `client_count` аддитивен только внутри одного дня и
одного уровня охвата. Сетевой и клубный scope нельзя складывать.

## Проверенные правила

| Control | Результат | Статус |
|---|---|---|
| SV-111 / WA-V06C | 730/730 дней BR-003 непусты для обоих scope; interval-подсчёт совпадает с прямым current-M на 4 датах | CONFIRMED source formation |
| S3-CBD-ADMISSION-001 | 4 независимые даты, 9 063 итоговые строки; неверных scope/club сочетаний, пустых обязательных разрезов и расхождений totals — 0 | CONFIRMED admission control |
| BR-005 | начало в D исключается, окончание D−1 включается | CONFIRMED |
| возраст и пол | sentinel-дата рождения → `Не указано`; два текущих пола → `Женский`/`Мужской`, иное/пустое → `Не указано` | CONFIRMED current rule |

## Созданная схема

[DDL](client_base_daily_ddl_review.sql) создал одну таблицу из семи полей.
`UNIQUE NULLS NOT DISTINCT` сохраняет единственность network-строк с пустым
клубом и строк неизвестного возраста. В схему не включаются client ID, ФИО,
контракты, посещения, стаж или категории активности.

[Проверка схемы](../../sql/tests/client_base_daily_schema_contract.sql) прошла
после DDL: 7 колонок, 5 ограничений (уникальный ключ и 4 проверки), 5
обязательных колонок и 0 строк. Перед отдельным initial-load пакетом
необходимы source extract, source/target controls, rerun и измерение SLA;
данный пакет создал только пустую схему.

Точный read-only admission control сохранён как
[client_base_daily_admission_2026-08-19.sql](../source_metadata/validation_sql/client_base_daily_admission_2026-08-19.sql).
