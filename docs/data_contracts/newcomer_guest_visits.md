# Data contract: «Новички и гостевые визиты»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

## Наборы

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| `mart.new_first_visit` | `Первые посещения New` | контракт × первое посещение; `contract_id` candidate |
| `mart.guest_visit_conversion` | `Гостевые визиты` | гость × дата; `(guest_registration_id, client_id, guest_visit_date)` candidate |
| `mart.v_guest_tour` | `Туры` | CRM-взаимодействие; `interaction_id` |

### Первые посещения New

Минимальные поля: `contract_id text`, `first_visit_date date`, `visit_club_id
text`, `client_id text`, `client_code text`, `client_name text`,
`membership_start_date date`, `tenure_type text`, `accuniq_flag boolean`.
Технические ID скрыты, detail видима по BR-017.

### Гостевые визиты

Поля: `guest_registration_id text`, `guest_visit_status_id text`,
`registered_at timestamp`, `guest_visit_date date`, `club_id text`,
`client_id/code/name text`, `tenure_at_registration text`,
`accuniq_same_day_flag boolean`, `accuniq_date date`,
`purchase_contract_id text`, `purchase_activation_date date`,
`purchase_lag_days integer`, `sex text`, `birth_date date`,
`age_at_guest_visit integer`, `age_group text`.

### Туры

Поля: `interaction_id text`, `tour_date date`, `task_id/client_id/club_id
text`, `client_code/name/phone text`, `interaction_state/status text`,
`tour_kind text`, `performer_id text`, `accuniq_booking_flag boolean`,
`purchase_contract_id text`, `purchase_activation_date date`,
`purchase_lag_days integer`, `sex text`, `birth_date date`, `age_at_tour
integer`, `age_group text`.

Общие дата, клуб и исполнитель связываются `1:*`, single direction. Между
тремя фактами связей нет. Внешний план встреч остаётся в Power BI.
PostgreSQL рассчитывает first-rank, as-of стаж, ACCUNIQ и outcome `[0,44]`;
DAX — distinct, конверсии, план-факт и временные сравнения.

Приёмка: deterministic first/tie-break, уникальные candidate keys, status
coverage, границы 0/44/45, несколько покупок, PII permissions, отсутствие
размножения, rerun и SLA.
