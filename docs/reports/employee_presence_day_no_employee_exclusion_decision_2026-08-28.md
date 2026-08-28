# Решение: исключить СКУД-посещения без employee-link

- Дата: 2026-08-28
- Отчёт: `employee_workload`
- Основание: явное решение пользователя: «если у посещения нет ссылки на
  реф225 нахуй тогда эти посещения».

## Решение

Из future employee-presence products исключаются 29,431 visit IDs exact
current-M domain, у которых client посещения не имеет связи с
`Reference225`. Они не материализуются ни в персональном
`employee_presence_day`, ни в non-personal продукте.

Решение не меняет 708 visit IDs, где у client больше одной employee-связи:
они остаются в non-personal продукте без `employee_id` и с единственным
статусом `MULTIPLE_EMPLOYEES`. Нет fallback, tie-break или назначения
сотрудника.

## Влияние

BR-044 отменяет только `NO_EMPLOYEE`-ветвь BR-043. Immutable planning-набор
commit `38ac5ec`, рассчитанный для двух статусов, `SUPERSEDED`: до новой
technical review запрещены его extract, DDL, loader и reconciliation plan.
Решение не разрешает DDL, DML, `COPY`, target-подключение, изменение 1С или
Power BI.
