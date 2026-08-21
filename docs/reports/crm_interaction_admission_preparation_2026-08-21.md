# Admission preparation: `mart.crm_interaction`

Дата: 2026-08-21. Статус: `ACTIVE`.

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

Только локальные read-only артефакты. Не входят подключения к VM-1/VM-2,
создание или изменение SQL-объектов, DDL/DML, изменение источника 1С, Power BI,
внешние файлы и расписания.

## Closure criterion

Есть единый документированный core grain, source-to-target mapping со
статусами evidence, список незакрытых физических проверок и reviewed future
implementation plan. Реализация не начинается: для неё требуется отдельный
пакет с точным SQL и явным пользовательским одобрением.
