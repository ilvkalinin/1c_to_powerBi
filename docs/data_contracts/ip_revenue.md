# Data contract: «Выручка ИП»

Статус: `STAGE_3 DML APPROVAL PENDING / empty target table CONFIRMED`.

| Параметр | Значение |
|---|---|
| Объект | `mart.ip_revenue_daily` |
| Таблица Power BI | `Выручка ИП` |
| Grain | дата оплаты × клуб движения (nullable) × услуга договора ИП |
| Логический ключ | `(revenue_date, club_id, service_id)`, где `NULL club_id` сравнивается как одно значение |
| Refresh | ежедневный полный bounded rebuild BR-003 |
| Power BI | Import; календарь и клубы — `1:*`, single direction |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `revenue_date` | `Дата оплаты` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | да | optional FK клуба; `NULL` отображается пустым как current M | не мера | да |
| `service_id` | `ID услуги` | text | нет | FK услуги | не мера | да |
| `service_name` | `Услуга` | text | нет | срез | не мера | нет |
| `revenue_amount` | `Выручка ИП` | decimal fixed 2 | нет | показатель | аддитивна | нет |

`revenue_amount` сохраняет знак и zero groups. Не добавлять relationship,
который заменяет nullable movement-club клубом договора. DAX считает
план-факт и доли; qualification, service path и дневная агрегация остаются в
PostgreSQL.
