# CRM initial implementation: superseded safely

Дата: 2026-08-21. Checkpoint: `CRM-IMP-001`. Статус: `CLOSED_CHECKPOINT`.

Пакет `crm_interaction_implementation_2026-08-21` был заменён явным решением
пользователя BR-032 до commit данных. Исходный immutable plan создал в VM-2
три таблицы и три views CRM с `REVOKE FROM PUBLIC`. Первый source-to-target
full rebuild был остановлен пользователем в первом квартальном блоке, когда
стало видно, что он переносит широкую выборку. Закрытие клиентского процесса
откатило незакоммиченную target-транзакцию; в `crm_interaction`,
`crm_interaction_phone` и `crm_interaction_comment` проверено по 0 строк.
Источник оставался `REPEATABLE READ READ ONLY`; изменений 1С не было.

Пользователь подтвердил новое направление: удалить эти шесть пустых объектов
и спроектировать компактную общую interaction-витрину там, где grain и
семантика действительно совпадают, с узкими scoped children только для
неизбежной phone/comment-кратности. Все подтверждённые фильтры, joins,
классификации, нормализация и допустимые агрегации должны выполняться на VM-1
до передачи. Это не разрешает DDL/DML: новый пакет потребует exact reviewed
SQL, reconciliation и отдельного approval.

Доказательства и proposal: [BR-032 optimisation review](crm_interaction_br032_optimization_review_2026-08-21.md),
[CRM mapping](../mappings/crm_interaction.md),
[business rules](../catalogs/business_rules.md).
