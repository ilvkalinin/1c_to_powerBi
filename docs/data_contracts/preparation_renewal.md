# Data contract: «Подготовка к продлению»

Статус: `IMPLEMENTED AND VALIDATED — 2026-08-24`.

PR-V10—V16 подтвердили technical contract/client pair, mandatory dimensions,
legacy freeze equivalence и independent source reconciliation path. Power BI
интеграция остаётся deferred by BR-036.

## Общие параметры

| Параметр | Значение | Статус |
|---|---|---|
| Объект PostgreSQL | `mart.preparation_renewal_checkpoint` | ADR-0013 |
| Таблица Power BI | `Подготовка к продлению` | CONFIRMED naming rule |
| Гранулярность | контракт × контрольная точка `7/14/21/28/30` | CONFIRMED mapping |
| Ключ | `(contract_id, checkpoint_day)` | PARTIALLY VALIDATED — PR-V05: 100 contracts × 5 points, duplicate key = 0 |
| Дата | `checkpoint_date` → общий `Календарь` | CONFIRMED |
| Обновление | ежедневный атомарный rebuild BR-003 | DESIGNED; watermark отсутствует |
| SLA | до 08:30 МСК | BR-014 |
| Power BI | Import | DESIGNED / deferred by BR-036 |

## Колонки

| PostgreSQL | Power BI | Тип PostgreSQL | Power BI | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|---|
| `contract_id` | `ID контракта` | text | Text | нет | ключ | не мера | да |
| `contract_code` | `Код контракта` | text | Text | нет | detail | не мера | нет |
| `client_id` | `ID клиента` | text | Text | нет | технический detail | не мера | да |
| `membership_start_date` | `Дата начала` | date | Date | нет | атрибут | не мера | нет |
| `membership_end_date` | `Дата окончания` | date | Date | нет | атрибут | не мера | нет |
| `access_club_id` | `ID клуба доступа` | text | Text | нет | FK клуба | не мера | да |
| `access_club_name` | `Клуб доступа` | text | Text | нет | срез | не мера | нет |
| `checkpoint_day` | `Контрольный день` | smallint | Whole number | нет | часть ключа | не суммировать | нет |
| `checkpoint_date` | `Дата контрольной точки` | date | Date | нет | FK даты | не мера | нет |
| `visit_count_to_checkpoint` | `Посещения к точке` | integer | Whole number | нет | показатель строки | не суммировать между точками | нет |
| `visit_bucket` | `Категория посещений` | text | Text | нет | срез | не мера | нет |
| `target_visit_count` | `Цель посещений` | smallint | Whole number | нет | порог | не суммировать | да |
| `below_target_flag` | `Ниже цели` | boolean | True/False | нет | признак | не мера | нет |
| `frozen_at_checkpoint_flag` | `Заморожен на дату` | boolean | True/False | нет | признак | не мера | нет |
| `age_group` | `Возрастная группа` | text | Text | да | срез | не мера | нет |
| `membership_tenure` | `Стаж контракта` | text | Text | нет | срез | не мера | нет |

## Связи и вычисления

`Календарь[Дата] 1:* [Дата контрольной точки]` и
`Клубы[ID клуба] 1:* [ID клуба доступа]`, только однонаправленно. Excel-план
остаётся отдельным фактом и фильтруется теми же измерениями.

PostgreSQL рассчитывает точки, посещения, заморозку и признаки. DAX считает
число контрактов, доли ниже цели, план-факт и временные сравнения. Power Query
только импортирует и назначает русские имена.

## Условия принятия

Уникальный ключ; не более пяти допустимых точек на контракт; нет размножения
после visits/freeze joins; подтверждены границы окна, states, rerun,
исправления/удаления и control values. PR-R01—PR-R06 прошли на initial load и
atomic rerun; full rebuild 165,58 s остаётся baseline, не incremental SLA.
Power BI connection/relationships остаются `VALIDATION_PENDING` до отдельного
общего пакета по BR-036.
