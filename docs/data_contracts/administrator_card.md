# Data contract: «Карта администратора»

Статус: `DESIGNED / IMPLEMENTATION DEFERRED / PHYSICAL SOURCE AVAILABILITY VALIDATED — SV-002 / STAGE 3 CONTROLS PENDING`.

## PostgreSQL-объект Gymmy

| Параметр | Значение |
|---|---|
| Объект | `mart.administrator_card_gymmy_daily` |
| Grain / ключ | `(event_date, club_id, direction)` |
| Обновление | ежедневно, bounded rebuild BR-003 |
| Power BI | Import |

| PostgreSQL | Power BI | Тип | NULL | Роль | Аддитивность | Скрыть |
|---|---|---|---|---|---|---|
| `event_date` | `Дата` | date | нет | FK даты | не мера | нет |
| `club_id` | `ID клуба` | text | нет | FK клуба | не мера | да |
| `direction` | `Направление` | text | нет | вход/выход | не мера | нет |
| `usage_count` | `Количество использований` | bigint | нет | показатель | аддитивна | нет |

## Семантическая таблица Power BI

Power Query добавляет к Gymmy малый внешний журнал и формирует таблицу
`Использования карты администратора` с полями `Дата`, `ID клуба`, `Клуб`,
`Направление`, `Источник`, `Причина`, `Количество использований`. Связи даты и
клуба — `1:*`, single direction. DAX считает входы/выходы и разницы источников.

SV-002 подтвердил существование `public._inforg5836`. Приёмка Stage 3:
успешность Gymmy, 12 кодов клуба, суммы до/после агрегации и повторный
refresh. Внешние Excel-файлы и их Power Query остаются вне анализа; сырые
карты, терминалы и события не входят.
