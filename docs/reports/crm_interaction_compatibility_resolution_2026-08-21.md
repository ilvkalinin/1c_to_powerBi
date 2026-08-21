# CRM report-compatibility decisions

Дата: 2026-08-21. Статус: `CLOSED`.

Пользователь явно одобрил самостоятельный read-only пакет для разрешения
трёх расхождений между согласованными mapping и локальными PBIT-шаблонами.

## Scope

- установить приоритет уже подтверждённых business rules, current PBIT/M/DAX
  evidence и Stage 2 controls для трёх точных report-view правил;
- зафиксировать по каждому правилу строковый grain, фильтр, date semantics и
  последствия для mapping/data contract/ADR;
- не менять core grain `Reference67.ID`;
- закрыть только те `DECISION_REQUIRED`, которые однозначно разрешаются
  существующей evidence и BR-018.

## Boundaries

Только локальные документы и уже извлечённые PBIT/M/DAX evidence. Не входят
подключения к VM-1/VM-2, новые server controls, SQL/DDL/DML, создание объектов,
изменение 1С или Power BI, внешние Excel/Google Sheets и расписания.

## Closure criterion

В `crm_interaction` mapping, трёх consumer mappings/contracts и ADR-0016
зафиксированы три совместимых с evidence report-view rules, все оставшиеся
unknowns отделены от бизнес-решений, а следующий package для exact SQL review
сформулирован без автоматического открытия.

## Resolved rules

### Sales interaction view

`Pbit_old/Загрузка ОП.pbit` includes the role «Ведущий менеджер» and direct
`InfoRg7146` join. The first-release view includes that role. The final PBIT
`Table.Distinct` cannot collapse two distinct technical phone rows: the
explicit user rule of 2026-08-05 defines each as an independent manager call.
`EXISTS` remains the only employment filter, so employment intervals cannot
multiply the phone rows. Acceptance compares both PBIT result and the count of
distinct `(interaction_id, phone technical key)` rows.

### Feedback interaction view

The user approved `Pbit_old/Отчет по обращениям.pbit` as the first-release
base on 2026-08-18. Its final query groups feedback by business attributes and
does not retain `Reference67.ID`; first follow-up is the earliest later
non-feedback interaction in the same client-code × task-code pair. Under
BR-018, `mart.crm_interaction` retains one row per interaction, while
`v_feedback_interaction` reproduces the final PBIT grouping. The view must not
add a hidden interaction ID if it changes its row count.

### Guest tour view

The approved guest PBIT retains direct phone rows, filters meeting + «Продажа
клубной карты», uses `Fld820` or `Fld822` for `ДатаДляОтчета`, and retains only
the two documented state/status pairs. Under BR-018, the compatibility view
keeps this multiplicity and exposes `report_date`; `interaction_id` remains
the core key. The physical implementation must profile the hidden phone key,
sentinel and stable funnel ID before producing SQL.

## Remaining work is technical, not a business decision

`VALIDATION_PENDING`: physical types/ID serialisation, PII grants, marked and
archive profile, technical phone key/null marker, HTML/follow-up tie-break,
stable guest-funnel ID, source/target reconciliation, rerun and timing. No
server operation was executed in this package.
