# Source-to-target mapping: retention клиентской базы

Статус: `DRAFT / STAGE_2 FOUNDATION PARTIALLY VALIDATED — SV-069`.
SV-069 подтверждает только общую для cohort membership-границу BR-005 и
раздельные club/network dedupe на 2026-07-01; retention-пересечение и его
атрибуты не выполнялись. SQL и реализация остаются отложенными до проверки
source statuses, физических типов и контрольных значений.

Предлагаемый объект: `mart.client_base_retention`.

## Бизнес-правило

Для каждой текущей отчётной даты строятся два baseline:

- `year_start` — 1 января текущего года;
- `previous_year` — подтверждённая ближайшая отчётная дата прошлого года.

Baseline cohort — уникальные клиенты на сравнительную дату:

- для `club` — distinct `(baseline_club_id, client_id)`;
- для `network` — distinct `client_id`.

Клиент считается удержанным, если на текущую отчётную дату он присутствует хотя бы в одном клубе сети. При переходе A → B клиент остаётся удержанным для baseline-клуба A. Клуб берётся с baseline-даты; возраст и стаж — с текущей отчётной даты.

Client IDs используются только внутри source-side пересечения и не сохраняются на VM-2.

## Гранулярность

> scope level × report date × comparison type/date × baseline club (для club scope) × current age × current age group × current gender × current tenure.

## Целевые колонки

| Целевая колонка | Бизнес-описание | Источник/преобразование | PostgreSQL тип | NULL | Статус | Тест |
|---|---|---|---|---|---|---|
| `scope_level` | `club` или `network` | явная branch | UNKNOWN | нет | CONFIRMED | allowed values |
| `report_date` | Текущая отчётная дата | календарь отчёта | `date` | нет | CONFIRMED | report calendar |
| `comparison_type` | `year_start` или `previous_year` | явная константа | UNKNOWN | нет | CONFIRMED | allowed values |
| `comparison_date` | Baseline-дата | 1 января либо nearest prior-year report date | `date` | нет | CONFIRMED | date mapping tests |
| `baseline_club_id` | Клуб baseline cohort | клуб клиента на comparison date; NULL для network | UNKNOWN | по scope | CONFIRMED | required iff club |
| `baseline_club_name` | Имя baseline-клуба | `Reference132.Description` | UNKNOWN | по scope | CONFIRMED source | ID/name mapping |
| `current_age_years` | Возраст на текущую report date | birth date + report date | `smallint` | UNKNOWN | CONFIRMED | birthday/leap tests |
| `current_age_group` | Текущая возрастная группа | current age | UNKNOWN | UNKNOWN | CONFIRMED boundaries | 13/14/17/18 |
| `current_gender` | Пол из текущей карточки клиента | `Reference141.Fld1527` | UNKNOWN | да | ASSUMPTION attribution | enum coverage |
| `current_membership_tenure` | Стаж на текущую report date | latest `InfoRg5654` before report date | UNKNOWN | UNKNOWN | CONFIRMED | as-of controls |
| `baseline_client_count` | Размер baseline cohort | distinct client count после baseline dedupe | `integer`/`bigint` | нет | CONFIRMED | sum vs source distinct |
| `retained_client_count` | Клиенты baseline cohort, присутствующие в сети на текущую дату | baseline client semi-join current network client set | `integer`/`bigint` | нет | CONFIRMED | `0 <= retained <= baseline` |

Процент retention не хранить: Power BI рассчитывает `retained_client_count / baseline_client_count`; при нулевом denominator мера возвращает `BLANK`.

## Открытые параметры

- Нужны ли в retention-разрезе текущая категория активности и другие атрибуты.
- Использовать ли текущий пол или пол baseline-даты; metadata истории пола пока отсутствует.
- Правила `NULL/Unknown` для возраста, пола и стажа.
- Формат отображения процента — один знак после запятой; нулевой denominator отображается как пустое значение.
