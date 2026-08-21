# Admission preparation: `mart.crm_interaction`

Дата: 2026-08-21. Статус: `CLOSED`.

Пользователь явно одобрил один read-only пакет для подготовки следующего
product-admission `mart.crm_interaction`.

## Scope

- сверить mapping, подтверждённый core grain и переиспользование для
  «Загрузки ОП», «Отчёта по обращениям» и «Новичков и гостевых визитов»;
- разобрать имеющиеся SQL/M/DAX/PBIT-evidence и relationship boundaries;
- составить evidence-based перечень будущих target columns, source
  dependencies, unknowns, safeguards и acceptance controls;
- подготовить будущий implementation plan с объектами, операциями, rollback и
  критериями для отдельного решения пользователя.

## Boundaries

Только read-only анализ локальных артефактов. По явному разрешению пользователя
2026-08-21 в scope добавлена сверка трёх локальных PBIT-шаблонов: `Загрузка
ОП`, `Отчет по обращениям`, `Новички и гостевые визиты`. Это не разрешает
изменение Power BI или анализ внешних Excel/Google Sheets.

Не входят подключения к VM-1/VM-2, создание или изменение SQL-объектов,
DDL/DML, изменение источника 1С, изменение Power BI, внешние Excel/Google
Sheets и расписания.

## Closure criterion

Есть единый документированный core grain, source-to-target mapping со
статусами evidence, список незакрытых физических проверок и reviewed future
implementation plan. Реализация не начинается: для неё требуется отдельный
пакет с точным SQL и явным пользовательским одобрением.

## Read-only result

Созданы единые [CRM core mapping](../mappings/crm_interaction.md) и
[draft data contract](../data_contracts/crm_interaction.md). Подтверждённая
граница core — одна `Reference67.ID`; источники task/CRM-классификаций
переиспользуются тремя report-specific views. Ни одного подключения к VM-1/VM-2
и ни одной DDL/DML-операции в этом пакете не было.

### PBIT cross-check

По явному разрешению пользователя read-only сверены:

| Template | SHA-256 | Result |
|---|---|---|
| `Pbit_old/Загрузка ОП.pbit` | `0bd13b545645246cb8498e7ac82f5d7b13ee436137be67197d579cdb16d92bfd` | direct phone join, final `Distinct`, три роли включая «Ведущий менеджер» |
| `Pbit_old/Отчет по обращениям.pbit` | `9c46cdc6847ec69617a1abf8eaa5cd0635777109d58ea162558391991bb1242f` | feedback/Jivo scope; HTML/phone grouping без `Reference67.ID`; first-followup по task × client |
| `Pbit_old/Новички и гостевые визиты.pbit` | `3d54a392bec0d3feed21f998c91bf4607886ca101eac7b0adc94d6bbce180796` | direct phone join; meeting/funnel/status filters; `Fld820`/`Fld822` report date |

Сверка не меняет core business grain. Три compatibility rules для точного
первого релиза разрешены отдельным локальным пакетом 2026-08-21 на основании
BR-018, ранее подтверждённого phone-row rule и утверждённых PBIT:

1. Sales включает «Ведущий менеджер» и сохраняет каждую technical phone row;
   `Distinct` удаляет лишь настоящий technical duplicate.
2. Feedback core остаётся interaction-grain, а first-release view сохраняет
   final PBIT grouping без `interaction_id`.
3. Guest-tour view сохраняет phone-multiplicity и `report_date` из PBIT;
   core остаётся interaction-grain.

## Future implementation plan — not executable SQL

После решений по трём расхождениям отдельный implementation package должен:

1. выполнить read-only profiling physical types, `Marked`/archive/sentinel,
   task-orphan и phone/HTML/employment cardinality;
2. подготовить на review точные SQL-артефакты для нового core table,
   трёх views, grants, индексов, bounded full-refresh, reconciliation и
   rollback; текущий пакет намеренно не содержит исполняемого SQL;
3. получить единое пользовательское одобрение этого exact SQL package;
4. только после него создать core и views, выполнить initial load и
   acceptance controls из mapping;
5. при неуспешной приёмке убрать только новые CRM objects и вернуть Power BI
   к текущим PBIT queries; source 1С и существующие mart не изменяются.

Перед фактическим созданием остаются `VALIDATION_PENDING`: физические типы и
serialisation ключей, PII/grant model, marked/archive profile, deterministic
HTML/follow-up ties, PBIT reconciliation values, refresh timing и rerun.
