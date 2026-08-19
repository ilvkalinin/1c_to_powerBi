# Data contract: «Карта администратора»

Статус: `IMPLEMENTED / INITIAL BR-003 LOAD VALIDATED — AC-REC-001—002 / STAGE_2 GYMMY SOURCE CONTROLS CLOSED — SV-002, SV-100, AC-V05`.

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

SV-002 подтвердил существование `public._inforg5836`; SV-100/AC-V05 уже
закрыли source-side успешность Gymmy, 12 кодов карт, card→club и суммы
до/после дневной агрегации. Начальная Stage 3-приёмка 2026-08-19 подтвердила
суммы `Вход = 107583`, `Выход = 86694`, отсутствие дубликатов ключа,
нарушений контракта и строк вне BR-003; evidence —
`sql/tests/administrator_card_gymmy_daily_reconciliation.sql`. Внешние
Excel-файлы и их Power Query остаются вне анализа; сырые карты, терминалы и
события не входят.
