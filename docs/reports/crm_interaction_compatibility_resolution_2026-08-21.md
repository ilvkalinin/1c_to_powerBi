# CRM report-compatibility decisions

Дата: 2026-08-21. Статус: `ACTIVE`.

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
