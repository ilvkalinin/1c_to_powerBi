# Data contract: «Посещения Физкульт»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

## Факты

| Объект | Таблица Power BI | Grain |
|---|---|---|
| `mart.visit_client_day` | `Посещения клиентов` | `(visit_date, club_id, client_key)` |
| `mart.club_day_metrics` | `Показатели клуба по дням` | `(event_date, club_id)` |
| `mart.ip_training_daily` | `Тренировки ИП` | контракт IP training |

`visit_client_day` содержит `visit_date date`, `club_id text`, `client_key
text` и boolean `has_visit`, `has_coupon`, `has_paid_service`. В модели
пользователь видит дату/клуб и меры; client key скрыт. `club_day_metrics`
содержит `event_date date`, `club_id text`, `group_program_visit_count bigint`.

Общие календарь и клуб фильтруют факты `1:*`, single direction. Между фактами
связей нет. PostgreSQL квалифицирует и схлопывает client-day; DAX считает
distinct посещения/купоны/ДПФУ, сумму ГП и ИП, «с тренером», «без тренера» и
доли. Категории намеренно могут пересекаться.

Приёмка: уникальный client-day, стабильный защищённый client key, actual club,
source states, отсутствие размножения, reconciliation категорий и refresh.

