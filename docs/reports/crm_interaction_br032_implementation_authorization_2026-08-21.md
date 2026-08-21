# CRM BR-032/BR-033 implementation authorization

Дата: 2026-08-21. Статус: `ACTIVE`.

Пользователь подтвердил единый Stage-3 пакет: выполнить
[`crm_br032_reviewed_plan.sql`](../../sql/marts/crm_br032_reviewed_plan.sql),
получить из одного read-only source snapshot четыре compact facts с
максимальным преобразованием на VM-1, выполнить atomic COPY, reconciliation,
rerun и измерение. Разрешено удалить только шесть ранее созданных пустых CRM
objects, перечисленных в reviewed plan. Не менять 1С, PBIT, schedules,
инкремент или guest outcomes BR-031. До commit любого failed DML — rollback;
после commit удаления/изменения не автоматизируются.
