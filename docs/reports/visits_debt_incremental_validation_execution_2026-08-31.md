# Stage 2 execution: incremental refresh для движений долга

- Пакет: `visits_debt_incremental_validation_2026-08-31`
- Среда: VM-1 `gymdb`, роль `gymdb_readonly`
- Snapshot: `2026-08-31 10:52:27.931778+03`
- Transaction outcome: `ROLLBACK` после read-only controls
- Target/loader/Power BI: не изменялись

## Результаты

| Check | Статус | Expected | Actual | Вывод |
|---|---|---|---|---|
| VD-INC-001 | `PASS` | полная metadata трёх relations | `_accumrg7509`: 18 колонок; `_document279`: 32; `_document329`: 33 | metadata получена |
| VD-INC-002 | `BLOCKED` | физический change watermark/feed | для `7509` найдена только `_accumrg7509`; у регистра нет `_version`/change timestamp | change capture отсутствует |
| VD-INC-003 | `BLOCKED` | обнаружение исчезнувшего target key | 4 551 016 rows/keys, `_active=false` = 0; tombstone/change log не найден | удаления не воспроизводимы инкрементом |
| VD-INC-004 | `BLOCKED` | исторические пары change time × event time | change time отсутствует | максимальный late-change lag не измеряется |
| VD-INC-005 | `PASS` | `_period` не повышается до watermark без evidence | min/max `_period`: 2017-10-06 09:00 / 2026-10-30 09:25; это event horizon | event date не является change watermark |

SQL: [visits_debt_incremental_validation_2026-08-31.sql](../source_metadata/validation_sql/visits_debt_incremental_validation_2026-08-31.sql).

## Решение

Отдельную активную incremental-настройку создать нельзя: источник не даёт
воспроизводимого множества изменённых и удалённых ключей, а достаточность
двухмесячного sliding window не доказана. Существующий full atomic BR-003
rebuild и его loader остаются без изменений. Допустимый новый trigger —
появление source change feed/audit history либо отдельное решение пользователя
принять bounded sliding-window риск как целевую методику, не выдавая её за
подтверждённый watermark.
