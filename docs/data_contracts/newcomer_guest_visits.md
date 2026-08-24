# Data contract: «Новички и гостевые визиты»

Статус: `CURRENT PBI CONTRACT RETAINED / MINIMAL PHYSICAL FACTS IMPLEMENTED — BR-035`.

NV-V01—V09 выполнены с зафиксированными ожиданиями. Physical guest key и
CRM-tour grain подтверждены; candidate guest key материально неуникален, но
current `Distinct(client code, visit date)` сохраняется по BR-018. ACCUNIQ,
latest-state path и outcomes 0/44/45 подтверждены source-side. По BR-031 эти
неоднозначные outcomes остаются в Power BI первого релиза; в PostgreSQL
переносится только CRM-tour base. Current PBI fields below remain its own
contract. Separately implemented minimal physical facts are documented in
[`newcomer_guest_visits_minimal_date_facts.md`](newcomer_guest_visits_minimal_date_facts.md);
they do not include club/demographic/document detail and do not switch PBI.

## Наборы

| Объект | Таблица Power BI | Grain / ключ |
|---|---|---|
| Power BI `Первые посещения New` | `Первые посещения New` | contract rank by `Period`; equal timestamps remain selected by current Power BI |
| Power BI `Гостевые визиты` | `Гостевые визиты` | final `Distinct(client_code, guest_visit_date)`; source detail selection remains Power BI |
| `mart.v_guest_tour` base | `Туры` | PBIT phone row; hidden technical key pending physical validation |
| Power BI outcomes | `Туры` | current ACCUNIQ/contract branches, including ties and multiplicity — BR-031 |

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

Поля: `interaction_id text`, `interaction_date date`, `report_date date`, `task_id/client_id/club_id
text`, `client_code/name/phone text`, `interaction_state/status text`,
`tour_kind text`, `performer_id text`, `sex text`, `birth_date date`, `age_at_tour
integer`, `age_group text`.

Общие дата, клуб и исполнитель связываются `1:*`, single direction. Между
тремя фактами связей нет. Внешний план встреч остаётся в Power BI.
PostgreSQL рассчитывает CRM-tour base; current Power BI сохраняет ACCUNIQ и
outcome `[0,44]` без нового tie-break по BR-031. DAX — distinct, конверсии,
план-факт и временные сравнения.

Приёмка будущей PostgreSQL migration этих двух facts требует отдельного
решения о детерминированном ключе или новом grain с отдельным Power BI switch;
до него их selection и reconciliation остаются в Power BI.
