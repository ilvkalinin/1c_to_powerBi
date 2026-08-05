# Data contract: «Членство для правления»

Статус: `DESIGNED REUSE / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

Отдельного board-факта нет. Отчёт REUSE
`mart.membership_receipt_movement` и `mart.membership_contract_kpi_unit` из
контракта `membership_receipts`/ADR-0017. Схема, ключи, роли дат и NULL
полностью наследуются.

Пользовательские поля: даты поступления/KPI/окончания, reporting/access/sales
club roles, manager, super stage, product age, payment type/source, product,
club/access-time types, duration category, net receipt amount, calculation
price и effective duration. Technical keys скрыты.

Календарь, клубы в разных ролях, менеджер и продуктовые справочники фильтруют
оба применимых факта `1:*`, single direction. Внешние текущий, среднесрочный и
годовой планы остаются Power BI-фактами. DAX повторно использует эталонные
пять KPI поступлений, затем считает board-specific план, отклонения, доли,
MTD/YTD и факторные компоненты.

Приёмка наследует MR-V01…MR-V12 и дополнительно требует равенство пяти KPI
оперативному отчёту, factor reconciliation, отсутствие влияния performance
aggregate `___Итого по сети`, корректные plan grains и SLA.
