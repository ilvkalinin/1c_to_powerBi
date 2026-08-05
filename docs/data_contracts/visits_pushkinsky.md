# Data contract: «Посещения Пушкинский»

Статус: `DESIGNED COMPOSITE MODEL / IMPLEMENTATION DEFERRED / TECHNICAL VALIDATION REQUIRED`.

REUSE `mart.visit_client_day` и `mart.club_day_metrics` из ADR-0003. Отдельного
факта Пушкинского нет.

Для Пушкинского `visit_client_day` дополнительно содержит `home_club_group
text` и флаги `has_member_visit`, `has_guest_visit`, `has_vip_visit`,
`has_drc_visit`, `has_after_school_visit`, `has_umnyashki_visit`; общие
`has_coupon` и `has_paid_service` не дублируются. Все флаги boolean, NOT NULL
после классификации; client key скрыт.

`mart.club_day_metrics` на `(report_date, club_id)` содержит bigint
`client_base_count`, `visited_today_count`, `active_nonvisitor_count`,
`inactive_count`, `group_program_visit_count`. Показатели аддитивны по клубу и
дате, но не суммируются между snapshot-днями как одна база.

Календарь и клубы фильтруют оба факта `1:*`, single direction. PostgreSQL
выполняет client-set intersections на VM-1; DAX — distinct категорий, доли и
временные сравнения. Приёмка: правило 00:00, `[D-30,D)`, actual club,
уникальные keys, reconciliation `base = visited + active_nonvisitor +
inactive`, rerun и SLA.

