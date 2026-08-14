# Data contract: «Тренировки ИП»

Статус: `STAGE_3 DDL APPLIED / initial DML pending`.

| Параметр | Значение | Статус |
|---|---|---|
| Объект | `mart.ip_training_daily` | ADR-0025 |
| Таблица Power BI | `Тренировки ИП` | CONFIRMED |
| Grain | дата × клуб × сотрудник × клиент × услуга | CONFIRMED |
| Ключ | полный состав grain | CONFIRMED — S3-IP-ADMISSION-001; DDL review defines physical PK |
| Обновление | ежедневно, bounded rebuild BR-003 | DESIGNED |
| Power BI | Import; общий календарь | DESIGNED |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `training_date` | `Дата тренировки` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `employee_id` | `ID сотрудника` | text | нет | FK сотрудника | не мера | да |
| `employee_name` | `Сотрудник` | text | нет | срез/detail | не мера | нет |
| `client_key` | `Ключ клиента` | text | нет | distinct | не мера | да |
| `client_code` | `Код клиента` | text | нет | detail | не мера | нет |
| `service_id` | `ID услуги` | text | нет | FK услуги | не мера | да |
| `service_name` | `Услуга` | text | нет | срез | не мера | нет |
| `training_count` | `Количество тренировок` | bigint | нет | показатель; число текущих квалифицированных строк, включая legacy-кратность ПЗ | аддитивна | нет |

Календарь, клубы, сотрудники и услуги имеют связи `1:*` к факту, single
direction. DAX: сумма тренировок, distinct УЧК/тренеров, регулярность и доли.
PostgreSQL: квалификация и агрегация текущих строк двух ветвей. `SV-058`
подтвердил legacy-кратность `VT4352`, которая сохраняется по BR-018;
`S3-IP-ADMISSION-001` подтвердил BR-003 source control: 142 638 PBIT-строк
сворачиваются в 141 326 строк grain, `SUM(training_count)=142 638`,
обязательные компоненты grain не `NULL`, а технические ключи ветвей не
пересекаются. `client_key` и `client_code` — один подтверждённый
`Reference141X1._Code::text`; детализация разрешена BR-017. Нормализация до
уникальных событий — отдельное улучшение. DDL и DML не получают разрешения
автоматически.
