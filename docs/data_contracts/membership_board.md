# Data contract: «Членство для правления»

Статус: `DESIGNED REUSE / IMPLEMENTATION DEFERRED / SHARED SOURCE TECHNICAL VALIDATION PARTIALLY VALIDATED — SV-083`.

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

SV-083 подтвердил в bounded срезах существование двух регистров и контрактных
справочников, уникальность physical technical keys и отсутствие orphan-contract.
Приёмка наследует незавершённые MR-V01…MR-V12 и дополнительно требует
равенство пяти KPI оперативному отчёту, factor reconciliation, отсутствие
влияния performance aggregate `___Итого по сети`, корректные plan grains и
SLA. Эти проверки выполняются только после отдельного разрешения Stage 3.
