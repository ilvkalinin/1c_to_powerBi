# Решение: любой employee-link достаточен для присутствия

- Дата: 2026-08-28
- Отчёт: `employee_workload`
- Основание: явное решение пользователя: «если мы просто смотрим
  принадлежность в формате есть запись/нет записи то бери любую строка,
  похер какую».

## Решение

Квалифицированное СКУД-посещение включается в `employee_presence_day`, если
его client имеет хотя бы одну строку `Reference225`. Для нескольких строк
используется `MIN(Reference225._idrref)` как произвольный, но стабильный
`employee_id`. Выбор не утверждает фактическую принадлежность посещения этому
employee; он фиксирует только наличие employee-link.

Посещения без любой `Reference225`-связи остаются исключёнными по BR-044.
Отдельный non-personal presence product не создаётся.

## Влияние

BR-045 отменяет multi-link non-personal-ветвь BR-043: 708 visit IDs с двумя
связями входят в personal domain. Prior two-product planning set остаётся
`SUPERSEDED`; до новой technical review запрещены его extract, DDL, loader и
reconciliation plan. Решение не разрешает DDL, DML, `COPY`, target-подключение,
изменение 1С или Power BI.
