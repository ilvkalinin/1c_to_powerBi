# Data contract: «План ДПФУ»

Статус: `IMPLEMENTED / initial BR-003 load VALIDATED`.

| Параметр | Значение |
|---|---|
| Объект | `mart.dpfu_plan_assignment` |
| Таблица Power BI | `План ДПФУ` |
| Grain | дата × клуб × подразделение × тренер × плановый клиент × technical plan-line discriminator |
| Логический ключ | `(plan_date, club_id, activity_id, employee_id, planned_client_key, plan_line_discriminator)` |
| Refresh | ежедневный full bounded rebuild BR-003 |
| Power BI | Import; calendar, club, activity and employee are `1:*`, single direction |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `plan_date` | `Дата` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `activity_id` | `ID вида деятельности` | text | нет | FK направления | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK тренера | не мера | да |
| `planned_client_key` | `Ключ планового клиента` | text | нет | detail key | не мера | да |
| `planned_client_code` | `Код планового клиента` | text | нет | detail display | не мера | нет |
| `plan_line_discriminator` | технический различитель | text | нет | logical-key component | не мера | да |
| `planned_revenue` | `Плановая выручка` | decimal fixed 2 | нет | показатель | аддитивна | нет |

Факт не связывается с другими фактами. Отрицательные суммы сохраняются.
Power BI считает plan-fact и report-level day×club aggregates; PostgreSQL
проецирует подтверждённые source fields и сохраняет детальный ключ.
